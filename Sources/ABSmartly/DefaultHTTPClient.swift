import Foundation
import PromiseKit

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
	private var session: URLSession

	public init(config: DefaultHTTPClientConfig) {
		self.config = config
		let sessionConfig = URLSessionConfiguration.ephemeral
		sessionConfig.timeoutIntervalForRequest = config.connectionRequestTimeout
		sessionConfig.timeoutIntervalForResource = config.connectionResourceTimeout
		self.session = URLSession(configuration: sessionConfig)
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
		return retry(
			times: config.retries, delay: config.retryInterval,
			body: { attempt in
				return Promise<Response> { seal in
					guard var components = URLComponents(string: url) else {
						throw URLError(.badURL)
					}

					if query != nil {
						components.queryItems = query!.compactMap { (key, value) in
							URLQueryItem(name: key, value: value)
						}
					}

					var request = URLRequest(url: components.url!)
					request.httpMethod = method
					request.timeoutInterval = self.config.connectionResourceTimeout

					if headers != nil {
						request.allHTTPHeaderFields = headers
					}

					if method != "GET" && body != nil {
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

func retry<T>(times: UInt, delay: TimeInterval, body: @escaping (UInt) -> Promise<T>) -> Promise<T> {
	var tryCounter: UInt = 0
	func attempt() -> Promise<T> {
		tryCounter += 1
		return body(tryCounter).recover(policy: CatchPolicy.allErrorsExceptCancellation) { error -> Promise<T> in
			guard tryCounter <= times else {
				throw error
			}
			return after(seconds: delay).then(attempt)
		}
	}
	return attempt()
}
