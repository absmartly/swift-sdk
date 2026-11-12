#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

/// Hermetic integration test that exercises the REAL SDK HTTP client (URLSession,
/// built inside DefaultHTTPClient) against a REAL local HTTP server bound to
/// 127.0.0.1 on an ephemeral port. No URLProtocol mocks — the production client
/// makes genuine TCP/HTTP requests so this verifies the actual wire contract.
///
/// Wire contract under test:
///   - GET  /context?application=<app>&environment=<env>  (no auth headers on GET)
///   - PUT  /context  with X-API-Key / X-Application / X-Environment /
///          X-Application-Version / X-Agent / Content-Type headers and a JSON
///          body containing hashed, units, publishedAt (+ goals/exposures).
final class HTTPIntegrationTest: XCTestCase {
	private var server: LocalHTTPServer!

	override func setUpWithError() throws {
		server = try LocalHTTPServer()
		try server.start()
	}

	override func tearDownWithError() throws {
		server.stop()
		server = nil
	}

	func testRealHTTPGetAndPublish() throws {
		let apiKey = "integration-test-key"
		let application = "integration-app"
		let environment = "integration-env"

		// Server returns an empty experiments set on GET so the context becomes ready.
		server.getResponseBody = #"{"experiments":[]}"#

		let sdk = try ABsmartlySDK(
			endpoint: "http://127.0.0.1:\(server.port)",
			apiKey: apiKey,
			application: application,
			environment: environment
		)

		// --- GET /context (drive context to ready via the real client) ---
		let contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "bleh@absmartly.com")

		let context = sdk.createContext(config: contextConfig)

		let readyExpectation = expectation(description: "context ready")
		context.waitUntilReady().done { _ in
			readyExpectation.fulfill()
		}.catch { error in
			XCTFail("waitUntilReady failed: \(error)")
		}
		wait(for: [readyExpectation], timeout: 10.0)

		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isFailed(), "context should not have failed: \(String(describing: context.readyError()))")

		// Assert the GET landed on the right path with the right query params.
		let getRequest = server.waitForRequest(method: "GET", timeout: 10.0)
		XCTAssertNotNil(getRequest, "expected a GET request to be received")
		guard let get = getRequest else { return }
		XCTAssertEqual(get.method, "GET")
		XCTAssertEqual(get.path, "/context")
		XCTAssertEqual(get.query["application"], application)
		XCTAssertEqual(get.query["environment"], environment)

		// --- PUT /context (publish a queued exposure + goal) ---
		server.putResponseBody = "{}"

		_ = context.getTreatment("exp_test_ab")
		context.track("payment", properties: ["amount": 100])

		let publishExpectation = expectation(description: "publish completed")
		context.publish().done {
			publishExpectation.fulfill()
		}.catch { error in
			XCTFail("publish failed: \(error)")
		}
		wait(for: [publishExpectation], timeout: 10.0)

		let putRequest = server.waitForRequest(method: "PUT", timeout: 10.0)
		XCTAssertNotNil(putRequest, "expected a PUT request to be received")
		guard let put = putRequest else { return }

		XCTAssertEqual(put.method, "PUT")
		XCTAssertEqual(put.path, "/context")

		// Headers (case-insensitive lookup).
		XCTAssertEqual(put.header("X-API-Key"), apiKey)
		XCTAssertEqual(put.header("X-Application"), application)
		XCTAssertEqual(put.header("X-Environment"), environment)
		XCTAssertEqual(put.header("X-Application-Version"), "0")
		let agent = put.header("X-Agent")
		XCTAssertNotNil(agent, "X-Agent header must be present")
		XCTAssertFalse((agent ?? "").isEmpty, "X-Agent header must be non-empty")
		let contentType = put.header("Content-Type") ?? ""
		XCTAssertTrue(contentType.contains("application/json"), "Content-Type should be application/json, got '\(contentType)'")

		// Body JSON fields.
		let bodyData = Data(put.body.utf8)
		let json = try XCTUnwrap(
			try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
			"PUT body should be a JSON object, got: \(put.body)")

		XCTAssertNotNil(json["hashed"], "body must contain 'hashed'")
		XCTAssertEqual(json["hashed"] as? Bool, true)

		let units = try XCTUnwrap(json["units"] as? [[String: Any]], "body must contain 'units' array")
		XCTAssertFalse(units.isEmpty, "units should not be empty")
		XCTAssertNotNil(units.first?["type"])
		XCTAssertNotNil(units.first?["uid"])

		XCTAssertNotNil(json["publishedAt"], "body must contain 'publishedAt'")
		XCTAssertTrue(json["publishedAt"] is NSNumber, "publishedAt should be a number")

		// We queued one exposure and one goal, so both arrays should be present.
		let exposures = try XCTUnwrap(json["exposures"] as? [[String: Any]], "body should contain 'exposures'")
		XCTAssertFalse(exposures.isEmpty, "exposures should not be empty")
		let goals = try XCTUnwrap(json["goals"] as? [[String: Any]], "body should contain 'goals'")
		XCTAssertFalse(goals.isEmpty, "goals should not be empty")

		_ = sdk.close()
	}
}

