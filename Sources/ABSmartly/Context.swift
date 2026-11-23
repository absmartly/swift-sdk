import Atomics
import Foundation
import PromiseKit

public final class Context {
	private let clock: Clock
	private let scheduler: Scheduler
	private let handler: ContextEventHandler
	private let provider: ContextDataProvider

	deinit {
		clearRefreshTimer()
		clearTimeout()
	}
	private let logger: ContextEventLogger?
	private let parser: VariableParser
	private let matcher: AudienceMatcher

	private var pendingCount = ManagedAtomic<UInt>(0)

	// Loading, ready or failed, published as one value so isReady()/isFailed() never see a
	// half-made transition (a recovering context stays ready throughout). Changed under contextLock.
	private static let loading: UInt8 = 0
	private static let readyState: UInt8 = 1
	private static let failedState: UInt8 = 2
	private var state = ManagedAtomic<UInt8>(Context.loading)
	private var closed = ManagedAtomic<Bool>(false)
	private var closing = ManagedAtomic<Bool>(false)
	private var refreshing = ManagedAtomic<Bool>(false)

	private var readyPromise: Promise<Void>?
	private var readyResolver: Resolver<Void>?
	// What the initial load's completion handlers hold the context through. A refresh that wins the
	// initial load empties it, so a provider promise that never settles stops retaining the context.
	private var initialLoadOwner: ContextOwner?
	private var refreshPromise: Promise<Void>?
	private var closePromise: Promise<Void>?

	private let timeoutLock = NSLock()
	private var timeout: ScheduledHandle?
	private var refreshTimer: ScheduledHandle?
	private let refreshTimerLock = NSLock()

	private let dataLock = NSLock()
	#if DEBUG
	var afterExperimentLookup: (() -> Void)?
	#endif
	// The current context data and its indexes, installed or cleared as one value; nil when there is
	// no data (still loading, or the load failed).
	private var prepared: PreparedData? = nil
	private var failedError: Error? = nil

	private var hashedUnits: [String: [UInt8]] = [:]
	private var assigners: [String: VariantAssigner] = [:]
	private var assignmentCache: [String: Assignment] = [:]
	// Incremented when a refresh recovers a failed context. Exposures claimed before that were made
	// without experiment data and are dropped instead of queued. Written under contextLock and
	// eventLock, so reading under either is safe.
	private var dataGeneration = 0
	// A holdout's arm per (holdout id, covered experiment's unit type), kept across refreshes while the
	// holdout's iteration is unchanged. Guarded by `contextLock`.
	private var holdoutAssignments: [HoldoutKey: Assignment] = [:]

	private let contextLock = NSRecursiveLock()
	// The string each unit is hashed from, and the UID as it was given (string or number).
	private var units: [String: String] = [:]
	private var unitValues: [String: JSON] = [:]
	private var attributes: [Attribute] = []
	private var overrides: [String: Int] = [:]
	private var cassignments: [String: Int] = [:]

	private let eventLock = NSLock()
	private let promiseLock = NSLock()
	private var inFlightPublishes: [UInt: Promise<Void>] = [:]
	private var nextPublishId: UInt = 0
	private var exposures: [Exposure] = []
	private var achievements: [GoalAchievement] = []

	private var publishDelay: TimeInterval = 0
	private var refreshInterval: TimeInterval = 0
	private var attrsSeq: Int = 0

	// Non-empty `application`/`environment` names from the client config, which the collector also
	// attaches to every exposure server-side. They seed the evaluation map so audiences and
	// assignment-rule conditions can target them; a user-set attribute of the same name wins.
	private let systemAttributes: [String: JSON]
	// Matched against an assignment rule's `environments`.
	private let environmentName: String?

	init(
		config: ContextConfig, clock: Clock, scheduler: Scheduler, handler: ContextEventHandler,
		provider: ContextDataProvider, logger: ContextEventLogger?, parser: VariableParser,
		matcher: AudienceMatcher,
		promise: Promise<ContextData>,
		application: String? = nil,
		environment: String? = nil
	) {
		self.clock = clock
		self.scheduler = scheduler
		self.handler = handler
		self.provider = provider
		self.logger = logger
		self.parser = parser
		self.matcher = matcher

		var systemAttributes: [String: JSON] = [:]
		if let application = application, !application.isEmpty {
			systemAttributes["application"] = JSON(application)
		}
		if let environment = environment, !environment.isEmpty {
			systemAttributes["environment"] = JSON(environment)
		}
		self.systemAttributes = systemAttributes
		self.environmentName = environment.flatMap { $0.isEmpty ? nil : $0 }

		publishDelay = config.publishDelay
		refreshInterval = config.refreshInterval

		assigners.reserveCapacity(config.units.count)
		hashedUnits.reserveCapacity(config.units.count)

		overrides.reserveCapacity(config.overrides.count)
		overrides.merge(config.overrides, uniquingKeysWith: { (_, new) in new })

		cassignments.reserveCapacity(config.cassignments.count)
		cassignments.merge(config.cassignments, uniquingKeysWith: { (_, new) in new })

		attributes.reserveCapacity(config.attributes.count)
		for (name, value) in config.attributes {
			appendAttribute(name: name, value: value)
		}

		units.reserveCapacity(config.unitValues.count)
		for (unitType, uid) in config.unitValues {
			do {
				try putUnit(unitType: unitType, value: uid)
			} catch {
				reportError(error)
			}
		}

		if promise.isResolved {
			if let data = promise.value {
				commitData(prepareData(data))
				// Mark ready before delivery so a logger's ready handler can read the context.
				state.store(Context.readyState, ordering: .releasing)
				setRefreshTimer()
				logEvent(event: .ready(data: data))
				// Goals tracked from inside the ready callback were queued before the
				// context was ready, so their publish timer could not start then.
				if pendingCount.load(ordering: .acquiring) > 0 {
					setTimeout()
				}
			} else if let error = promise.error {
				// The context is failed (and ready) by the time the `.error` event is delivered.
				applyDataFailed(error)
				state.store(Context.failedState, ordering: .releasing)
				logError(error: error)
			}
		} else {
			// Published under promiseLock: the completions below may already run (on another queue)
			// and clear it before this assignment would otherwise happen.
			promiseLock.lock()
			defer { promiseLock.unlock() }
			// Whichever of the initial load and a refresh makes the context ready first takes this
			// resolver and settles it, after scheduling queued goals. Set before any completion runs.
			let (ready, resolver) = Promise<Void>.pending()
			readyPromise = ready
			readyResolver = resolver
			let owner = ContextOwner(self)
			initialLoadOwner = owner

			// The completion handlers hold the context until the provider's promise settles, so a
			// caller that keeps only waitUntilReady()'s promise still gets it settled.
			promise.done(on: DispatchQueue.global()) { data in
				guard let self = owner.take() else {
					// Superseded by a refresh, which already made the context ready.
					#if DEBUG
					Context.runTestHook(.initialLoadSettled)
					#endif
					return
				}
				#if DEBUG
				Context.runTestHook(.initialLoadTookContext)
				#endif
				// Outside every lock: a VariableParser that calls back into the context must not deadlock.
				let prepared = self.prepareData(data)
				self.contextLock.lock()
				let wins = self.state.load(ordering: .acquiring) == Context.loading
				if wins {
					self.commitData(prepared)
					// Ready before delivery so a logger's ready handler can read the context.
					// Under eventLock, like track()'s append: with only atomics, track()'s state load
					// (in setTimeout()) and settleReadiness()'s pendingCount load could both see the
					// old values (store-load reordering), and neither would schedule the goal. No
					// deterministic test can force that reordering.
					self.eventLock.lock()
					self.state.store(Context.readyState, ordering: .releasing)
					self.eventLock.unlock()
				}
				self.contextLock.unlock()
				if wins {
					self.setRefreshTimer()
					self.deliverOnMain { self.logEvent(event: .ready(data: data)) }
					self.settleReadiness()
				}
				#if DEBUG
				Context.runTestHook(.initialLoadSettled)
				#endif
			}.catch(on: DispatchQueue.global(), policy: .allErrors) { error in
				// `.allErrors`: PromiseKit's default policy skips cancellation, which would leave
				// `owner` holding the context and readiness waiters pending forever.
				guard let self = owner.take() else {
					// Superseded by a refresh, which already made the context ready.
					#if DEBUG
					Context.runTestHook(.initialLoadSettled)
					#endif
					return
				}
				#if DEBUG
				Context.runTestHook(.initialLoadTookContext)
				#endif
				// The context is failed (and ready) by the time the `.error` event is delivered.
				self.contextLock.lock()
				let wins = self.state.load(ordering: .acquiring) == Context.loading
				if wins {
					self.applyDataFailed(error)
					// Under eventLock too (defensive): a failed-state exposure is only queued, under
					// eventLock, by a thread that already sees the context failed, so the flush's
					// re-check under eventLock sees it failed either way.
					self.eventLock.lock()
					self.state.store(Context.failedState, ordering: .releasing)
					self.eventLock.unlock()
				}
				self.contextLock.unlock()
				Logger.error("Context initialization failed: \(error.safeLocalizedDescription)")
				if wins {
					self.deliverOnMain { self.logError(error: error) }
					// Goals queued while loading wait for a successful refresh (setTimeout() schedules
					// nothing on a failed context).
					self.settleReadiness()
				}
				#if DEBUG
				Context.runTestHook(.initialLoadSettled)
				#endif
			}
			}
		}

