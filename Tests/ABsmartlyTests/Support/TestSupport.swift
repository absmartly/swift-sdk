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

/// A clock whose time stands still: timestamps are `value`, and a timer with a positive delay never
/// fires (a zero delay fires at once, as `Task.sleep(0)` does). Tests that exercise a timer use
/// `TestClock`.
struct FixedClock: Clock {
	let value: Int64
	func millis() -> Int64 { value }
	func sleep(seconds: TimeInterval) async throws {
		try await TestClock.sleepZeroOrForever(seconds)
	}
}

/// A fixed clock that can block the next `millis()` read until resumed, to stop a caller at the
/// point where it reads the time (e.g. between `track()`'s check and its queueing).
final class PausingClock: Clock, @unchecked Sendable {
	private let lock = NSLock()
	private var pauseNext = false
	private var paused = false
	private let resumed = DispatchSemaphore(value: 0)

	func pauseNextRead() { lock.withLock { pauseNext = true } }
	var isPaused: Bool { lock.withLock { paused } }
	func resume() { resumed.signal() }

	func millis() -> Int64 {
		let pause: Bool = lock.withLock {
			guard pauseNext else { return false }
			pauseNext = false
			paused = true
			return true
		}
		if pause {
			resumed.wait()
			lock.withLock { paused = false }
		}
		return Fixtures.now
	}

	func sleep(seconds: TimeInterval) async throws {
		try await TestClock.sleepZeroOrForever(seconds)
	}
}

/// A manual clock for the publish and refresh timers: a timer sleeps until the test advances the
/// clock past its deadline, so timer tests need no wall-clock waits. Timestamps stay `millis`.
final class TestClock: Clock, @unchecked Sendable {
	private struct Sleeper {
		let id: Int
		let deadline: TimeInterval
		let continuation: CheckedContinuation<Void, any Error>
	}

	private let lock = NSLock()
	private let fixedMillis: Int64
	private var now: TimeInterval = 0
	private var nextID = 0
	private var sleepers: [Sleeper] = []

	init(millis: Int64 = Fixtures.now) { fixedMillis = millis }

	func millis() -> Int64 { fixedMillis }

	/// The number of timers currently waiting.
	var sleeperCount: Int { lock.withLock { sleepers.count } }

	func sleep(seconds: TimeInterval) async throws {
		if seconds <= 0 {
			try Task.checkCancellation()
			return
		}
		let id = lock.withLock { () -> Int in
			nextID += 1
			return nextID
		}
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
				let resumeNow: Bool = lock.withLock {
					if Task.isCancelled { return true }
					sleepers.append(Sleeper(id: id, deadline: now + max(0, seconds), continuation: continuation))
					return false
				}
				if resumeNow { continuation.resume(throwing: CancellationError()) }
			}
		} onCancel: {
			let sleeper: Sleeper? = lock.withLock {
				guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
				return sleepers.remove(at: index)
			}
			sleeper?.continuation.resume(throwing: CancellationError())
		}
	}

	/// Moves time forward by `seconds`, waking every timer whose deadline has passed.
	func advance(by seconds: TimeInterval) {
		let due: [Sleeper] = lock.withLock {
			now += seconds
			let due = sleepers.filter { $0.deadline <= now }
			sleepers.removeAll { $0.deadline <= now }
			return due
		}
		for sleeper in due {
			sleeper.continuation.resume()
		}
	}

	/// Waits until `count` timers are sleeping (they start asynchronously).
	func waitForSleepers(_ count: Int = 1, timeout: TimeInterval = 5) async -> Bool {
		await eventually(timeout: timeout) { sleeperCount >= count }
	}

	/// A zero delay returns at once; any other suspends until the task is cancelled.
	static func sleepZeroOrForever(_ seconds: TimeInterval) async throws {
		try await TestClock().sleep(seconds: seconds <= 0 ? 0 : .infinity)
	}
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
		_ fixture: String = "context", units: [UnitType: String] = Fixtures.units,
		attributes: [String: JSONValue] = [:],
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
