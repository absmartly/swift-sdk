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

		public init(
			publishDelay: TimeInterval = 0.1, refreshInterval: TimeInterval = 0, eventLogger: EventLogger? = nil
		) {
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
	/// Every caller gets the same result: when a `refresh()` overlaps the first fetch, whichever
	/// settles first decides.
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

	/// Fetches the first data. A refresh that completes first makes the context ready instead, and
	/// this fetch's late result (data or error) is then ignored, so every `ready()` caller gets the
	/// same result.
	func load(_ fetch: @escaping @Sendable () async throws(ABsmartlyError) -> ContextData) {
		// Holds the context until the fetch settles, so `ready()` always returns.
		Task { [self] in
			do throws(ABsmartlyError) {
				let data = try await fetch()
				install(data, deliverOnMain: true, onlyWhileLoading: true)
			} catch {
				fail(error)
			}
		}
	}

	/// Installs the context's first data. With `deliverOnMain` false (pre-fetched data) the ready
	/// event is delivered synchronously, as in 1.x.
	func install(_ data: ContextData, deliverOnMain: Bool = false, onlyWhileLoading: Bool = false) {
		let index = DataIndex(data)
		let waiters: [CheckedContinuation<Result<Void, ABsmartlyError>, Never>]? = storage.withLock { state in
			if onlyWhileLoading && state.isReady {
				return nil
			}
			state.install(index)
			markReady(&state)
			let waiters = state.readyWaiters
			state.readyWaiters = []
			return waiters
		}
		guard let waiters else { return }
		settleReady(data, waiters: waiters, deliverOnMain: deliverOnMain)
	}

	private func settleReady(
		_ data: ContextData, waiters: [CheckedContinuation<Result<Void, ABsmartlyError>, Never>], deliverOnMain: Bool
	) {
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
		let waiters: [CheckedContinuation<Result<Void, ABsmartlyError>, Never>]? = storage.withLock { state in
			if state.isReady {
				return nil
			}
			state.install(.empty)
			state.failure = error
			state.failed = true
			let waiters = state.readyWaiters
			state.readyWaiters = []
			return waiters
		}
		guard let waiters else { return }
		Log.error("Context initialization failed", error)
		// The context is already failed when the logger hears of it, as in 1.5.0 and JavaScript.
		emitError(error, onMain: true)
		for waiter in waiters {
			waiter.resume(returning: .failure(error))
		}
	}

	private func markReady(_ state: inout ContextState) {
		state.ready = true
		// A refresh that lands after close() must not re-arm the timer close() cleared.
		guard !state.closed, !state.closing, refreshInterval > 0, state.refreshTimer == nil else { return }
		let interval = refreshInterval
		let clock = clock
		state.refreshTimer = Task { [weak self] in
			while !Task.isCancelled {
				do {
					try await clock.sleep(seconds: interval)
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
	/// On a failed context this succeeds without fetching, as in the Java and JavaScript SDKs (1.5.0
	/// fetches and can recover); one that was in flight when the first
	/// fetch failed succeeds without installing its data.
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
					// While the first fetch is still pending, this refresh makes the context ready. Once
					// that fetch failed (`failure` is set before the error is delivered), the context
					// stays failed, as `refresh()` on a failed context does.
					let outcome: RefreshOutcome = self.storage.withLock { state in
						state.refreshTask = nil
						// A refresh that lands once close() has started changes nothing (as in 1.5.0).
						if state.failure != nil || state.closing || state.closed {
							return .discarded
						}
						let loading = !state.ready
						state.install(index)
						markReady(&state)
						guard loading else {
							// As in 1.5.0: events still queued (e.g. a failed publish) get a publish timer.
							if state.pendingCount > 0 {
								schedulePublish(&state)
							}
							return .refreshed
						}
						let waiters = state.readyWaiters
						state.readyWaiters = []
						return .wonStartup(waiters)
					}
					switch outcome {
					case .discarded:
						break
					case .refreshed:
						emit(.refresh(data), onMain: true)
					case .wonStartup(let waiters):
						settleReady(data, waiters: waiters, deliverOnMain: true)
						emit(.refresh(data), onMain: true)
					}
					result = .success(())
				} catch {
					// Like a late success, a late failure after close() started logs no event (as in 1.5.0);
					// the caller still gets the error.
					let closing = self.storage.withLock { state in
						state.refreshTask = nil
						return state.closing || state.closed
					}
					Log.error("Context refresh failed", error)
					if !closing {
						emitError(error, onMain: true)
					}
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

	private enum RefreshOutcome {
		/// The first fetch failed, or close() has started: the data is not installed.
		case discarded
		/// Installed on a ready context.
		case refreshed
		/// Installed while the first fetch was pending: the context became ready with this data.
		case wonStartup([CheckedContinuation<Result<Void, ABsmartlyError>, Never>])
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
		// As in 1.5.0: wait for publishes in flight (a failed one re-queues its events), send what is
		// queued, and repeat until nothing is queued or in flight. That check and marking the context
		// closed are one critical section, so a timer publish that starts in between is waited for
		// and its batch cannot be stranded.
		while true {
			while let inFlight = storage.withLock({ $0.inFlightPublishes.values.first }) {
				#if DEBUG
					Self.closeWaitsForInFlightHook?()
				#endif
				_ = await inFlight.value
			}
			#if DEBUG
				await Self.closeAwaitedInFlightHook?()
			#endif
			let closedStreams = storage.withLock { state -> [Int: AsyncStream<Event>.Continuation]? in
				guard state.inFlightPublishes.isEmpty, state.pendingCount == 0 else { return nil }
				state.closed = true
				state.closing = false
				let streams = state.streams
				state.streams = [:]
				return streams
			}
			if let closedStreams {
				emit(.close, onMain: true, streams: closedStreams)
				for continuation in closedStreams.values {
					continuation.finish()
				}
				return .success(())
			}
			if case .failure(let error) = await flush() {
				// Reopened with the batch re-queued: the usual automatic publish retries it even if the
				// app does not call publish() or close() again (a negative delay still needs a call).
				storage.withLock { state in
					state.closing = false
					if state.pendingCount > 0 {
						schedulePublish(&state)
					}
				}
				return .failure(error)
			}
		}
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
			// Registered in the same critical section that drains the queue, so close()'s idle check
			// sees either the queued events or the publish in flight.
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
			Log.error("Publish failed", error)
			emitError(error, onMain: true)
			result = .failure(error)
		}
		storage.withLock { $0.inFlightPublishes[id] = nil }
		return result
	}

	private func schedulePublish(_ state: inout ContextState) {
		// No timer for a closed context (a logger returning after another caller closed it), which
		// would only hold the context for the delay. The queue may be momentarily empty because
		// another publish has taken the batch; if that publish fails it re-queues the batch, and this
		// timer sends it (as in 1.5.0), so the queue is not checked here.
		guard state.isReady, !state.closed, publishDelay >= 0, state.publishTimer == nil else { return }
		let delay = publishDelay
		// Held strongly until it fires, so goals tracked just before the caller drops its last
		// reference are still published.
		state.publishTimer = Task { [self] in
			do {
				try await clock.sleep(seconds: delay)
			} catch {
				return
			}
			// flush() already reports a failure as one `.error` event.
			_ = await self.flush()
		}
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
		let result: Result<(Int, [Exposure]), ABsmartlyError> = storage.withLock { state in
			if let error = state.checkReady(expectNotClosed: true) {
				return .failure(error)
			}
			if exposing {
				let (assignment, exposures) = state.lookupExposing(experiment, now: { clock.millis() })
				return .success((assignment.variant, exposures))
			}
			return .success((state.lookup(experiment, now: { clock.millis() }).variant, []))
		}
		switch result {
		case .failure(let error):
			reportError(error)
			return 0
		case .success((let variant, let exposures)):
			didQueue(exposures)
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

	/// The value of a variable in the variant of the first experiment defining it (by ascending id)
	/// that this context is in, or `nil` when its variant does not define the key. When the context is
	/// in none of them but a holdout holds it out of one, the first held-out experiment's control value
	/// (or `nil` when its control does not define the key); otherwise `nil`.
	/// With `exposing` (the default) that experiment is exposed and no other experiment is, but the
	/// holdouts covering every experiment checked publish their own exposures; a held-out experiment
	/// publishes no exposure of its own.
	public func variableValue(_ key: String, exposing: Bool = true) -> JSONValue? {
		// One critical section: the ready check, the candidates, their assignments and the winner's
		// exposure all come from one data install.
		let clock = clock
		let result: Result<(JSONValue?, [Exposure]), ABsmartlyError> = storage.withLock { state in
			if let error = state.checkReady(expectNotClosed: true) {
				return .failure(error)
			}
			return .success(state.variableValue(key, peek: !exposing, now: { clock.millis() }))
		}
		switch result {
		case .failure(let error):
			reportError(error)
			return nil
		case .success((let value, let exposures)):
			didQueue(exposures)
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
	/// counted as assigned.
	///
	/// Reading returns a snapshot. Assigning (including `overrides["exp"] = 1`) replaces the whole
	/// dictionary, so concurrent writers can overwrite each other: from several threads, use
	/// `setOverride(_:for:)` and `setOverrides(_:)`, which update atomically.
	public var overrides: [String: Int] {
		get { storage.withLock { $0.overrides } }
		// A plain setter, not `_modify`: the caller's expression (which may read this context, e.g.
		// `overrides["a", default: context.treatment(for: "b")] += 1`) runs before the lock is taken.
		set { storage.withLock { $0.overrides = newValue } }
	}

	/// Sets (or, with `nil`, removes) the override of one experiment, atomically.
	public func setOverride(_ variant: Int?, for experiment: String) {
		storage.withLock { $0.overrides[experiment] = variant }
	}

	/// Sets several overrides at once, atomically; existing overrides of other experiments are kept.
	public func setOverrides(_ overrides: [String: Int]) {
		storage.withLock { $0.overrides.merge(overrides) { _, new in new } }
	}

	/// The variant to assign for each experiment when the unit is eligible, instead of the hashed one.
	///
	/// Reading returns a snapshot. Assigning replaces the whole dictionary, so concurrent writers can
	/// overwrite each other: from several threads, use `setCustomAssignment(_:for:)` and
	/// `setCustomAssignments(_:)`, which update atomically.
	public var customAssignments: [String: Int] {
		get { storage.withLock { $0.customAssignments } }
		set { storage.withLock { $0.customAssignments = newValue } }
	}

	/// Sets (or, with `nil`, removes) the custom assignment of one experiment, atomically.
	public func setCustomAssignment(_ variant: Int?, for experiment: String) {
		storage.withLock { $0.customAssignments[experiment] = variant }
	}

	/// Sets several custom assignments at once, atomically.
	public func setCustomAssignments(_ assignments: [String: Int]) {
		storage.withLock { $0.customAssignments.merge(assignments) { _, new in new } }
	}

	// MARK: - Goals

	/// Records a goal achievement. Ignored (with an `.error` event) after the context is closed.
	public func track(_ goal: String, properties: [String: JSONValue]? = nil) {
		guard ensureNotClosed() else { return }
		let achievement = Goal(name: goal, achievedAt: clock.millis(), properties: properties)
		// Admitted under the same lock as queueing (as in 1.5.0): once close() has started the goal
		// is rejected, so it can never be left queued on a closed context.
		let rejected: ABsmartlyError? = storage.withLock { state in
			if let error = state.checkNotClosed() {
				return error
			}
			state.goals.append(achievement)
			state.pendingCount += 1
			return nil
		}
		if let rejected {
			reportError(rejected)
			return
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

	// Exposures and goals reach the logger synchronously on the caller's thread, so a logger sees
	// each one before the call that queued it returns.
	private func didQueue(_ event: Event) {
		emit(event, onMain: false)
		storage.withLock { schedulePublish(&$0) }
	}

	// Every exposure one read queued is in the queue before the logger hears of any, so a logger
	// that closes the context cannot flush between them. Streams get the whole batch, in queue order,
	// before the logger runs, so a logger that closes the context cannot finish them mid-batch.
	private func didQueue(_ exposures: [Exposure]) {
		guard !exposures.isEmpty else { return }
		let streams = storage.withLock { $0.streams }
		for exposure in exposures {
			for continuation in streams.values {
				continuation.yield(.exposure(exposure))
			}
		}
		for exposure in exposures {
			emit(.exposure(exposure), onMain: false, streams: [:])
		}
		storage.withLock { schedulePublish(&$0) }
	}

	// Streams see every event at once, in order. The logger sees `ready`/`refresh`/`publish`/`close`
	// and the errors of background work (load, refresh, publish) on the main thread on Apple
	// platforms (`onMain`), as in 1.x, without the work waiting for it.
	private func emit(_ event: Event, onMain: Bool, streams: [Int: AsyncStream<Event>.Continuation]? = nil) {
		let streams = streams ?? storage.withLock { $0.streams }
		for continuation in streams.values {
			continuation.yield(event)
		}
		guard let logger else { return }
		// While the logger handles an `.error`, a further error it causes on that thread is not
		// given to the logger again (it would recurse without bound), as in 1.5.0; streams, which
		// cannot recurse, still see it, and it has already gone to the SDK log.
		let deliver: @Sendable () -> Void = { [self] in
			guard case .error = event else {
				logger.handle(self, event)
				return
			}
			let threadDictionary = Thread.current.threadDictionary
			if threadDictionary[deliveringErrorKey] != nil {
				return
			}
			threadDictionary[deliveringErrorKey] = true
			defer { threadDictionary.removeObject(forKey: deliveringErrorKey) }
			logger.handle(self, event)
		}
		#if DEBUG
			if onMain, let dispatcher = Self.mainThreadDispatcher {
				dispatcher(event, deliver)
				return
			}
		#endif
		if onMain && Self.mainThreadDeliveryEnabled && !Thread.isMainThread {
			DispatchQueue.main.async(execute: deliver)
		} else {
			deliver()
		}
	}

	private var deliveringErrorKey: String {
		"com.absmartly.Context.deliveringError.\(ObjectIdentifier(self).hashValue)"
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

	private static var mainThreadDeliveryEnabled: Bool {
		#if DEBUG
			if let override = mainThreadDeliveryOverride {
				return override
			}
		#endif
		return deliversEventsOnMainThread
	}

	#if DEBUG
		/// Test hook: forces main-thread delivery on or off for the current task and the tasks it
		/// starts, without touching the process-wide setting other tests use.
		@TaskLocal static var mainThreadDeliveryOverride: Bool?

		/// Test hook: runs each time close() has waited for the publishes in flight, before it checks
		/// whether the context is idle (the window in which a timer publish can start).
		@TaskLocal static var closeAwaitedInFlightHook: (@Sendable () async -> Void)?

		/// Test hook: runs when close() starts waiting for a publish in flight.
		@TaskLocal static var closeWaitsForInFlightHook: (@Sendable () -> Void)?

		/// Test hook: receives each event routed to the main thread, with its delivery, in place of
		/// the main queue (which nothing services under Linux tests). Task-local, so tasks the
		/// context starts inherit it and parallel tests do not see it.
		@TaskLocal static var mainThreadDispatcher: (@Sendable (Event, @escaping @Sendable () -> Void) -> Void)?
	#endif

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
		Log.error(error.logSummary, detail: error.logDetail)
		emitError(error)
	}

	private func emitError(_ error: ABsmartlyError, onMain: Bool = false) {
		emit(.error(error), onMain: onMain)
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
			guard let data = try? JSONEncoder.absmartly().encode(self) else { return nil }
			return try? JSONDecoder().decode(T.self, from: data)
		}
	}
}

#if DEBUG
	extension Context {
		/// Test hook: actual assignment-cache dictionary writes, including redundant write-backs.
		var assignmentCacheWriteCount: Int {
			storage.withLock { $0.assignmentCacheWrites }
		}

		/// Test hook: how many times cached assignments were re-evaluated against their rules/audience.
		var revalidationCount: Int {
			storage.withLock { $0.revalidations }
		}

		/// Test hook: how many times a cached assignment's holdout set was compared with the data's.
		var holdoutSetComparisonCount: Int {
			storage.withLock { $0.holdoutSetComparisons }
		}

		/// Test hook: how many times a covered assignment's holdouts were visited to queue exposures.
		var holdoutVisitCount: Int {
			storage.withLock { $0.holdoutVisits }
		}
	}
#endif
