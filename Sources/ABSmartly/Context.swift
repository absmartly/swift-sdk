import Atomics
import Foundation
import MapKit
import PromiseKit

public final class Context {
	private let clock: Clock
	private let scheduler: Scheduler
	private let handler: ContextEventHandler
	private let provider: ContextDataProvider
	private let logger: ContextEventLogger?
	private let parser: VariableParser
	private let matcher: AudienceMatcher
	private var promise: Promise<ContextData>?
	private var config: ContextConfig

	private var pendingCount = ManagedAtomic<UInt>(0)

	private var failed: Bool = false
	private var closed = ManagedAtomic<Bool>(false)
	private var closing = ManagedAtomic<Bool>(false)
	private var refreshing = ManagedAtomic<Bool>(false)
	private var readyPromise: Promise<Void>?
	private var refreshPromise: Promise<Void>?
	private var closePromise: Promise<Void>?

	private let timeoutLock = NSLock()
	private var timeout: ScheduledHandle?

	private let dataLock = NSLock()
	private var index: [String: ExperimentVariables] = [:]
	private var indexVariables: [String: ExperimentVariables] = [:]
	private var data: ContextData? = nil

	private let assignmentLock = NSRecursiveLock()
	private var hashedUnits: [String: [UInt8]] = [:]
	private var assigners: [String: VariantAssigner] = [:]
	private var assignmentCache: [String: Assignment] = [:]

	private let contextLock = NSLock()
	private var attributes: [Attribute] = []
	private var overrides: [String: Int] = [:]
	private var cassignments: [String: Int] = [:]

	private let eventLock = NSLock()
	private var exposures: [Exposure] = []
	private var achievements: [GoalAchievement] = []

	init(
		config: ContextConfig, clock: Clock, scheduler: Scheduler, handler: ContextEventHandler,
		provider: ContextDataProvider, logger: ContextEventLogger?, parser: VariableParser,
		matcher: AudienceMatcher,
		promise: Promise<ContextData>
	) {
		self.clock = clock
		self.scheduler = scheduler
		self.handler = handler
		self.provider = provider
		self.logger = logger
		self.parser = parser
		self.matcher = matcher
		self.promise = promise
		self.config = config

		assigners.reserveCapacity(config.units.count)
		hashedUnits.reserveCapacity(config.units.count)

		overrides.reserveCapacity(config.overrides.count)
		overrides.merge(config.overrides, uniquingKeysWith: { (_, new) in new })

		cassignments.reserveCapacity(config.cassignments.count)
		cassignments.merge(config.cassignments, uniquingKeysWith: { (_, new) in new })

		attributes.reserveCapacity(config.attributes.count)
		setAttributes(config.attributes)

		if promise.isResolved {
			if let data = promise.value {
				setData(data)

				logEvent(event: .ready(data: data))
			} else if let error = promise.error {
				setDataFailed(error)

				logError(error: error)
			}
		} else {
			readyPromise = Promise<Void> { seal in
				promise.done { [self] data in
					setData(data)
					seal.fulfill(())
					readyPromise = nil

					logEvent(event: .ready(data: data))

					if pendingCount.load(ordering: .relaxed) > 0 {
						setTimeout()
					}
				}.catch { [self] error in
					setDataFailed(error)
					readyPromise = nil
					seal.fulfill(())  // throw no user-visible errors

					logError(error: error)
				}
			}
		}
	}

	public func isReady() -> Bool {
		return failed || data != nil
	}

	public func isFailed() -> Bool {
		return failed
	}

	public func isClosing() -> Bool {
		return !closed.load(ordering: .relaxed) && closing.load(ordering: .relaxed)
	}

	public func isClosed() -> Bool {
		return closed.load(ordering: .relaxed)
	}

	public func waitUntilReady() -> Promise<Context> {
		return Promise<Context> { seal in
			if isReady() || readyPromise == nil {
				seal.fulfill(self)
			} else if let ready = readyPromise {
				_ = ready.done {
					seal.fulfill(self)
				}
			}
		}
	}

