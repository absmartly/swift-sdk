import Foundation
import Testing

@testable import ABsmartly

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

@Suite struct URLSessionTransportTests {
	@Test func creatable() async throws {
		var configuration = ABsmartlyClient.Configuration(
			endpoint: URL(string: "https://test.absmartly.io/v1")!, apiKey: "k", application: "a", environment: "e")
		configuration.retries = 4
		let client = try ABsmartlyClient(configuration: configuration)
		#expect(client.connection.transport is URLSessionTransport)
		#expect(client.connection.retries == 4)
		_ = URLSessionTransport()
	}

	@Test func urlSessionConfiguration() throws {
		var configuration = ABsmartlyClient.Configuration(
			endpoint: URL(string: "https://test.absmartly.io/v1")!, apiKey: "k", application: "a", environment: "e")
		configuration.timeout = 30
		configuration.retries = 3
		configuration.retryInterval = 1.0
		let client = try ABsmartlyClient(configuration: configuration)
		#expect(client.connection.timeout == 30)
		#expect(client.connection.retries == 3)
		#expect(client.connection.retryInterval == 1.0)
		_ = URLSessionTransport(timeout: 60)
	}

	@Test func httpResponse() {
		let response = HTTPResponse(statusCode: 200, body: Data(#"{"key": "value"}"#.utf8))
		#expect(response.statusCode == 200)
		#expect(response.body == Data(#"{"key": "value"}"#.utf8))
		// Foundation's text differs by platform ("no error" on Apple, "OK" on Linux).
		#expect(Connection.statusMessage(200) == HTTPURLResponse.localizedString(forStatusCode: 200))
	}

	@Test func badURL() async throws {
		let transport = URLSessionTransport()
		let request = HTTPRequest(method: "GET", url: URL(string: "not-a-valid-url")!, headers: [:], timeout: 1)
		do {
			_ = try await withTimeout { try await transport.send(request) }
			Issue.record("Request should have failed with bad URL")
		} catch let error as URLError {
			#expect([.badURL, .unsupportedURL].contains(error.code), "unexpected code \(error.code)")
		}
	}

	// MARK: - URLProtocol stub

	@Test func sendsMethodURLHeadersAndBody() async throws {
		let (endpoint, stub) = StubURLProtocol.register { request in
			(request.method == "GET" ? 200 : 201, Data("\(request.method)-reply".utf8))
		}
		let transport = URLSessionTransport(session: StubURLProtocol.session())
		let url = endpoint.appendingPathComponent("context")

		let get = try await withTimeout {
			try await transport.send(
				HTTPRequest(method: "GET", url: url, headers: ["X-Test": "1"], body: Data("ignored".utf8), timeout: 2))
		}
		#expect(get == HTTPResponse(statusCode: 200, body: Data("GET-reply".utf8)))

		let put = try await withTimeout {
			try await transport.send(
				HTTPRequest(method: "PUT", url: url, headers: ["X-Test": "2"], body: Data("payload".utf8), timeout: 2))
		}
		#expect(put == HTTPResponse(statusCode: 201, body: Data("PUT-reply".utf8)))

		let requests = stub.requests
		#expect(requests.map(\.method) == ["GET", "PUT"])
		#expect(requests.allSatisfy { $0.url == url })
		#expect(requests[0].header("X-Test") == "1")
		#expect(requests[0].body.isEmpty, "GET sends no body")
		#expect(requests[1].header("X-Test") == "2")
		#expect(requests[1].body == Data("payload".utf8))
	}

	@Test(arguments: [301, 404, 500, 502, 503])
	func returnsEveryStatus(status: Int) async throws {
		let (endpoint, _) = StubURLProtocol.register { _ in (status, Data("x".utf8)) }
		let transport = URLSessionTransport(session: StubURLProtocol.session())
		let response = try await withTimeout {
			try await transport.send(HTTPRequest(method: "GET", url: endpoint, headers: [:], timeout: 2))
		}
		#expect(response.statusCode == status)
		#expect(response.body == Data("x".utf8))
	}

	@Test func throwsTheLoadingError() async throws {
		let (endpoint, _) = StubURLProtocol.register { _ in throw URLError(.notConnectedToInternet) }
		let transport = URLSessionTransport(session: StubURLProtocol.session())
		do {
			_ = try await withTimeout {
				try await transport.send(HTTPRequest(method: "GET", url: endpoint, headers: [:], timeout: 2))
			}
			Issue.record("expected an error")
		} catch let error as URLError {
			#expect(error.code == .notConnectedToInternet)
		}
	}

	@Test func clientOverURLSessionSendsTheWireContract() async throws {
		let (endpoint, stub) = StubURLProtocol.register { request in
			(200, Data(request.method == "GET" ? Fixtures.data("context") : Data("{}".utf8)))
		}
		var configuration = ABsmartlyClient.Configuration(
			endpoint: endpoint, apiKey: "integration-test-key", application: "integration-app",
			environment: "integration-env")
		configuration.applicationVersion = " 42 "
		configuration.transport = URLSessionTransport(session: StubURLProtocol.session())
		configuration.defaultContextOptions = Context.Options(publishDelay: -1)
		let client = try ABsmartlyClient(configuration: configuration)

		let context = try await withTimeout { try await client.context(units: [.sessionID: "bleh@absmartly.com"]) }
		_ = context.treatment(for: "exp_test_ab")
		context.track("payment", properties: ["amount": 100])
		try await withTimeout { try await context.publish() }

		let requests = stub.requests
		#expect(requests.map(\.method) == ["GET", "PUT"])
		let get = requests[0]
		#expect(get.url.path == "/v1/context")
		#expect(get.query == ["application": "integration-app", "environment": "integration-env"])
		let put = requests[1]
		#expect(put.url.path == "/v1/context")
		#expect(put.query.isEmpty)
		for request in requests {
			#expect(request.header("X-API-Key") == "integration-test-key")
			#expect(request.header("X-Application") == "integration-app")
			#expect(request.header("X-Environment") == "integration-env")
			#expect(request.header("X-Application-Version") == "42")
			#expect(request.header("X-Agent") == "absmartly-swift-sdk/2.1.0")
			#expect(request.header("Content-Type") == "application/json; charset=utf-8")
		}
		let body = try JSONDecoder().decode(JSONValue.self, from: put.body)
		#expect(body["hashed"] == true)
		#expect(body["exposures"]?.arrayValue?.count == 1)
		#expect(body["goals"]?.arrayValue?.count == 1)
	}

	// MARK: - Real local HTTP server

	/// Exercises the real `URLSessionTransport` against a real HTTP server bound to 127.0.0.1 on an
	/// ephemeral port: genuine TCP/HTTP requests, so this verifies the actual wire contract.
	@Test func realHTTPGetAndPublish() async throws {
		let server = try LocalHTTPServer()
		defer { server.stop() }
		try server.start()

		let apiKey = "integration-test-key"
		let application = "integration-app"
		let environment = "integration-env"

		// Server returns an empty experiments set on GET so the context becomes ready.
		server.getResponseBody = #"{"experiments":[]}"#

		var configuration = ABsmartlyClient.Configuration(
			endpoint: URL(string: "http://127.0.0.1:\(server.port)")!, apiKey: apiKey, application: application,
			environment: ABsmartlyClient.Environment(rawValue: environment))
		configuration.timeout = 5
		configuration.retries = 0
		configuration.defaultContextOptions = Context.Options(publishDelay: -1)
		let client = try ABsmartlyClient(configuration: configuration)

		// --- GET /context (drive the context to ready via the real transport) ---
		let context = client.makeContext(units: [.sessionID: "bleh@absmartly.com"])
		try await withTimeout(10) { try await context.ready() }
		#expect(context.state == .ready)

		// The GET landed on the right path with the right query params.
		let get = try #require(server.request(method: "GET"), "expected a GET request to be received")
		#expect(get.method == "GET")
		#expect(get.path == "/context")
		#expect(get.query["application"] == application)
		#expect(get.query["environment"] == environment)

		// --- PUT /context (publish a queued exposure + goal) ---
		server.putResponseBody = "{}"
		_ = context.treatment(for: "exp_test_ab")
		context.track("payment", properties: ["amount": 100])
		try await withTimeout(10) { try await context.publish() }

		let put = try #require(server.request(method: "PUT"), "expected a PUT request to be received")
		#expect(put.method == "PUT")
		#expect(put.path == "/context")

		// Headers (case-insensitive lookup).
		#expect(put.header("X-API-Key") == apiKey)
		#expect(put.header("X-Application") == application)
		#expect(put.header("X-Environment") == environment)
		#expect(put.header("X-Application-Version") == "0")
		let agent = put.header("X-Agent")
		#expect(agent != nil, "X-Agent header must be present")
		#expect(!(agent ?? "").isEmpty, "X-Agent header must be non-empty")
		let contentType = put.header("Content-Type") ?? ""
		#expect(
			contentType.contains("application/json"), "Content-Type should be application/json, got '\(contentType)'")

		// Body JSON fields.
		let json = try JSONDecoder().decode(JSONValue.self, from: Data(put.body.utf8))
		#expect(json.objectValue != nil, "PUT body should be a JSON object, got: \(put.body)")
		#expect(json["hashed"] == true, "body must contain 'hashed'")

		let units = try #require(json["units"]?.arrayValue, "body must contain 'units' array")
		#expect(!units.isEmpty, "units should not be empty")
		#expect(units.first?["type"] != nil)
		#expect(units.first?["uid"] != nil)

		#expect(json["publishedAt"]?.isNumber == true, "publishedAt should be a number")

		// One exposure (exp_test_ab is not in the data, still exposed) and one goal were queued.
		let exposures = try #require(json["exposures"]?.arrayValue, "body should contain 'exposures'")
		#expect(!exposures.isEmpty, "exposures should not be empty")
		let goals = try #require(json["goals"]?.arrayValue, "body should contain 'goals'")
		#expect(!goals.isEmpty, "goals should not be empty")

		try await withTimeout(10) { try await context.close() }
	}
}

// MARK: - Minimal localhost HTTP server (POSIX sockets)

/// A tiny HTTP/1.1 server bound to 127.0.0.1 on an ephemeral port. It parses the request line,
/// headers and (Content-Length) body, records each request, and replies 200 with a small JSON body.
/// Built on POSIX sockets so it also runs on Linux.
private final class LocalHTTPServer: @unchecked Sendable {
	struct Request {
		let method: String
		let path: String
		let query: [String: String]
		let headers: [String: String]  // keys lowercased
		let body: String

