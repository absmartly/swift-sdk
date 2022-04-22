import Atomics
import Foundation
import PromiseKit

public final class Context {
	private let readyLock = NSLock()
	private let dataLock = NSLock()
	private let timeoutLock = NSLock()
	private let eventLock = NSLock()

	private let clock: Clock
	private let scheduler: Scheduler
	private let handler: ContextEventHandler
	private let provider: ContextDataProvider
	private let parser: VariableParser
	private var promise: Promise<ContextData>?
	private var config: ContextConfig

	private var timeout: ScheduledHandle?

	private var index: [String: ExperimentVariables] = [:]
	private var indexVariables: [String: ExperimentVariables] = [:]
	private var data: ContextData?

	private var pendingCount = ManagedAtomic<UInt>(0)

	private var failed: Bool = false
	private var closed = ManagedAtomic<Bool>(false)
	private var closing = ManagedAtomic<Bool>(false)
	private var refreshing = ManagedAtomic<Bool>(false)
	private var readyPromise: Promise<Void>?
	private var refreshPromise: Promise<Void>?
	private var closePromise: Promise<Void>?

	private var attributes = ThreadSafeArray<Attribute>()
	private var overrides: ThreadSafeMap<String, Int>
	private var hashedUnits = ThreadSafeMap<String, [UInt8]>()
	private var assigners = ThreadSafeMap<String, VariantAssigner>()
	private var assignmentCache = ThreadSafeMap<String, Assignment>()

	private var exposures: [Exposure] = []
	private var achievements: [GoalAchievement] = []

