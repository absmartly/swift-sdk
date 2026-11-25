import Foundation
import Testing

@testable import ABsmartly

/// An error with a fixed message, thrown by test transports. The SDK reports it as
/// `.transport(message)`.
struct TestError: LocalizedError {
	let message: String
	init(_ message: String) { self.message = message }
	var errorDescription: String? { message }
}

/// A value shared with `@Sendable` closures (logger hooks, transport handlers).
final class Box<Value>: @unchecked Sendable {
	private let lock = NSLock()
	private var _value: Value
	init(_ value: Value) { _value = value }
	var value: Value {
		get { lock.withLock { _value } }
		set { lock.withLock { _value = newValue } }
	}
	func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&_value) } }
}

/// A one-shot result that async code can wait for, settled later by the test.
final class Gate<Value: Sendable>: @unchecked Sendable {
	private let lock = NSLock()
	private var result: Result<Value, any Error>?
	private var waiters: [CheckedContinuation<Value, any Error>] = []

	func wait() async throws -> Value {
		try await withCheckedThrowingContinuation { continuation in
			let settled: Result<Value, any Error>? = lock.withLock {
				if result == nil { waiters.append(continuation) }
				return result
			}
			if let settled { continuation.resume(with: settled) }
		}
	}

	func resolve(_ value: Result<Value, any Error>) {
		let waiting: [CheckedContinuation<Value, any Error>] = lock.withLock {
			guard result == nil else { return [] }
			result = value
			defer { waiters = [] }
			return waiters
		}
		for waiter in waiting { waiter.resume(with: value) }
	}

	func fulfill(_ value: Value) { resolve(.success(value)) }
	func reject(_ error: any Error) { resolve(.failure(error)) }
}

extension Gate where Value == HTTPResponse {
	func fulfill(data: Data) { fulfill(HTTPResponse(statusCode: 200, body: data)) }
	func fulfill(fixture: String) { fulfill(data: Fixtures.data(fixture)) }
	func fulfill(contextData: ContextData) { fulfill(data: try! JSONEncoder().encode(contextData)) }
}

/// A recording event logger: every event with the context it was for, plus an optional hook
/// called outside the lock.
final class LoggedEvents: @unchecked Sendable {
	private let lock = NSLock()
	private var entries: [(context: ObjectIdentifier, event: Context.Event)] = []
	private var _hook: (@Sendable (Context, Context.Event) -> Void)?

	var logger: EventLogger {
		EventLogger { [self] context, event in
			let hook = lock.withLock {
				entries.append((ObjectIdentifier(context), event))
				return _hook
			}
			hook?(context, event)
		}
	}

	func setHook(_ hook: (@Sendable (Context, Context.Event) -> Void)?) { lock.withLock { _hook = hook } }

	var events: [Context.Event] { lock.withLock { entries.map(\.event) } }
	var contexts: [ObjectIdentifier] { lock.withLock { entries.map(\.context) } }
	var count: Int { lock.withLock { entries.count } }
	var last: Context.Event? { events.last }

	var exposures: [Exposure] {
		events.compactMap { if case .exposure(let e) = $0 { return e } else { return nil } }
	}

	var goals: [Goal] {
		events.compactMap { if case .goal(let g) = $0 { return g } else { return nil } }
	}

	var errors: [ABsmartlyError] {
		events.compactMap { if case .error(let e) = $0 { return e } else { return nil } }
	}

	var errorMessages: [String] { errors.map(\.description) }

	var publishes: [PublishEvent] {
		events.compactMap { if case .publish(let p) = $0 { return p } else { return nil } }
	}

	/// Forgets the events recorded so far.
	func clear() { lock.withLock { entries = [] } }
}

/// The context test fixture: a `Harness` (fake transport, fixed clock) whose logger is a
/// `LoggedEvents`, and helpers to create ready, loading and failed contexts.
struct ContextEnv {
	let harness: Harness
	let log = LoggedEvents()

	init(
		retries: Int = 0, options: Context.Options = Context.Options(publishDelay: -1),
		clock: Clock = FixedClock(value: Fixtures.now)
	) {
		let log = log
		harness = Harness(clock: clock, retries: retries) { configuration in
			configuration.eventLogger = log.logger
			configuration.defaultContextOptions = options
		}
	}