		func header(_ name: String) -> String? { headers[name.lowercased()] }
	}

	private let lock = NSLock()
	private var _getResponseBody = #"{"experiments":[]}"#
	private var _putResponseBody = "{}"
	private var requests: [Request] = []
	private var stopped = false
	private var acceptThread: Thread?
	private let listenFD: Int32
	private(set) var port: UInt16 = 0

	var getResponseBody: String {
		get { lock.withLock { _getResponseBody } }
		set { lock.withLock { _getResponseBody = newValue } }
	}

	var putResponseBody: String {
		get { lock.withLock { _putResponseBody } }
		set { lock.withLock { _putResponseBody = newValue } }
	}

	struct ServerError: Error {
		let message: String
	}

	init() throws {
		#if canImport(Glibc) && !canImport(Darwin)
			listenFD = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
		#else
			listenFD = socket(AF_INET, SOCK_STREAM, 0)
		#endif
		guard listenFD >= 0 else { throw ServerError(message: "could not create a socket") }
		var reuse: Int32 = 1
		setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
	}

	func start() throws {
		var address = sockaddr_in()
		#if canImport(Darwin)
			address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		#endif
		address.sin_family = sa_family_t(AF_INET)
		address.sin_port = 0
		address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
		let bound = withUnsafePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard bound == 0, listen(listenFD, 16) == 0 else {
			throw ServerError(message: "failed to listen on 127.0.0.1")
		}

		var boundAddress = sockaddr_in()
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		_ = withUnsafeMutablePointer(to: &boundAddress) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listenFD, $0, &length) }
		}
		port = UInt16(bigEndian: boundAddress.sin_port)
		guard port != 0 else { throw ServerError(message: "did not bind to a port") }

		let thread = Thread { [self] in acceptLoop() }
		lock.withLock { acceptThread = thread }
		thread.start()
	}

	/// Also releases the socket when `start()` failed.
	func stop() {
		let (wasStopped, thread) = lock.withLock { () -> (Bool, Thread?) in
			defer { stopped = true }
			return (stopped, acceptThread)
		}
		guard !wasStopped else { return }
		// The accept loop polls with a timeout, so it notices `stopped` and exits (bounded wait).
		let deadline = Date().addingTimeInterval(2)
		while thread?.isFinished == false && Date() < deadline {
			Thread.sleep(forTimeInterval: 0.01)
		}
		close(listenFD)
	}

	/// The first recorded request with this method. The SDK call that sent it has already returned
	/// (the response is written after recording), so no waiting is needed.
	func request(method: String) -> Request? {
		lock.withLock { requests.first { $0.method == method } }
	}

	private var isStopped: Bool { lock.withLock { stopped } }

	private func acceptLoop() {
		while !isStopped {
			var pollFD = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
			guard poll(&pollFD, 1, 50) > 0 else { continue }
			let connection = accept(listenFD, nil, nil)
			guard connection >= 0 else { continue }
			DispatchQueue.global().async { [self] in
				handle(connection)
				close(connection)
			}
		}
	}

	private func handle(_ connection: Int32) {
		#if canImport(Darwin)
			var noSigPipe: Int32 = 1
			setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
		#endif
		var timeout = timeval(tv_sec: 5, tv_usec: 0)
		setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
		var accumulated = Data()
		var chunk = [UInt8](repeating: 0, count: 64 * 1024)
		while true {
			let count = recv(connection, &chunk, chunk.count, 0)
			if count <= 0 { return }  // closed, failed or timed out before a full request arrived
			accumulated.append(contentsOf: chunk[0..<count])
			if let request = Self.parse(accumulated) {
				lock.withLock { requests.append(request) }
				respond(connection, to: request)
				return
			}
		}
	}

	/// Parses a full request once the headers and the body are in; nil if more bytes are needed.
	private static func parse(_ data: Data) -> Request? {
		guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
			let headerText = String(data: data.subdata(in: data.startIndex..<headerEnd.lowerBound), encoding: .utf8)
		else { return nil }

		var lines = headerText.components(separatedBy: "\r\n")
		let requestParts = lines.removeFirst().split(separator: " ", maxSplits: 2).map(String.init)
		guard requestParts.count >= 2 else { return nil }

		var headers: [String: String] = [:]
		for line in lines {
			guard let colon = line.firstIndex(of: ":") else { continue }
			let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
			headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
		}

		let contentLength = Int(headers["content-length"] ?? "0") ?? 0
		guard data.distance(from: headerEnd.upperBound, to: data.endIndex) >= contentLength else { return nil }
		let bodyData = data.subdata(
			in: headerEnd.upperBound..<data.index(headerEnd.upperBound, offsetBy: contentLength))

		let target = URLComponents(string: requestParts[1])
		var query: [String: String] = [:]
		for item in target?.queryItems ?? [] {
			query[item.name] = item.value ?? ""
		}
		return Request(
			method: requestParts[0], path: target?.path ?? requestParts[1], query: query, headers: headers,
			body: String(decoding: bodyData, as: UTF8.self))
	}

	private func respond(_ connection: Int32, to request: Request) {
		let body = Data((request.method == "PUT" ? putResponseBody : getResponseBody).utf8)
		var out = Data(
			"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
				.utf8)
		out.append(body)
		#if canImport(Darwin)
			let flags: Int32 = 0
		#else
			let flags = Int32(MSG_NOSIGNAL)
		#endif
		out.withUnsafeBytes { buffer in
			var sent = 0
			while sent < buffer.count {
				let result = send(connection, buffer.baseAddress! + sent, buffer.count - sent, flags)
				if result <= 0 { return }
				sent += result
			}
		}
	}
}
