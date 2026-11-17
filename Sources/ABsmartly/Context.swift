import Foundation

/// A user's view of the experiments: assigns treatments, records exposures and goals, and publishes
/// them to the collector.
///
/// Reads (`treatment(for:)`, `variable(_:default:)`, ...) are synchronous and may be called from any
/// thread, including a SwiftUI `body`. Network work (`ready()`, `refresh()`, `publish()`, `close()`)
/// is `async`. All state is behind one lock; no user code runs while it is held.
///
/// Misuse never crashes: a read before the context is ready, or after it is closed, returns the
/// default and emits an `.error` event, as in 1.x.
public final class Context: Sendable {
	/// The options a context is created with.
	public struct Options: Sendable {
		/// Seconds to wait after an exposure or goal before publishing automatically. A negative value
		/// disables automatic publishing: events are sent by `publish()` and `close()` only.
		public var publishDelay: TimeInterval
		/// Seconds between automatic refreshes of the experiment data; `0` disables them.
		public var refreshInterval: TimeInterval
		/// Receives this context's events; the client's `eventLogger` when nil.
		public var eventLogger: EventLogger?

		public init(publishDelay: TimeInterval = 0.1, refreshInterval: TimeInterval = 0, eventLogger: EventLogger? = nil) {
			self.publishDelay = publishDelay
			self.refreshInterval = refreshInterval
			self.eventLogger = eventLogger
		}
	}

	/// Where the context is in its lifecycle.
	public enum State: Sendable, Equatable {
		/// The experiment data is being fetched.
		case loading
		case ready
		/// The data could not be fetched. Reads return their defaults and no events are published.
		case failed(ABsmartlyError)
		/// `close()` is publishing the remaining events.
		case closing
		case closed
	}

	/// Everything the context reports, in the order it happens.
	public enum Event: Sendable, Equatable {
		case ready(ContextData)
		case refresh(ContextData)
		case publish(PublishEvent)
		case exposure(Exposure)
		case goal(Goal)
		case close
		case error(ABsmartlyError)
	}

	private let storage: Locked<ContextState>
	private let connection: Connection
	private let clock: Clock
	private let publishDelay: TimeInterval
	private let refreshInterval: TimeInterval
	private let logger: EventLogger?

	init(
		connection: Connection, clock: Clock, options: Options, application: String?, environment: String?,
		units: [(String, ContextState.UID)], attributes: [String: JSONValue], overrides: [String: Int],
		customAssignments: [String: Int]
	) {
		self.connection = connection
		self.clock = clock
		publishDelay = options.publishDelay
		refreshInterval = options.refreshInterval
		logger = options.eventLogger

		var initial = ContextState(application: application, environment: environment)
		initial.overrides = overrides
		initial.customAssignments = customAssignments
		let now = clock.millis()
		for (name, value) in attributes.sorted(by: { $0.key < $1.key }) {
			initial.appendAttribute(name, value, at: now)
		}
		var unitErrors: [ABsmartlyError] = []
		for (unitType, uid) in units.sorted(by: { $0.0 < $1.0 }) {
			do {
				try initial.putUnit(unitType, uid)
			} catch {
				unitErrors.append(error)
			}
		}
		storage = Locked(initial)
		for error in unitErrors {
			reportError(error)
		}
	}

	deinit {
		storage.withLock { state in
			state.refreshTimer?.cancel()
			state.publishTimer?.cancel()
			for continuation in state.streams.values {
				continuation.finish()
			}
		}
	}

	// MARK: - Lifecycle

	/// The current lifecycle state.
	public var state: State {
		storage.withLock { state in
			if state.closed { return .closed }
			if state.closing { return .closing }
			if state.failed { return .failed(state.failure ?? .notReady) }
			return state.ready ? .ready : .loading
		}
	}

	/// Returns once the experiment data is loaded; throws the load error if it could not be fetched.
	public func ready() async throws(ABsmartlyError) {
		let result: Result<Void, ABsmartlyError> = await withCheckedContinuation { continuation in
			let settled: Result<Void, ABsmartlyError>? = storage.withLock { state in
				if state.failed {
					return .failure(state.failure ?? .notReady)
				}
				if state.ready {
					return .success(())
				}
				state.readyWaiters.append(continuation)
				return nil
			}
			if let settled {
				continuation.resume(returning: settled)
			}
		}
		try result.get()
	}

