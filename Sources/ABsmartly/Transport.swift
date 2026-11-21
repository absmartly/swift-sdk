import Foundation

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

/// An HTTP request the SDK sends through its `Transport`.
public struct HTTPRequest: Sendable, Equatable {
	public var method: String
	public var url: URL
	public var headers: [String: String]
	public var body: Data?
	/// Seconds the transport should allow for the request.
	public var timeout: TimeInterval

	public init(method: String, url: URL, headers: [String: String], body: Data? = nil, timeout: TimeInterval) {
		self.method = method
		self.url = url
		self.headers = headers
		self.body = body
		self.timeout = timeout
	}
}

/// The response a `Transport` returns for any status code; the SDK interprets the status.
public struct HTTPResponse: Sendable, Equatable {
	public var statusCode: Int
	public var body: Data

	public init(statusCode: Int, body: Data) {
		self.statusCode = statusCode
		self.body = body
	}
}

/// Sends the SDK's HTTP requests. The SDK builds the requests (URL, headers, body), retries and
/// interprets the responses, so a transport only moves bytes: a proxy, a different HTTP stack or a
/// test double.
///
/// Throw for a failed request (no response); return the response for every status code.
public protocol Transport: Sendable {
	func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The default transport: an ephemeral `URLSession` allowing at most 4 connections per host.
public final class URLSessionTransport: Transport {
	private let session: URLSession

	/// - Parameter timeout: the session's request and resource timeouts in seconds.
	public init(timeout: TimeInterval = 3) {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = timeout
		configuration.timeoutIntervalForResource = timeout
		configuration.httpMaximumConnectionsPerHost = 4
		session = URLSession(configuration: configuration)
	}

	/// Uses `session` as it is configured.
	public init(session: URLSession) {
		self.session = session
	}

	public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
		var urlRequest = URLRequest(url: request.url)
		urlRequest.httpMethod = request.method
		urlRequest.timeoutInterval = request.timeout
		urlRequest.allHTTPHeaderFields = request.headers
		if request.method != "GET" {
			urlRequest.httpBody = request.body
		}

		let (data, response) = try await session.data(for: urlRequest)
		guard let http = response as? HTTPURLResponse else {
			throw URLError(.badServerResponse)
		}
		return HTTPResponse(statusCode: http.statusCode, body: data)
	}
}