	// Called once, by whichever completion made the context ready (or failed): schedules goals that
	// were queued while loading, then settles waitUntilReady() callers.
	private func settleReadiness() {
		if pendingCount.load(ordering: .acquiring) > 0 {
			setTimeout()
		}
		promiseLock.lock()
		let resolver = readyResolver
		readyResolver = nil
		readyPromise = nil
		promiseLock.unlock()
		resolver?.fulfill(())
	}

	public func isReady() -> Bool {
		return state.load(ordering: .acquiring) != Context.loading
	}

	public func isFailed() -> Bool {
		return state.load(ordering: .acquiring) == Context.failedState
	}

	public func readyError() -> Error? {
		dataLock.lock()
		defer { dataLock.unlock() }
		return failedError
	}

	public func isClosing() -> Bool {
		return !closed.load(ordering: .acquiring) && closing.load(ordering: .acquiring)
	}

	public func isClosed() -> Bool {
		return closed.load(ordering: .acquiring)
	}

	public func isFinalizing() -> Bool {
		return isClosing()
	}

	public func isFinalized() -> Bool {
		return isClosed()
	}

	public func finalize() -> Promise<Void> {
		return close()
	}

	public func waitUntilReady() -> Promise<Context> {
		return Promise<Context> { [weak self] seal in
			guard let self = self else {
				seal.reject(ABSmartlyError("Context was deallocated"))
				return
			}
			self.promiseLock.lock()
			let currentReadyPromise = self.readyPromise
			self.promiseLock.unlock()
			if self.isReady() || currentReadyPromise == nil {
				seal.fulfill(self)
			} else if let ready = currentReadyPromise {
				_ = ready.done(on: DispatchQueue.global()) { [self] in
					seal.fulfill(self)
				}.catch(on: DispatchQueue.global(), policy: .allErrors) { [self] _ in
					seal.fulfill(self)
				}
			}
		}
	}

	public func getExperiments() -> [String] {
		guard ensureReady(false) else { return [] }

		dataLock.lock()
		defer { dataLock.unlock() }
		return prepared?.data.experiments.map { $0.name } ?? []
	}

	public func getCustomFieldKeys() -> Set<String> {
		guard ensureReady(false) else { return [] }

		var keys: Set<String> = []

		dataLock.lock()
		defer { dataLock.unlock() }

		guard let data = prepared?.data else { return keys }

		for experiment in data.experiments {
			guard let customFieldValues = experiment.customFieldValues else { continue }
			for customFieldValue in customFieldValues {
				guard let name = customFieldValue.name else { continue }
				keys.insert(name)
			}
		}

		return keys
	}

	@_disfavoredOverload
	public func getCustomFieldKeys(experimentName: String) -> [String] {

		dataLock.lock()
		defer { dataLock.unlock() }

		guard let experimentCustomFields = prepared?.customFieldValues[experimentName] else {
			return []
		}

		return Array(experimentCustomFields.keys)
	}

	public func getCustomFieldValue(experimentName: String, key: String) -> Any? {

		dataLock.lock()
		defer { dataLock.unlock() }

		return prepared?.customFieldValues[experimentName]?[key]?.value
	}

	public func getCustomFieldValueType(experimentName: String, key: String) -> String? {

		dataLock.lock()
		defer { dataLock.unlock() }

		return prepared?.customFieldValues[experimentName]?[key]?.type
	}

	public func getContextData() -> ContextData? {
		guard ensureReady(false) else { return nil }

		dataLock.lock()
		defer { dataLock.unlock() }
		return prepared?.data
	}

	private func putLocked<K, V>(lock: NSRecursiveLock, dict: inout [K: V], key: K, value: V) -> V? {
		lock.lock()
		defer { lock.unlock() }
		return dict.updateValue(value, forKey: key)
	}

	// The dictionary is read through a closure, inside the lock: passing it by value would copy the
	// stored property before the lock is taken, racing with writers.
	private func getLocked<V>(lock: NSLocking, _ read: () -> V?) -> V? {
		lock.lock()
		defer { lock.unlock() }
		return read()
	}

	public func setOverride(experimentName: String, variant: Int) {
		_ = putLocked(lock: contextLock, dict: &overrides, key: experimentName, value: variant)
	}

	public func getOverride(experimentName: String) -> Int? {
		return getLocked(lock: contextLock) { overrides[experimentName] }
	}

	public func setOverrides(_ overrides: [String: Int]) {
		for (key, value) in overrides {
			setOverride(experimentName: key, variant: value)
		}
	}

	public func setCustomAssignment(experimentName: String, variant: Int) {
		_ = putLocked(lock: contextLock, dict: &cassignments, key: experimentName, value: variant)
	}

	public func getCustomAssignment(experimentName: String) -> Int? {
		return getLocked(lock: contextLock) { cassignments[experimentName] }
	}

	public func setCustomAssignments(_ assignments: [String: Int]) {
		for (key, value) in assignments {
			setCustomAssignment(experimentName: key, variant: value)
		}
	}

	public func getUnit(unitType: String) -> String? {
		return getLocked(lock: contextLock) { unitValues[unitType] }.map { $0.string ?? $0.stringValue }
	}

	/// The UID as it was set: a JSON string or a JSON number.
	public func getUnitValue(unitType: String) -> JSON? {
		return getLocked(lock: contextLock) { unitValues[unitType] }
	}

	public func getUnitValues() -> [String: JSON] {
		contextLock.lock()
		defer { contextLock.unlock() }
		return unitValues
	}

	public func setUnit(unitType: String, uid: String) {
		setUnit(unitType: unitType, value: JSON(uid))
	}

	/// Sets a unit whose UID is a number; see `ContextConfig.setUnit(unitType:uid:)`.
	@_disfavoredOverload
	public func setUnit(unitType: String, uid: Int) {
		setUnit(unitType: unitType, value: JSON(uid))
	}

	@_disfavoredOverload
	public func setUnit(unitType: String, uid: Double) {
		setUnit(unitType: unitType, value: JSON(uid))
	}

	/// Sets a unit from a JSON value. Only strings and numbers are accepted. An invalid UID
	/// (blank, not a string or number, or a change to an already set unit) or a closed context
	/// leaves the unit unchanged and logs an `.error` event.
	@_disfavoredOverload
	public func setUnit(unitType: String, value: JSON) {
		guard ensureNotClosed() else { return }
		do {
			try putUnit(unitType: unitType, value: value)
		} catch {
			reportError(error)
		}
	}

	private func putUnit(unitType: String, value: JSON) throws {
		let stored: JSON
		let hashSource: String
		switch value.type {
		case .string:
			let trimmed = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else {
				throw ABSmartlyError("Unit '\(unitType)' UID must not be blank.")
			}
			stored = JSON(trimmed)
			hashSource = trimmed
		case .number:
			stored = value
			hashSource = Hashing.unitString(value.doubleValue)
		default:
			throw ABSmartlyError("Unit '\(unitType)' must be a string or a number.")
		}

		contextLock.lock()
		defer { contextLock.unlock() }

		if let previous = unitValues[unitType], !Self.sameUID(previous, stored) {
			throw ABSmartlyError("Unit '\(unitType)' already set.")
		}

		unitValues[unitType] = stored
		units[unitType] = hashSource

		// A split rule or a holdout resolved without its unit is rebuilt now that the unit is known. An
		// exposed one is kept, so the user never switches variant or gets a second exposure.
		assignmentCache = assignmentCache.filter { _, assignment in
			assignment.unitType != unitType || assignment.exposed.load(ordering: .acquiring)
				|| !(assignment.ruleMissingUnit || assignment.holdoutMissingUnit)
		}
	}