	func load(_ fetch: @escaping @Sendable () async throws(ABsmartlyError) -> ContextData) {
		// Holds the context until the fetch settles, so `ready()` always returns.
		Task { [self] in
			do throws(ABsmartlyError) {
				let data = try await fetch()
				install(data, deliverOnMain: true)
			} catch {
				fail(error)
			}
		}
	}

	/// Installs the context's first data. With `deliverOnMain` false (pre-fetched data) the ready
	/// event is delivered synchronously, as in 1.x.
	func install(_ data: ContextData, deliverOnMain: Bool = false) {
		let index = DataIndex(data)
		let waiters = storage.withLock { state in
			state.index = index
			markReady(&state)
			let waiters = state.readyWaiters
			state.readyWaiters = []
			return waiters
		}
		// Ready before delivery, so a logger's ready handler can read the context.
		emit(.ready(data), onMain: deliverOnMain)
		for waiter in waiters {
			waiter.resume(returning: .success(()))
		}
		storage.withLock { state in
			// Goals tracked from inside the ready handler were queued before the context was ready,
			// so their publish timer could not start then.
			if state.pendingCount > 0 {
				schedulePublish(&state)
			}
		}
	}

	private func fail(_ error: ABsmartlyError) {
		storage.withLock { state in
			state.index = .empty
			state.failure = error
		}
		Log.error("Context initialization failed: \(error)")
		// Delivered before the context reports failed, like the JavaScript SDK.
		emitError(error)
		let waiters = storage.withLock { state in
			state.failed = true
			let waiters = state.readyWaiters
			state.readyWaiters = []
			return waiters
		}
		for waiter in waiters {
			waiter.resume(returning: .failure(error))
		}
	}

	private func markReady(_ state: inout ContextState) {
		state.ready = true
		// A refresh that lands after close() must not re-arm the timer close() cleared.
		guard !state.closed, !state.closing, refreshInterval > 0, state.refreshTimer == nil else { return }
		let interval = refreshInterval
		state.refreshTimer = Task { [weak self] in
			while !Task.isCancelled {
				do {
					try await Task.sleep(nanoseconds: Self.nanoseconds(interval))
				} catch {
					return
				}
				guard let self else { return }
				// refresh() already reports a failure as one `.error` event.
				try? await self.refresh()
			}
		}
	}

	/// Fetches the experiment data again. Assignments that the new data does not change are kept.
	/// On a failed context this succeeds without fetching.
	public func refresh() async throws(ABsmartlyError) {
		let claimed: Result<Task<Result<Void, ABsmartlyError>, Never>?, ABsmartlyError> = storage.withLock { state in
			if let error = state.checkNotClosed() {
				return .failure(error)
			}
			if state.failed {
				return .success(nil)
			}
			if let running = state.refreshTask {
				return .success(running)
			}
			// Held strongly until the fetch settles, so the call always returns.
			let task = Task { [self] () -> Result<Void, ABsmartlyError> in
				let result: Result<Void, ABsmartlyError>
				do throws(ABsmartlyError) {
					let data = try await connection.fetchContextData()
					let index = DataIndex(data)
					self.storage.withLock { state in
						state.index = index
						state.refreshTask = nil
						markReady(&state)
					}
					emit(.refresh(data), onMain: true)
					result = .success(())
				} catch {
					self.storage.withLock { $0.refreshTask = nil }
					Log.error("Context refresh failed: \(error)")
					emitError(error)
					result = .failure(error)
				}
				return result
			}
			state.refreshTask = task
			return .success(task)
		}
		let task = try claimed.get()
		try await task?.value.get()
	}

	/// Publishes the pending exposures and goals now. A failed publish keeps them queued.
	public func publish() async throws(ABsmartlyError) {
		if let error = storage.withLock({ $0.checkNotClosed() }) {
			throw error
		}
		try await flush().get()
	}

	/// Publishes what is pending and closes the context. Calling it again returns the same result
	/// while it runs, and returns at once after it succeeded. If the final publish fails, the
	/// context stays open with its events queued, so `publish()` or `close()` can retry.
	public func close() async throws(ABsmartlyError) {
		let task: Task<Result<Void, ABsmartlyError>, Never>? = storage.withLock { state in
			if state.closed || state.closing {
				return state.closeTask
			}
			state.closing = true
			// The task holds the context: once close() starts, the final publish completes even if
			// the caller drops its last reference.
			let task = Task { [self] in await self.runClose() }
			state.closeTask = task
			return task
		}
		try await task?.value.get()
	}