	init(
		config: ContextConfig, clock: Clock, scheduler: Scheduler, handler: ContextEventHandler,
		provider: ContextDataProvider, parser: VariableParser, promise: Promise<ContextData>
	) {
		self.clock = clock
		self.scheduler = scheduler
		self.handler = handler
		self.provider = provider
		self.parser = parser
		self.promise = promise
		self.config = config

		overrides = ThreadSafeMap<String, Int>(with: config.overrides)
		setAttributes(config.attributes)

		if promise.isResolved {
			if let data = promise.value {
				self.setData(data)
			} else if let error = promise.error {
				self.setDataFailed(error)
			}
		} else {
			readyPromise = Promise<Void> { seal in
				promise.done { result in
					self.setData(result)
					seal.fulfill(())
					self.readyPromise = nil
					if self.pendingCount.load(ordering: .relaxed) > 0 {
						self.setTimeout()
					}
				}.catch { error in
					self.setDataFailed(error)
					self.readyPromise = nil
					seal.fulfill(())  // throw no user-visible errors

					Logger.error(error.localizedDescription)
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

	public func setOverride(experimentName: String, variant: Int) {
		checkNotClosed()

		let previous: Int? = overrides[experimentName]
		overrides[experimentName] = variant

		if previous == nil || previous != variant {
			if let assignment: Assignment = assignmentCache[experimentName] {
				if !assignment.overridden || assignment.variant != variant {
					if assignmentCache[experimentName] == assignment {
						assignmentCache.remove(experimentName)
					}
				}
			}
		}
	}

	public func getOverride(experimentName: String) -> Int? {
		return overrides[experimentName]
	}

	public func setOverrides(_ overrides: [String: Int]) {
		overrides.forEach { setOverride(experimentName: $0.key, variant: $0.value) }
	}

	public func setAttribute(name: String, value: JSON) {
		checkNotClosed()

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
			assignment.overridden, assignment.fullOn)

		do {
			eventLock.lock()
			defer { eventLock.unlock() }

			exposures.append(exposure)
			pendingCount.wrappingIncrement(by: 1, ordering: .relaxed)
		}

		setTimeout()
	}

	public func peekTreatment(_ experimentName: String) -> Int {
		checkReady(true)

		return getAssignment(experimentName).variant
	}

	public func getVariableKeys() -> [String: String] {
		checkReady(true)

		return indexVariables.mapValues { $0.data.name }
	}

	public func getVariableValue(key: String, defaultValue: JSON? = nil) -> JSON? {
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

	public func peekVariableValue(key: String, defaultValue: JSON? = nil) -> JSON? {
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
			provider.getContextData().done { data in
				self.setData(data)
				self.refreshing.store(false, ordering: .relaxed)
				seal.fulfill(())
			}.catch { error in
				self.refreshing.store(false, ordering: .relaxed)
				seal.reject(error)
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
				self.closing.store(true, ordering: .relaxed)

				if pendingCount.load(ordering: .relaxed) > 0 {
					flush().done {
						self.closed.store(true, ordering: .relaxed)
						self.closing.store(false, ordering: .relaxed)
						seal.fulfill(())
					}.catch({ error in
						self.closed.store(true, ordering: .relaxed)
						self.closing.store(true, ordering: .relaxed)
						seal.reject(error)
					})
				} else {
					self.closed.store(true, ordering: .relaxed)
					self.closing.store(false, ordering: .relaxed)
					seal.fulfill(())
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

		guard !isFailed() else {
			eventLock.lock()
			defer { eventLock.unlock() }

			exposures = []
			achievements = []
			pendingCount.store(0, ordering: .relaxed)

			return Promise<Void>.value(())
		}

		let eventCount = pendingCount.load(ordering: .relaxed)
		if eventCount == 0 {
			return Promise<Void>.value(())
		}

		if !pendingCount.compareExchange(expected: eventCount, desired: 0, ordering: .acquiringAndReleasing).0 {
			return Promise<Void>.value(())
		}

		let localExposures: [Exposure]
		let localAchievements: [GoalAchievement]
		do {
			eventLock.lock()
			defer { eventLock.unlock() }

			localExposures = self.exposures
			self.exposures = []

			localAchievements = self.achievements
			self.achievements = []
		}

		let event = PublishEvent(
			true,
			config.units.map {
				Unit(type: $0.key, uid: String(bytes: getUnitHash($0.key, $0.value), encoding: .ascii) ?? "")
			},
			clock.millis(),
			localExposures,
			localAchievements,
			attributes.rawArray)

		return handler.publish(event: event)
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
		dataLock.lock()
		defer {
			dataLock.unlock()
		}

		return index[experimentName]
	}

	private func getAssignment(_ experimentName: String) -> Assignment {
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

				if experiment.data.fullOnVariant == 0 {
					if let unitType = experiment.data.unitType, let uid = config.units[unitType] {
						let unitHash: [UInt8] = getUnitHash(unitType, uid)
						let assigner = getVariantAssigner(unitType, unitHash)

						let eligible =
							assigner.assign(
								experiment.data.trafficSplit, experiment.data.trafficSeedHi,
								experiment.data.trafficSeedLo) == 1

						if eligible {
							assignment.variant = assigner.assign(
								experiment.data.split, experiment.data.seedHi, experiment.data.seedLo)
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
		dataLock.lock()
		defer { dataLock.unlock() }

		return indexVariables[experimentName]
	}

	private func getUnitHash(_ unitType: String, _ unitUID: String) -> [UInt8] {
		if let unitHash = hashedUnits[unitType] { return unitHash }

		let hashValue: [UInt8] = Hashing.hash(unitUID)
		hashedUnits[unitType] = hashValue
		return hashValue
	}

	private func getVariantAssigner(_ unitType: String, _ unitHash: [UInt8]) -> VariantAssigner {
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

			timeout = scheduler.schedule(
				after: config.publishDelay,
				execute: {
					_ = self.flush()
				})
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
		defer {
			dataLock.unlock()
		}

		var previousAssignments: [String: Assignment] = [:]
		var assignments = hasNewValues(previousAssignments, assignmentCache.rawHashmap)

		while assignments.count > 0 {
			for entry in assignments {

				if let experiment = index[entry.key] {
					if !entry.value.assigned {
						assignmentCache.remove(entry.key)
					} else if !experimentMatches(experiment.data, entry.value) {
						assignmentCache.remove(entry.key)
					}
				} else {
					if entry.value.assigned {
						assignmentCache.remove(entry.key)
					}
				}

				previousAssignments[entry.key] = entry.value
			}

			assignments = hasNewValues(previousAssignments, assignmentCache.rawHashmap)
		}

		self.data = data
		self.index = index
		self.indexVariables = indexVariables
	}

	private func hasNewValues(_ lastData: [String: Assignment], _ newData: [String: Assignment]) -> [String: Assignment]
	{
		var newValues: [String: Assignment] = [:]

		for item in newData {
			if lastData.keys.contains(item.key) { continue }
			newValues[item.key] = item.value
		}

		return newValues
	}

	private func setDataFailed(_ error: Error) {
		dataLock.lock()
		defer { dataLock.unlock() }

		index = [:]
		indexVariables = [:]
		data = nil
		failed = true
	}
}

private class ExperimentVariables {
	let data: Experiment
	var variables: [[String: JSON]] = []

	init(_ experiment: Experiment) {
		self.data = experiment
	}
}

private class Assignment: Equatable {
	static func == (lhs: Assignment, rhs: Assignment) -> Bool {
		return lhs.id == rhs.id && lhs.iteration == rhs.iteration && lhs.fullOnVariant == rhs.fullOnVariant
			&& lhs.name == rhs.name && lhs.unitType == rhs.unitType && lhs.trafficSplit == rhs.trafficSplit
			&& lhs.variant == rhs.variant && lhs.assigned == rhs.assigned && lhs.overridden == rhs.overridden
			&& lhs.eligible == rhs.eligible && lhs.fullOn == rhs.fullOn && lhs.variables == rhs.variables
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
	var variables: [String: JSON] = [:]
	var exposed = ManagedAtomic<Bool>(false)
}