// MARK: - Minimal localhost HTTP server (POSIX sockets)

/// A tiny, hermetic HTTP/1.1 server bound to 127.0.0.1 on an ephemeral port.
/// It parses request line + headers + (Content-Length) body, records each
/// request, and replies 200 with a small JSON body. Just enough to exercise the
/// SDK's real URLSession client; not a general-purpose server.
/// Built on POSIX sockets rather than Network.framework so it also runs on Linux.
private final class LocalHTTPServer {
	struct Request {
		let method: String
		let path: String
		let query: [String: String]
		let headers: [String: String]  // keys lowercased
		let body: String

		func header(_ name: String) -> String? {
			return headers[name.lowercased()]
		}
	}

	var getResponseBody: String = #"{"experiments":[]}"#
	var putResponseBody: String = "{}"

	private let listenFD: Int32
	private let lock = NSLock()
	private var requests: [Request] = []
	private var stopped = false
	private var acceptThread: Thread?
	private(set) var port: UInt16 = 0

	init() throws {
		#if canImport(Glibc) && !canImport(Darwin)
			listenFD = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
		#else
			listenFD = socket(AF_INET, SOCK_STREAM, 0)
		#endif
		guard listenFD >= 0 else {
			throw ABSmartlyError("Local HTTP server could not create a socket")
		}
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
			throw ABSmartlyError("Local HTTP server failed to listen on 127.0.0.1")
		}