	public func getExperiments() -> [String] {
		checkReady(true)

		dataLock.lock()
		defer { dataLock.unlock() }
		return data?.experiments.map { $0.name } ?? []
	}

	public func getContextData() -> ContextData? {
		checkReady(true)

		dataLock.lock()
		defer { dataLock.unlock() }
		return data
	}

	private func putLocked<K, V>(lock: NSLock, dict: inout [K: V], key: K, value: V) -> V? {
		lock.lock()
		defer { lock.unlock() }
		return dict.updateValue(value, forKey: key)
	}

	private func getLocked<K, V>(lock: NSLock, dict: [K: V], key: K) -> V? {
		lock.lock()
		defer { lock.unlock() }
		return dict[key]
	}

	public func setOverride(experimentName: String, variant: Int) {
		checkNotClosed()

		let previous: Int? = putLocked(lock: contextLock, dict: &overrides, key: experimentName, value: variant)
		if previous == nil || previous != variant {
			assignmentLock.lock()
			defer { assignmentLock.unlock() }

			if let assignment: Assignment = assignmentCache[experimentName] {
				if !assignment.overridden || assignment.variant != variant {
					if assignmentCache[experimentName] == assignment {
						assignmentCache.removeValue(forKey: experimentName)
					}
				}
			}
		}
	}

	public func getOverride(experimentName: String) -> Int? {
		return getLocked(lock: contextLock, dict: overrides, key: experimentName)
	}

	public func setOverrides(_ overrides: [String: Int]) {
		overrides.forEach { setOverride(experimentName: $0.key, variant: $0.value) }
	}

	public func setCustomAssignment(experimentName: String, variant: Int) {
		checkNotClosed()

		let previous: Int? = putLocked(lock: contextLock, dict: &cassignments, key: experimentName, value: variant)
		if previous == nil || previous != variant {
			assignmentLock.lock()
			defer { assignmentLock.unlock() }

			if let assignment: Assignment = assignmentCache[experimentName] {
				if !assignment.custom || assignment.variant != variant {
					if assignmentCache[experimentName] == assignment {
						assignmentCache.removeValue(forKey: experimentName)
					}
				}
			}
		}
	}

	public func getCustomAssignment(experimentName: String) -> Int? {
		return getLocked(lock: contextLock, dict: cassignments, key: experimentName)
	}

	public func setCustomAssignments(_ assignments: [String: Int]) {
		assignments.forEach { setCustomAssignment(experimentName: $0.key, variant: $0.value) }
	}

	public func setAttribute(name: String, value: JSON) {
		checkNotClosed()

		contextLock.lock()
		defer { contextLock.unlock() }

		attributes.append(Attribute(name, value: value, setAt: clock.millis()))
	}

	public func setAttributes(_ attributes: [String: JSON]) {
		attributes.forEach { setAttribute(name: $0, value: $1) }
	}

	public func getTreatment(_ experimentName: String) -> Int {
		checkReady(true)

		let assignment = getAssignment(experimentName)
		if !assignment.exposed.load(ordering: .relaxed) {
			queueExposure(assignment)
		}

		return assignment.variant
	}

	private func queueExposure(_ assignment: Assignment) {
		if !assignment.exposed.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).0 {
			return
		}

		let exposure = Exposure(
			assignment.id, assignment.name, assignment.unitType, assignment.variant,
			clock.millis(), assignment.assigned, assignment.eligible,
			assignment.overridden, assignment.fullOn, assignment.custom, assignment.audienceMismatch)

		do {
			eventLock.lock()
			defer { eventLock.unlock() }

			exposures.append(exposure)
			pendingCount.wrappingIncrement(by: 1, ordering: .relaxed)
		}

		logEvent(event: .exposure(exposure: exposure))

