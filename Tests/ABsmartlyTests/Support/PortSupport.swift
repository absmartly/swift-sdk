import Foundation
import Testing

@testable import ABsmartly

#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

/// A one-shot latch: `wait()` suspends until `open()` is called (or returns at once after it).
final class ResponseGate: @unchecked Sendable {
	private let lock = NSLock()
	private var opened = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func wait() async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			let resumeNow: Bool = lock.withLock {
				if opened { return true }
				waiters.append(continuation)
				return false
			}
			if resumeNow { continuation.resume() }
		}
	}

	func open() {
		let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
			opened = true
			defer { self.waiters = [] }
			return self.waiters
		}
		for waiter in waiters { waiter.resume() }
	}
}

struct TimedOut: Error {}

/// Runs `operation`, failing with `TimedOut` after `seconds` so a test never waits unboundedly.
func withTimeout<T: Sendable>(
	_ seconds: TimeInterval = 5, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
	try await withThrowingTaskGroup(of: T.self) { group in
		group.addTask { try await operation() }
		group.addTask {
			try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
			throw TimedOut()
		}
		defer { group.cancelAll() }
		return try await group.next()!
	}
}

/// Awaits a typed-throwing SDK call and returns its error, or nil when it succeeded.
/// (The SDK's typed throws guarantee the error is an `ABsmartlyError`; anything else is recorded.)
func sdkError(_ operation: () async throws -> Void) async -> ABsmartlyError? {
	do {
		try await operation()
		return nil
	} catch let error as ABsmartlyError {
		return error
	} catch {
		Issue.record("not an ABsmartlyError: \(error)")
		return nil
	}
}

/// A request as `StubURLProtocol` saw it on the wire side of `URLSession`.
struct CapturedRequest: Sendable {
	let method: String
	let url: URL
	let headers: [String: String]
	let body: Data

	/// Case-insensitive header lookup.
	func header(_ name: String) -> String? {
		headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
	}

	var query: [String: String] {
		var result: [String: String] = [:]
		for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
			result[item.name] = item.value ?? ""
		}
		return result
	}
}

/// A `URLProtocol` that answers every request of a host registered with `register(host:)`, so
/// `URLSessionTransport` runs its real `URLSession` code without a network. Hosts keep parallel
/// tests apart.
final class StubURLProtocol: URLProtocol {
	typealias Handler = @Sendable (CapturedRequest) throws -> (status: Int, body: Data)

	final class Stub: @unchecked Sendable {
		private let lock = NSLock()
		private var _requests: [CapturedRequest] = []
		let handler: Handler

		init(handler: @escaping Handler) { self.handler = handler }

		var requests: [CapturedRequest] { lock.withLock { _requests } }
		func record(_ request: CapturedRequest) { lock.withLock { _requests.append(request) } }
	}

	private static let registry = Locked<[String: Stub]>([:])

	/// Registers a unique host answered by `handler`; returns its base URL and the stub.
	static func register(handler: @escaping Handler) -> (endpoint: URL, stub: Stub) {
		let host = "stub-\(UUID().uuidString.lowercased()).test"
		let stub = Stub(handler: handler)
		registry.withLock { $0[host] = stub }
		return (URL(string: "https://\(host)/v1")!, stub)
	}

	static func session() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [StubURLProtocol.self]
		configuration.timeoutIntervalForRequest = 5
		configuration.timeoutIntervalForResource = 5
		return URLSession(configuration: configuration)
	}

	override class func canInit(with request: URLRequest) -> Bool {
		guard let host = request.url?.host else { return false }
		return registry.withLock { $0[host] } != nil
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		guard let url = request.url, let host = url.host, let stub = Self.registry.withLock({ $0[host] }) else {
			client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
			return
		}
		let captured = CapturedRequest(
			method: request.httpMethod ?? "GET", url: url, headers: request.allHTTPHeaderFields ?? [:],
			body: request.httpBody ?? Self.read(request.httpBodyStream))
		stub.record(captured)
		do {
			let (status, body) = try stub.handler(captured)
			let response = HTTPURLResponse(
				url: url, statusCode: status, httpVersion: "HTTP/1.1",
				headerFields: ["Content-Type": "application/json"])!
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
			client?.urlProtocol(self, didLoad: body)
			client?.urlProtocolDidFinishLoading(self)
		} catch {
			client?.urlProtocol(self, didFailWithError: error)
		}
	}

	override func stopLoading() {}

	private static func read(_ stream: InputStream?) -> Data {
		guard let stream else { return Data() }
		stream.open()
		defer { stream.close() }
		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 4096)
		while stream.hasBytesAvailable {
			let count = stream.read(&buffer, maxLength: buffer.count)
			if count <= 0 { break }
			data.append(buffer, count: count)
		}
		return data
	}
}

/// exp_test_ab with a strict audience and a 0/100 split, so a match gives variant 1 and a mismatch 0.
func strictAudienceContextData(filter: String) throws -> ContextData {
	let json = """
		{"experiments":[{"id":1,"name":"exp_test_ab","iteration":1,"unitType":"session_id","seedHi":3603515,
		"seedLo":233373850,"split":[0.0,1.0],"trafficSeedHi":449867249,"trafficSeedLo":455443629,
		"trafficSplit":[0.0,1.0],"fullOnVariant":0,"variants":[{"name":"A","config":null},{"name":"B","config":"{}"}],
		"audienceStrict":true,"audience":\(String(describing: JSONValue.string("{\"filter\":\(filter)}")))}]}
		"""
	return try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
}