		var boundAddress = sockaddr_in()
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		_ = withUnsafeMutablePointer(to: &boundAddress) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				getsockname(listenFD, $0, &length)
			}
		}
		port = UInt16(bigEndian: boundAddress.sin_port)
		guard port != 0 else {
			throw ABSmartlyError("Local HTTP server did not bind to a port")
		}

		let thread = Thread { [weak self] in
			self?.acceptLoop()
		}
		acceptThread = thread
		thread.start()
	}

	/// Also releases the socket when `start()` failed (tearDown still calls this).
	func stop() {
		lock.lock()
		let wasStopped = stopped
		stopped = true
		lock.unlock()
		if !wasStopped {
			// The accept loop polls with a timeout, so it notices `stopped` and exits;
			// closing here is safe because it no longer blocks in accept().
			while acceptThread?.isFinished == false {
				Thread.sleep(forTimeInterval: 0.01)
			}
			close(listenFD)
		}
	}

	/// Block until a request with the given method has been recorded (or timeout).
	func waitForRequest(method: String, timeout: TimeInterval) -> Request? {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			lock.lock()
			let found = requests.first { $0.method == method }
			lock.unlock()
			if let found = found {
				return found
			}
			Thread.sleep(forTimeInterval: 0.02)
		}
		return nil
	}

	// MARK: connection handling

	private var isStopped: Bool {
		lock.lock()
		defer { lock.unlock() }
		return stopped
	}

	private func acceptLoop() {
		while !isStopped {
			var pollFD = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
			guard poll(&pollFD, 1, 50) > 0 else { continue }
			let connection = accept(listenFD, nil, nil)
			guard connection >= 0 else { continue }
			DispatchQueue.global().async { [weak self] in
				self?.handle(connection)
				close(connection)
			}
		}
	}

	private func handle(_ connection: Int32) {
		#if canImport(Darwin)
			var noSigPipe: Int32 = 1
			setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
		#endif
		var accumulated = Data()
		var chunk = [UInt8](repeating: 0, count: 64 * 1024)
		while true {
			let count = recv(connection, &chunk, chunk.count, 0)
			if count <= 0 {
				return  // closed or failed before a full request arrived
			}
			accumulated.append(contentsOf: chunk[0..<count])

			if let parsed = tryParse(accumulated) {
				lock.lock()
				requests.append(parsed.request)
				lock.unlock()
				respond(connection, to: parsed.request)
				return
			}
		}
	}

	/// Parse a full HTTP request once headers + (any) body are present.
	/// Returns nil if more bytes are needed.
	private func tryParse(_ data: Data) -> (request: Request, consumed: Int)? {
		guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
			return nil
		}

		let headerData = data.subdata(in: data.startIndex..<headerEndRange.lowerBound)
		guard let headerText = String(data: headerData, encoding: .utf8) else {
			return nil
		}

		var lines = headerText.components(separatedBy: "\r\n")
		guard let requestLine = lines.first else { return nil }
		lines.removeFirst()

		let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
		guard requestParts.count >= 2 else { return nil }
		let method = requestParts[0]
		let target = requestParts[1]

		var headers: [String: String] = [:]
		for line in lines where !line.isEmpty {
			guard let colon = line.firstIndex(of: ":") else { continue }
			let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
			let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
			headers[name] = value
		}

		let bodyStart = headerEndRange.upperBound
		let contentLength = Int(headers["content-length"] ?? "0") ?? 0
		let availableBody = data.count - data.distance(from: data.startIndex, to: bodyStart)
		if availableBody < contentLength {
			return nil  // wait for the rest of the body
		}

		let bodyData = data.subdata(in: bodyStart..<data.index(bodyStart, offsetBy: contentLength))
		let body = String(data: bodyData, encoding: .utf8) ?? ""

		let (path, query) = Self.splitTarget(target)
		let request = Request(method: method, path: path, query: query, headers: headers, body: body)
		return (request, data.count)
	}

	private static func splitTarget(_ target: String) -> (String, [String: String]) {
		guard let qIndex = target.firstIndex(of: "?") else {
			return (target, [:])
		}
		let path = String(target[target.startIndex..<qIndex])
		let queryString = String(target[target.index(after: qIndex)...])
		var query: [String: String] = [:]
		for pair in queryString.split(separator: "&") {
			let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
			let key = kv[0].removingPercentEncoding ?? kv[0]
			let value = kv.count > 1 ? (kv[1].removingPercentEncoding ?? kv[1]) : ""
			query[key] = value
		}
		return (path, query)
	}

	private func respond(_ connection: Int32, to request: Request) {
		let body = request.method == "PUT" ? putResponseBody : getResponseBody
		let bodyData = Data(body.utf8)
		var response = "HTTP/1.1 200 OK\r\n"
		response += "Content-Type: application/json\r\n"
		response += "Content-Length: \(bodyData.count)\r\n"
		response += "Connection: close\r\n"
		response += "\r\n"

		var out = Data(response.utf8)
		out.append(bodyData)

		#if !canImport(Darwin)
			let flags = Int32(MSG_NOSIGNAL)
		#else
			let flags: Int32 = 0
		#endif
		out.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
			var sent = 0
			while sent < buffer.count {
				let result = send(connection, buffer.baseAddress! + sent, buffer.count - sent, flags)
				if result <= 0 {
					return
				}
				sent += result
			}
		}
	}
}