	private func runClose() async -> Result<Void, ABsmartlyError> {
		storage.withLock { state in
			state.refreshTimer?.cancel()
			state.refreshTimer = nil
		}
		// Publishes already in flight finish first (a failed one re-queues its events).
		while let inFlight = storage.withLock({ $0.inFlightPublishes.values.first }) {
			_ = await inFlight.value
		}
		if storage.withLock({ $0.pendingCount }) > 0, case .failure(let error) = await flush() {
			storage.withLock { $0.closing = false }
			return .failure(error)
		}
		let streams = storage.withLock { state in
			state.closed = true
			state.closing = false
			let streams = state.streams
			state.streams = [:]
			return streams
		}
		emit(.close, onMain: true, streams: streams)
		for continuation in streams.values {
			continuation.finish()
		}
		return .success(())
	}

	/// Sends the queued events. A failed context drops them instead.
	private func flush() async -> Result<Void, ABsmartlyError> {
		let now = clock.millis()
		let task: Task<Result<Void, ABsmartlyError>, Never>? = storage.withLock { state in
			state.publishTimer?.cancel()
			state.publishTimer = nil

			if state.failed {
				state.exposures = []
				state.goals = []
				state.pendingCount = 0
				return nil
			}
			guard state.pendingCount > 0 else { return nil }

			let exposures = state.exposures
			let goals = state.goals
			let count = state.pendingCount
			state.exposures = []
			state.goals = []
			state.pendingCount = 0

			let event = PublishEvent(
				hashed: true, units: state.publishUnits(), publishedAt: now, exposures: exposures, goals: goals,
				attributes: state.attributes)
			let id = state.nextPublishID
			state.nextPublishID += 1
			// Registered in the same critical section that drains the queue, so close() never sees an
			// empty queue and no publish in flight.
			let task = Task { [self] in
				await self.send(event, id: id, count: count)
			}
			state.inFlightPublishes[id] = task
			return task
		}
		return await task?.value ?? .success(())
	}

	private func send(_ event: PublishEvent, id: Int, count: Int) async -> Result<Void, ABsmartlyError> {
		let result: Result<Void, ABsmartlyError>
		do {
			try await connection.publish(event)
			emit(.publish(event), onMain: true)
			result = .success(())
		} catch {
			storage.withLock { state in
				state.exposures.insert(contentsOf: event.exposures, at: 0)
				state.goals.insert(contentsOf: event.goals, at: 0)
				state.pendingCount += count
			}
			Log.error("Publish failed: \(error)")
			emitError(error)
			result = .failure(error)
		}
		storage.withLock { $0.inFlightPublishes[id] = nil }
		return result
	}

	private func schedulePublish(_ state: inout ContextState) {
		guard state.isReady, publishDelay >= 0, state.publishTimer == nil else { return }
		let delay = publishDelay
		// Held strongly until it fires, so goals tracked just before the caller drops its last
		// reference are still published.
		state.publishTimer = Task { [self] in
			do {
				try await Task.sleep(nanoseconds: Self.nanoseconds(delay))
			} catch {
				return
			}
			// flush() already reports a failure as one `.error` event.
			_ = await self.flush()
		}
	}