	// Undoes an exposure claim whose exposure was not queued. Under contextLock, so setUnit sees the
	// claim and its release together: a missing-unit split kept across setUnit only because it
	// looked exposed is dropped once its unit is known, so the next read re-resolves it with the
	// unit. Takes contextLock without holding eventLock (refresh takes them in that order).
	private func releaseUnqueuedExposure(_ assignment: Assignment?, arms: [Assignment]) {
		contextLock.lock()
		defer { contextLock.unlock() }
		releaseUnqueuedArms(arms)
		guard let assignment = assignment else { return }
		assignment.exposed.store(false, ordering: .releasing)
		if assignment.ruleMissingUnit || assignment.holdoutMissingUnit, let unitType = assignment.unitType, units[unitType] != nil,
			assignmentCache[assignment.name] === assignment
		{
			assignmentCache[assignment.name] = nil
		}
	}

	// Undoes the claim of holdout arms whose exposures were not queued, so another read can expose them.
	private func releaseUnqueuedArms(_ arms: [Assignment]) {
		guard !arms.isEmpty else { return }
		contextLock.lock()
		defer { contextLock.unlock() }
		for arm in arms {
			arm.exposed.store(false, ordering: .releasing)
		}
	}

	private static func sameUID(_ a: JSON, _ b: JSON) -> Bool {
		switch (a.type, b.type) {
		case (.string, .string): return a.stringValue == b.stringValue
		case (.number, .number): return a.doubleValue == b.doubleValue
		default: return false
		}
	}

	public func getUnits() -> [String: String] {
		contextLock.lock()
		defer { contextLock.unlock() }

		return unitValues.mapValues { $0.string ?? $0.stringValue }
	}

	public func setUnits(_ units: [String: String]) {
		for (unitType, uid) in units {
			setUnit(unitType: unitType, uid: uid)
		}
	}

	public func getAttribute(name: String) -> JSON? {
		contextLock.lock()
		defer { contextLock.unlock() }

		for attribute in attributes.reversed() {
			if attribute.name == name {
				return attribute.value
			}
		}

		return nil
	}

	public func setAttribute(name: String, value: JSON) {
		guard ensureNotClosed() else { return }
		appendAttribute(name: name, value: value)
	}

	private func appendAttribute(name: String, value: JSON) {
		contextLock.lock()
		defer { contextLock.unlock() }

		attributes.append(Attribute(name, value: value, setAt: clock.millis()))
		attrsSeq += 1
	}

	public func getAttributes() -> [String: JSON] {
		var result: [String:JSON] = [:]

		contextLock.lock()
		defer { contextLock.unlock() }

		for attribute in attributes {
			result[attribute.name] = attribute.value
		}
		return result;
	}

	public func setAttributes(_ attributes: [String: JSON]) {
		for (name, value) in attributes {
			setAttribute(name: name, value: value)
		}
	}

	public func getTreatment(_ experimentName: String) -> Int {
		guard ensureReady(true) else { return 0 }

		return getAssignmentExposing(experimentName).variant
	}

	// Looks the assignment up and marks it exposed in one `contextLock` section, so `setUnit` cannot
	// evict it in between and let a later call expose a second, different variant. Return only the
	// assignment on the hot path; build and queue an exposure only for a new claim.
	private func getAssignmentExposing(_ experimentName: String) -> Assignment {
		let (assignment, claimed) = claimExposure(experimentName)
		if let claimed = claimed {
			queueClaimed(claimed)
		}
		return assignment
	}

	@inline(__always)
	private func claimExposure(_ experimentName: String) -> (Assignment, ClaimedExposure?) {
		contextLock.lock()
		defer { contextLock.unlock() }

		let assignment = lookupAssignment(experimentName)
		if assignment.exposed.load(ordering: .acquiring) || closed.load(ordering: .acquiring)
			|| closing.load(ordering: .acquiring)
		{
			return (assignment, nil)
		}
		var claim = ClaimBuilder()
		claimLocked(assignment, into: &claim)
		return (assignment, claim.build(generation: dataGeneration))
	}

	// The lookup, the claim and the exposure's construction all happen in one contextLock section, so
	// the exposure reads the assignment's fields consistently with any refresh; the generation lets
	// the queue drop it if a recovery happened in between. Every write to `exposed` (these claims and
	// the releases) holds contextLock, so a store after the check is an exclusive claim.
	//
	// A held-out experiment publishes no exposure of its own (an override or a matching rule still
	// does); every holdout covering it publishes its own, once per epoch, from the arms pinned when
	// the assignment was resolved.
	private func claimLocked(_ assignment: Assignment, into claim: inout ClaimBuilder) {
		guard !assignment.exposed.load(ordering: .acquiring) else { return }
		assignment.exposed.store(true, ordering: .releasing)
		claim.assignment = assignment
		if !assignment.suppressed || assignment.overridden || assignment.ruleOverride {
			claim.exposures.append(makeExposure(assignment, name: assignment.name))
		}
		claimHoldoutArmsLocked(assignment, into: &claim)
	}

	private func claimHoldoutArmsLocked(_ assignment: Assignment, into claim: inout ClaimBuilder) {
		for holdout in assignment.holdouts ?? [] {
			if let arm = holdout.arm, !arm.exposed.load(ordering: .acquiring) {
				arm.exposed.store(true, ordering: .releasing)
				claim.arms.append(arm)
				// Named by the definition the assignment was resolved with, as in JavaScript.
				claim.exposures.append(makeExposure(arm, name: holdout.definition.name))
			}
		}
	}

	private func makeExposure(_ assignment: Assignment, name: String) -> Exposure {
		return Exposure(
			assignment.id, name, assignment.unitType, assignment.variant,
			clock.millis(), assignment.assigned, assignment.eligible,
			assignment.overridden, assignment.fullOn, assignment.custom, assignment.audienceMismatch,
			ruleOverride: assignment.ruleOverride)
	}

	// All of a claim's exposures are queued before the logger hears of any, so a logger that closes
	// the context cannot flush between them.
	private func queueClaimed(_ claimed: ClaimedExposure) {
		#if DEBUG
		Context.runTestHook(.exposureClaimed)
		#endif
		guard !claimed.exposures.isEmpty else { return }
		eventLock.lock()
		// Made before a recovery replaced the data it came from: drop it, the rebuilt assignment
		// will be exposed by the next read.
		if claimed.generation != dataGeneration {
			eventLock.unlock()
			releaseUnqueuedArms(claimed.arms)
			return
		}
		guard !closed.load(ordering: .acquiring), !closing.load(ordering: .acquiring) else {
			eventLock.unlock()
			// Not queued, so not exposed: a read after a failed close can still expose it.
			releaseUnqueuedExposure(claimed.assignment, arms: claimed.arms)
			return
		}
		exposures.append(contentsOf: claimed.exposures)
		pendingCount.wrappingIncrement(by: UInt(claimed.exposures.count), ordering: .releasing)
		eventLock.unlock()

		for exposure in claimed.exposures {
			logEvent(event: .exposure(exposure: exposure))
		}

		setTimeout()
	}

	public func peekTreatment(_ experimentName: String) -> Int {
		guard ensureReady(true) else { return 0 }

		return getAssignment(experimentName).variant
	}

	public func getVariableKeys() -> [String: [String]] {
		guard ensureReady(true) else { return [:] }

		dataLock.lock()
		defer { dataLock.unlock() }

		return (prepared?.indexVariables ?? [:]).mapValues { $0.map({ $0.data.name }) }
	}

	public func getVariableValue(_ key: String, defaultValue: JSON? = nil) -> JSON? {
		guard ensureReady(true) else { return defaultValue }

		return resolveVariableValue(key, defaultValue: defaultValue, peek: false)
	}

