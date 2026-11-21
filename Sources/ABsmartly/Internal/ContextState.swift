import Foundation

/// A cached assignment of one experiment, revalidated on every read (see `ContextState.lookup`).
/// A class, as in 1.5.0, so a cached read neither copies it nor writes it back; it is only read and
/// mutated under the context's lock.
final class Assignment {
	var id = 0
	var iteration = 0
	var fullOnVariant = 0
	var name = ""
	var unitType: String?
	var trafficSplit: [Double] = []
	var variant = 0
	var assigned = false
	var overridden = false
	var eligible = false
	var fullOn = false
	var custom = false
	var audienceMismatch = false
	var ruleOverride = false
	// The variant of the matching rule and the rules it came from, to detect when they change.
	var ruleVariant: Int?
	var ruleKey = ""
	// A split rule matched while the unit was missing.
	var ruleMissingUnit = false
	var variables: [String: JSONValue]?
	var exposed = false
	var attrsSeq = 0
}

/// Everything mutable about a context, guarded by the context's one lock. The assignment logic is
/// 1.5.0's `Context` logic, unchanged, on value types.
struct ContextState {
	var index = DataIndex.empty

	var ready = false
	var failed = false
	var failure: ABsmartlyError?
	var closing = false
	var closed = false

	// The string each unit is hashed from, and the UID as it was given (string or number).
	var units: [String: String] = [:]
	var unitValues: [String: JSONValue] = [:]
	var attributes: [PublishEvent.Attribute] = []
	var attrsSeq = 0
	var overrides: [String: Int] = [:]
	var customAssignments: [String: Int] = [:]

	#if DEBUG
		// Test hooks: actual dictionary writes and cached rule/audience re-evaluations.
		var assignmentCacheWrites = 0
		var revalidations = 0
	#endif

	var hashedUnits: [String: [UInt8]] = [:]
	var assigners: [String: VariantAssigner] = [:]
	#if DEBUG
		var assignmentCache: [String: Assignment] = [:] {
			didSet { assignmentCacheWrites += 1 }
		}
	#else
		var assignmentCache: [String: Assignment] = [:]
	#endif

	var exposures: [Exposure] = []
	var goals: [Goal] = []
	var pendingCount = 0

	// Async lifecycle.
	var readyWaiters: [CheckedContinuation<Result<Void, ABsmartlyError>, Never>] = []
	var refreshTask: Task<Result<Void, ABsmartlyError>, Never>?
	var closeTask: Task<Result<Void, ABsmartlyError>, Never>?
	var inFlightPublishes: [Int: Task<Result<Void, ABsmartlyError>, Never>] = [:]
	var nextPublishID = 0
	var publishTimer: Task<Void, Never>?
	var publishTimerID = 0
	var refreshTimer: Task<Void, Never>?
	var streams: [Int: AsyncStream<Context.Event>.Continuation] = [:]
	var nextStreamID = 0

	// Non-empty `application`/`environment` names from the client configuration. They seed the
	// evaluation map so audiences and assignment-rule conditions can target them; a user-set
	// attribute of the same name wins.
	let systemAttributes: [String: JSONValue]
	// Matched against an assignment rule's `environments`.
	let environmentName: String?

	init(application: String?, environment: String?) {
		var systemAttributes: [String: JSONValue] = [:]
		if let application, !application.isEmpty {
			systemAttributes["application"] = .string(application)
		}
		if let environment, !environment.isEmpty {
			systemAttributes["environment"] = .string(environment)
		}
		self.systemAttributes = systemAttributes
		environmentName = environment.flatMap { $0.isEmpty ? nil : $0 }
	}

	var isReady: Bool { ready || failed }

	func checkReady(expectNotClosed: Bool) -> ABsmartlyError? {
		if !isReady {
			return .notReady
		}
		return expectNotClosed ? checkNotClosed() : nil
	}

	func checkNotClosed() -> ABsmartlyError? {
		if closed {
			return .closed
		}
		if closing {
			return .closing
		}
		return nil
	}

	// MARK: Units and attributes

	enum UID: Sendable {
		case string(String)
		case number(JSONValue)
	}

	mutating func putUnit(_ unitType: String, _ uid: UID) throws(ABsmartlyError) {
		let stored: JSONValue
		let hashSource: String
		switch uid {
		case .string(let string):
			let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else {
				throw .blankUnitUID(unitType: unitType)
			}
			stored = .string(trimmed)
			hashSource = trimmed
		case .number(let number):
			// Hashed like JavaScript's toFixed(0) of the number, as in 1.5.0.
			stored = number
			hashSource = Hashing.unitString(number.doubleValue ?? .nan)
		}

		if let previous = unitValues[unitType], !Self.sameUID(previous, stored) {
			throw .unitAlreadySet(unitType: unitType)
		}

		unitValues[unitType] = stored
		units[unitType] = hashSource

		// A split rule resolved without its unit is rebuilt now that the unit is known. An exposed one
		// is kept, so the user never switches variant or gets a second exposure.
		assignmentCache = assignmentCache.filter { _, assignment in
			assignment.unitType != unitType || !assignment.ruleMissingUnit || assignment.exposed
		}
	}

