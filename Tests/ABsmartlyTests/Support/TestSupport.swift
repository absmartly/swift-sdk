import Foundation
import Testing

@testable import ABsmartly

/// A transport that serves context data and records every request, without a network.
final class FakeTransport: Transport, @unchecked Sendable {
	private let lock = NSLock()
	private var _requests: [HTTPRequest] = []
	private var _responses: [(HTTPRequest) async throws -> HTTPResponse] = []
	var contextData: Data
	var defaultPublishStatus = 200

	init(contextData: Data = Data(#"{"experiments":[]}"#.utf8)) {
		self.contextData = contextData
	}

	var requests: [HTTPRequest] {
		lock.withLock { _requests }
	}

	var publishes: [HTTPRequest] {
		requests.filter { $0.method == "PUT" }
	}

	/// The decoded JSON body of every publish.
	var publishedBodies: [JSONValue] {
		publishes.compactMap { $0.body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } }
	}

	/// Queues a one-shot handler for the next request.
	func enqueue(_ handler: @escaping (HTTPRequest) async throws -> HTTPResponse) {
		lock.withLock { _responses.append(handler) }
	}

	func enqueue(status: Int, body: Data = Data()) {
		enqueue { _ in HTTPResponse(statusCode: status, body: body) }
	}

	func send(_ request: HTTPRequest) async throws -> HTTPResponse {
		let handler: ((HTTPRequest) async throws -> HTTPResponse)? = lock.withLock {
			_requests.append(request)
			return _responses.isEmpty ? nil : _responses.removeFirst()
		}
		if let handler {
			return try await handler(request)
		}
		if request.method == "GET" {
			return HTTPResponse(statusCode: 200, body: contextData)
		}
		return HTTPResponse(statusCode: defaultPublishStatus, body: Data("{}".utf8))
	}
}

struct FixedClock: Clock {
	let value: Int64
	func millis() -> Int64 { value }
}

final class MutableClock: Clock, @unchecked Sendable {
	private let lock = NSLock()
	private var value: Int64
	init(_ value: Int64) { self.value = value }
	func millis() -> Int64 { lock.withLock { value } }
	func set(_ newValue: Int64) { lock.withLock { value = newValue } }
}

/// Records every event a logger receives, in order.
final class EventRecorder: @unchecked Sendable {
	private let lock = NSLock()
	private var _events: [Context.Event] = []

	var logger: EventLogger {
		EventLogger { [self] _, event in lock.withLock { _events.append(event) } }
	}

	var events: [Context.Event] { lock.withLock { _events } }

	var errors: [ABsmartlyError] {
		events.compactMap { if case .error(let e) = $0 { return e } else { return nil } }
	}

	var exposures: [Exposure] {
		events.compactMap { if case .exposure(let e) = $0 { return e } else { return nil } }
	}

	var goals: [Goal] {
		events.compactMap { if case .goal(let e) = $0 { return e } else { return nil } }
	}

	func clear() { lock.withLock { _events = [] } }
}

enum Fixtures {
	static let resources: URL = {
		#if canImport(FoundationNetworking)
			return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
				.appendingPathComponent("Resources")
		#else
			// `.copy("Resources")` puts the directory itself in the bundle; fall back to the bundle root
			// in case a toolchain flattens it.
			let bundle = Bundle.module
			if let directory = bundle.url(forResource: "Resources", withExtension: nil) {
				return directory
			}
			return bundle.resourceURL ?? bundle.bundleURL
		#endif
	}()

	static func data(_ name: String) -> Data {
		try! Data(contentsOf: resources.appendingPathComponent(name + ".json"))
	}

	static func contextData(_ name: String = "context") -> ContextData {
		try! JSONDecoder().decode(ContextData.self, from: data(name))
	}

	static let units: [UnitType: String] = [
		"email": "bleh@absmartly.com",
		.sessionID: "e791e240fcd3df7d238cfc285f475e8152fcc0ec",
		.userID: "123456789",
	]

	static let now: Int64 = 1_620_000_000_000
}

/// Builds clients and contexts around a `FakeTransport`, a fixed clock and an `EventRecorder`, with
/// lifecycle events delivered synchronously so tests can assert them right away.
struct Harness {
	let transport: FakeTransport
	let recorder = EventRecorder()
	let clock: Clock
	let client: ABsmartlyClient

	init(
		contextData: Data = Fixtures.data("context"), clock: Clock = FixedClock(value: Fixtures.now),
		application: String = "website", environment: ABsmartlyClient.Environment = "production",
		retries: Int = 0, configure: (inout ABsmartlyClient.Configuration) -> Void = { _ in }
	) {
		Context.deliversEventsOnMainThread = false
		transport = FakeTransport(contextData: contextData)
		self.clock = clock
		var configuration = ABsmartlyClient.Configuration(
			endpoint: URL(string: "https://test.absmartly.io/v1")!, apiKey: "test-api-key",
			application: application, environment: environment)
		configuration.transport = transport
		configuration.retries = retries
		configuration.retryInterval = 0
		configuration.eventLogger = recorder.logger
		configuration.defaultContextOptions = Context.Options(publishDelay: -1)
		configure(&configuration)
		client = try! ABsmartlyClient(configuration: configuration, clock: clock)
	}

	/// A ready context from the given fixture (pre-fetched path).
	func context(
		_ fixture: String = "context", units: [UnitType: String] = Fixtures.units, attributes: [String: JSONValue] = [:],
		overrides: [String: Int] = [:], customAssignments: [String: Int] = [:], options: Context.Options? = nil
	) -> Context {
		client.context(
			units: units, attributes: attributes, overrides: overrides, customAssignments: customAssignments,
			options: options, data: Fixtures.contextData(fixture))
	}

	func context(
		data: ContextData, units: [UnitType: String] = Fixtures.units, attributes: [String: JSONValue] = [:],
		options: Context.Options? = nil
	) -> Context {
		client.context(units: units, attributes: attributes, options: options, data: data)
	}
}

/// Polls `condition` every millisecond for up to `timeout` seconds.
func eventually(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
	let deadline = Date().addingTimeInterval(timeout)
	while Date() < deadline {
		if condition() { return true }
		try? await Task.sleep(nanoseconds: 1_000_000)
	}
	return condition()
}