		setTimeout()
	}

	public func peekTreatment(_ experimentName: String) -> Int {
		checkReady(true)

		return getAssignment(experimentName).variant
	}

	public func getVariableKeys() -> [String: String] {
		checkReady(true)

		dataLock.lock()
		defer { dataLock.unlock() }

		return indexVariables.mapValues { $0.data.name }
	}

	public func getVariableValue(_ key: String, defaultValue: JSON? = nil) -> JSON? {
		checkReady(true)

		if let assignment = getVariableAssignment(key) {
			if !assignment.exposed.load(ordering: .relaxed) {
				queueExposure(assignment)
			}

			if let object = assignment.variables[key] {
				return object
			}
		}

		return defaultValue
	}

	public func peekVariableValue(_ key: String, defaultValue: JSON? = nil) -> JSON? {
		checkReady(true)

		if let assignment = getVariableAssignment(key) {
			if let object = assignment.variables[key] {
				return object
			}
		}

		return defaultValue
	}

	public func track(_ goalName: String, properties: [String: JSON]? = nil) {
		checkNotClosed()

		let achievement: GoalAchievement = GoalAchievement(
			goalName, achievedAt: clock.millis(), properties: properties)

		do {
			eventLock.lock()
			defer { eventLock.unlock() }

			achievements.append(achievement)
			pendingCount.wrappingIncrement(by: 1, ordering: .relaxed)
		}

		logEvent(event: .goal(goal: achievement))

		setTimeout()
	}

	public func getPendingCount() -> UInt {
		return pendingCount.load(ordering: .relaxed)
	}

	public func publish() -> Promise<Void> {
		checkNotClosed()

		return flush()
	}

	public func refresh() -> Promise<Void> {
		checkNotClosed()

		if !refreshing.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).0 {
			return refreshPromise!
		}

		refreshPromise = Promise<Void> { seal in
			provider.getContextData().done { [self] data in
				setData(data)
				refreshing.store(false, ordering: .relaxed)
				seal.fulfill(())

				logEvent(event: .refresh(data: data))
			}.catch { [self] error in
				refreshing.store(false, ordering: .relaxed)
				seal.reject(error)

				logError(error: error)
			}
		}

		return refreshPromise!
	}

	public func close() -> Promise<Void> {
		if !closed.load(ordering: .relaxed) {
			if !closing.compareExchange(expected: false, desired: true, ordering: .relaxed).0 {
				return closePromise!
			}

			closePromise = Promise<Void> { seal in
				closing.store(true, ordering: .relaxed)

				if pendingCount.load(ordering: .relaxed) > 0 {
					flush().done { [self] in
						closed.store(true, ordering: .relaxed)
						closing.store(false, ordering: .relaxed)
						seal.fulfill(())

						logEvent(event: .close)
					}.catch({ [self] error in
						closed.store(true, ordering: .relaxed)
						closing.store(true, ordering: .relaxed)
						seal.reject(error)

						// event logger gets this error during publish
					})
				} else {
					closed.store(true, ordering: .relaxed)
					closing.store(false, ordering: .relaxed)
					seal.fulfill(())

					logEvent(event: .close)
				}
			}
		}

		if let closePromise = closePromise {
			return closePromise
		}
		return Promise<Void>.value(())
	}

	private func flush() -> Promise<Void> {
		clearTimeout()

		if !isFailed() {
			var eventCount = pendingCount.load(ordering: .relaxed)
			if eventCount > 0 {
				var localExposures: [Exposure] = []
				var localAchievements: [GoalAchievement] = []

				do {
					eventLock.lock()
					defer { eventLock.unlock() }

					eventCount = pendingCount.load(ordering: .relaxed)
					if eventCount > 0 {
						if !exposures.isEmpty {
							localExposures = exposures
							exposures = []
						}

						if !achievements.isEmpty {
							localAchievements = achievements
							achievements = []
						}

						pendingCount.store(0, ordering: .relaxed)
					}
				}

				if eventCount > 0 {
					let event = PublishEvent(
						true,
						config.units.map {
							Unit(
								type: $0.key, uid: String(bytes: getUnitHash($0.key, $0.value), encoding: .ascii) ?? "")
						},
						clock.millis(),
						localExposures,
						localAchievements,
						attributes)

					return Promise<Void> { [self] seal in
						_ = handler.publish(event: event).done { [self] in
							seal.fulfill(())

							logEvent(event: .publish(event: event))
						}.catch { [self] error in
							seal.reject(error)

							logError(error: error)
						}
					}
				}
			}
		} else {
			eventLock.lock()
			defer { eventLock.unlock() }

			exposures = []
			achievements = []
			pendingCount.store(0, ordering: .relaxed)
		}

		return Promise<Void>.value(())
	}

	private func checkReady(_ expectNotClosed: Bool) {
		precondition(isReady(), "ABSmartly Context is not yet ready.")
		if expectNotClosed {
			checkNotClosed()
		}
	}

	private func checkNotClosed() {
		precondition(!isClosed(), "ABSmartly Context is closed.")
		precondition(!isClosing(), "ABSmartly Context is closing.")
	}

	private func experimentMatches(_ experiment: Experiment, _ assignment: Assignment) -> Bool {
		return experiment.id == assignment.id && experiment.unitType == assignment.unitType
			&& experiment.iteration == assignment.iteration && experiment.fullOnVariant == assignment.fullOnVariant
			&& experiment.trafficSplit == assignment.trafficSplit
	}

	private func getExperiment(_ experimentName: String) -> ExperimentVariables? {
		return getLocked(lock: dataLock, dict: index, key: experimentName)
	}

	private func getAssignment(_ experimentName: String) -> Assignment {
		assignmentLock.lock()
		defer { assignmentLock.unlock() }

		if let assignment = assignmentCache[experimentName] {
			return assignment
		}

		let experiment: ExperimentVariables? = getExperiment(experimentName)

		let assignment = Assignment()
		assignment.name = experimentName
		assignment.eligible = true

		if let override = overrides[experimentName] {
			if let experimentVariables = experiment {
				assignment.id = experimentVariables.data.id
				assignment.unitType = experimentVariables.data.unitType

				if let unitType = experimentVariables.data.unitType, config.units[unitType] != nil {
					assignment.assigned = true
				} else {
					assignment.assigned = false
				}
			}

			assignment.overridden = true
			assignment.variant = override
		} else {
			if let experiment = experiment {
				let unitType = experiment.data.unitType

				if let audience = experiment.data.audience {
					if audience.count > 0 {
						var attrs: [String: JSON] = [:]
						for attr in attributes {
							attrs[attr.name] = attr.value
						}

						if let result = matcher.evaluate(audience, attrs) {
							assignment.audienceMismatch = !result
						}
					}
				}

				if experiment.data.audienceStrict && assignment.audienceMismatch {
					assignment.variant = 0
				} else if experiment.data.fullOnVariant == 0 {
					if let unitType = experiment.data.unitType, let uid = config.units[unitType] {
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

				assignment.unitType = unitType
				assignment.id = experiment.data.id
				assignment.iteration = experiment.data.iteration
				assignment.trafficSplit = experiment.data.trafficSplit
				assignment.fullOnVariant = experiment.data.fullOnVariant
			}
		}

		if let experiment = experiment, assignment.variant < experiment.data.variants.count {
			assignment.variables = experiment.variables[assignment.variant]
		}

		assignmentCache[experimentName] = assignment
		return assignment
	}

	private func getVariableAssignment(_ key: String) -> Assignment? {
		guard let experiment = getVariableExperiment(key) else {
			return nil
		}

		return getAssignment(experiment.data.name)
	}

	private func getVariableExperiment(_ experimentName: String) -> ExperimentVariables? {
		return getLocked(lock: dataLock, dict: indexVariables, key: experimentName)
	}

	private func getUnitHash(_ unitType: String, _ unitUID: String) -> [UInt8] {
		assignmentLock.lock()
		defer { assignmentLock.unlock() }

		if let unitHash = hashedUnits[unitType] { return unitHash }

		let hashValue: [UInt8] = Hashing.hash(unitUID)
		hashedUnits[unitType] = hashValue
		return hashValue
	}

	private func getVariantAssigner(_ unitType: String, _ unitHash: [UInt8]) -> VariantAssigner {
		assignmentLock.lock()
		defer { assignmentLock.unlock() }

		if let variantAssigner = assigners[unitType] {
			return variantAssigner
		}

		let variantAssigner = VariantAssigner(unitHash)
		assigners[unitType] = variantAssigner

		return variantAssigner
	}

	private func setTimeout() {
		guard isReady() else { return }

		if timeout == nil {
			timeoutLock.lock()
			defer { timeoutLock.unlock() }

			if timeout == nil {
				timeout = scheduler.schedule(
					after: config.publishDelay,
					execute: { [self] in
						_ = flush()
					})
			}
		}
	}

	private func clearTimeout() {
		if timeout != nil {
			timeoutLock.lock()
			defer { timeoutLock.unlock() }

			timeout?.cancel()
			timeout = nil
		}
	}

	private func setData(_ data: ContextData) {
		var index: [String: ExperimentVariables] = [:]
		var indexVariables: [String: ExperimentVariables] = [:]

		for experiment in data.experiments {
			let experimentVariables = ExperimentVariables(experiment)

			for variant in experiment.variants {
				if let config = variant.config, !config.isEmpty {
					if let parsed = parser.parse(experimentName: experiment.name, config: config) {
						for (key, _) in parsed {
							indexVariables[key] = experimentVariables
						}
						experimentVariables.variables.append(parsed)
					} else {
						experimentVariables.variables.append([:])
					}
				} else {
					experimentVariables.variables.append([:])
				}
			}

			index[experiment.name] = experimentVariables
		}

		dataLock.lock()
		assignmentLock.lock()
		defer {
			assignmentLock.lock()
			dataLock.unlock()
		}

		assignmentCache.forEach { experimentName, assignment in
			if let experiment = index[experimentName] {
				if !assignment.assigned {
					// previously not running experiment was started
					assignmentCache.removeValue(forKey: experimentName)
				} else if !experimentMatches(experiment.data, assignment) {
					// other relevant experiment data changed
					assignmentCache.removeValue(forKey: experimentName)
				}
			} else {
				if assignment.assigned {
					// previously running experiment was stopped
					assignmentCache.removeValue(forKey: experimentName)
				}
			}
		}

		self.data = data
		self.index = index
		self.indexVariables = indexVariables
	}

	private func setDataFailed(_ error: Error) {
		dataLock.lock()
		defer { dataLock.unlock() }

		index = [:]
		indexVariables = [:]
		data = nil
		failed = true
	}

	private func logEvent(event: ContextEventLoggerEvent) {
		if let logger = logger {
			logger.handleEvent(context: self, event: event)
		}
	}

	private func logError(error: Error) {
		if let logger = logger {
			logger.handleEvent(context: self, event: ContextEventLoggerEvent.error(error: error))
		}
	}
}

private class ExperimentVariables {
	let data: Experiment
	var variables: [[String: JSON]] = []

	init(_ experiment: Experiment) {
		data = experiment
	}
}

private class Assignment: Equatable {
	static func == (lhs: Assignment, rhs: Assignment) -> Bool {
		return lhs.id == rhs.id && lhs.iteration == rhs.iteration && lhs.fullOnVariant == rhs.fullOnVariant
			&& lhs.name == rhs.name && lhs.unitType == rhs.unitType && lhs.trafficSplit == rhs.trafficSplit
			&& lhs.variant == rhs.variant && lhs.assigned == rhs.assigned && lhs.overridden == rhs.overridden
			&& lhs.eligible == rhs.eligible && lhs.fullOn == rhs.fullOn && lhs.custom == rhs.custom
			&& lhs.audienceMismatch == rhs.audienceMismatch && lhs.variables == rhs.variables
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
	var variables: [String: JSON] = [:]
	var exposed = ManagedAtomic<Bool>(false)
}
