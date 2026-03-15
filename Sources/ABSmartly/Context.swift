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
	private var promise: Promise<ContextData>?

	private var pendingCount = ManagedAtomic<UInt>(0)

	private var ready = ManagedAtomic<Bool>(false)
	private var failed = ManagedAtomic<Bool>(false)
	private var closed = ManagedAtomic<Bool>(false)
	private var closing = ManagedAtomic<Bool>(false)
	private var refreshing = ManagedAtomic<Bool>(false)

	private let promiseLock = NSLock()
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
	private var failedError: Error? = nil

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
						self.promiseLock.lock()
						self.readyPromise = nil
						self.promiseLock.unlock()

						self.logEvent(event: .ready(data: data))
						if self.pendingCount.load(ordering: .acquiring) > 0 {
							self.setTimeout()
						}
						seal.fulfill(())
					}.catch(on: DispatchQueue.global()) { [weak self] error in
						guard let self = self else { return }
						self.setDataFailed(error)
						self.promiseLock.lock()
						self.readyPromise = nil
						self.promiseLock.unlock()
						Logger.error("Context initialization failed: \(error.localizedDescription)")

						self.logError(error: error)
						seal.reject(error)
					}
				}
			}
		}

	public func isReady() -> Bool {
		return ready.load(ordering: .acquiring) || failed.load(ordering: .acquiring)
	}

	public func isFailed() -> Bool {
		return failed.load(ordering: .acquiring)
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
				_ = ready.done(on: DispatchQueue.global()) { [weak self] in
					guard let self = self else { return }
					seal.fulfill(self)
				}.catch(on: DispatchQueue.global()) { [weak self] _ in
					guard let self = self else { return }
					seal.fulfill(self)
				}
			}
		}
	}

	public func getExperiments() -> [String] {
		guard checkReady(true) else { return [] }

		dataLock.lock()
		defer { dataLock.unlock() }
		return data?.experiments.map { $0.name } ?? []
	}

	public func getCustomFieldKeys() -> Set<String> {
		var keys: Set<String> = []

		dataLock.lock()
		defer { dataLock.unlock() }

		guard let data = data else { return keys }

		for experiment in data.experiments {
			guard let customFieldValues = experiment.customFieldValues else { continue }
			for customFieldValue in customFieldValues {
				guard let name = customFieldValue.name else { continue }
				keys.insert(name)
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

		return customFieldValues[experimentName]?[key]?.value
	}

	public func getCustomFieldValueType(experimentName: String, key: String) -> String? {
		dataLock.lock()
		defer { dataLock.unlock() }

		return customFieldValues[experimentName]?[key]?.type
	}

	public func getContextData() -> ContextData? {
		guard checkReady(true) else { return nil }

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
		_ = putLocked(lock: contextLock, dict: &overrides, key: experimentName, value: variant)
	}

	public func getOverride(experimentName: String) -> Int? {
		return getLocked(lock: contextLock, dict: overrides, key: experimentName)
	}

	public func setOverrides(_ overrides: [String: Int]) {
		for (key, value) in overrides {
			setOverride(experimentName: key, variant: value)
		}
	}

	public func setCustomAssignment(experimentName: String, variant: Int) {
		guard checkNotClosed() else { return }

		_ = putLocked(lock: contextLock, dict: &cassignments, key: experimentName, value: variant)
	}

	public func getCustomAssignment(experimentName: String) -> Int? {
		return getLocked(lock: contextLock, dict: cassignments, key: experimentName)
	}

	public func setCustomAssignments(_ assignments: [String: Int]) {
		for (key, value) in assignments {
			setCustomAssignment(experimentName: key, variant: value)
		}
	}

	public func getUnit(unitType: String) -> String? {
		return getLocked(lock: contextLock, dict: units, key: unitType)
	}

	private static let maxUnitUIDLength = 256

	public func setUnit(unitType: String, uid: String) {
		guard !isClosed() && !isClosing() else {
			Logger.error("ABSmartly Context is finalized.")
			return
		}

		let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			Logger.error("Unit '\(unitType)' UID must not be blank")
			return
		}

		guard trimmed.count <= Self.maxUnitUIDLength else {
			Logger.error("Unit '\(unitType)' UID exceeds maximum length of \(Self.maxUnitUIDLength) characters")
			return
		}

		contextLock.lock()
		defer { contextLock.unlock() }

		if let previous = units[unitType], previous != uid {
			Logger.error("Unit '\(unitType)' already set to '\(previous)', cannot change to '\(uid)'")
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
		guard checkNotClosed() else { return }

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
		for (name, value) in attributes {
			setAttribute(name: name, value: value)
		}
	}

	public func getTreatment(_ experimentName: String) -> Int {
		guard checkReady(true) else { return 0 }

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
		guard checkReady(true) else { return 0 }

		return getAssignment(experimentName).variant
	}

	public func getVariableKeys() -> [String: [String]] {
		guard checkReady(true) else { return [:] }

		dataLock.lock()
		defer { dataLock.unlock() }

		return indexVariables.mapValues { $0.map({ $0.data.name }) }
	}

	public func getVariableValue(_ key: String, defaultValue: JSON? = nil) -> JSON? {
		guard checkReady(true) else { return defaultValue }

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
		guard checkReady(true) else { return defaultValue }

		if let assignment = getVariableAssignment(key), let variables = assignment.variables {
			if let object = variables[key] {
				return object
			}
		}

		return defaultValue
	}

	public func track(_ goalName: String, properties: [String: JSON]? = nil) {
		guard checkNotClosed() else { return }

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
		guard checkNotClosed() else { return Promise<Void>.value(()) }

		return flush()
	}

	public func refresh() -> Promise<Void> {
		guard checkNotClosed() else { return Promise<Void>.value(()) }

		if !refreshing.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).0 {
			promiseLock.lock()
			let existingPromise = refreshPromise
			promiseLock.unlock()
			if let existingPromise = existingPromise {
				return existingPromise
			}
			return Promise<Void>.value(())
		}

		let promise = Promise<Void> { [weak self] seal in
			guard let self = self else {
				seal.fulfill(())
				return
			}

			self.provider.getContextData().done(on: DispatchQueue.global()) { [weak self] data in
				guard let self = self else { return }
				self.setData(data)
				self.refreshing.store(false, ordering: .releasing)
				self.logEvent(event: .refresh(data: data))
				seal.fulfill(())
			}.catch(on: DispatchQueue.global()) { [weak self] error in
				guard let self = self else { return }
				self.refreshing.store(false, ordering: .releasing)

				Logger.error("Context refresh failed: \(error.localizedDescription)")
				self.logError(error: error)

				seal.reject(error)
			}
		}

		promiseLock.lock()
		refreshPromise = promise
		promiseLock.unlock()
		return promise
	}

	public func close() -> Promise<Void> {
		if !closed.load(ordering: .acquiring) {
			if !closing.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).0 {
				promiseLock.lock()
				let existingPromise = closePromise
				promiseLock.unlock()
				if let existingPromise = existingPromise {
					return existingPromise
				}
				return Promise<Void>.value(())
			}

			let newClosePromise = Promise<Void> { [weak self] seal in
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
						self.closing.store(false, ordering: .releasing)
						seal.reject(error)
					}
				} else {
					self.closed.store(true, ordering: .releasing)
					self.closing.store(false, ordering: .releasing)
					self.logEvent(event: .close)
					seal.fulfill(())
				}
			}
			promiseLock.lock()
			closePromise = newClosePromise
			promiseLock.unlock()
		}

		promiseLock.lock()
		let currentClosePromise = closePromise
		promiseLock.unlock()
		if let closePromise = currentClosePromise {
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
					defer { contextLock.unlock() }
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

						self.eventLock.lock()
						self.exposures.insert(contentsOf: localExposures, at: 0)
						self.achievements.insert(contentsOf: localAchievements, at: 0)
						self.pendingCount.wrappingIncrement(by: UInt(eventCount), ordering: .releasing)
						self.eventLock.unlock()

						Logger.error("Publish failed: \(error.localizedDescription)")
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

	private func checkReady(_ expectNotClosed: Bool) -> Bool {
		if !isReady() {
			Logger.error("ABSmartly Context is not yet ready.")
			return false
		}
		if expectNotClosed {
			return checkNotClosed()
		}
		return true
	}

	private func checkNotClosed() -> Bool {
		if isClosed() {
			Logger.error("ABSmartly Context is finalized.")
			return false
		}
		if isClosing() {
			Logger.error("ABSmartly Context is finalizing.")
			return false
		}
		return true
	}

	private func buildAttributeMap() -> [String: JSON] {
		var attrs: [String: JSON] = [:]
		for attr in attributes {
			attrs[attr.name] = attr.value
		}
		return attrs
	}

	private func experimentMatches(_ experiment: Experiment, _ assignment: Assignment) -> Bool {
		return experiment.id == assignment.id && experiment.unitType == assignment.unitType
			&& experiment.iteration == assignment.iteration && experiment.fullOnVariant == assignment.fullOnVariant
			&& experiment.trafficSplit == assignment.trafficSplit
	}

	private func audienceMatches(_ experiment: Experiment, _ assignment: Assignment) -> Bool {
		if let audience = experiment.audience, audience.count > 0 {
			if attrsSeq > assignment.attrsSeq {
				let attrs = buildAttributeMap()

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
			} else if let exp = experiment {
				let custom = cassignments[experimentName]
				if let customVariant = custom {
					if customVariant == assignment.variant && experimentMatches(exp.data, assignment) && audienceMatches(exp.data, assignment) {
						// assignment up-to-date
						return assignment
					}
				} else if experimentMatches(exp.data, assignment) && audienceMatches(exp.data, assignment) {
					// assignment up-to-date
					return assignment
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

	private func setTimeout() {
		guard isReady() else { return }
		guard publishDelay >= 0 else { return }

		timeoutLock.lock()
		defer { timeoutLock.unlock() }

		if timeout == nil {
				timeout = scheduler.schedule(
					after: publishDelay,
					execute: { [weak self] in
						guard let self = self else { return }
						self.flush().catch { error in
							Logger.error("Auto-flush failed: \(error.localizedDescription)")
							self.logError(error: error)
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
		if refreshInterval > 0 && refreshTimer == nil {
			refreshTimer = scheduler.scheduleWithFixedDelay(
				after: refreshInterval, repeating: refreshInterval,
				execute: { [weak self] in
					guard let self = self else { return }
					self.refresh()
						.done { }
						.catch { error in
							Logger.error("Auto-refresh failed: \(error.localizedDescription)")
							self.logError(error: error)
						}
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

			if let fieldValues = experiment.customFieldValues {
				for customFieldValue in fieldValues {
					guard let fieldType = customFieldValue.type,
						  let fieldName = customFieldValue.name else { continue }

					let value = ContextCustomFieldValue()
					value.type = fieldType

					if let customValue = customFieldValue.value {
						if fieldType.starts(with: "json") {
							let data = Data(customValue.utf8)
							do {
								let jsonObject = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
								let nativeValue = jsonObjectToNative(jsonObject)
								value.value = nativeValue
							} catch {
								Logger.error("Failed to parse JSON custom field '\(fieldName)' for experiment '\(experiment.name)': \(error.localizedDescription). Original value: '\(customValue.prefix(100))...'")
								value.value = nil
							}
						} else if fieldType.starts(with: "boolean") {
							let lowercased = customValue.lowercased()
							value.value = lowercased == "true" || lowercased == "1"
						} else if fieldType.starts(with: "number") {
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

					experimentCustomFieldValues[fieldName] = value
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

		// Only reset exposed flag for assignments where the experiment data changed.
		contextLock.lock()
		defer { contextLock.unlock() }
		for (experimentName, assignment) in assignmentCache {
			if let experiment = index[experimentName] {
				if !experimentMatches(experiment.data, assignment) {
					assignment.exposed.store(false, ordering: .releasing)
				}
			} else {
				assignment.exposed.store(false, ordering: .releasing)
			}
		}
		ready.store(true, ordering: .releasing)

		setRefreshTimer()
	}

	private func setDataFailed(_ error: Error) {
		dataLock.lock()
		defer { dataLock.unlock() }

		index = [:]
		indexVariables = [:]
		data = nil
		failedError = error
		failed.store(true, ordering: .releasing)
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
		logger?.handleEvent(context: self, event: event)
	}

	private func logError(error: Error) {
		logEvent(event: .error(error: error))
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