	var transport: FakeTransport { harness.transport }
	var client: ABsmartlyClient { harness.client }
	var now: Int64 { Fixtures.now }

	/// A context created ready from fixture data.
	func context(
		_ fixture: String = "context", units: [UnitType: String] = Fixtures.units,
		attributes: [String: JSONValue] = [:],
		overrides: [String: Int] = [:], customAssignments: [String: Int] = [:], options: Context.Options? = nil
	) -> Context {
		context(
			data: Fixtures.contextData(fixture), units: units, attributes: attributes, overrides: overrides,
			customAssignments: customAssignments, options: options)
	}

	func context(
		data: ContextData, units: [UnitType: String] = Fixtures.units, attributes: [String: JSONValue] = [:],
		overrides: [String: Int] = [:], customAssignments: [String: Int] = [:], options: Context.Options? = nil
	) -> Context {
		client.context(
			units: units, attributes: attributes, overrides: overrides, customAssignments: customAssignments,
			options: options, data: data)
	}

	/// A context whose data is fetched through a GET the test settles later.
	/// Returns once that GET is in flight, so later requests do not race it for the gated response.
	func loadingContext(
		units: [UnitType: String] = Fixtures.units, attributes: [String: JSONValue] = [:],
		overrides: [String: Int] = [:], options: Context.Options? = nil
	) async -> (Context, Gate<HTTPResponse>) {
		let gate = pendingRequest()
		let before = getCount
		let context = client.makeContext(units: units, attributes: attributes, overrides: overrides, options: options)
		_ = await eventually(timeout: 5) { getCount > before }
		return (context, gate)
	}

	/// A context whose data load fails with `message`. Returns once it failed.
	func failedContext(_ message: String = "test", units: [UnitType: String] = Fixtures.units) async -> Context {
		transport.enqueue { _ in throw TestError(message) }
		let context = client.makeContext(units: units)
		try? await context.ready()
		return context
	}

	/// The next request waits for the returned gate.
	func pendingRequest() -> Gate<HTTPResponse> {
		let gate = Gate<HTTPResponse>()
		transport.enqueue { _ in try await gate.wait() }
		return gate
	}

	/// The next request fails without a response.
	func failNextRequest(_ message: String = "test") {
		transport.enqueue { _ in throw TestError(message) }
	}

	/// The next GET serves `fixture`.
	func serveNext(_ fixture: String) {
		transport.enqueue(status: 200, body: Fixtures.data(fixture))
	}

	func serveNext(_ data: ContextData) {
		transport.enqueue(status: 200, body: try! JSONEncoder().encode(data))
	}

	/// Creates a context directly, with any application and environment names, including none (the
	/// client requires both).
	func directContext(
		data: ContextData, units: [UnitType: String] = Fixtures.units, attributes: [String: JSONValue] = [:],
		overrides: [String: Int] = [:], customAssignments: [String: Int] = [:], application: String? = "website",
		environment: String? = "production"
	) -> Context {
		var options = client.configuration.defaultContextOptions
		options.eventLogger = client.configuration.eventLogger
		let context = Context(
			connection: client.connection, clock: harness.clock, options: options, application: application,
			environment: environment, units: units.map { ($0.key.rawValue, ContextState.UID.string($0.value)) },
			attributes: attributes, overrides: overrides, customAssignments: customAssignments)
		context.install(data)
		return context
	}

	var getCount: Int { transport.requests.filter { $0.method == "GET" }.count }
	var publishCount: Int { transport.publishes.count }

	/// The decoded bodies of every publish, normalised (units and attributes sorted).
	var sentEvents: [JSONValue] { transport.publishedBodies.map(normalized) }
	var lastSentEvent: JSONValue? { sentEvents.last }
}

