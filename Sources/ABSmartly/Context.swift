import Atomics
import Foundation
#if canImport(MapKit)
import MapKit
#endif
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
	private var promise: Promise<ContextData>?

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
	private var refreshTimer: ScheduledHandle?

	private let dataLock = NSLock()
	private var index: [String: ExperimentVariables] = [:]
	private var indexVariables: [String: [ExperimentVariables]] = [:]
	private var customFieldValues: [String: [String: ContextCustomFieldValue]] = [:]
	private var data: ContextData? = nil

	private var hashedUnits: [String: [UInt8]] = [:]
	private var assigners: [String: VariantAssigner] = [:]
	private var assignmentCache: [String: Assignment] = [:]

	private let contextLock = NSRecursiveLock()
	private var units: [String: String] = [:]
	private var attributes: [Attribute] = []
	private let maxAttributes = 500
	private var overrides: [String: Int] = [:]
	private var cassignments: [String: Int] = [:]

	private let eventLock = NSLock()
	private var exposures: [Exposure] = []
	private var achievements: [GoalAchievement] = []
	private let maxExposures = 500
	private let maxAchievements = 500

	private var publishDelay: TimeInterval = 0
	private var refreshInterval: TimeInterval = 0
	private var attrsSeq: Int = 0

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

		publishDelay = config.publishDelay
		refreshInterval = config.refreshInterval

		assigners.reserveCapacity(config.units.count)
		hashedUnits.reserveCapacity(config.units.count)

		overrides.reserveCapacity(config.overrides.count)
		overrides.merge(config.overrides, uniquingKeysWith: { (_, new) in new })

		cassignments.reserveCapacity(config.cassignments.count)
		cassignments.merge(config.cassignments, uniquingKeysWith: { (_, new) in new })

		attributes.reserveCapacity(config.attributes.count)
		setAttributes(config.attributes)

		units.reserveCapacity(config.units.count)
		setUnits(config.units)

		if promise.isResolved {
			if let data = promise.value {
				setData(data)

				logEvent(event: .ready(data: data))
			} else if let error = promise.error {
				setDataFailed(error)

				logError(error: error)
			}
		} else {
			readyPromise = Promise<Void> { [weak self] seal in
				guard let self = self else {
					seal.fulfill(())
					return
				}

				promise.done(on: DispatchQueue.global()) { [weak self] data in
					guard let self = self else { return }
					self.setData(data)
					seal.fulfill(())
					self.readyPromise = nil

					self.logEvent(event: .ready(data: data))

					if self.pendingCount.load(ordering: .acquiring) > 0 {
						self.setTimeout()
					}
				}.catch(on: DispatchQueue.global()) { [weak self] error in
					guard let self = self else { return }
					self.setDataFailed(error)
					self.readyPromise = nil
					seal.fulfill(())  // throw no user-visible errors

					self.logError(error: error)
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
		return !closed.load(ordering: .acquiring) && closing.load(ordering: .acquiring)
	}

	public func isClosed() -> Bool {
		return closed.load(ordering: .acquiring)
	}

	public func waitUntilReady() -> Promise<Context> {
		return Promise<Context> { [weak self] seal in
			guard let self = self else {
				seal.reject(ABSmartlyError("Context was deallocated"))
				return
			}
			if self.isReady() || self.readyPromise == nil {
				seal.fulfill(self)
			} else if let ready = self.readyPromise {
				_ = ready.done(on: DispatchQueue.global()) { [weak self] in
					guard let self = self else { return }
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

	public func getCustomFieldKeys() -> Set<String> {
		var keys: Set<String> = []

		dataLock.lock()
		defer { dataLock.unlock() }

		for experiment in data!.experiments {
			let customFieldValues = experiment.customFieldValues
			if customFieldValues != nil {
				for customFieldValue in customFieldValues! {
					keys.insert(customFieldValue.name!)
				}
			}
		}

		return keys
	}

	public func getCustomFieldKeys(experimentName: String) -> [String] {
		dataLock.lock()
		defer { dataLock.unlock() }

		guard let experimentCustomFields = customFieldValues[experimentName] else {
			return []
		}

		return Array(experimentCustomFields.keys)
	}

	public func getCustomFieldValue(experimentName: String, key: String) -> Any? {
		dataLock.lock()
		defer { dataLock.unlock() }

		let experimentCustomFieldValues = customFieldValues[experimentName]

		if experimentCustomFieldValues != nil {
			let field = experimentCustomFieldValues?[key]
			if field != nil {
				return field?.value
			}
		}
		return nil
	}

	public func getCustomFieldValueType(experimentName: String, key: String) -> String? {
		dataLock.lock()
		defer { dataLock.unlock() }

		let experimentCustomFieldValues = customFieldValues[experimentName]

		if experimentCustomFieldValues != nil {
			let field = experimentCustomFieldValues?[key]
			if field != nil {
				return field?.type
			}
		}
		return nil
	}

	public func getContextData() -> ContextData? {
		checkReady(true)

		dataLock.lock()
		defer { dataLock.unlock() }
		return data
	}

	private func putLocked<K, V>(lock: NSRecursiveLock, dict: inout [K: V], key: K, value: V) -> V? {
		lock.lock()
		defer { lock.unlock() }
		return dict.updateValue(value, forKey: key)
	}

	private func getLocked<K, V>(lock: NSRecursiveLock, dict: [K: V], key: K) -> V? {
		lock.lock()
		defer { lock.unlock() }
		return dict[key]
	}

	private func getLocked<K, V>(lock: NSLock, dict: [K: V], key: K) -> V? {
		lock.lock()
		defer { lock.unlock() }
		return dict[key]
	}

	public func setOverride(experimentName: String, variant: Int) {
		checkNotClosed()

		_ = putLocked(lock: contextLock, dict: &overrides, key: experimentName, value: variant)
	}

	public func getOverride(experimentName: String) -> Int? {
		return getLocked(lock: contextLock, dict: overrides, key: experimentName)
	}

	public func setOverrides(_ overrides: [String: Int]) {
		overrides.forEach { setOverride(experimentName: $0.key, variant: $0.value) }
	}

	public func setCustomAssignment(experimentName: String, variant: Int) {
		checkNotClosed()

		_ = putLocked(lock: contextLock, dict: &cassignments, key: experimentName, value: variant)
	}

	public func getCustomAssignment(experimentName: String) -> Int? {
		return getLocked(lock: contextLock, dict: cassignments, key: experimentName)
	}

	public func setCustomAssignments(_ assignments: [String: Int]) {
		assignments.forEach { setCustomAssignment(experimentName: $0.key, variant: $0.value) }
	}

	public func getUnit(unitType: String) -> String? {
		return getLocked(lock: contextLock, dict: units, key: unitType)
	}

	public func setUnit(unitType: String, uid: String) {
		guard !isClosed() && !isClosing() else { return }

		let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			Logger.error("Unit '\(unitType)' UID must not be blank.")
			return
		}

		contextLock.lock()
		defer { contextLock.unlock() }

		if let previous = units[unitType], previous != uid {
			Logger.error("Unit '\(unitType)' already set to different value.")
			return
		}

		units[unitType] = trimmed
	}

	public func getUnits() -> [String: String] {
		contextLock.lock()
		defer { contextLock.unlock() }

		return units
	}

	public func setUnits(_ units: [String: String]) {
		units.forEach { setUnit(unitType: $0, uid: $1) }
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
		checkNotClosed()

		contextLock.lock()
		defer { contextLock.unlock() }

		if attributes.count >= maxAttributes {
			attributes.removeFirst(maxAttributes / 4)
		}

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
		attributes.forEach { setAttribute(name: $0, value: $1) }
	}

	public func getTreatment(_ experimentName: String) -> Int {
		checkReady(true)

		let assignment = getAssignment(experimentName)
		if !assignment.exposed.load(ordering: .acquiring) {
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

			if exposures.count >= maxExposures {
				let removeCount = maxExposures / 4
				exposures.removeFirst(removeCount)
				pendingCount.wrappingDecrement(by: UInt(removeCount), ordering: .releasing)
			}

			exposures.append(exposure)
			pendingCount.wrappingIncrement(by: 1, ordering: .releasing)
		}

		logEvent(event: .exposure(exposure: exposure))

		setTimeout()
	}

	public func peekTreatment(_ experimentName: String) -> Int {
		checkReady(true)

		return getAssignment(experimentName).variant
	}

	public func getVariableKeys() -> [String: [String]] {
		checkReady(true)

		dataLock.lock()
		defer { dataLock.unlock() }

		return indexVariables.mapValues { $0.map({ $0.data.name }) }
	}

	public func getVariableValue(_ key: String, defaultValue: JSON? = nil) -> JSON? {
		checkReady(true)

		if let assignment = getVariableAssignment(key), let variables = assignment.variables {
			if !assignment.exposed.load(ordering: .acquiring) {
				queueExposure(assignment)
			}

			if let object = variables[key] {
				return object
			}
		}

		return defaultValue
	}

	public func peekVariableValue(_ key: String, defaultValue: JSON? = nil) -> JSON? {
		checkReady(true)

		if let assignment = getVariableAssignment(key), let variables = assignment.variables {
			if let object = variables[key] {
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

			if achievements.count >= maxAchievements {
				let removeCount = maxAchievements / 4
				achievements.removeFirst(removeCount)
				pendingCount.wrappingDecrement(by: UInt(removeCount), ordering: .releasing)
			}

			achievements.append(achievement)
			pendingCount.wrappingIncrement(by: 1, ordering: .releasing)
		}

		logEvent(event: .goal(goal: achievement))

		setTimeout()
	}

	public func getPendingCount() -> UInt {
		return pendingCount.load(ordering: .acquiring)
	}

	public func publish() -> Promise<Void> {
		checkNotClosed()

		return flush()
	}

	public func refresh() -> Promise<Void> {
		checkNotClosed()

		if !refreshing.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).0 {
			if let existingPromise = refreshPromise {
				return existingPromise
			}
			return Promise<Void>.value(())
		}

		refreshPromise = Promise<Void> { [weak self] seal in
			guard let self = self else {
				seal.fulfill(())
				return
			}

			self.provider.getContextData().done(on: DispatchQueue.global()) { [weak self] data in
				guard let self = self else { return }
				self.setData(data)
				self.refreshing.store(false, ordering: .releasing)
				seal.fulfill(())

				self.logEvent(event: .refresh(data: data))
			}.catch(on: DispatchQueue.global()) { [weak self] error in
				guard let self = self else { return }
				self.refreshing.store(false, ordering: .releasing)
				seal.reject(error)

				self.logError(error: error)
			}
		}

		return refreshPromise!
	}

	public func close() -> Promise<Void> {
		if !closed.load(ordering: .acquiring) {
			if !closing.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).0 {
				if let existingPromise = closePromise {
					return existingPromise
				}
				return Promise<Void>.value(())
			}

			closePromise = Promise<Void> { [weak self] seal in
				guard let self = self else {
					seal.fulfill(())
					return
				}

				self.clearRefreshTimer()

				if self.pendingCount.load(ordering: .acquiring) > 0 {
					self.flush().done(on: DispatchQueue.global()) { [weak self] in
						guard let self = self else { return }
						self.closed.store(true, ordering: .releasing)
						self.closing.store(false, ordering: .releasing)
						self.logEvent(event: .close)
						seal.fulfill(())
					}.catch(on: DispatchQueue.global()) { [weak self] error in
						guard let self = self else { return }
						self.closed.store(true, ordering: .releasing)
						self.closing.store(true, ordering: .releasing)
						seal.reject(error)
					}
				} else {
					self.closed.store(true, ordering: .releasing)
					self.closing.store(false, ordering: .releasing)
					self.logEvent(event: .close)
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

		if !isFailed() {
			var eventCount = pendingCount.load(ordering: .acquiring)
			if eventCount > 0 {
				var localExposures: [Exposure] = []
				var localAchievements: [GoalAchievement] = []
				var localUnits: [Unit] = []
				var localAttributes: [Attribute] = []

				do {
					eventLock.lock()
					defer { eventLock.unlock() }

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
					}
				}

				if eventCount > 0 {
					contextLock.lock()
					localUnits = units.map {
						Unit(
							type: $0.key, uid: String(bytes: getUnitHash($0.key, $0.value), encoding: .ascii) ?? "")
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

					return handler.publish(event: event).done(on: DispatchQueue.global()) { [weak self] in
						guard let self = self else { return }
						self.logEvent(event: .publish(event: event))
					}.recover { [weak self] error -> Promise<Void> in
						guard let self = self else { return Promise.value(()) }
						self.logError(error: error)
						throw error
					}
				}
			}
		} else {
			eventLock.lock()
			defer { eventLock.unlock() }

			exposures = []
			achievements = []
			pendingCount.store(0, ordering: .releasing)
		}

		return Promise<Void>.value(())
	}

	private func checkReady(_ expectNotClosed: Bool) {
		if !isReady() {
			Logger.error("ABSmartly Context is not yet ready.")
		}
		if expectNotClosed {
			checkNotClosed()
		}
	}

	private func checkNotClosed() {
		if isClosed() {
			Logger.error("ABSmartly Context is closed.")
		}
		if isClosing() {
			Logger.error("ABSmartly Context is closing.")
		}
	}

	private func experimentMatches(_ experiment: Experiment, _ assignment: Assignment) -> Bool {
		return experiment.id == assignment.id && experiment.unitType == assignment.unitType
			&& experiment.iteration == assignment.iteration && experiment.fullOnVariant == assignment.fullOnVariant
			&& experiment.trafficSplit == assignment.trafficSplit
	}

	private func audienceMatches(_ experiment: Experiment, _ assignment: Assignment) -> Bool {
		if let audience = experiment.audience, audience.count > 0 {
			if attrsSeq > assignment.attrsSeq {
				var attrs: [String: JSON] = [:]
				for attr in attributes {
					attrs[attr.name] = attr.value
				}

				let result = matcher.evaluate(audience, attrs)
				let newAudienceMismatch = result != nil ? !result! : false

				if newAudienceMismatch != assignment.audienceMismatch {
					return false
				}

				assignment.attrsSeq = attrsSeq
			}
		}
		return true
	}

	private func getExperiment(_ experimentName: String) -> ExperimentVariables? {
		return getLocked(lock: dataLock, dict: index, key: experimentName)
	}

	private func getAssignment(_ experimentName: String) -> Assignment {
		contextLock.lock()
		defer { contextLock.unlock() }

		let experiment: ExperimentVariables? = getExperiment(experimentName)

		if let assignment = assignmentCache[experimentName] {
			if let override = overrides[experimentName] {
				if assignment.overridden && assignment.variant == override {
					// override up-to-date
					return assignment
				}
			} else if experiment == nil {
				if !assignment.assigned {
					// previously not-running experiment
					return assignment
				}
			} else {
				let custom = cassignments[experimentName]
				if custom == nil || custom! == assignment.variant {
					if experimentMatches(experiment!.data, assignment) && audienceMatches(experiment!.data, assignment) {
						// assignment up-to-date
						return assignment
					}
				}
			}
		}

		let assignment = Assignment()
		assignment.name = experimentName
		assignment.eligible = true

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

	private func getVariableAssignment(_ key: String) -> Assignment? {
		guard let keyExperimentVariables = getVariableExperiments(key) else {
			return nil
		}

		for experimentVariables in keyExperimentVariables {
			let assignment = getAssignment(experimentVariables.data.name)
			if assignment.assigned || assignment.overridden {
				return assignment
			}
		}

		return nil
	}

	private func getVariableExperiments(_ experimentName: String) -> [ExperimentVariables]? {
		return getLocked(lock: dataLock, dict: indexVariables, key: experimentName)
	}

	private func getUnitHash(_ unitType: String, _ unitUID: String) -> [UInt8] {
		contextLock.lock()
		defer { contextLock.unlock() }

		if let unitHash = hashedUnits[unitType] { return unitHash }

		let hashValue: [UInt8] = Hashing.hash(unitUID)
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

	private func setTimeout() {
		guard isReady() else { return }
		guard publishDelay >= 0 else { return }

		if timeout == nil {
			timeoutLock.lock()
			defer { timeoutLock.unlock() }

			if timeout == nil {
				timeout = scheduler.schedule(
					after: publishDelay,
					execute: { [weak self] in
						_ = self?.flush()
					})
			}
		}
	}

	private func clearTimeout() {
		timeoutLock.lock()
		defer { timeoutLock.unlock() }

		timeout?.cancel()
		timeout = nil
	}

	private func setRefreshTimer() {
		if refreshInterval > 0 && refreshTimer == nil {
			refreshTimer = scheduler.scheduleWithFixedDelay(
				after: refreshInterval, repeating: refreshInterval,
				execute: { [weak self] in
					_ = self?.refresh().done(on: DispatchQueue.global()) {}
				})
		}
	}

	private func clearRefreshTimer() {
		refreshTimer?.cancel()
		refreshTimer = nil
	}

	public func setData(_ data: ContextData) {
		var index: [String: ExperimentVariables] = [:]
		var indexVariables: [String: [ExperimentVariables]] = [:]
		var customFieldValues: [String: [String: ContextCustomFieldValue]] = [:]

		for experiment in data.experiments {
			let experimentVariables = ExperimentVariables(experiment)
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

			if experiment.customFieldValues != nil {
				for customFieldValue in experiment.customFieldValues! {
					let value = ContextCustomFieldValue()
					value.type = customFieldValue.type!

					if customFieldValue.value != nil {
						let customValue = customFieldValue.value!
						if customFieldValue.type!.starts(with: "json") {
							let data = Data(customValue.utf8)
							do {
								let jsonObject = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
								let nativeValue = jsonObjectToNative(jsonObject)
								value.value = nativeValue
							} catch {
								Logger.error("Failed to parse JSON custom field: \(error.localizedDescription)")
								value.value = nil
							}
						} else if customFieldValue.type!.starts(with: "boolean") {
							let lowercased = customValue.lowercased()
							value.value = lowercased == "true" || lowercased == "1"
						} else if customFieldValue.type!.starts(with: "number") {
							if let intVal = Int(customValue) {
								value.value = intVal
							} else if let doubleVal = Double(customValue) {
								value.value = doubleVal
							} else {
								value.value = nil
							}
						} else {
							value.value = customFieldValue.value
						}
					}

					experimentCustomFieldValues[customFieldValue.name!] = value
				}
			}

			index[experiment.name] = experimentVariables
			customFieldValues[experiment.name] = experimentCustomFieldValues
		}



		dataLock.lock()
		self.data = data
		self.index = index
		self.indexVariables = indexVariables
		self.customFieldValues = customFieldValues
		dataLock.unlock()

		contextLock.lock()
		assignmentCache = [:]
		contextLock.unlock()

		setRefreshTimer()
	}

	private func setDataFailed(_ error: Error) {
		dataLock.lock()
		defer { dataLock.unlock() }

		index = [:]
		indexVariables = [:]
		data = nil
		failed = true
	}

	private func jsonToNative(_ json: JSON) -> Any? {
		if let dict = json.dictionary {
			var result: [String: Any] = [:]
			for (key, value) in dict {
				if let nativeValue = jsonToNative(value) {
					result[key] = nativeValue
				}
			}
			return result
		} else if let array = json.array {
			return array.compactMap { jsonToNative($0) }
		} else if let string = json.string {
			return string
		} else if let number = json.number {
			return number
		} else if let bool = json.bool {
			return bool
		} else if json.null != nil {
			return nil
		}
		return nil
	}

	private func jsonObjectToNative(_ jsonObject: Any) -> Any? {
		if jsonObject is NSNull {
			return nil
		} else if let dict = jsonObject as? [String: Any] {
			var result: [String: Any] = [:]
			for (key, value) in dict {
				if let nativeValue = jsonObjectToNative(value) {
					result[key] = nativeValue
				}
			}
			return result
		} else if let array = jsonObject as? [Any] {
			return array.compactMap { jsonObjectToNative($0) }
		} else if let string = jsonObject as? String {
			return string
		} else if let bool = jsonObject as? Bool {
			return bool
		} else if let number = jsonObject as? NSNumber {
			return number
		}
		return jsonObject
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

private class ContextCustomFieldValue {
	var type: String?
	var value: Any?
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
	var variables: [String: JSON]?
	var exposed = ManagedAtomic<Bool>(false)
	var attrsSeq: Int = 0
}