	private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
		UInt64(max(0, min(seconds, 1e9)) * 1_000_000_000)
	}

	/// The number of exposures and goals waiting to be published.
	public var pendingEventCount: Int {
		storage.withLock { $0.pendingCount }
	}

	// MARK: - Treatments and variables

	/// The variant of `experiment` for this context: `0` (control) when the experiment is unknown or
	/// the context is not ready. With `exposing` (the default) the first read queues an exposure.
	public func treatment(for experiment: String, exposing: Bool = true) -> Int {
		// One critical section: the ready check, the lookup and (on first exposure) the queueing. The
		// clock is read only when an exposure is queued.
		let clock = clock
		let result: Result<(Int, Exposure?), ABsmartlyError> = storage.withLock { state in
			if let error = state.checkReady(expectNotClosed: true) {
				return .failure(error)
			}
			if exposing {
				let (assignment, exposure) = state.lookupExposing(experiment, now: clock.millis)
				return .success((assignment.variant, exposure))
			}
			return .success((state.lookup(experiment).variant, nil))
		}
		switch result {
		case .failure(let error):
			reportError(error)
			return 0
		case .success((let variant, let exposure)):
			if let exposure {
				didQueue(.exposure(exposure))
			}
			return variant
		}
	}

	/// The variant as a case of `variants`, or `nil` when it has no case for the variant number.
	public func treatment<Variant: RawRepresentable>(
		for experiment: String, as variants: Variant.Type, exposing: Bool = true
	) -> Variant? where Variant.RawValue == Int {
		Variant(rawValue: treatment(for: experiment, exposing: exposing))
	}

	/// Whether the variant of `experiment` is not the control (`0`). Queues an exposure like `treatment(for:)`.
	public func isInTreatment(_ experiment: String, exposing: Bool = true) -> Bool {
		treatment(for: experiment, exposing: exposing) != 0
	}

	/// The value of a variable in the variant this context is assigned to, or `nil` when no running
	/// experiment defines it. With `exposing` (the default) the experiments read are exposed.
	public func variableValue(_ key: String, exposing: Bool = true) -> JSONValue? {
		let clock = clock
		let result: Result<(JSONValue?, [Exposure]), ABsmartlyError> = storage.withLock { state in
			if let error = state.checkReady(expectNotClosed: true) {
				return .failure(error)
			}
			return .success(state.variableValue(key, peek: !exposing, now: clock.millis))
		}
		switch result {
		case .failure(let error):
			reportError(error)
			return nil
		case .success((let value, let exposures)):
			for exposure in exposures {
				didQueue(.exposure(exposure))
			}
			return value
		}
	}

	/// The value of a variable decoded as `T`, or `defaultValue` when no running experiment defines it
	/// or it does not decode as `T`.
	public func variable<T: Decodable & Sendable>(_ key: String, default defaultValue: T, exposing: Bool = true) -> T {
		guard let value = variableValue(key, exposing: exposing) else { return defaultValue }
		return value.decode(T.self) ?? defaultValue
	}

	/// For each variable key, the names of the experiments that define it, by ascending experiment id.
	public var variableKeys: [String: [String]] {
		guard ensureReady(expectNotClosed: true) else { return [:] }
		return storage.withLock { $0.index.variableExperiments.mapValues { $0.map(\.data.name) } }
	}

	/// The names of the experiments in the context data.
	public var experiments: [String] {
		guard ensureReady(expectNotClosed: false) else { return [] }
		return storage.withLock { $0.index.data.experiments.map(\.name) }
	}

	/// The experiment data the context uses: empty when loading it failed, `nil` before it is ready.
	public var contextData: ContextData? {
		guard ensureReady(expectNotClosed: false) else { return nil }
		return storage.withLock { $0.index.data }
	}

	// MARK: - Custom fields

	/// A custom field of an experiment, typed by its field type: `json` fields parsed, `number`
	/// fields numbers, `boolean` fields `true` only for `"true"`, anything else text.
	public func customFieldValue(_ key: String, in experiment: String) -> JSONValue? {
		guard ensureReady(expectNotClosed: true) else { return nil }
		return storage.withLock { $0.index.experiments[experiment]?.customFields[key]?.value }
	}

	/// The type of a custom field (`"json"`, `"number"`, `"boolean"`, `"text"`, ...).
	public func customFieldType(_ key: String, in experiment: String) -> String? {
		guard ensureReady(expectNotClosed: true) else { return nil }
		return storage.withLock { $0.index.experiments[experiment]?.customFields[key]?.type }
	}

	/// The custom field names of an experiment.
	public func customFieldKeys(in experiment: String) -> [String] {
		guard ensureReady(expectNotClosed: true) else { return [] }
		return storage.withLock { $0.index.experiments[experiment].map { Array($0.customFields.keys) } ?? [] }
	}

	/// The custom field names of every experiment.
	public var customFieldKeys: Set<String> {
		guard ensureReady(expectNotClosed: true) else { return [] }
		return storage.withLock { state in
			Set(state.index.data.experiments.flatMap { $0.customFieldValues.compactMap(\.name) })
		}
	}

	// MARK: - Units, attributes, overrides

	/// Sets the UID of a unit type. Throws (and emits an `.error` event) when the UID is blank, when
	/// a different UID is already set for the type, or when the context is closed; the unit is then
	/// left unchanged.
	public func setUnit(_ unitType: UnitType, to uid: String) throws(ABsmartlyError) {
		try putUnit(unitType.rawValue, .string(uid))
	}

	/// Sets a numeric UID. It is hashed like the JavaScript SDK does, as the number rounded to an
	/// integer (`toFixed(0)`), and `unitValues` keeps the number.
	public func setUnit(_ unitType: UnitType, to uid: Int) throws(ABsmartlyError) {
		try putUnit(unitType.rawValue, .number(.int(Int64(uid))))
	}

	/// Sets a numeric UID; see `setUnit(_:to:)` for `Int`.
	public func setUnit(_ unitType: UnitType, to uid: Double) throws(ABsmartlyError) {
		try putUnit(unitType.rawValue, .number(.double(uid)))
	}

	/// Sets several string UIDs; stops at the first that fails.
	public func setUnits(_ units: [UnitType: String]) throws(ABsmartlyError) {
		for (unitType, uid) in units.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
			try setUnit(unitType, to: uid)
		}
	}

	private func putUnit(_ unitType: String, _ uid: ContextState.UID) throws(ABsmartlyError) {
		let error: ABsmartlyError? = storage.withLock { state -> ABsmartlyError? in
			if let error = state.checkNotClosed() {
				return error
			}
			do throws(ABsmartlyError) {
				try state.putUnit(unitType, uid)
				return nil
			} catch {
				return error
			}
		}
		if let error {
			reportError(error)
			throw error
		}
	}

	/// The UID of each unit type, as text (numeric UIDs in their shortest form).
	public var units: [UnitType: String] {
		storage.withLock { state in
			Dictionary(uniqueKeysWithValues: state.unitValues.map { (UnitType($0.key), $0.value.uidString) })
		}
	}

	/// The UID of each unit type as it was set: a string or a number.
	public var unitValues: [UnitType: JSONValue] {
		storage.withLock { state in
			Dictionary(uniqueKeysWithValues: state.unitValues.map { (UnitType($0.key), $0.value) })
		}
	}

	/// Sets an attribute for audiences and assignment rules. Every value set is published with the
	/// time it was set. Ignored (with an `.error` event) after the context is closed.
	public func setAttribute(_ name: String, to value: some JSONValueConvertible) {
		guard ensureNotClosed() else { return }
		let now = clock.millis()
		let jsonValue = value.jsonValue
		storage.withLock { $0.appendAttribute(name, jsonValue, at: now) }
	}

	/// Sets several attributes, in key order.
	public func setAttributes(_ attributes: [String: JSONValue]) {
		for (name, value) in attributes.sorted(by: { $0.key < $1.key }) {
			setAttribute(name, to: value)
		}
	}

	/// The latest value of each attribute set on this context.
	public var attributes: [String: JSONValue] {
		storage.withLock { state in
			var result: [String: JSONValue] = [:]
			for attribute in state.attributes {
				result[attribute.name] = attribute.value
			}
			return result
		}
	}

	/// The latest value of an attribute set on this context.
	public func attribute(_ name: String) -> JSONValue? {
		storage.withLock { state in state.attributes.last(where: { $0.name == name })?.value }
	}

	/// The variant to serve for each experiment, regardless of its assignment. An override is never
	/// counted as assigned. Set one with `overrides["exp"] = 1`, remove it with `overrides["exp"] = nil`.
	public var overrides: [String: Int] {
		get { storage.withLock { $0.overrides } }
		// A plain setter, not `_modify`: the caller's expression (which may read this context, e.g.
		// `overrides["a", default: context.treatment(for: "b")] += 1`) runs before the lock is taken.
		set { storage.withLock { $0.overrides = newValue } }
	}

	/// Sets several overrides at once.
	public func setOverrides(_ overrides: [String: Int]) {
		storage.withLock { $0.overrides.merge(overrides) { _, new in new } }
	}

	/// The variant to assign for each experiment when the unit is eligible, instead of the hashed one.
	public var customAssignments: [String: Int] {
		get { storage.withLock { $0.customAssignments } }
		set { storage.withLock { $0.customAssignments = newValue } }
	}

	/// Sets several custom assignments at once.
	public func setCustomAssignments(_ assignments: [String: Int]) {
		storage.withLock { $0.customAssignments.merge(assignments) { _, new in new } }
	}

	// MARK: - Goals

	/// Records a goal achievement. Ignored (with an `.error` event) after the context is closed.
	public func track(_ goal: String, properties: [String: JSONValue]? = nil) {
		guard ensureNotClosed() else { return }
		let achievement = Goal(name: goal, achievedAt: clock.millis(), properties: properties)
		storage.withLock { state in
			state.goals.append(achievement)
			state.pendingCount += 1
		}
		didQueue(.goal(achievement))
	}

	// MARK: - Events

	/// A stream of this context's events from now on. Each access returns a new stream; every stream
	/// finishes after the `close` event. After close, the stream is already finished.
	public var events: AsyncStream<Event> {
		let (stream, continuation) = AsyncStream<Event>.makeStream()
		let id: Int? = storage.withLock { state in
			if state.closed {
				return nil
			}
			let id = state.nextStreamID
			state.nextStreamID += 1
			state.streams[id] = continuation
			return id
		}
		guard let id else {
			continuation.finish()
			return stream
		}
		continuation.onTermination = { [weak self] _ in
			_ = self?.storage.withLock { $0.streams.removeValue(forKey: id) }
		}
		return stream
	}

	// Delivers an exposure or goal just queued, then starts the publish timer.
	private func didQueue(_ event: Event) {
		emit(event, onMain: false)
		storage.withLock { schedulePublish(&$0) }
	}

	// Streams see every event at once, in order. The logger sees `ready`/`refresh`/`publish`/`close`
	// on the main thread on Apple platforms (`onMain`), as in 1.x, without the work waiting for it.
	private func emit(_ event: Event, onMain: Bool, streams: [Int: AsyncStream<Event>.Continuation]? = nil) {
		let streams = streams ?? storage.withLock { $0.streams }
		for continuation in streams.values {
			continuation.yield(event)
		}
		guard let logger else { return }
		if onMain && Self.deliversEventsOnMainThread && !Thread.isMainThread {
			DispatchQueue.main.async { logger.handle(self, event) }
		} else {
			logger.handle(self, event)
		}
	}

	#if canImport(Darwin)
		private static let mainThreadDelivery = Locked(true)
	#else
		// On Linux nothing may service the main queue.
		private static let mainThreadDelivery = Locked(false)
	#endif

	/// Test hook: whether lifecycle events reach the logger on the main thread.
	static var deliversEventsOnMainThread: Bool {
		get { mainThreadDelivery.withLock { $0 } }
		set { mainThreadDelivery.withLock { $0 = newValue } }
	}

	// MARK: - Errors

	private func ensureReady(expectNotClosed: Bool) -> Bool {
		guard let error = storage.withLock({ $0.checkReady(expectNotClosed: expectNotClosed) }) else { return true }
		reportError(error)
		return false
	}

	private func ensureNotClosed() -> Bool {
		guard let error = storage.withLock({ $0.checkNotClosed() }) else { return true }
		reportError(error)
		return false
	}

	private func reportError(_ error: ABsmartlyError) {
		Log.error(error.description)
		emitError(error)
	}

	// An error raised while this context is already delivering `.error` on the same thread (e.g. a
	// logger reading a value from its error handler before the context is ready) is not delivered
	// again, which would recurse without bound; it has already gone to the SDK log.
	private func emitError(_ error: ABsmartlyError) {
		let key = "com.absmartly.Context.deliveringError.\(ObjectIdentifier(self).hashValue)"
		let threadDictionary = Thread.current.threadDictionary
		if threadDictionary[key] != nil {
			return
		}
		threadDictionary[key] = true
		defer { threadDictionary.removeObject(forKey: key) }
		emit(.error(error), onMain: false)
	}
}