	public func peekVariableValue(_ key: String, defaultValue: JSON? = nil) -> JSON? {
		guard ensureReady(true) else { return defaultValue }

		return resolveVariableValue(key, defaultValue: defaultValue, peek: true)
	}

	public func track(_ goalName: String, properties: [String: JSON]? = nil) {
		guard ensureNotClosed() else { return }

		let achievement: GoalAchievement = GoalAchievement(
			goalName, achievedAt: clock.millis(), properties: properties)

		eventLock.lock()
		guard !closed.load(ordering: .acquiring), !closing.load(ordering: .acquiring) else {
			eventLock.unlock()
			return
		}
		achievements.append(achievement)
		pendingCount.wrappingIncrement(by: 1, ordering: .releasing)
		eventLock.unlock()

		logEvent(event: .goal(goal: achievement))

		setTimeout()
	}

	public func getPendingCount() -> UInt {
		return pendingCount.load(ordering: .acquiring)
	}

	public func publish() -> Promise<Void> {
		do {
			try checkNotClosed()
		} catch {
			return Promise<Void>(error: error)
		}

		return flush()
	}

	public func refresh() -> Promise<Void> {
		do {
			try checkNotClosed()
		} catch {
			return Promise<Void>(error: error)
		}

		promiseLock.lock()
		defer { promiseLock.unlock() }

		if !refreshing.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).0 {
			return refreshPromise ?? Promise<Void>.value(())
		}

		let promise = Promise<Void> { [weak self] seal in
			guard let self = self else {
				seal.fulfill(())
				return
			}

			// Held strongly until the fetch settles, so the returned promise always settles.
			self.provider.getContextData().done(on: DispatchQueue.global()) { [self] data in
				// Outside every lock: a VariableParser that calls back into the context must not deadlock.
				let prepared = self.prepareData(data)
				// A context whose first load failed (or is still loading) becomes ready once a refresh
				// succeeds, so events queued from the refreshed data are published instead of
				// discarded. Data, error and state change together under contextLock and eventLock,
				// so no evaluation or flush sees the new data while the context still reports failed.
				self.contextLock.lock()
				self.eventLock.lock()
				let previousState = self.state.load(ordering: .acquiring)
				let winsInitialLoad = previousState == Context.loading
				// Recovering a failed context: assignments and exposures made while it had no experiment
				// data (e.g. an override, with no experiment id or variables) are discarded, as v1.4.0
				// discarded every event of a failed context. The next read rebuilds the assignment from
				// the new data and exposes it once, correctly attributed. Goals are kept.
				if previousState == Context.failedState {
					self.assignmentCache = [:]
					self.dataGeneration += 1
					let dropped = self.exposures.count
					self.exposures = []
					if dropped > 0 {
						self.pendingCount.wrappingDecrement(by: UInt(dropped), ordering: .releasing)
					}
				}
				self.commitData(prepared)
				self.state.store(Context.readyState, ordering: .releasing)
				self.eventLock.unlock()
				self.contextLock.unlock()
				self.setRefreshTimer()
				if winsInitialLoad {
					// The initial load's late result is ignored: stop it retaining the context.
					self.promiseLock.lock()
					let owner = self.initialLoadOwner
					self.initialLoadOwner = nil
					self.promiseLock.unlock()
					owner?.release()
					self.deliverOnMain { self.logEvent(event: .ready(data: data)) }
					self.settleReadiness()
				} else if self.pendingCount.load(ordering: .acquiring) > 0 {
					self.setTimeout()
				}
				self.refreshing.store(false, ordering: .releasing)
				self.deliverOnMain { self.logEvent(event: .refresh(data: data)) }
				seal.fulfill(())
			}.catch(on: DispatchQueue.global(), policy: .allErrors) { [self] error in
				// `.allErrors`: a cancelled fetch must still clear `refreshing` and settle the promise.
				self.refreshing.store(false, ordering: .releasing)

				Logger.error("Context refresh failed: \(error.safeLocalizedDescription)")
				self.deliverOnMain { self.logError(error: error) }

				seal.reject(error)
			}
		}