/// An exposure from positional arguments, at the fixture time.
func exposure(
	_ id: Int, _ name: String, _ unit: String?, _ variant: Int, _ assigned: Bool, _ eligible: Bool, _ overridden: Bool,
	_ fullOn: Bool, _ custom: Bool, _ audienceMismatch: Bool, ruleOverride: Bool = false, at time: Int64 = Fixtures.now
) -> Exposure {
	Exposure(
		id: id, name: name, unit: unit, variant: variant, exposedAt: time, assigned: assigned, eligible: eligible,
		overridden: overridden, fullOn: fullOn, custom: custom, audienceMismatch: audienceMismatch,
		ruleOverride: ruleOverride)
}

func goal(_ name: String, _ properties: [String: JSONValue]?, at time: Int64 = Fixtures.now) -> Goal {
	Goal(name: name, achievedAt: time, properties: properties)
}

func attribute(_ name: String, _ value: JSONValue, at time: Int64 = Fixtures.now) -> PublishEvent.Attribute {
	PublishEvent.Attribute(name: name, value: value, setAt: time)
}

/// The fixture units as published (UIDs hashed).
let fixturePublishUnits: [PublishEvent.Unit] = [
	PublishEvent.Unit(type: "email", uid: "IuqYkNRfEx5yClel4j3NbA"),
	PublishEvent.Unit(type: "session_id", uid: "pAE3a1i5Drs5mKRNq56adA"),
	PublishEvent.Unit(type: "user_id", uid: "JfnnlDI7RTiF9RgfG2JNCw"),
]

/// The expected publish body, as the JSON the SDK sends, normalised like `sentEvents`.
func expectedBody(
	units: [PublishEvent.Unit] = fixturePublishUnits, exposures: [Exposure] = [], goals: [Goal] = [],
	attributes: [PublishEvent.Attribute] = [], publishedAt: Int64 = Fixtures.now
) -> JSONValue {
	let event = PublishEvent(
		hashed: true, units: units, publishedAt: publishedAt, exposures: exposures, goals: goals, attributes: attributes
	)
	return normalized(try! JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(event)))
}

/// Sorts a publish body's units by type and attributes by name then time, so array equality works.
func normalized(_ body: JSONValue) -> JSONValue {
	guard case .object(var object) = body else { return body }
	if case .array(let units)? = object["units"] {
		object["units"] = .array(units.sorted { ($0["type"]?.stringValue ?? "") < ($1["type"]?.stringValue ?? "") })
	}
	if case .array(let attributes)? = object["attributes"] {
		object["attributes"] = .array(
			attributes.sorted {
				let (l, r) = ($0["name"]?.stringValue ?? "", $1["name"]?.stringValue ?? "")
				return l != r ? l < r : ($0["setAt"]?.intValue ?? 0) < ($1["setAt"]?.intValue ?? 0)
			})
	}
	return .object(object)
}

/// A publish event with its units and attributes sorted, to compare logged events.
func sorted(_ event: PublishEvent) -> PublishEvent {
	var event = event
	event.units.sort { $0.type < $1.type }
	event.attributes.sort { $0.name != $1.name ? $0.name < $1.name : $0.setAt < $1.setAt }
	return event
}

/// The hash a unit UID is published with.
func unitHash(_ uid: String) -> String {
	String(decoding: Hashing.hashUnit(uid), as: UTF8.self)
}

/// Waits a bounded time (for asserting that something does *not* happen).
func pause(_ seconds: TimeInterval) async {
	try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

enum ContextFixtures {
	static let expectedVariants: [String: Int] = [
		"exp_test_ab": 1,
		"exp_test_abc": 2,
		"exp_test_not_eligible": 0,
		"exp_test_fullon": 2,
		"exp_test_new": 1,
	]

	static let variableExperiments: [String: [String]] = [
		"banner.border": ["exp_test_ab"],
		"banner.size": ["exp_test_ab"],
		"button.color": ["exp_test_abc"],
		"card.width": ["exp_test_not_eligible"],
		"submit.color": ["exp_test_fullon"],
		"submit.shape": ["exp_test_fullon"],
		"show-modal": ["exp_test_new"],
	]

	static let expectedVariables: [String: JSONValue] = [
		"banner.border": 1,
		"banner.size": "large",
		"button.color": "red",
		"submit.color": "blue",
		"submit.shape": "rect",
		"show-modal": true,
	]

	static func decode(_ json: String) -> ContextData {
		try! JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
	}
}
