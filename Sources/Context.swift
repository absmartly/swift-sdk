//
//  Context.swift
//  absmartly
//
//  Created by Roman Odyshew on 18.08.2021.
//

import Foundation

public class Context {
    private let readyLock = NSLock()
    private let dataLock = NSLock()
    private let timeoutLock = NSLock()
    private let compareAndSetLock = NSLock()
    private let eventLock = NSLock()
    
    private let eventPublisher: EventPublisher
    private let provider: ContextDataProvider
    private var contextDataPromise: Promise<ContextData>?
    private var config: ContextConfig
    
    private var dispatchWorkItem: DispatchWorkItem?
    
    private var pendingCount: PendingCount = 0
    
    private(set) var isFailed: Bool = false
    
    private var index: [String:ExperimentVariables] = [:]
    private var indexVariables: [String:ExperimentVariables] = [:]
    private var data: ContextData?
    
    @Atomic private(set) var isClosed: Bool = false
    @Atomic private var closing: Bool = false
    @Atomic private var isRefreshing: Bool = false
    
    private var attributes = ThreadSafeArray<PublishEvent.Attribute>()
    private var overrides: ThreadSafeMap<String, Int>
    private var hashedUnits = ThreadSafeMap<String, [UInt8]>()
    private var assigners = ThreadSafeMap<String, VariantAssigner>()
    private var assignmentCache = ThreadSafeMap<String, Assignment>()
    
    private var exposures: [PublishEvent.Exposure] = []
    private var achievements: [GoalAchievement] = []
    
    private var closeCallbacks: ThreadSafeArray<(_:Any?)->()>
    private var refreshCallbacks: ThreadSafeArray<(_:Error?)->()>
    private var readyCallback: (_:(Context?) -> ())?
    
    init(_ eventPublisher: EventPublisher, _ provider: ContextDataProvider, _ promise: Promise<ContextData>, _ config: ContextConfig) {
        self.eventPublisher = eventPublisher
        self.provider = provider
        self.contextDataPromise = promise
        self.config = config
        
        overrides = ThreadSafeMap<String, Int>(with: config.overrides)
        closeCallbacks = ThreadSafeArray<(_:Any?)->()>()
        refreshCallbacks = ThreadSafeArray<(_:Error?)->()>()
        
        do {
            try setAttributes(config.attributes)
        } catch {
        }
        
        if promise.isDone {
            // NOTE: Should be strong reference, important!
            promise.onSuccess() { result in
                self.setData(result)
                Logger.notice("Context ready")
                self.readyLock.lock()
                self.readyCallback?(self)
                self.readyLock.unlock()
            }
            
            promise.onError() { error in
                self.setDataFailed(error)
                self.readyLock.lock()
                self.readyCallback?(nil)
                self.readyLock.unlock()
            }
        } else {
            promise.onSuccess() { result in
                self.setData(result)
                Logger.notice("Context ready")
                self.readyLock.lock()
                self.readyCallback?(self)
                self.readyLock.unlock()
                
                if self.pendingCount.value > 0 {
                    self.setTimeout()
                }
            }
            
            promise.onError() { error in
                self.setDataFailed(error)
                self.readyLock.lock()
                self.readyCallback?(nil)
                self.readyLock.unlock()
            }
        }
    }
    
    public var isClosing: Bool {
        return !isClosed && closing
    }
    
    public var isReady: Bool {
        return isFailed || data != nil
    }
    
    public func waitUntilReadyAsync(_ callBack: @escaping (_:(Context?) -> ())) {
        if isReady {
            return callBack(self)
        } else {
            readyLock.lock()
            readyCallback = callBack
            readyLock.unlock()
        }
    }
    
    public func getExperiments() throws -> [String] {
        try checkReady(true)
        
        defer {
            dataLock.unlock()
        }
        dataLock.lock()
        return data?.experiments.map { $0.name } ?? []
    }
    
    public func getContextData() throws -> ContextData? {
        try checkReady(true)
        
        defer {
            dataLock.unlock()
        }
        dataLock.lock()
        return data
    }
    