		refreshPromise = promise
		return promise
	}

	public func close() -> Promise<Void> {
		// Claim the close and publish its promise in one critical section, so a concurrent
		// caller never sees `closing` set without the promise it should join.
		promiseLock.lock()
		if closed.load(ordering: .acquiring) || closing.load(ordering: .acquiring) {
			let existingPromise = closePromise
			promiseLock.unlock()
			return existingPromise ?? Promise<Void>.value(())
		}
		closing.store(true, ordering: .releasing)
		let (newClosePromise, seal) = Promise<Void>.pending()
		closePromise = newClosePromise
		promiseLock.unlock()

		clearRefreshTimer()
		// The final flush below sends what a pending automatic publish would have.
		clearTimeout()

		// Nothing queued or in flight: close now, as v1.4.0 did, so isClosed() is true and `.close`
		// has been logged when close() returns. As in v1.4.0, that `.close` reaches the logger on
		// the thread that called close().
		if closeIfIdle() {
			logEvent(event: .close)
			seal.fulfill(())
			return newClosePromise
		}

		// The closures hold the context strongly: once close() starts, the final flush must
		// complete even if the caller drops its last reference (e.g. close() from deinit).
		finishClose(seal)
		return newClosePromise
	}

	// Marks the context closed if nothing is queued or in flight, deciding and marking in one
	// eventLock section: a flush drains and registers its in-flight barrier under the same lock, so
	// close can never report success while a publish that may re-queue its events is running.
	private func closeIfIdle() -> Bool {
		eventLock.lock()
		defer { eventLock.unlock() }
		guard inFlightPublishes.isEmpty && pendingCount.load(ordering: .acquiring) == 0 else { return false }
		closed.store(true, ordering: .releasing)
		closing.store(false, ordering: .releasing)
		return true
	}

	// Waits for publishes in flight (a failed one re-queues its events), flushes what is queued and
	// repeats until the context is idle, then closes it. A failed final flush reopens the context so
	// the re-queued events can be retried via publish()/close().
	private func finishClose(_ seal: Resolver<Void>) {
		_ = awaitInFlightPublishes().done(on: DispatchQueue.global()) { [self] in
			#if DEBUG
			Context.runTestHook(.closeAwaitedInFlight)
			#endif
			if self.closeIfIdle() {
				self.deliverOnMain { self.logEvent(event: .close) }
				seal.fulfill(())
				return
			}
			self.flush().done(on: DispatchQueue.global()) { [self] in
				self.finishClose(seal)
			}.catch(on: DispatchQueue.global(), policy: .allErrors) { [self] error in
				// Failed close does not itself re-arm refresh (cross-SDK contract). A successful
				// refresh completing after this rejection can still restart the timer.
				self.closing.store(false, ordering: .releasing)
				// Reopened with the batch re-queued: schedule the usual automatic publish for it, so it
				// is retried even if the app does not call publish() or close() again.
				if self.pendingCount.load(ordering: .acquiring) > 0 {
					self.setTimeout()
				}
				seal.reject(error)
			}
		}
	}

	private func awaitInFlightPublishes() -> Promise<Void> {
		eventLock.lock()
		let inFlight = Array(inFlightPublishes.values)
		eventLock.unlock()

		if inFlight.isEmpty {
			return Promise<Void>.value(())
		}
		return when(resolved: inFlight).then(on: DispatchQueue.global()) { [weak self] _ -> Promise<Void> in
			guard let self = self else { return Promise<Void>.value(()) }
			return self.awaitInFlightPublishes()
		}
	}

	private func flush() -> Promise<Void> {
		clearTimeout()

		if !isFailed() {
			#if DEBUG
			Context.runTestHook(.flushObservedNotFailed)
			#endif
			var eventCount = pendingCount.load(ordering: .acquiring)
			if eventCount > 0 {
				var localExposures: [Exposure] = []
				var localAchievements: [GoalAchievement] = []
				var localUnits: [Unit] = []
				var localAttributes: [Attribute] = []
				var publishId: UInt = 0
				var barrierSeal: Resolver<Void>?

				do {
					eventLock.lock()
					defer { eventLock.unlock() }

					// The context failed after the check above: discard instead of draining, so
					// exposures made without experiment data are never sent (see the failed branch).
					if isFailed() {
						exposures = []
						achievements = []
						pendingCount.store(0, ordering: .releasing)
						return Promise<Void>.value(())
					}

					eventCount = pendingCount.load(ordering: .acquiring)
					if eventCount > 0 {
						if !exposures.isEmpty {
							localExposures = exposures
							exposures = []
						}

						if !achievements.isEmpty {
							localAchievements = achievements
							achievements = []
						}

						pendingCount.store(0, ordering: .releasing)

						// Register the close barrier in the same critical section that drains the
						// queue, so close() can never observe an empty queue and no in-flight publish.
						let (barrier, seal) = Promise<Void>.pending()
						publishId = nextPublishId
						nextPublishId += 1
						inFlightPublishes[publishId] = barrier
						barrierSeal = seal
					}
				}

				if eventCount > 0 {
					// Units and attributes are snapshotted under contextLock; the handler is called
					// after releasing it, so a handler that waits on another thread which reads the
					// context cannot deadlock (v1.4.0 held no lock there either).
					contextLock.lock()
					localUnits = units.map {
						let hashBytes = getUnitHash($0.key, $0.value)
						if let hashString = String(bytes: hashBytes, encoding: .ascii) {
							return Unit(type: $0.key, uid: hashString)
						} else {
							Logger.error("Failed to encode unit hash for type '\($0.key)' to ASCII. Using base64 fallback.")
							return Unit(type: $0.key, uid: Data(hashBytes).base64EncodedString())
						}
					}
					localAttributes = attributes
					contextLock.unlock()

					let event = PublishEvent(
						true,
						localUnits,
						clock.millis(),
						localExposures,
						localAchievements,
						localAttributes)

					// Held strongly until the publish settles, so a failure is never reported as success.
					let publishPromise = handler.publish(event: event).done(on: DispatchQueue.global()) { [self] in
						self.deliverOnMain { self.logEvent(event: .publish(event: event)) }
					}.recover(on: DispatchQueue.global(), policy: .allErrors) { [self] error -> Promise<Void> in
						// .allErrors: a cancelled publish must re-queue its events too, or they are lost
						// and close() never settles.
						self.eventLock.lock()
						self.exposures.insert(contentsOf: localExposures, at: 0)
						self.achievements.insert(contentsOf: localAchievements, at: 0)
						self.pendingCount.wrappingIncrement(by: UInt(eventCount), ordering: .releasing)
						self.eventLock.unlock()

						Logger.error("Publish failed: \(error.safeLocalizedDescription)")
						self.deliverOnMain { self.logError(error: error) }
						throw error
					}
					_ = publishPromise.ensure(on: DispatchQueue.global()) { [weak self] in
						if let self = self {
							self.eventLock.lock()
							self.inFlightPublishes[publishId] = nil
							self.eventLock.unlock()
						}
						barrierSeal?.fulfill(())
					}
					return publishPromise
				}
			}
		} else {
			#if DEBUG
			Context.runTestHook(.flushObservedFailed)
			#endif
			eventLock.lock()
			// Recovery and this decision are serialized: a flush that observed the old failed
			// state must not discard events queued after recovery.
			if !isFailed() {
				eventLock.unlock()
				return flush()
			}
			defer { eventLock.unlock() }

			exposures = []
			achievements = []
			pendingCount.store(0, ordering: .releasing)
		}

		return Promise<Void>.value(())
	}

	#if DEBUG
	// Test hooks, compiled into debug builds only, that let tests interleave lifecycle steps
	// deterministically: `flushObservedFailed` runs after a flush has seen the context failed and
	// before it takes `eventLock`; `initialLoadSettled` runs after the initial load's completion has
	// been handled (whether it was applied or superseded by a refresh); `exposureClaimed` runs after
	// a read claimed an exposure and before it is queued; `initialLoadTookContext` runs after the
	// initial load's completion took its context reference and before it checks the state;
	// `flushObservedNotFailed` runs after a flush has seen the context not failed and before it
	// takes `eventLock`; `closeAwaitedInFlight` runs after close() waited for in-flight publishes
	// and before it decides whether the context is idle.
	enum TestHook: Hashable {
		case flushObservedFailed
		case initialLoadSettled
		case exposureClaimed
		case initialLoadTookContext
		case flushObservedNotFailed
		case closeAwaitedInFlight
	}

	private static var testHooks: [TestHook: () -> Void] = [:]
	private static let testHooksLock = NSLock()

	static func setTestHook(_ hook: TestHook, _ body: (() -> Void)?) {
		testHooksLock.lock()
		defer { testHooksLock.unlock() }
		testHooks[hook] = body
	}

	private static func runTestHook(_ hook: TestHook) {
		testHooksLock.lock()
		let body = testHooks[hook]
		testHooksLock.unlock()
		body?()
	}
	#endif

	private func checkReady(_ expectNotClosed: Bool) throws {
		if !isReady() {
			throw ABSmartlyError("ABSmartly Context is not yet ready.")
		}
		if expectNotClosed {
			try checkNotClosed()
		}
	}

	private func checkNotClosed() throws {
		if isClosed() {
			throw ABSmartlyError("ABSmartly Context is closed.")
		}
		if isClosing() {
			throw ABSmartlyError("ABSmartly Context is closing.")
		}
	}

	// The public API never throws: misuse such as reading before ready or
	// writing after close is reported through Logger and an `.error` event instead.
	private func ensureReady(_ expectNotClosed: Bool) -> Bool {
		do {
			try checkReady(expectNotClosed)
			return true
		} catch {
			reportError(error)
			return false
		}
	}

	private func ensureNotClosed() -> Bool {
		do {
			try checkNotClosed()
			return true
		} catch {
			reportError(error)
			return false
		}
	}

	private func reportError(_ error: Error) {
		Logger.error(error.safeLocalizedDescription)
		logError(error: error)
	}

	// System values first, then user attributes overlaid on top, so a user-set value always wins —
	// including one set after an assignment was cached (the `attrsSeq` bump invalidates it). A
	// user value of `null`/empty still overwrites the system key, matching the JavaScript SDK.
	private func buildAttributeMap() -> [String: JSON] {
		var attrs: [String: JSON] = systemAttributes
		for attr in attributes {
			attrs[attr.name] = attr.value
		}
		return attrs
	}

	// Reads the fields through `ExperimentVariables` so a cached read does not copy the whole `Experiment`.
	private func experimentMatches(_ experimentVariables: ExperimentVariables, _ assignment: Assignment) -> Bool {
		let experiment = experimentVariables.data
		return experiment.id == assignment.id && experiment.unitType == assignment.unitType
			&& experiment.iteration == assignment.iteration && experiment.fullOnVariant == assignment.fullOnVariant
			&& experiment.trafficSplit == assignment.trafficSplit
	}

	// The covering holdouts are the same (id, iteration) pairs the assignment was resolved with. A
	// same-iteration seed or split edit is not a change, so it never forces a second exposure.
	private func holdoutSetMatches(_ experiment: ExperimentVariables, _ assignment: Assignment) -> Bool {
		guard let fresh = experiment.holdouts, let pinned = assignment.holdouts else {
			return experiment.holdouts == nil && assignment.holdouts == nil
		}
		guard fresh.count == pinned.count else { return false }
		for (freshHoldout, pinnedHoldout) in zip(fresh, pinned) {
			if freshHoldout.id != pinnedHoldout.definition.id
				|| freshHoldout.iteration != pinnedHoldout.definition.iteration
			{
				return false
			}
		}
		return true
	}

	// Whether the cached assignment still holds for the current attributes and rules: the matching
	// rule (if any) must give the same variant, and the audience result must not have flipped.
	private func audienceMatches(_ experiment: ExperimentVariables, _ assignment: Assignment) -> Bool {
		let ruleKey = experiment.data.assignmentRules ?? ""
		let ruleKeyChanged = ruleKey != assignment.ruleKey

		let hasAudience = !(experiment.data.audience ?? "").isEmpty
		if (attrsSeq > assignment.attrsSeq && (experiment.rules != nil || hasAudience)) || ruleKeyChanged {
			let attrs = buildAttributeMap()

			// An exposed split resolved without its unit keeps resolving as if the unit were still
			// missing, so a unit set afterwards cannot switch the variant the user already saw.
			let unitPinnedMissing = assignment.ruleMissingUnit && assignment.exposed.load(ordering: .acquiring)
			let rule = resolveRule(experiment, attrs, unitPinnedMissing: unitPinnedMissing)
			if rule?.variant != assignment.ruleVariant {
				return false
			}
			assignment.ruleMissingUnit = rule?.missingUnit ?? false

			if !assignment.ruleOverride && hasAudience, let audience = experiment.data.audience {
				let result = matcher.evaluate(audience, attrs)
				let newAudienceMismatch = result != nil ? !result! : assignment.audienceMismatch

				if newAudienceMismatch != assignment.audienceMismatch {
					return false
				}
			}

			assignment.ruleKey = ruleKey
			assignment.attrsSeq = attrsSeq
		}
		return true
	}

	// The variant of the first matching assignment rule, or nil when none matches. An out-of-bounds
	// assign variant or a split whose length differs from the variant count stops rule evaluation
	// and falls back to normal assignment. A split matched while the unit is missing gives the
	// experiment's own no-unit result (the full-on variant, else 0) and is flagged `missingUnit`.
	private func resolveRule(
		_ experiment: ExperimentVariables, _ attrs: [String: JSON], unitPinnedMissing: Bool
	) -> (variant: Int, missingUnit: Bool)? {
		guard let rules = experiment.rules else { return nil }

		let data = experiment.data
		let variantCount = data.variants.count
		switch matcher.evaluateRules(rules, environmentName: environmentName, attributes: attrs) {
		case nil:
			return nil
		case .assign(let variant)?:
			return variant >= 0 && variant < variantCount ? (variant, false) : nil
		case .split(let split)?:
			guard split.count == variantCount else { return nil }
			guard !unitPinnedMissing, let unitType = data.unitType, let uid = units[unitType] else {
				return (data.fullOnVariant, true)
			}
			let assigner = getVariantAssigner(unitType, getUnitHash(unitType, uid))
			return (assigner.assign(split, data.seedHi, data.seedLo), false)
		}
	}

	private func getExperiment(_ experimentName: String) -> ExperimentVariables? {
		return getLocked(lock: dataLock) { prepared?.index[experimentName] }
	}

	private func getAssignment(_ experimentName: String) -> Assignment {
		contextLock.lock()
		defer { contextLock.unlock() }

		return lookupAssignment(experimentName)
	}

	// The cached assignment if still up to date, else a newly computed and cached one. The caller
	// holds `contextLock`.
	private func lookupAssignment(_ experimentName: String) -> Assignment {
		let experiment: ExperimentVariables? = getExperiment(experimentName)
		#if DEBUG
		afterExperimentLookup?()
		#endif

		if let assignment = assignmentCache[experimentName] {
			if let override = overrides[experimentName] {
				if assignment.overridden && assignment.variant == override
					&& (experiment == nil || holdoutSetMatches(experiment!, assignment))
				{
					// override up-to-date
					return assignment
				}
			} else if experiment == nil {
				// A rule-won assignment came from the experiment's rules, so it is rebuilt once the
				// experiment is gone.
				if !assignment.assigned && !assignment.ruleOverride {
					// previously not-running experiment
					return assignment
				}
			} else if let exp = experiment {
				// A held-out experiment is forced to variant 0 and a matching rule wins over a custom
				// assignment, so a custom mismatch is not staleness.
				let custom = cassignments[experimentName]
				if custom == nil || custom == assignment.variant || assignment.ruleOverride || assignment.suppressed {
					if experimentMatches(exp, assignment) && audienceMatches(exp, assignment)
						&& holdoutSetMatches(exp, assignment)
					{
						// assignment up-to-date
						return assignment
					}
				}
			}
		}

		let assignment = Assignment()
		assignment.name = experimentName
		assignment.eligible = true

		// Resolved for overrides too: the holdouts still publish their exposures. Arms are drawn from
		// the definitions of the same data install as `experiment`, so they always agree with them.
		if let experiment = experiment, let holdouts = experiment.holdouts {
			let unitType = experiment.data.unitType
			let pinned = holdouts.map { holdout in
				PinnedHoldout(
					definition: holdout, arm: unitType.flatMap { getHoldoutAssignment(holdout, unitType: $0, live: holdout) })
			}

			assignment.holdouts = pinned
			assignment.suppressed = pinned.contains { holdout in
				guard let arm = holdout.arm else { return false }
				return Context.isHeldOutBy(
					arm.variant, armCount: arm.holdoutArmCount, fullOnVariant: experiment.data.fullOnVariant)
			}
		}

		if let override = overrides[experimentName] {
			if let experimentVariables = experiment {
				assignment.id = experimentVariables.data.id
				assignment.unitType = experimentVariables.data.unitType
			}

			assignment.overridden = true
			assignment.variant = override
		} else {
			if let experiment = experiment {
				let unitType = experiment.data.unitType

				let rule =
					experiment.rules != nil ? resolveRule(experiment, buildAttributeMap(), unitPinnedMissing: false) : nil
				assignment.ruleKey = experiment.data.assignmentRules ?? ""
				assignment.ruleVariant = rule?.variant
				assignment.ruleMissingUnit = rule?.missingUnit ?? false

				// A matching assignment rule is an explicit, author-specified assignment: it wins over
				// holdout suppression, the audience, traffic eligibility, full-on and custom assignments;
				// only an override beats it. It is flagged `ruleOverride` so the collector keeps it out of
				// analysis.
				if let rule = rule {
					assignment.variant = rule.variant
					assignment.ruleOverride = true
				} else if assignment.suppressed {
					assignment.assigned = false
					assignment.variant = 0
				} else {
					if let audience = experiment.data.audience {
						if audience.count > 0 {
							let attrs = buildAttributeMap()

							if let result = matcher.evaluate(audience, attrs) {
								assignment.audienceMismatch = !result
							}
						}
					}

					if experiment.data.audienceStrict && assignment.audienceMismatch {
						assignment.variant = 0
					} else if experiment.data.fullOnVariant == 0 {
						if let unitType = experiment.data.unitType, let uid = units[unitType] {
							let unitHash: [UInt8] = getUnitHash(unitType, uid)
							let assigner = getVariantAssigner(unitType, unitHash)

							let eligible =
								assigner.assign(
									experiment.data.trafficSplit, experiment.data.trafficSeedHi,
									experiment.data.trafficSeedLo) == 1

							if eligible {
								let custom = cassignments[experimentName]
								if custom != nil {
									assignment.variant = custom!
									assignment.custom = true
								} else {
									assignment.variant = assigner.assign(
										experiment.data.split, experiment.data.seedHi, experiment.data.seedLo)
								}
							} else {
								assignment.eligible = false
								assignment.variant = 0
							}

							assignment.assigned = true
						}
					} else {
						assignment.assigned = true
						assignment.variant = experiment.data.fullOnVariant
						assignment.fullOn = true
					}
				}

				assignment.unitType = unitType
				assignment.id = experiment.data.id
				assignment.iteration = experiment.data.iteration
				assignment.trafficSplit = experiment.data.trafficSplit
				assignment.fullOnVariant = experiment.data.fullOnVariant
				assignment.attrsSeq = attrsSeq
			}
		}

		if let experiment = experiment, assignment.variant >= 0, assignment.variant < experiment.variables.count {
			assignment.variables = experiment.variables[assignment.variant]
		}

		assignmentCache[experimentName] = assignment
		return assignment
	}

	// Experiments sharing a key are candidates in ascending id order, as in the Java SDK. The winner
	// is the first candidate the unit is in (assigned, overridden or won by an assignment rule); when
	// there is none, the first held-out candidate supplies its control value. The value is the
	// winner's for the key, or the default when the winner's variant does not define it: a later
	// candidate is never used because of the variant the unit got. Only the winner is exposed; like
	// Java, the holdouts covering every candidate visited are exposed too. Peeking exposes nothing.
	private func resolveVariableValue(_ key: String, defaultValue: JSON?, peek: Bool) -> JSON? {
		guard let candidates = getVariableExperiments(key) else {
			return defaultValue
		}

		let (winner, claimed) = selectVariableAssignment(candidates, expose: !peek)
		if let claimed = claimed {
			queueClaimed(claimed)
		}
		return winner?.variables?[key] ?? defaultValue
	}

	// Selects and claims in one contextLock section, so setUnit cannot change a candidate in between.
	private func selectVariableAssignment(
		_ candidates: [ExperimentVariables], expose: Bool
	) -> (Assignment?, ClaimedExposure?) {
		contextLock.lock()
		defer { contextLock.unlock() }

		let expose = expose && !closed.load(ordering: .acquiring) && !closing.load(ordering: .acquiring)
		var claim = ClaimBuilder()
		var winner: Assignment?
		var suppressedFallback: Assignment?
		for candidate in candidates {
			let assignment = lookupAssignment(candidate.data.name)
			if expose {
				claimHoldoutArmsLocked(assignment, into: &claim)
			}
			if assignment.assigned || assignment.overridden || assignment.ruleOverride {
				winner = assignment
				break
			}
			if assignment.suppressed && suppressedFallback == nil {
				suppressedFallback = assignment
			}
		}

		winner = winner ?? suppressedFallback
		if expose, let winner = winner {
			claimLocked(winner, into: &claim)
		}
		return (winner, expose ? claim.build(generation: dataGeneration) : nil)
	}

	// Arm 0 always holds the experiment out. In a 3-arm holdout, arm 1 holds out only an experiment
	// that is not full-on. The arm count comes from the holdout's split, never its `holdoutType`.
	static func isHeldOutBy(_ holdoutVariant: Int, armCount: Int, fullOnVariant: Int) -> Bool {
		if holdoutVariant == 0 {
			return true
		}
		if armCount == 3 && holdoutVariant == 1 {
			return fullOnVariant == 0
		}
		return false
	}

	// The unit's arm in a holdout, hashed with the covered experiment's unit type, or nil while that
	// unit is missing. `live` is the holdout's current definition; when not given it is looked up, as
	// `holdout` may predate a refresh. The caller holds `contextLock`.
	private func getHoldoutAssignment(_ holdout: Experiment, unitType: String, live: Experiment? = nil) -> Assignment? {
		let live = live ?? getLocked(lock: dataLock, { prepared?.holdoutsById[holdout.id] }) ?? holdout

		let key = HoldoutKey(id: live.id, unitType: unitType)
		if let cached = holdoutAssignments[key], cached.iteration == live.iteration {
			return cached
		}

		guard let uid = units[unitType] else {
			return nil
		}

		let assigner = getVariantAssigner(unitType, getUnitHash(unitType, uid))
		let assignment = Assignment()
		assignment.id = live.id
		assignment.name = live.name
		assignment.iteration = live.iteration
		assignment.unitType = unitType
		assignment.variant = assigner.assign(live.split, live.seedHi, live.seedLo)
		assignment.assigned = true
		assignment.eligible = true
		// Pinned with the arm: a same-iteration refresh may change the live split's length.
		assignment.holdoutArmCount = live.split.count

		holdoutAssignments[key] = assignment
		return assignment
	}

	private func getVariableExperiments(_ experimentName: String) -> [ExperimentVariables]? {
		return getLocked(lock: dataLock) { prepared?.indexVariables[experimentName] }
	}

	private func getUnitHash(_ unitType: String, _ unitUID: String) -> [UInt8] {
		contextLock.lock()
		defer { contextLock.unlock() }

		if let unitHash = hashedUnits[unitType] { return unitHash }

		let hashValue: [UInt8] = Hashing.hashBytes(unitUID)
		hashedUnits[unitType] = hashValue
		return hashValue
	}

	private func getVariantAssigner(_ unitType: String, _ unitHash: [UInt8]) -> VariantAssigner {
		contextLock.lock()
		defer { contextLock.unlock() }

		if let variantAssigner = assigners[unitType] {
			return variantAssigner
		}

		let variantAssigner = VariantAssigner(unitHash)
		assigners[unitType] = variantAssigner

		return variantAssigner
	}

	// Only while ready: a loading context schedules its queue once settled, and a failed one keeps it
	// for a recovering refresh (an automatic flush of a failed context would discard it).
	private func setTimeout() {
		guard state.load(ordering: .acquiring) == Context.readyState else { return }

		timeoutLock.lock()
		defer { timeoutLock.unlock() }

		if timeout == nil {
				// Held strongly until it fires (flush() then drops the handle), so goals tracked
				// just before the caller drops its last reference are still published, as in v1.4.0.
				timeout = scheduler.schedule(
					after: publishDelay,
					execute: { [self] in
						// flush() already reports the failure as one `.error` event.
						self.flush().catch(on: DispatchQueue.global(), policy: .allErrors) { error in
							Logger.error("Auto-flush failed: \(error.safeLocalizedDescription)")
						}
					})
		}
	}

	private func clearTimeout() {
		timeoutLock.lock()
		defer { timeoutLock.unlock() }

		timeout?.cancel()
		timeout = nil
	}

	private func setRefreshTimer() {
		refreshTimerLock.lock()
		defer { refreshTimerLock.unlock() }
		// A refresh that lands after close() must not re-arm the timer close() cleared.
		if isClosed() || isClosing() {
			return
		}
		if refreshInterval > 0 && refreshTimer == nil {
			refreshTimer = scheduler.scheduleWithFixedDelay(
				after: refreshInterval, repeating: refreshInterval,
				execute: { [weak self] in
					guard let self = self else { return }
					// refresh() already logs the failure and reports it as one `.error` event.
					self.refresh().catch(on: DispatchQueue.global(), policy: .allErrors) { _ in }
				})
		}
	}

	private func clearRefreshTimer() {
		refreshTimerLock.lock()
		defer { refreshTimerLock.unlock() }
		refreshTimer?.cancel()
		refreshTimer = nil
	}

	internal func setData(_ data: ContextData) {
		commitData(prepareData(data))
		contextLock.lock()
		_ = state.compareExchange(expected: Context.loading, desired: Context.readyState, ordering: .acquiringAndReleasing)
		contextLock.unlock()
		setRefreshTimer()
	}

	private struct PreparedData {
		let data: ContextData
		let index: [String: ExperimentVariables]
		let indexVariables: [String: [ExperimentVariables]]
		let customFieldValues: [String: [String: ContextCustomFieldValue]]
		// Holdouts with a non-empty split, by id.
		let holdoutsById: [Int: Experiment]
	}

	// Builds the indexes for new context data. Runs the configured VariableParser, so it is called
	// without holding any lock; commitData publishes the result.
	private func prepareData(_ data: ContextData) -> PreparedData {
		var index: [String: ExperimentVariables] = [:]
		var indexVariables: [String: [ExperimentVariables]] = [:]
		var customFieldValues: [String: [String: ContextCustomFieldValue]] = [:]

		var holdoutsById: [Int: Experiment] = [:]
		for holdout in data.holdouts ?? [] where !holdout.split.isEmpty {
			holdoutsById[holdout.id] = holdout
		}

		for experiment in data.experiments {
			let experimentVariables = ExperimentVariables(experiment)
			if let holdoutIds = experiment.holdoutIds, !holdoutsById.isEmpty {
				var holdouts: [Experiment] = []
				for holdoutId in holdoutIds {
					if let holdout = holdoutsById[holdoutId] {
						holdouts.insertUniqueSorted(holdout, isSorted: { $0.id < $1.id })
					}
				}
				experimentVariables.holdouts = holdouts.isEmpty ? nil : holdouts
			}
			if let assignmentRules = experiment.assignmentRules, !assignmentRules.isEmpty {
				experimentVariables.rules = matcher.parseRules(assignmentRules)
				if experimentVariables.rules == nil {
					Logger.error("Failed to parse assignmentRules for experiment '\(experiment.name)'.")
				}
			}
			var experimentCustomFieldValues: [String: ContextCustomFieldValue] = [:]

			for variant in experiment.variants {
				if let config = variant.config, !config.isEmpty {
					if let parsed = parser.parse(experimentName: experiment.name, config: config) {
						for (key, _) in parsed {
							var keyExperimentVariables = indexVariables[key] ?? []
							keyExperimentVariables.insertUniqueSorted(
								experimentVariables, isSorted: { $0.data.id < $1.data.id })
							indexVariables[key] = keyExperimentVariables
						}
						experimentVariables.variables.append(parsed)
					} else {
						experimentVariables.variables.append([:])
					}
				} else {
					experimentVariables.variables.append([:])
				}
			}

			if let fieldValues = experiment.customFieldValues {
				for customFieldValue in fieldValues {
					guard let fieldType = customFieldValue.type,
						  let fieldName = customFieldValue.name else { continue }

					let value = ContextCustomFieldValue()
					value.type = fieldType

					if let customValue = customFieldValue.value {
						if fieldType.starts(with: "json") {
							// Objects and invalid JSON go through the configured VariableParser; other valid JSON is
							// kept as `JSON`; `null` is nil.
							let parsed = try? JSON(data: Data(customValue.utf8), options: .fragmentsAllowed)
							switch parsed?.type {
							case .array?, .number?, .string?, .bool?:
								value.value = parsed
							case .null?:
								value.value = nil
							default:
								if parsed == nil {
									Logger.error("Invalid JSON in custom field '\(fieldName)' of experiment '\(experiment.name)'.")
								}
								value.value = parser.parse(experimentName: experiment.name, config: customValue)
							}
						} else if fieldType.starts(with: "boolean") {
							value.value = Bool(customValue)
						} else if fieldType.starts(with: "number") {
							value.value = Double(customValue)
						} else {
							value.value = customFieldValue.value
						}
					}

					experimentCustomFieldValues[fieldName] = value
				}
			}

			index[experiment.name] = experimentVariables
			customFieldValues[experiment.name] = experimentCustomFieldValues
		}

		return PreparedData(
			data: data, index: index, indexVariables: indexVariables, customFieldValues: customFieldValues,
			holdoutsById: holdoutsById)
	}

	// Publishes prepared data and clears a previous load failure in one dataLock section, so
	// readyError() is only cleared together with the recovered data. Installed under `contextLock`
	// (then `dataLock`, the order assignment lookups use), so a refresh lands between assignment
	// resolutions, never inside one: an assignment never pairs one data install's holdout definitions
	// with another's arms.
	private func commitData(_ prepared: PreparedData) {
		contextLock.lock()
		defer { contextLock.unlock() }
		dataLock.lock()
		self.prepared = prepared
		self.failedError = nil
		dataLock.unlock()
	}

	private func applyDataFailed(_ error: Error) {
		dataLock.lock()
		defer { dataLock.unlock() }

		prepared = nil
		failedError = error
	}

	// ready/refresh/publish/close and `.error` events from asynchronously completed work reach the
	// logger on the main thread, as in v1.4.0, so loggers may touch UIKit; the work itself stays off
	// the main thread and never waits for the delivery. Events from work that completes concurrently
	// (e.g. an initial load and a refresh finishing together) are not ordered relative to each other. Events for data that was already loaded (or
	// already failed) when the context was created, and errors from misuse, are logged
	// synchronously on the calling thread, as in v1.4.0.
	// On Linux, where nothing may service the main queue, events use the completing thread.
	#if canImport(Darwin)
	private static var deliversEventsOnMainThreadValue = true
	#else
	private static var deliversEventsOnMainThreadValue = false
	#endif
	private static let deliversEventsOnMainThreadLock = NSLock()

	static var deliversEventsOnMainThread: Bool {
		get {
			deliversEventsOnMainThreadLock.lock()
			defer { deliversEventsOnMainThreadLock.unlock() }
			return deliversEventsOnMainThreadValue
		}
		set {
			deliversEventsOnMainThreadLock.lock()
			defer { deliversEventsOnMainThreadLock.unlock() }
			deliversEventsOnMainThreadValue = newValue
		}
	}

	private func deliverOnMain(_ deliver: @escaping () -> Void) {
		if !Context.deliversEventsOnMainThread || Thread.isMainThread {
			deliver()
		} else {
			DispatchQueue.main.async(execute: deliver)
		}
	}

	private func logEvent(event: ContextEventLoggerEvent) {
		logger?.handleEvent(context: self, event: event)
	}

	// An error raised while this context is already delivering `.error` on the same thread
	// (e.g. a logger reading getContextData() from its error handler before the context is
	// ready) is not delivered again, which would recurse without bound; reportError has
	// already written it to Logger.
	private func logError(error: Error) {
		let key = "ABSmartly.Context.deliveringError.\(ObjectIdentifier(self))"
		let threadDictionary = Thread.current.threadDictionary
		if threadDictionary[key] != nil {
			return
		}
		threadDictionary[key] = true
		defer { threadDictionary.removeObject(forKey: key) }
		logEvent(event: .error(error: error))
	}
}