extension Context.State {
	/// Whether loading finished, successfully or not (1.x's `isReady()`).
	public var isSettled: Bool {
		switch self {
		case .loading: return false
		default: return true
		}
	}
}

extension JSONValue {
	// A UID as text: strings as given, numbers in their shortest form ("125", "125.75").
	var uidString: String {
		switch self {
		case .string(let string): return string
		case .int(let value): return String(value)
		case .double(let value):
			if let int = Int64(exactly: value), Swift.abs(value) < 1e15 { return String(int) }
			return "\(value)"
		default: return description
		}
	}

	/// Decodes the value as `T`: directly for the scalar types and `JSONValue`, else through `Codable`.
	func decode<T: Decodable>(_ type: T.Type) -> T? {
		switch T.self {
		case is JSONValue.Type: return self as? T
		case is String.Type: return stringValue as? T
		case is Bool.Type: return boolValue as? T
		case is Int.Type: return intValue as? T
		case is Double.Type: return doubleValue as? T
		default:
			guard let data = try? JSONEncoder().encode(self) else { return nil }
			return try? JSONDecoder().decode(T.self, from: data)
		}
	}
}

extension Context {
	/// Test hook: how many times cached assignments were re-evaluated against their rules/audience.
	var revalidationCount: Int {
		storage.withLock { $0.revalidations }
	}
}