	private static func sameUID(_ a: JSONValue, _ b: JSONValue) -> Bool {
		switch (a, b) {
		case (.string(let l), .string(let r)): return l == r
		case (.string, _), (_, .string): return false
		default: return a.doubleValue == b.doubleValue
		}
	}

	mutating func appendAttribute(_ name: String, _ value: JSONValue, at time: Int64) {
		attributes.append(PublishEvent.Attribute(name: name, value: value, setAt: time))
		attrsSeq += 1
	}

	// System values first, then user attributes overlaid on top, so a user-set value always wins —
	// including one set after an assignment was cached (the `attrsSeq` bump invalidates it).
	func attributeMap() -> [String: JSONValue] {
		var map = systemAttributes
		for attribute in attributes {
			map[attribute.name] = attribute.value
		}
		return map
	}

	// MARK: Assignment

	private mutating func unitHash(_ unitType: String, _ uid: String) -> [UInt8] {
		if let hash = hashedUnits[unitType] {
			return hash
		}
		let hash = Hashing.hashUnit(uid)
		hashedUnits[unitType] = hash
		return hash
	}

	private mutating func assigner(_ unitType: String, _ uid: String) -> VariantAssigner {
		if let assigner = assigners[unitType] {
			return assigner
		}
		let assigner = VariantAssigner(unitHash: unitHash(unitType, uid))
		assigners[unitType] = assigner
		return assigner
	}

	private static func experimentMatches(_ experiment: Experiment, _ assignment: Assignment) -> Bool {
		return experiment.id == assignment.id && experiment.unitType == assignment.unitType
			&& experiment.iteration == assignment.iteration && experiment.fullOnVariant == assignment.fullOnVariant
			&& experiment.trafficSplit == assignment.trafficSplit
	}