private struct ClaimedExposure {
	// The newly claimed assignment (nil when only holdout arms were claimed), its own exposure (unless
	// held out) and one per newly claimed holdout arm.
	let assignment: Assignment?
	let exposures: [Exposure]
	let arms: [Assignment]
	let generation: Int
}

private struct ClaimBuilder {
	var assignment: Assignment?
	var exposures: [Exposure] = []
	var arms: [Assignment] = []

	// nil when nothing was claimed.
	func build(generation: Int) -> ClaimedExposure? {
		if assignment == nil && arms.isEmpty {
			return nil
		}
		return ClaimedExposure(assignment: assignment, exposures: exposures, arms: arms, generation: generation)
	}
}

// Holds a context strongly until taken or released; the initial load's completions go through it.
private final class ContextOwner {
	private let lock = NSLock()
	private var context: Context?

	init(_ context: Context) {
		self.context = context
	}

	func take() -> Context? {
		lock.lock()
		defer { lock.unlock() }
		let taken = context
		context = nil
		return taken
	}

	func release() {
		_ = take()
	}
}

#if DEBUG
extension Context {
	func cachedAssignmentIdentity(_ experimentName: String) -> ObjectIdentifier {
		return ObjectIdentifier(getAssignment(experimentName))
	}

	func resolveHoldoutArm(_ holdout: Experiment, unitType: String) -> (
		variant: Int, iteration: Int, exposed: Bool
	)? {
		contextLock.lock()
		defer { contextLock.unlock() }
		return getHoldoutAssignment(holdout, unitType: unitType).map {
			($0.variant, $0.iteration, $0.exposed.load(ordering: .acquiring))
		}
	}
}
#endif

