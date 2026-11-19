import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PromiseKit
import Atomics

public class DefaultHTTPResponse: Response {
	public init(status: Int, statusMessage: String, contentType: String, content: Data) {
		self.status = status
		self.statusMessage = statusMessage
		self.contentType = contentType
		self.content = content
	}

	public var status: Int
	public var statusMessage: String
	public var contentType: String
	public var content: Data
}

public class DefaultHTTPClient: HTTPClient {
	private var config: DefaultHTTPClientConfig = DefaultHTTPClientConfig()
	private let session: URLSession

	public init(config: DefaultHTTPClientConfig) {
		self.config = config
		let sessionConfig = URLSessionConfiguration.ephemeral
		sessionConfig.timeoutIntervalForRequest = config.connectionRequestTimeout
		sessionConfig.timeoutIntervalForResource = config.connectionResourceTimeout
		self.session = URLSession(configuration: sessionConfig)
	}

	deinit {
		#if !canImport(FoundationNetworking)
		// Not on Linux: swift-corelibs-foundation crashes in dispatch queue teardown when a session
		// is invalidated during deinit; ARC releases it there instead.
		session.invalidateAndCancel()
		#endif
	}

	public func get(url: String, query: [String: String]?, headers: [String: String]?) -> Promise<Response> {
		return request(method: "GET", url: url, query: query, headers: headers, body: nil)
	}

	public func put(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) -> Promise<Response>
	{
		return request(method: "PUT", url: url, query: query, headers: headers, body: body)
	}

	public func post(url: String, query: [String: String]?, headers: [String: String]?, body: Data?) -> Promise<
		Response
	> {
		return request(method: "POST", url: url, query: query, headers: headers, body: body)
	}

	public func request(method: String, url: String, query: [String: String]?, headers: [String: String]?, body: Data?)
		-> Promise<Response>
	{
		return Self.retry(
			times: config.retries, delay: config.retryInterval,
			// Holds the client strongly until the request settles, as in v1.4.0, so a caller that
			// drops the client mid-request still gets its Promise settled.
			body: { [self] attempt in
				return Promise<Response> { seal in

					guard var components = URLComponents(string: url) else {
						seal.reject(URLError(.badURL))
						return
					}

					if let query = query {
						components.queryItems = query.compactMap { (key, value) in
							URLQueryItem(name: key, value: value)
						}
					}

					guard let requestURL = components.url else {
						seal.reject(URLError(.badURL))
						return
					}

					var request = URLRequest(url: requestURL)
					request.httpMethod = method
					request.timeoutInterval = self.config.connectionRequestTimeout

					if let headers = headers {
						request.allHTTPHeaderFields = headers
					}

					if method != "GET", let body = body {
						request.httpBody = body
					}

					self.session.dataTask(
						with: request,
						completionHandler: { data, rsp, error in
							if let data = data, let rsp = rsp as? HTTPURLResponse {
								if (rsp.statusCode == 502 || rsp.statusCode == 503)
									&& (attempt < self.config.retries)
								{
									seal.reject(
										ABSmartlyHTTPError(
											rsp.statusCode,
											HTTPURLResponse.localizedString(
												forStatusCode: rsp.statusCode)))
								} else {
									seal.fulfill(
										DefaultHTTPResponse(
											status: rsp.statusCode,
											statusMessage: HTTPURLResponse.localizedString(
												forStatusCode: rsp.statusCode),
											contentType: rsp.mimeType ?? "text/plain", content: data))
								}
							} else if let error = error {
								seal.reject(error)
							} else {
								seal.reject(PMKError.invalidCallingConvention)
							}
						}
					).resume()
				}
			})
	}

	public func close() -> Promise<Void> {
		return Promise<Void>.value(())
	}
}

extension DefaultHTTPClient {
	static func retry<T>(times: UInt, delay: TimeInterval, body: @escaping (UInt) -> Promise<T>) -> Promise<T> {
		let tryCounter = ManagedAtomic<UInt>(0)
		func attempt() -> Promise<T> {
			let currentTry = tryCounter.wrappingIncrementThenLoad(ordering: .acquiringAndReleasing)
			return body(currentTry).recover(on: DispatchQueue.global(), policy: CatchPolicy.allErrorsExceptCancellation) {
				error -> Promise<T> in
				guard currentTry <= times else {
					throw error
				}
				return after(seconds: delay).then(on: DispatchQueue.global(), attempt)
			}
		}
		return attempt()
	}
}
