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
	// Held out by a covering holdout: forced to control, with no exposure of its own unless an
	// override or a matching rule decided the variant.
	var suppressed = false
	// The covering holdouts and the unit's arm in each, pinned when the assignment was resolved.
	var holdouts: [PinnedHoldout]?
	// On a holdout arm: the holdout split's length when `variant` was drawn.
	var holdoutArmCount = 0

	// A covering holdout was resolved while the unit was missing.
	var holdoutMissingUnit: Bool {
		holdouts?.contains { $0.arm == nil } ?? false
	}
}

/// A covering holdout and the unit's arm in it; the arm is nil while the unit is missing.
struct PinnedHoldout {
	let definition: Experiment
	let arm: Assignment?
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
		var assignmentCacheWrites = 0
		var revalidations = 0
	#endif

	var hashedUnits: [String: [UInt8]] = [:]
	var assigners: [String: VariantAssigner] = [:]
	// A holdout's arm per (holdout id, covered experiment's unit type), kept across refreshes while
	// the holdout's iteration is unchanged, so each holdout publishes one exposure per unit type.
	var holdoutArms: [HoldoutKey: Assignment] = [:]
	struct HoldoutKey: Hashable {
		let id: Int
		let unitType: String
	}
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

		// A split rule or a holdout resolved without its unit is rebuilt now that the unit is known. An
		// exposed one is kept, so the user never switches variant or gets a second exposure.
		assignmentCache = assignmentCache.filter { _, assignment in
			assignment.unitType != unitType || assignment.exposed
				|| !(assignment.ruleMissingUnit || assignment.holdoutMissingUnit)
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
	#if DEBUG
		@TaskLocal static var attributeMapBuildCount: Locked<Int>?
	#endif

	func attributeMap() -> [String: JSONValue] {
		#if DEBUG
			Self.attributeMapBuildCount?.withLock { $0 += 1 }
		#endif
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

	// The covering holdouts are the same (id, iteration) pairs the assignment was resolved with. A
	// same-iteration seed or split edit is not a change, so it never forces a second exposure.
	private static func holdoutSetMatches(_ entry: DataIndex.Entry, _ assignment: Assignment) -> Bool {
		let fresh = entry.holdouts ?? []
		let pinned = assignment.holdouts ?? []
		guard fresh.count == pinned.count else { return false }
		return zip(fresh, pinned).allSatisfy { $0.id == $1.definition.id && $0.iteration == $1.definition.iteration }
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
	// unit is missing (never cached, so the unit can still be set later).
	private mutating func holdoutArm(_ holdout: Experiment, unitType: String) -> Assignment? {
		let key = HoldoutKey(id: holdout.id, unitType: unitType)
		if let cached = holdoutArms[key], cached.iteration == holdout.iteration {
			return cached
		}
		guard let uid = units[unitType] else {
			return nil
		}

		let arm = Assignment()
		arm.id = holdout.id
		arm.name = holdout.name
		arm.iteration = holdout.iteration
		arm.unitType = unitType
		arm.variant = assigner(unitType, uid).assign(holdout.split, seedHi: holdout.seedHi, seedLo: holdout.seedLo)
		arm.assigned = true
		arm.eligible = true
		// Pinned with the arm: a same-iteration refresh may change the split's length.
		arm.holdoutArmCount = holdout.split.count
		holdoutArms[key] = arm
		return arm
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
				if assignment.overridden && assignment.variant == override
					&& (entry.map { Self.holdoutSetMatches($0, assignment) } ?? true)
				{
					return assignment
				}
			} else if assignment.overridden {
				// The override was removed.
			} else if let entry {
				// A held-out experiment is forced to control and a matching rule wins over a custom
				// assignment, so a custom mismatch is not staleness.
				let custom = customAssignments[experimentName]
				if custom == nil || custom == assignment.variant || assignment.ruleOverride || assignment.suppressed {
					if Self.experimentMatches(entry.data, assignment) && audienceMatches(entry, assignment)
						&& Self.holdoutSetMatches(entry, assignment)
					{
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

		// Resolved for overrides too: the holdouts still publish their exposures.
		if let entry, let holdouts = entry.holdouts {
			let unitType = entry.data.unitType
			let pinned = holdouts.map { holdout in
				PinnedHoldout(definition: holdout, arm: unitType.flatMap { holdoutArm(holdout, unitType: $0) })
			}
			assignment.holdouts = pinned
			assignment.suppressed = pinned.contains { holdout in
				guard let arm = holdout.arm else { return false }
				return Self.isHeldOutBy(arm.variant, armCount: arm.holdoutArmCount, fullOnVariant: entry.data.fullOnVariant)
			}
		}

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

			// A matching assignment rule is an explicit, author-specified assignment: it wins over
			// holdout suppression, the audience, traffic eligibility, full-on and custom assignments;
			// only an override beats it. It is flagged `ruleOverride` so the collector keeps it out of
			// analysis.
			if let rule {
				assignment.variant = rule.variant
				assignment.ruleOverride = true
			} else if assignment.suppressed {
				assignment.variant = 0
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
							assigner.assign(data.trafficSplit, seedHi: data.trafficSeedHi, seedLo: data.trafficSeedLo)
							== 1
						if eligible {
							if let custom = customAssignments[experimentName] {
								assignment.variant = custom
								assignment.custom = true
							} else {
								assignment.variant = assigner.assign(
									data.split, seedHi: data.seedHi, seedLo: data.seedLo)
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
	/// exposed and queues its exposures, in one critical section. Returns the exposures queued.
	mutating func lookupExposing(_ experimentName: String, now: () -> Int64) -> (Assignment, [Exposure]) {
		let assignment = lookup(experimentName)
		var queued: [Exposure] = []
		expose(assignment, now: now, into: &queued)
		return (assignment, queued)
	}

	// A held-out experiment queues no exposure of its own (an override or a matching rule still
	// does); its covering holdouts queue theirs.
	private mutating func expose(_ assignment: Assignment, now: () -> Int64, into queued: inout [Exposure]) {
		guard !assignment.exposed, !closed, !closing else {
			return
		}
		assignment.exposed = true

		if !assignment.suppressed || assignment.overridden || assignment.ruleOverride {
			queue(assignment, name: assignment.name, now: now, into: &queued)
		}
		exposeHoldouts(assignment, now: now, into: &queued)
	}

	// Every holdout covering the assignment queues its own exposure once per arm, from the arms
	// pinned when the assignment was resolved, named by the definition it was resolved with.
	private mutating func exposeHoldouts(_ assignment: Assignment, now: () -> Int64, into queued: inout [Exposure]) {
		guard !closed, !closing else {
			return
		}
		for holdout in assignment.holdouts ?? [] {
			if let arm = holdout.arm, !arm.exposed {
				arm.exposed = true
				queue(arm, name: holdout.definition.name, now: now, into: &queued)
			}
		}
	}

	private mutating func queue(_ assignment: Assignment, name: String, now: () -> Int64, into queued: inout [Exposure]) {
		let exposure = Exposure(
			id: assignment.id, name: name, unit: assignment.unitType, variant: assignment.variant,
			exposedAt: now(), assigned: assignment.assigned, eligible: assignment.eligible,
			overridden: assignment.overridden, fullOn: assignment.fullOn, custom: assignment.custom,
			audienceMismatch: assignment.audienceMismatch, ruleOverride: assignment.ruleOverride)
		exposures.append(exposure)
		pendingCount += 1
		queued.append(exposure)
	}

	/// The value of a variable key shared by several experiments, and the exposures queued for it
	/// unless peeking. The candidates are the experiments whose variants define the key, by ascending
	/// id, as in the Java SDK. The winner is the first candidate the unit is in (assigned, overridden or
	/// won by an assignment rule), and the value is the winner's for the key, or nil when the winner's
	/// variant does not define it: a later candidate is never used because of the variant the unit got.
	/// Only the winner is exposed. With no winner, a unit held out of a candidate reads the first
	/// held-out candidate's control value (nil when it does not define the key), and that candidate is
	/// exposed instead (it has no exposure of its own, so only its holdouts publish).
	///
	/// Unless peeking, the holdouts covering every candidate visited publish their exposures, as in the
	/// Java SDK, so each holdout's arms stay symmetric whichever candidate wins.
	mutating func variableValue(_ key: String, peek: Bool, now: () -> Int64) -> (JSONValue?, [Exposure]) {
		guard let candidates = index.variableExperiments[key] else {
			return (nil, [])
		}
		var queued: [Exposure] = []
		var suppressedFallback: Assignment?
		for candidate in candidates {
			let assignment = lookup(candidate.data.name)
			if assignment.assigned || assignment.overridden || assignment.ruleOverride {
				if !peek {
					expose(assignment, now: now, into: &queued)
				}
				return (assignment.variables?[key], queued)
			}
			if !peek {
				exposeHoldouts(assignment, now: now, into: &queued)
			}
			if assignment.suppressed && suppressedFallback == nil {
				suppressedFallback = assignment
			}
		}
		guard let suppressedFallback else {
			return (nil, queued)
		}
		if !peek {
			expose(suppressedFallback, now: now, into: &queued)
		}
		return (suppressedFallback.variables?[key], queued)
	}

	// MARK: Publishing

	/// The units as published: each unit type with the hash of its UID.
	mutating func publishUnits() -> [PublishEvent.Unit] {
		var result: [PublishEvent.Unit] = []
		for (unitType, uid) in units {
			result.append(
				PublishEvent.Unit(type: unitType, uid: String(decoding: unitHash(unitType, uid), as: UTF8.self)))
		}
		return result
	}
}