    public func setOverride(_ experimentName: String, _ variant: Int) throws {
        try checkNotClosed()
        
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
    
    public func getOverride(_ experimentName: String) -> Int? {
        return overrides[experimentName]
    }
    
    public func setOverrides(_ overrides: [String: Int]) throws {
        try overrides.forEach { try setOverride($0.key, $0.value) }
    }
    
    public func setAttribute(_ name: String, _ value: Any?) throws {
        try checkNotClosed()
        
        attributes.append(PublishEvent.Attribute(name, value, Int64((Date().timeIntervalSince1970 * 1000.0).rounded())))
    }
    
    public func setAttributes(_ attributes: [String:Any?]) throws {
        try attributes.forEach { try setAttribute($0, $1) }
    }
    
    public func getTreatment(_ experimentName: String) throws -> Int {
        try checkReady(true)
        
        let assignment = getAssignment(experimentName)
        if !assignment.exposed {
            queueExposure(assignment)
        }
        
        return assignment.variant
    }
    
    private func queueExposure(_ assignment: Assignment) {
        compareAndSetLock.lock()
        
        guard !assignment.exposed else {
            compareAndSetLock.unlock()
            return
        }
        
        assignment.exposed = true
        compareAndSetLock.unlock()
        
        let exposure = PublishEvent.Exposure(assignment.id, assignment.name, assignment.unitType, assignment.variant, Int64((Date().timeIntervalSince1970 * 1000.0).rounded()), assignment.assigned, assignment.eligible, assignment.overridden, assignment.fullOn)
        
        eventLock.lock()
        
        pendingCount.increment()
        exposures.append(exposure)
        
        eventLock.unlock()
        Logger.notice("exposure")
        setTimeout()
    }
    
    public func peekTreatment(_ experimentName: String) throws ->  Int {
        try checkReady(true)
        return getAssignment(experimentName).variant
    }
    
    public func getVariableKeys() throws -> [String: String] {
        try checkReady(true)
        
        var variableKeys: [String: String] = [:]
        indexVariables.forEach { variableKeys[$0.key] = $0.value.data.name }
        return variableKeys
    }
    
    public func getVariableValue(_ key: String, _ defaultValue: Any) throws -> Any {
        try checkReady(true)
        
        if let assignment = getVariableAssignment(key), assignment.variables.count > 0 {
            if !assignment.exposed {
                queueExposure(assignment)
            }
            
            if let object = assignment.variables[key] {
                return object
            }
        }
        
        return defaultValue
    }
    
    public func peekVariableValue(_ key: String, _ defaultValue: Any) throws -> Any {
        try checkReady(true)
        
        if let assignment = getVariableAssignment(key) {
            
            if let object = assignment.variables[key] {
                return object
            }
        }
        
        return defaultValue
    }
    
    public func track(_ goalName: String, _ properties: [String: Any]) throws {
        try checkNotClosed()
        
        let achievement: GoalAchievement = GoalAchievement(goalName, achievedAt: Int64((Date().timeIntervalSince1970 * 1000.0).rounded()), properties: properties)
        
        eventLock.lock()
        pendingCount.increment()
        achievements.append(achievement)
        eventLock.unlock()
        Logger.notice("Goal: " + achievement.serializeValue)
        setTimeout()
    }
    
    var getPendingCount: Int {
        return pendingCount.value
    }
    
    public func publish(_ callBack: ((_:Error?)->())?) throws {
        try checkNotClosed()
        
        flush(callBack)
    }
    
    // TODO: maybe wait or send error if busy
    public func refresh(_ callback: ((_:Error?)->())?) throws {
        try checkNotClosed()
        
        compareAndSetLock.lock()
        guard isRefreshing else {
            compareAndSetLock.unlock()
            if let callback = callback {
                refreshCallbacks.append(callback)
            }
            
            return
        }
        
        isRefreshing = true
        compareAndSetLock.unlock()
        
        let result = provider.getContextData()
        result.onSuccess { [weak self] data in
            self?.setData(data)
            Logger.notice("Refresh")
            self?.isRefreshing = false
            callback?(nil)
            let callbacks = self?.refreshCallbacks.getDataAndClear()
            callbacks?.forEach { $0(nil) }
        }
        
        result.onError{ [weak self] error in
            self?.isRefreshing = false
            callback?(error)
            let callbacks = self?.refreshCallbacks.getDataAndClear()
            callbacks?.forEach { $0(error) }
        }
    }
    
    public func close(_ callback: ((_:Any?)->())?) {
        guard !isClosed else {
            callback?(nil)
            return
        }
        
        compareAndSetLock.lock()
        if closing {
            if let callback = callback {
                closeCallbacks.append(callback)
            }
            compareAndSetLock.unlock()
            return
        } else {
            closing = true
            compareAndSetLock.unlock()
            
            if pendingCount.value > 0 {
                flush { [weak self] result in
                    self?.isClosed = true
                    self?.closing = false
                    callback?(result)
                    self?.closeCallbacks.getDataAndClear().forEach { $0(result) }
                }
            } else {
                closing = false
                isClosed = true
                callback?(nil)
                closeCallbacks.getDataAndClear().forEach { $0(nil) }
            }
        }
    }
    
    private func flush(_ callBack: ((_:Error?)->())?) {
        timeoutLock.lock()
        dispatchWorkItem?.cancel()
        dispatchWorkItem = nil
        timeoutLock.unlock()
        
        guard !isFailed else {
            eventLock.lock()
            
            exposures = []
            achievements = []
            pendingCount = 0
            callBack?(nil)
            
            eventLock.unlock()
            return
        }
        
        if pendingCount.value == 0 {
            callBack?(nil)
            return
        }
        
        eventLock.lock()
        
        let eventCount: Int = pendingCount.value
        pendingCount = 0
        
        let localExposures: [PublishEvent.Exposure] = self.exposures
        self.exposures = []
        
        let localAchievements: [GoalAchievement] = self.achievements
        self.achievements = []
        
        eventLock.unlock()
        
        if eventCount == 0 {
            callBack?(nil)
            return
        }
        
        let event = PublishEvent(true,
                                 config.units.map { PublishEvent.Unit($0.key, String(bytes: getUnitHash($0.key, $0.value), encoding: .ascii) ?? "") },
                                 Int64((Date().timeIntervalSince1970 * 1000.0).rounded()),
                                 localExposures,
                                 localAchievements,
                                 attributes.rawArray)
        
        eventPublisher.publish(event) { error in
            if let error = error {
                Logger.error("Publish event error: " + error.localizedDescription)
                callBack?(error)
                return
            }
            
            Logger.notice("Publish event: " + event.serializeValue)
            callBack?(nil)
        }
    }
    
    private func checkReady(_ expectNotClosed: Bool) throws {
        guard isReady else {
            Logger.notice("Context is not yet ready")
            throw ABSmartlyError("ABSmartly Context is not yet ready.")
        }
        
        if expectNotClosed {
            try checkNotClosed()
        }
    }
    
    private func checkNotClosed() throws {
        if isClosed {
            Logger.notice("Context is closed")
            throw ABSmartlyError("ABSmartly Context is closed.")
        }
        
        if closing {
            Logger.notice("Context is closing")
            throw ABSmartlyError("ABSmartly Context is closing.")
        }
    }
    
    private func experimentMatches(_ experiment: Experiment, _ assignment: Assignment) -> Bool {
        return experiment.id == assignment.id &&
            experiment.unitType == assignment.unitType &&
            experiment.iteration == assignment.iteration &&
            experiment.fullOnVariant == assignment.fullOnVariant &&
            experiment.trafficSplit == assignment.trafficSplit
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
            if let experimentVaiables = experiment {
                assignment.unitType = experimentVaiables.data.unitType
                
                if let unitType = experimentVaiables.data.unitType, config.units[unitType] != nil {
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
                        
                        let eligible = assigner.assign(experiment.data.trafficSplit, experiment.data.trafficSeedHi, experiment.data.trafficSeedLo) == 1
                        
                        if eligible {
                            assignment.variant = assigner.assign(experiment.data.split, experiment.data.seedHi, experiment.data.seedLo)
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
        defer {
            dataLock.unlock()
        }
        
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
        guard isReady else { return }
        
        if dispatchWorkItem == nil, config.publishDelay > 0 {
            timeoutLock.lock()
            dispatchWorkItem = DispatchWorkItem { [weak self] in
                self?.flush(nil)
            }
            
            Logger.notice("Pending flush after: \(config.publishDelay / 1000) seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(config.publishDelay / 1000), execute: dispatchWorkItem!)
            timeoutLock.unlock()
        }
    }
    
    private func setData(_ data: ContextData) {
        var index: [String:ExperimentVariables] = [:]
        var indexVariables: [String:ExperimentVariables] = [:]
        
        for experiment in data.experiments {
            let experimentVariable = ExperimentVariables(experiment)
            
            for variant in experiment.variants {
                var parsed: [String: Any] = [:]
                
                if let config = variant.config, !config.isEmpty {
                    let data = Data(config.utf8)
                    do {
                        if let parsedData = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject] {
                            parsed = parsedData
                            for (key, _) in parsedData {
                                indexVariables[key] = experimentVariable
                            }
                            experimentVariable.variables.append(parsed)
                        } else {
                            experimentVariable.variables.append([:])
                        }
                    } catch {
                        Logger.error("Experiment " + experiment.name + " with id \(experiment.id) variant " + (variant.name ?? "") + " config can not be deserialized")
                        experimentVariable.variables.append([:])
                    }
                } else {
                    experimentVariable.variables.append([:])
                }
            }
            
            index[experiment.name] = experimentVariable
        }
        
        dataLock.lock()
        defer {
            dataLock.unlock()
        }
        
        var previousAssignments: [String : Assignment] = [:]
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
    
    private func hasNewValues(_ lastData: [String : Assignment], _ newData: [String : Assignment]) -> [String : Assignment] {
        var newValues: [String : Assignment] = [:]
        
        for item in newData {
            if lastData.keys.contains(item.key) { continue }
            newValues[item.key] = item.value
        }
        
        return newValues
    }
    
    private func setDataFailed(_ error: Error) {
        dataLock.lock()
        index = [:]
        indexVariables = [:]
        data = nil
        isFailed = true
        dataLock.unlock()
    }
}

private class ExperimentVariables {
    let data: Experiment
    var variables: [[String: Any]] = []
    
    init(_ experiment: Experiment) {
        self.data = experiment
    }
}


private class Assignment: Equatable {
    static func == (lhs: Assignment, rhs: Assignment) -> Bool {
        return lhs.id == rhs.id &&
            lhs.iteration == rhs.iteration &&
            lhs.fullOnVariant == rhs.fullOnVariant &&
            lhs.name == rhs.name &&
            lhs.unitType == rhs.unitType &&
            lhs.trafficSplit == rhs.trafficSplit &&
            lhs.variant == rhs.variant &&
            lhs.assigned == rhs.assigned &&
            lhs.overridden == rhs.overridden &&
            lhs.eligible == rhs.eligible &&
            lhs.fullOn == rhs.fullOn &&
            lhs.variables.count == rhs.variables.count &&
            lhs.exposed == rhs.exposed
        
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
    var variables: [String: Any] = [:]
    
    @Atomic var exposed: Bool = false
}


extension Context {
    class PendingCount: ExpressibleByIntegerLiteral {
        required init(integerLiteral value: Int) {
            lock.lock()
            _value = value
            lock.unlock()
        }
        
        typealias IntegerLiteralType = Int
        
        private let lock = NSLock()
        private var _value: Int
        
        init(_ value: Int) {
            self._value = value
        }
        
        var value: Int {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _value
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _value = newValue
            }
        }
        
        var incrementAndGet: Int {
            lock.lock()
            defer { lock.unlock() }
            self._value += 1
            return _value
        }
        
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            self._value += 1
        }
    }
}