private class ExperimentVariables {
	let data: Experiment
	var variables: [[String: JSON]] = []
	// Parsed `data.assignmentRules`; nil when there are none or they are not valid JSON.
	var rules: [JSON]?
	var holdouts: [Experiment]?

	init(_ experiment: Experiment) {
		data = experiment
	}
}

private class ContextCustomFieldValue {
	var type: String?
	var value: Any?
}

private final class Assignment: Equatable {
	static func == (lhs: Assignment, rhs: Assignment) -> Bool {
		return lhs.id == rhs.id && lhs.iteration == rhs.iteration && lhs.fullOnVariant == rhs.fullOnVariant
			&& lhs.name == rhs.name && lhs.unitType == rhs.unitType && lhs.trafficSplit == rhs.trafficSplit
			&& lhs.variant == rhs.variant && lhs.assigned == rhs.assigned && lhs.overridden == rhs.overridden
			&& lhs.eligible == rhs.eligible && lhs.fullOn == rhs.fullOn && lhs.custom == rhs.custom
			&& lhs.audienceMismatch == rhs.audienceMismatch && lhs.ruleOverride == rhs.ruleOverride
			&& lhs.variables == rhs.variables
	}

	var id: Int = 0
	var iteration: Int = 0
	var fullOnVariant: Int = 0
	var name: String = ""
	var unitType: String?
	var trafficSplit: [Double] = []
	var variant: Int = 0
	var assigned: Bool = false
	var overridden: Bool = false
	var eligible: Bool = false
	var fullOn: Bool = false
	var custom: Bool = false
	var audienceMismatch = false
	var ruleOverride = false
	// The variant of the matching rule and the rules it came from, to detect when they change.
	var ruleVariant: Int?
	var ruleKey = ""
	// A split rule matched while the unit was missing.
	var ruleMissingUnit = false
	var variables: [String: JSON]?
	var exposed = ManagedAtomic<Bool>(false)
	var attrsSeq: Int = 0
	var suppressed = false
	var holdouts: [PinnedHoldout]?
	// On a holdout's own assignment: its split's length when `variant` was drawn.
	var holdoutArmCount = 0

	var holdoutMissingUnit: Bool {
		return holdouts?.contains { $0.arm == nil } ?? false
	}
}

// A covering holdout and the unit's arm in it; the arm is nil while the unit is missing.
private struct PinnedHoldout {
	let definition: Experiment
	let arm: Assignment?
}

private struct HoldoutKey: Hashable {
	let id: Int
	let unitType: String
}