	// Whether the cached assignment still holds for the current attributes and rules: the matching
	// rule (if any) must give the same variant, and the audience result must not have flipped. On
	// success the assignment's stamps advance, so the next read does not re-evaluate.
	private mutating func audienceMatches(_ entry: DataIndex.Entry, _ assignment: Assignment) -> Bool {
		let ruleKey = entry.data.assignmentRules ?? ""
		let ruleKeyChanged = ruleKey != assignment.ruleKey

		let hasAudience = !(entry.data.audience ?? "").isEmpty
		if (attrsSeq > assignment.attrsSeq && (entry.rules != nil || hasAudience)) || ruleKeyChanged {
			#if DEBUG
				revalidations += 1
			#endif
			let attrs = attributeMap()

			// An exposed split resolved without its unit keeps resolving as if the unit were still
			// missing, so a unit set afterwards cannot switch the variant the user already saw.
			let unitPinnedMissing = assignment.ruleMissingUnit && assignment.exposed
			let rule = resolveRule(entry, attrs, unitPinnedMissing: unitPinnedMissing)
			if rule?.variant != assignment.ruleVariant {
				return false
			}
			assignment.ruleMissingUnit = rule?.missingUnit ?? false

			if !assignment.ruleOverride && hasAudience {
				let result = AudienceMatcher.evaluate(entry.audience, attrs)
				let audienceMismatch = result.map { !$0 } ?? assignment.audienceMismatch
				if audienceMismatch != assignment.audienceMismatch {
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
	private mutating func resolveRule(
		_ entry: DataIndex.Entry, _ attrs: [String: JSONValue], unitPinnedMissing: Bool
	) -> (variant: Int, missingUnit: Bool)? {
		guard let rules = entry.rules else { return nil }

		let data = entry.data
		let variantCount = data.variants.count
		switch AudienceMatcher.evaluateRules(rules, environmentName: environmentName, attributes: attrs) {
		case nil:
			return nil
		case .assign(let variant)?:
			return variant >= 0 && variant < variantCount ? (variant, false) : nil
		case .split(let split)?:
			guard split.count == variantCount else { return nil }
			guard !unitPinnedMissing, let unitType = data.unitType, let uid = units[unitType] else {
				return (data.fullOnVariant, true)
			}
			return (assigner(unitType, uid).assign(split, seedHi: data.seedHi, seedLo: data.seedLo), false)
		}
	}

	/// The cached assignment if still up to date, else a newly computed and cached one.
	mutating func lookup(_ experimentName: String) -> Assignment {
		let entry = index.experiments[experimentName]

		if let assignment = assignmentCache[experimentName] {
			if let override = overrides[experimentName] {
				if assignment.overridden && assignment.variant == override {
					return assignment
				}
			} else if assignment.overridden {
				// The override was removed.
			} else if let entry {
				// A matching rule wins over a custom assignment, so a custom mismatch is not staleness.
				let custom = customAssignments[experimentName]
				if custom == nil || custom == assignment.variant || assignment.ruleOverride {
					if Self.experimentMatches(entry.data, assignment) && audienceMatches(entry, assignment) {
						return assignment
					}
				}
			} else if !assignment.assigned && !assignment.ruleOverride {
				// previously not-running experiment. A rule-won assignment came from the experiment's
				// rules, so it is rebuilt once the experiment is gone.
				return assignment
			}
		}

		let assignment = Assignment()
		assignment.name = experimentName
		assignment.eligible = true

		if let override = overrides[experimentName] {
			if let entry {
				assignment.id = entry.data.id
				assignment.unitType = entry.data.unitType
			}
			assignment.overridden = true
			assignment.variant = override
		} else if let entry {
			let data = entry.data
			let rule = entry.rules != nil ? resolveRule(entry, attributeMap(), unitPinnedMissing: false) : nil
			assignment.ruleKey = data.assignmentRules ?? ""
			assignment.ruleVariant = rule?.variant
			assignment.ruleMissingUnit = rule?.missingUnit ?? false

			// A matching assignment rule is an explicit, author-specified assignment: it wins over the
			// audience, traffic eligibility, full-on and custom assignments; only an override beats it.
			// It is flagged `ruleOverride` so the collector keeps it out of analysis.
			if let rule {
				assignment.variant = rule.variant
				assignment.ruleOverride = true
			} else {
				if let audience = data.audience, !audience.isEmpty,
					let result = AudienceMatcher.evaluate(entry.audience, attributeMap())
				{
					assignment.audienceMismatch = !result
				}

				if data.audienceStrict && assignment.audienceMismatch {
					assignment.variant = 0
				} else if data.fullOnVariant == 0 {
					if let unitType = data.unitType, let uid = units[unitType] {
						let assigner = assigner(unitType, uid)
						let eligible =
							assigner.assign(data.trafficSplit, seedHi: data.trafficSeedHi, seedLo: data.trafficSeedLo) == 1
						if eligible {
							if let custom = customAssignments[experimentName] {
								assignment.variant = custom
								assignment.custom = true
							} else {
								assignment.variant = assigner.assign(data.split, seedHi: data.seedHi, seedLo: data.seedLo)
							}
						} else {
							assignment.eligible = false
							assignment.variant = 0
						}
						assignment.assigned = true
					}
				} else {
					assignment.assigned = true
					assignment.variant = data.fullOnVariant
					assignment.fullOn = true
				}
			}

			assignment.unitType = data.unitType
			assignment.id = data.id
			assignment.iteration = data.iteration
			assignment.trafficSplit = data.trafficSplit
			assignment.fullOnVariant = data.fullOnVariant
			assignment.attrsSeq = attrsSeq
		}

		if let entry, entry.variables.indices.contains(assignment.variant) {
			assignment.variables = entry.variables[assignment.variant]
		}

		assignmentCache[experimentName] = assignment
		return assignment
	}

	/// Looks the assignment up and, unless it is already exposed or the context is closing, marks it
	/// exposed and queues its exposure, in one critical section. With `requireVariables`, only an
	/// assignment whose variant has variables is exposed. Returns the exposure queued, if any.
	mutating func lookupExposing(
		_ experimentName: String, requireVariables: Bool = false, now: () -> Int64
	) -> (Assignment, Exposure?) {
		let assignment = lookup(experimentName)
		guard !assignment.exposed, !requireVariables || assignment.variables != nil, !closed, !closing else {
			return (assignment, nil)
		}
		assignment.exposed = true

		let exposure = Exposure(
			id: assignment.id, name: assignment.name, unit: assignment.unitType, variant: assignment.variant,
			exposedAt: now(), assigned: assignment.assigned, eligible: assignment.eligible,
			overridden: assignment.overridden, fullOn: assignment.fullOn, custom: assignment.custom,
			audienceMismatch: assignment.audienceMismatch, ruleOverride: assignment.ruleOverride)
		exposures.append(exposure)
		pendingCount += 1
		return (assignment, exposure)
	}

	// Experiments sharing a key are walked in ascending id order, like the JavaScript SDK: each one
	// visited is exposed (unless peeking), and the first that is assigned, overridden or won by an
	// assignment rule and whose variant defines the key provides the value. The caller walks them
	// one at a time, delivering each exposure before resolving the next, as 1.5.0 did.

	/// The value `experimentName` provides for `key`, if any, and the exposure queued for it unless
	/// peeking.
	mutating func variableValue(
		_ key: String, of experimentName: String, peek: Bool, now: () -> Int64
	) -> (JSONValue?, Exposure?) {
		let (assignment, exposure) =
			peek ? (lookup(experimentName), nil) : lookupExposing(experimentName, requireVariables: true, now: now)
		if let variables = assignment.variables, let value = variables[key],
			assignment.assigned || assignment.overridden || assignment.ruleOverride
		{
			return (value, exposure)
		}
		return (nil, exposure)
	}

	// MARK: Publishing

	/// The units as published: each unit type with the hash of its UID.
	mutating func publishUnits() -> [PublishEvent.Unit] {
		var result: [PublishEvent.Unit] = []
		for (unitType, uid) in units {
			result.append(PublishEvent.Unit(type: unitType, uid: String(decoding: unitHash(unitType, uid), as: UTF8.self)))
		}
		return result
	}
}
