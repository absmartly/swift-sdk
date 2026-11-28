import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// Port of java-sdk ContextSwitchbackTest, from strictMismatchedSwitchbackGivesWayOnASharedVariableKey to
// the end: exposure-flag parity with unit experiments, exposure timing, per-period eviction, epochs,
// refresh from inside audience evaluation, and concurrent resolution.
final class ContextSwitchbackLifecycleTest: SwitchbackTestCase {
	static let strictGoldAudience = "{\"filter\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"gold\"}]}]}"
	static let assignVariant1 = "{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":1}]}"
	static let assignVariant2 = "{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":2}]}"
	static let assignVariant1ToUS =
		"{\"rules\":[{\"type\":\"assign\",\"environments\":[],"
		+ "\"conditions\":{\"and\":[{\"eq\":[{\"var\":\"country\"},{\"value\":\"US\"}]}]},\"variant\":1}]}"
	static let trueAudience = "{\"filter\":[{\"value\":true}]}"

	// MARK: - Fixtures

	// The same experiment as a unit experiment: no switchback fields.
	func unitize(_ experiment: [String: Any]) -> [String: Any] {
		var unit = experiment
		for key in ["randomizationType", "switchbackClusters", "switchbackStartAt", "switchbackPeriodMs"] {
			unit.removeValue(forKey: key)
		}
		return unit
	}

	func variable(_ context: Context, _ key: String = "sb.arm", peek: Bool = false) -> Int? {
		let value =
			peek
			? context.peekVariableValue(key, defaultValue: JSON(-1)) : context.getVariableValue(key, defaultValue: JSON(-1))
		return value?.int
	}

	func ruleExposure(_ name: String, _ variant: Int, _ exposedAt: Int64) -> Exposure {
		return exposure(variant, exposedAt, name: name, assigned: false, ruleOverride: true)
	}

	func publishedJSON(_ context: Context) -> String? {
		return publish(context).map { encoded($0) }
	}

	// MARK: - Variable keys

	// A strict-mismatched switchback is not assigned, so on a shared variable key it gives way to the
	// next experiment that declares the key, as a unit experiment does. Only that experiment is exposed.
	func testStrictMismatchedSwitchbackGivesWayOnASharedVariableKey() {
		var sb = SB.switchback(arms: 2, periodMs: SB.hour)
		sb["audience"] = Self.strictGoldAudience
		sb["audienceStrict"] = true
		var unit = unitize(SB.switchback(2, "exp_unit", arms: 2, periodMs: SB.hour))
		unit["variants"] = [["name": "A", "config": "{\"sb.arm\":10}"], ["name": "B", "config": "{\"sb.arm\":11}"]]
		unit["fullOnVariant"] = 1
		clock.now = SB.anchor + SB.hour + 3
		let context = createContext(SB.data([sb, unit]))
		XCTAssertEqual(["sb.arm": ["exp_sb", "exp_unit"]], context.getVariableKeys())

		XCTAssertEqual(11, variable(context, peek: true))
		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(11, variable(context))
		// Only the winner is recorded, as in Java (CHANGELOG 1.5.0 "Variable keys shared by several
		// experiments").
		XCTAssertEqual(
			[Exposure(2, "exp_unit", SB.unitType, 1, SB.anchor + SB.hour + 3, true, true, false, true, false, false)],
			publishExposures(context))
	}

	// Alone on the key, a strict-mismatched unit experiment yields the default and records nothing,
	// like the switchback below.
	func testStrictMismatchedUnitExperimentOnAVariableKeyIsRecordedLikeTheSwitchback() {
		var sb = unitize(SB.switchback(arms: 2, periodMs: SB.hour))
		sb["audience"] = Self.strictGoldAudience
		sb["audienceStrict"] = true
		clock.now = SB.anchor + SB.hour + 3
		let context = createContext(SB.data([sb]))
		XCTAssertEqual(-1, variable(context))
		XCTAssertEqual([], publishExposures(context))
	}

	// Alone on the key, a strict-mismatched switchback yields the default value and records nothing.
	func testStrictMismatchedSwitchbackAloneOnAVariableKeyReturnsTheDefault() {
		var sb = SB.switchback(arms: 2, periodMs: SB.hour)
		sb["audience"] = Self.strictGoldAudience
		sb["audienceStrict"] = true
		clock.now = SB.anchor + SB.hour + 3
		let context = createContext(SB.data([sb]))
		XCTAssertEqual(-1, variable(context, peek: true))
		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(-1, variable(context))
		// No winner, so nothing is recorded, as for a strict-mismatched unit experiment and in Java.
		XCTAssertEqual([], publishExposures(context))
	}

	// MARK: - Exposure flag parity

	// The branches of the SWITCHBACK.md "Exposure flags" table: every branch an eligible-cluster
	// switchback shares with a unit experiment.
	enum ParityBranch: CaseIterable {
		case override, overrideOverStrictMismatch, rule, ruleOverStrictMismatch, strictMismatch
		case strictMismatchOverFullOn, strictMismatchOverTrafficMiss, nonStrictMismatch, fullOn, trafficMiss
		case custom, draw

		func configure(_ experiment: inout [String: Any]) {
			switch self {
			case .overrideOverStrictMismatch, .ruleOverStrictMismatch, .strictMismatch:
				experiment["audience"] = ContextSwitchbackLifecycleTest.strictGoldAudience
				experiment["audienceStrict"] = true
			case .strictMismatchOverFullOn:
				experiment["audience"] = ContextSwitchbackLifecycleTest.strictGoldAudience
				experiment["audienceStrict"] = true
				experiment["fullOnVariant"] = 2
			case .strictMismatchOverTrafficMiss:
				experiment["audience"] = ContextSwitchbackLifecycleTest.strictGoldAudience
				experiment["audienceStrict"] = true
				experiment["trafficSplit"] = [1.0, 0.0]
			case .nonStrictMismatch:
				experiment["audience"] = ContextSwitchbackLifecycleTest.strictGoldAudience
			case .fullOn:
				experiment["fullOnVariant"] = 2
			case .trafficMiss:
				experiment["trafficSplit"] = [1.0, 0.0]
			default:
				break
			}
			if self == .rule || self == .ruleOverStrictMismatch {
				experiment["assignmentRules"] = ContextSwitchbackLifecycleTest.assignVariant2
			}
		}

		func configure(_ context: Context) {
			if self == .override || self == .overrideOverStrictMismatch {
				context.setOverride(experimentName: "exp_parity", variant: 2)
			} else if self == .custom {
				context.setCustomAssignment(experimentName: "exp_parity", variant: 2)
			}
		}

		// The table's row. Columns: assigned, eligible, overridden, fullOn, custom, audienceMismatch,
		// ruleOverride.
		var flags: [Bool] {
			switch self {
			case .override, .overrideOverStrictMismatch: return [false, true, true, false, false, false, false]
			case .rule, .ruleOverStrictMismatch: return [false, true, false, false, false, false, true]
			case .strictMismatch, .strictMismatchOverFullOn, .strictMismatchOverTrafficMiss:
				return [false, true, false, false, false, true, false]
			case .nonStrictMismatch: return [true, true, false, false, false, true, false]
			case .fullOn: return [true, true, false, true, false, false, false]
			case .trafficMiss: return [true, false, false, false, false, false, false]
			case .custom: return [true, true, false, false, true, false, false]
			case .draw: return [true, true, false, false, false, false, false]
			}
		}

		// The variant served at anchor + 2h + 3 (period 2, whose 3-arm draw is 1). Override, rule,
		// full-on and custom force arm 2, which differs from both control and the draw.
		var expectedVariant: Int {
			switch self {
			case .override, .overrideOverStrictMismatch, .rule, .ruleOverStrictMismatch, .fullOn, .custom: return 2
			case .strictMismatch, .strictMismatchOverFullOn, .strictMismatchOverTrafficMiss, .trafficMiss: return 0
			case .nonStrictMismatch, .draw: return SB.expected3Arms[2]
			}
		}
	}

	func exposureFlags(_ exposure: Exposure) -> [Bool] {
		return [
			exposure.assigned, exposure.eligible, exposure.overridden, exposure.fullOn, exposure.custom,
			exposure.audienceMismatch, exposure.ruleOverride,
		]
	}

	func exposeOnce(_ experiment: [String: Any], _ branch: ParityBranch) -> Exposure? {
		var experiment = experiment
		branch.configure(&experiment)
		let context = createContext(SB.data([experiment]))
		branch.configure(context)
		_ = context.getTreatment("exp_parity")
		let exposures = publishExposures(context)
		XCTAssertEqual(1, exposures.count, "\(branch)")
		return exposures.first
	}

	// The same branch run on a unit experiment and on an eligible-cluster switchback publishes the same
	// exposure, apart from the unit and the variant, and both match the SWITCHBACK.md table. The variant
	// is checked too: on the switchback for every branch, on the unit wherever it does not draw.
	func testExposureFlagsMatchAUnitExperimentForEveryBranch() throws {
		XCTAssertEqual(1, SB.expected3Arms[2])
		for branch in ParityBranch.allCases {
			clock.now = SB.anchor + 2 * SB.hour + 3
			let unit = unitize(SB.switchback(1, "exp_parity", arms: 3, periodMs: SB.hour))
			let unitExposure = try XCTUnwrap(exposeOnce(unit, branch))
			let switchbackExposure = try XCTUnwrap(exposeOnce(SB.switchback(1, "exp_parity", arms: 3, periodMs: SB.hour), branch))

			XCTAssertEqual(branch.flags, exposureFlags(unitExposure), "unit \(branch)")
			XCTAssertEqual(branch.flags, exposureFlags(switchbackExposure), "switchback \(branch)")
			XCTAssertEqual(branch.expectedVariant, switchbackExposure.variant, "switchback variant \(branch)")
			if branch != .draw && branch != .nonStrictMismatch {
				XCTAssertEqual(branch.expectedVariant, unitExposure.variant, "unit variant \(branch)")
			}
			XCTAssertEqual(unitExposure.id, switchbackExposure.id)
			XCTAssertEqual(unitExposure.name, switchbackExposure.name)
			XCTAssertEqual(unitExposure.exposedAt, switchbackExposure.exposedAt, "\(branch)")
		}
	}

	// MARK: - Traffic, lookups, cache

	// A traffic miss on an eligible cluster is recorded: eligible=false, variant 0, under the serving
	// unit. An ineligible cluster, by contrast, records nothing.
	func testTrafficMissOnAnEligibleClusterPublishesAnIneligibleExposure() {
		var miss = SB.switchback(1, "exp_miss", arms: 2, periodMs: SB.hour)
		miss["trafficSplit"] = [1.0, 0.0]
		var ineligibleCluster = SB.switchback(2, "exp_cluster_ineligible", arms: 2, periodMs: SB.hour)
		ineligibleCluster["trafficSplit"] = [1.0, 0.0]
		ineligibleCluster["switchbackClusterValues"] = ["other-store"]
		let context = createContext(SB.data([miss, ineligibleCluster]))
		clock.now = SB.anchor + 2 * SB.hour + 3
		XCTAssertEqual(0, context.getTreatment("exp_miss"))
		XCTAssertEqual(0, context.getTreatment("exp_cluster_ineligible"))
		XCTAssertEqual(
			[exposure(0, SB.anchor + 2 * SB.hour + 3, name: "exp_miss", eligible: false)], publishExposures(context))
	}

	func testCustomFieldValuesAndUnitLookupsWork() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.uid, context.getUnit(unitType: SB.unitType))
		XCTAssertEqual(0, context.getCustomFieldKeys().count)
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_sb", key: "missing"))
	}

	// Each experiment keeps entries for at most its two most recent periods. Swift has no cache-size
	// seam (java-sdk's assignmentCacheSizeForTest), so the bound is shown by what it does: a period
	// still retained is not re-exposed, an evicted one is, once.
	func testPerPeriodCacheIsBounded() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		for i in 0..<50 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			_ = context.getTreatment("exp_sb")
		}
		XCTAssertEqual(50, context.getPendingCount())

		// Retained: periods 48 and 49.
		for i in [48, 49] {
			clock.now = SB.anchor + Int64(i) * SB.hour
			_ = context.getTreatment("exp_sb")
		}
		XCTAssertEqual(50, context.getPendingCount())
		// Every earlier period was evicted.
		for i in [0, 47] {
			clock.now = SB.anchor + Int64(i) * SB.hour
			_ = context.getTreatment("exp_sb")
			_ = context.getTreatment("exp_sb")
		}
		XCTAssertEqual(52, context.getPendingCount())
	}

	// unitType on a switchback payload is never used for assignment: the cluster map decides.
	func testUnitTypeIsNotUsedForSwitchbackAssignment() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["unitType"] = "user_id"
		let context = createContext(SB.data([experiment]), units: [SB.unitType: SB.uid, "user_id": "u1"])
		for i in 0..<3 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(SB.expected2Arms[i], context.getTreatment("exp_sb"))
		}
		let exposures = publishExposures(context)
		XCTAssertEqual(3, exposures.count)
		for exposure in exposures {
			XCTAssertEqual(SB.unitType, exposure.unit)
		}
	}

	// MARK: - Publish payload

	// The publish payload carries no switchback-specific exposure or publish fields.
	func testPublishPayloadHasNoNewFields() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 5
		_ = context.getTreatment("exp_sb")
		clock.now = SB.anchor + SB.hour + 7
		_ = context.getTreatment("exp_sb")
		clock.now = SB.anchor + SB.hour + 9

		func exposureJSON(_ variant: Int, _ exposedAt: Int64) -> String {
			return "{\"assigned\":true,\"audienceMismatch\":false,\"custom\":false,\"eligible\":true,\"exposedAt\":\(exposedAt),"
				+ "\"fullOn\":false,\"id\":1,\"name\":\"exp_sb\",\"overridden\":false,\"ruleOverride\":false,"
				+ "\"unit\":\"store_id\",\"variant\":\(variant)}"
		}
		// The cluster attribute is published timestamped, as before: the Collector re-resolves the
		// cluster at exposedAt from it.
		XCTAssertEqual(
			"{\"attributes\":[{\"name\":\"\(SB.clusterPath)\",\"setAt\":\(SB.anchor),\"value\":\"\(SB.clusterKey)\"}],"
				+ "\"exposures\":[" + exposureJSON(SB.expected2Arms[0], SB.anchor + 5) + ","
				+ exposureJSON(SB.expected2Arms[1], SB.anchor + SB.hour + 7) + "],"
				+ "\"hashed\":true,\"publishedAt\":\(SB.anchor + SB.hour + 9),"
				+ "\"units\":[{\"type\":\"store_id\",\"uid\":\"\(SB.uidHash)\"}]}",
			publishedJSON(context))
		XCTAssertNotEqual(SB.expected2Arms[0], SB.expected2Arms[1])
	}

	func testPeriodsPublishedAcrossFlushesStayOnePerPeriod() throws {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		handler.clearInvocations()
		clock.now = SB.anchor
		_ = context.getTreatment("exp_sb")
		try context.publish().wait()
		clock.now = SB.anchor + 1
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(0, context.getPendingCount())
		clock.now = SB.anchor + SB.hour
		_ = context.getTreatment("exp_sb")
		try context.publish().wait()

		XCTAssertEqual(2, handler.publishEventCallsCount)
		let variants = handler.publishEventReceivedInvocations.flatMap { ($0.exposures ?? []).map { $0.variant } }
		XCTAssertEqual([SB.expected2Arms[0], SB.expected2Arms[1]], variants)
	}

	// MARK: - Exposure timing

	// The clock crosses into period 1 between resolution (first read) and any later read; the exposure
	// must still carry the instant that selected period 0.
	func testTreatmentExposureIsStampedWithTheResolutionInstant() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + SB.hour
		clock.nextRead = SB.anchor + SB.hour - 1

		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual([exposure(SB.expected2Arms[0], SB.anchor + SB.hour - 1)], publishExposures(context))
	}

	func testVariableExposureIsStampedWithTheResolutionInstant() {
		// Two arms, all traffic in arm 1; holdouts never fire through a switchback.
		var covered = SB.switchback(arms: 2, periodMs: SB.hour)
		covered["holdoutIds"] = [11]
		let context = createContext(SB.data([covered], holdouts: [SB.holdout(split: [0.0, 1.0])]))
		clock.now = SB.anchor + SB.hour
		clock.nextRead = SB.anchor + SB.hour - 1

		XCTAssertEqual(SB.expected2Arms[0], variable(context))
		XCTAssertEqual([exposure(SB.expected2Arms[0], SB.anchor + SB.hour - 1)], publishExposures(context))
	}

	// A peek caches the period's assignment without exposing; the later getTreatment exposes at its own
	// resolution instant, not the peek's.
	func testExposureAfterPeekUsesTheExposingCallsInstant() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(SB.expected2Arms[0], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + 20 * 60_000
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual([exposure(SB.expected2Arms[0], SB.anchor + 20 * 60_000)], publishExposures(context))
	}

	// Unit experiments keep stamping at enqueue time. java-sdk's getTreatment reads the clock once up
	// front, so its nextRead goes to that read and the enqueue read sees `now`. Swift reads the clock for
	// resolution only for a switchback, so a unit experiment's one read is the enqueue read: it takes
	// nextRead, and no resolution read happens before it.
	func testUnitExposureTimingIsUnchanged() {
		var unit = SB.switchback(arms: 2, periodMs: SB.hour)
		unit["randomizationType"] = "unit"
		let context = createContext(SB.data([unit]))
		clock.now = SB.anchor + SB.hour
		_ = context.peekTreatment("exp_sb")
		let readsBefore = clock.reads
		clock.nextRead = SB.anchor + SB.hour - 1

		let variant = context.getTreatment("exp_sb")
		XCTAssertEqual(readsBefore + 1, clock.reads)
		clock.nextRead = nil
		XCTAssertEqual([exposure(variant, SB.anchor + SB.hour - 1)], publishExposures(context))
	}

	// MARK: - Eviction and rewinds

	// A grid change that lowers the current index below the retained ones must not evict the entry it
	// just installed.
	func testGridRefreshToALowerIndexExposesOnce() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 99 * SB.hour
		_ = context.getTreatment("exp_sb")
		clock.now = SB.anchor + 100 * SB.hour
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(2, context.getPendingCount())

		var restarted = SB.switchback(arms: 2, periodMs: SB.hour)
		restarted["switchbackStartAt"] = SB.anchor + 100 * SB.hour
		refresh(context, SB.data([restarted]))
		for _ in 0..<3 {
			XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		}
		XCTAssertEqual(3, context.getPendingCount())
	}

	func testPeriodLengthRefreshToALowerIndexExposesOnce() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 100 * SB.hour
		_ = context.getTreatment("exp_sb")
		clock.now = SB.anchor + 101 * SB.hour
		_ = context.getTreatment("exp_sb")

		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: 200 * SB.hour)]))
		_ = context.getTreatment("exp_sb")
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(3, context.getPendingCount())
	}

	// Rewinding the clock across retained periods re-exposes each re-entered evicted period at most
	// once, never once per call.
	func testClockRewindReexposesAnEvictedPeriodAtMostOnce() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		for i in 0..<3 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			_ = context.getTreatment("exp_sb")
		}
		XCTAssertEqual(3, context.getPendingCount())

		clock.now = SB.anchor
		for _ in 0..<3 {
			XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		}
		XCTAssertEqual(4, context.getPendingCount())

		// Retained {0, 2}: period 2 is still deduplicated, period 1 was evicted.
		clock.now = SB.anchor + 2 * SB.hour
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(4, context.getPendingCount())
		clock.now = SB.anchor + SB.hour
		for _ in 0..<3 {
			XCTAssertEqual(SB.expected2Arms[1], context.getTreatment("exp_sb"))
		}
		XCTAssertEqual(5, context.getPendingCount())

		let exposures = publishExposures(context)
		XCTAssertEqual(5, exposures.count)
		guard exposures.count == 5 else { return }
		XCTAssertEqual(exposure(SB.expected2Arms[0], SB.anchor), exposures[3])
		XCTAssertEqual(exposure(SB.expected2Arms[1], SB.anchor + SB.hour), exposures[4])
	}

	// MARK: - Epochs

	// An overridden switchback slot is re-resolved on a grid change like a normal one; the override
	// still wins and the holdout never fires.
	func testOverrideIsReresolvedWhenTheGridChanges() {
		let holdout = SB.holdout(split: [0.0, 1.0])
		var original = SB.switchback(arms: 3, periodMs: SB.hour)
		original["holdoutIds"] = [11]
		let context = createContext(SB.data([original], holdouts: [holdout]))
		context.setOverride(experimentName: "exp_sb", variant: 2)

		clock.now = SB.anchor + 10
		XCTAssertEqual(2, context.getTreatment("exp_sb"))
		XCTAssertEqual(2, variable(context))
		XCTAssertEqual(1, context.getPendingCount())

		// Same index 0 under the new period length; variant 2 now carries a different value.
		var regridded = SB.switchback(arms: 3, periodMs: 2 * SB.hour)
		regridded["holdoutIds"] = [11]
		var variants = regridded["variants"] as! [[String: Any]]
		variants[2] = ["name": "C", "config": "{\"sb.arm\":22}"]
		regridded["variants"] = variants
		refresh(context, SB.data([regridded], holdouts: [holdout]))

		XCTAssertEqual(2, context.getTreatment("exp_sb"))
		XCTAssertEqual(22, variable(context))
		XCTAssertEqual(2, context.getPendingCount())

		let exposures = publishExposures(context)
		XCTAssertEqual(2, exposures.count)
		for exposure in exposures {
			XCTAssertEqual(
				Exposure(1, "exp_sb", SB.unitType, 2, SB.anchor + 10, false, true, true, false, false, false), exposure)
		}
	}

	// Each identity transition is a new epoch: returning to an identical grid re-resolves instead of
	// resurrecting the slot from before the transition.
	func testSwitchbackToUnitToIdenticalSwitchbackReresolves() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		var toUnit = SB.switchback(arms: 2, periodMs: SB.hour)
		toUnit["randomizationType"] = "unit"
		refresh(context, SB.data([toUnit]))
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(2, context.getPendingCount())

		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(3, context.getPendingCount())
	}

	func testRemovedAndRestoredSwitchbackReresolves() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		_ = context.getTreatment("exp_sb")

		refresh(context, SB.data([]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())

		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(3, context.getPendingCount())
	}

	// The pre-anchor bare-name slot shares the lifecycle of the period slots.
	func testPreAnchorSlotIsDroppedWhenTheGridChanges() {
		var gridA = SB.switchback(arms: 2, periodMs: SB.hour)
		gridA["switchbackStartAt"] = SB.anchor + 10 * SB.hour
		let context = createContext(SB.data([gridA]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())

		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		refresh(context, SB.data([gridA]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(0, variable(context))
		XCTAssertEqual(1, context.getPendingCount())
	}

	// Epochs are reconciled lazily; an intermediate state that is never looked up must still end the
	// epoch.
	func testTransitionsWithoutAnInterveningLookupStillReresolve() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(1, context.getPendingCount())

		var toUnit = SB.switchback(arms: 2, periodMs: SB.hour)
		toUnit["randomizationType"] = "unit"
		refresh(context, SB.data([toUnit]))
		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())

		refresh(context, SB.data([]))
		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(3, context.getPendingCount())

		var regridded = SB.switchback(arms: 2, periodMs: SB.hour)
		regridded["switchbackDesignType"] = "other"
		refresh(context, SB.data([regridded]))
		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(4, context.getPendingCount())

		// An unchanged identity keeps the epoch.
		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(4, context.getPendingCount())
	}

	// MARK: - Rules on switchback slots

	// java-sdk counts AudienceMatcher.evaluateRules calls. In Swift evaluateRules is declared in an
	// extension and cannot be overridden, so the observable behaviour is ported: a unit experiment
	// whose rule outcome changes after setAttribute is rebuilt with the rule's variant and stays
	// current afterwards.
	func testStaleRuleTransitionEvaluatesTheRulesTwice() {
		var unit = SB.switchback(arms: 2, periodMs: SB.hour)
		unit["randomizationType"] = "unit"
		unit["assignmentRules"] = Self.assignVariant1ToUS
		let context = createContext(SB.data([unit]))
		let before = context.peekTreatment("exp_sb")
		#if DEBUG
		let identity = context.cachedAssignmentIdentity("exp_sb")
		XCTAssertEqual(identity, context.cachedAssignmentIdentity("exp_sb"))
		#endif

		context.setAttribute(name: "country", value: JSON("US"))
		XCTAssertEqual(1, context.peekTreatment("exp_sb"))
		#if DEBUG
		let rebuilt = context.cachedAssignmentIdentity("exp_sb")
		if before != 1 {
			XCTAssertNotEqual(identity, rebuilt)
		}
		#endif
		// Current again: the same assignment is served.
		XCTAssertEqual(1, context.peekTreatment("exp_sb"))
		#if DEBUG
		XCTAssertEqual(rebuilt, context.cachedAssignmentIdentity("exp_sb"))
		#endif
	}

	// A legacy (missing or unreadable cluster map) switchback serves under its declared unitType, so a
	// unitType change on refresh is identity for it, unlike for a readable map. Swift has no
	// switchbackResolutionForTest seam: the unit it is served under is read from an overridden twin's
	// exposure, and the silent ineligible control from the pending count.
	func testLegacySwitchbackUnitTypeChangeIsIdentity() {
		func legacy(_ unitType: String, _ id: Int = 1, _ name: String = "exp_sb") -> [String: Any] {
			var experiment = SB.switchback(id, name, arms: 2, periodMs: SB.hour, clusters: nil)
			experiment["unitType"] = unitType
			if id != 1 {
				// The twin declares no variables, so it never answers the `sb.arm` key.
				experiment["variants"] = [["name": "A", "config": NSNull()], ["name": "B", "config": NSNull()]]
			}
			return experiment
		}
		let context = createContext(
			SB.data([legacy(SB.unitType), legacy(SB.unitType, 2, "exp_twin")]), units: [SB.unitType: SB.uid, "user_id": "u1"])
		context.setOverride(experimentName: "exp_twin", variant: 1)
		clock.now = SB.anchor + 10
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, variable(context))
		_ = context.getTreatment("exp_twin")

		refresh(context, SB.data([legacy("other"), legacy("other", 2, "exp_twin")]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(-1, variable(context))

		refresh(context, SB.data([legacy("user_id"), legacy("user_id", 2, "exp_twin")]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, variable(context))
		_ = context.getTreatment("exp_twin")
		// Only the overridden twin published, once under each declared unit type it had a unit for.
		XCTAssertEqual(
			[SB.unitType, "user_id"], publishExposures(context).map { $0.unit ?? "nil" })
	}

	// An ineligible or absent switchback slot never consulted its rules, so neither a set attribute nor
	// a rules refresh changes its result. (java-sdk also counts zero evaluateRules calls; see
	// testStaleRuleTransitionEvaluatesTheRulesTwice for why Swift cannot count them.)
	func testRulesAreNotReevaluatedForAnIneligibleOrAbsentSlot() {
		var ineligible = SB.switchback(1, "exp_ineligible", arms: 2, periodMs: SB.hour)
		ineligible["assignmentRules"] = Self.assignVariant1
		ineligible["switchbackClusterValues"] = ["other-store"]
		var absent = SB.switchback(2, "exp_absent", arms: 2, periodMs: SB.hour, clusters: [("device_id", SB.clusterPath)])
		absent["assignmentRules"] = Self.assignVariant1
		let context = createContext(SB.data([ineligible, absent]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(0, context.getTreatment("exp_ineligible"))
		XCTAssertEqual(0, context.getTreatment("exp_absent"))
		#if DEBUG
		let ineligibleSlot = context.cachedAssignmentIdentity("exp_ineligible")
		let absentSlot = context.cachedAssignmentIdentity("exp_absent")
		#endif

		context.setAttribute(name: "x", value: JSON(1))
		let changedRules = "{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":1,\"name\":\"changed\"}]}"
		ineligible["assignmentRules"] = changedRules
		absent["assignmentRules"] = changedRules
		refresh(context, SB.data([ineligible, absent]))

		XCTAssertEqual(0, context.getTreatment("exp_ineligible"))
		XCTAssertEqual(0, context.getTreatment("exp_absent"))
		XCTAssertEqual(0, context.getPendingCount())
		// Neither slot consulted its rules, so a rule change does not rebuild it.
		#if DEBUG
		XCTAssertEqual(ineligibleSlot, context.cachedAssignmentIdentity("exp_ineligible"))
		XCTAssertEqual(absentSlot, context.cachedAssignmentIdentity("exp_absent"))
		#endif
	}

	// A rule-won switchback re-resolved in the same period (an attribute set, a different rule with the
	// same variant) keeps its variant and is exposed once.
	func testInPeriodRuleRefreshKeepsTheVariantAndExposesOnce() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["assignmentRules"] = Self.assignVariant1
		let context = createContext(SB.data([experiment]))
		clock.now = SB.anchor + 5
		XCTAssertEqual(1, context.getTreatment("exp_sb"))

		context.setAttribute(name: "tier", value: JSON("x"))
		var refreshed = SB.switchback(arms: 2, periodMs: SB.hour)
		refreshed["assignmentRules"] =
			"{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":1,"
			+ "\"conditions\":{\"and\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"x\"}]}]}}]}"
		refresh(context, SB.data([refreshed]))
		clock.now = SB.anchor + 6
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual([ruleExposure("exp_sb", 1, SB.anchor + 5)], publishExposures(context))
	}

	// SDK choice (see SWITCHBACK.md): before the anchor nothing is recorded, a traffic miss included,
	// because the pre-period check precedes traffic. From the anchor the same miss is recorded.
	func testPreAnchorTrafficMissIsSilent() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["trafficSplit"] = [1.0, 0.0]
		clock.now = SB.anchor - 1
		let context = createContext(SB.data([experiment]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())

		clock.now = SB.anchor
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual([exposure(0, SB.anchor, eligible: false)], publishExposures(context))
	}

	// An override on a switchback with no serving unit is exposed under the declared unitType when the
	// cluster map is missing or unreadable (the legacy path's unit), never under nil or a cluster map
	// type.
	func testOverrideWithoutAServingUnitOnALegacySwitchbackUsesTheDeclaredUnitType() {
		var missing = SB.switchback(1, "exp_missing_map", arms: 2, periodMs: SB.hour, clusters: nil)
		missing["unitType"] = "user_id"
		var unreadable = SB.switchback(
			2, "exp_unreadable_map", arms: 2, periodMs: SB.hour, clusters: [(SB.unitType, "'unterminated")])
		unreadable["unitType"] = "user_id"
		let context = createContext(SB.data([missing, unreadable]))
		context.setOverride(experimentName: "exp_missing_map", variant: 1)
		context.setOverride(experimentName: "exp_unreadable_map", variant: 1)
		clock.now = SB.anchor + 5
		XCTAssertEqual(1, context.getTreatment("exp_missing_map"))
		XCTAssertEqual(1, context.getTreatment("exp_unreadable_map"))

		XCTAssertEqual(
			[
				Exposure(1, "exp_missing_map", "user_id", 1, SB.anchor + 5, false, true, true, false, false, false),
				Exposure(2, "exp_unreadable_map", "user_id", 1, SB.anchor + 5, false, true, true, false, false, false),
			], publishExposures(context))
	}

	// Exact wire form of a rule-won and a traffic-miss switchback exposure.
	func testRuleWonAndTrafficMissExposuresSerializeExactly() {
		var rule = SB.switchback(1, "exp_rule", arms: 2, periodMs: SB.hour)
		rule["assignmentRules"] = Self.assignVariant1
		var miss = SB.switchback(2, "exp_miss", arms: 2, periodMs: SB.hour)
		miss["trafficSplit"] = [1.0, 0.0]
		let context = createContext(SB.data([rule, miss]))
		clock.now = SB.anchor + 5
		_ = context.getTreatment("exp_rule")
		_ = context.getTreatment("exp_miss")
		clock.now = SB.anchor + 9

		XCTAssertEqual(
			"{\"attributes\":[{\"name\":\"\(SB.clusterPath)\",\"setAt\":\(SB.anchor),\"value\":\"\(SB.clusterKey)\"}],"
				+ "\"exposures\":["
				+ "{\"assigned\":false,\"audienceMismatch\":false,\"custom\":false,\"eligible\":true,\"exposedAt\":\(SB.anchor + 5),"
				+ "\"fullOn\":false,\"id\":1,\"name\":\"exp_rule\",\"overridden\":false,\"ruleOverride\":true,"
				+ "\"unit\":\"store_id\",\"variant\":1},"
				+ "{\"assigned\":true,\"audienceMismatch\":false,\"custom\":false,\"eligible\":false,\"exposedAt\":\(SB.anchor + 5),"
				+ "\"fullOn\":false,\"id\":2,\"name\":\"exp_miss\",\"overridden\":false,\"ruleOverride\":false,"
				+ "\"unit\":\"store_id\",\"variant\":0}],"
				+ "\"hashed\":true,\"publishedAt\":\(SB.anchor + 9),"
				+ "\"units\":[{\"type\":\"store_id\",\"uid\":\"\(SB.uidHash)\"}]}",
			publishedJSON(context))
	}

	// MARK: - Refresh from inside audience evaluation

	// Audience evaluation runs under `contextLock`; this matcher refreshes the context from inside it.
	final class RefreshingAudienceMatcher: AudienceMatcher {
		private let lock = NSLock()
		weak var context: Context?
		private var refreshOnNextEvaluationValue = false
		private(set) var refreshes: [Promise<Void>] = []

		var refreshOnNextEvaluation: Bool {
			get { lock.lock(); defer { lock.unlock() }; return refreshOnNextEvaluationValue }
			set { lock.lock(); refreshOnNextEvaluationValue = newValue; lock.unlock() }
		}

		override func evaluate(_ audience: String, _ attributes: [String: JSON]) -> Bool? {
			if refreshOnNextEvaluation {
				refreshOnNextEvaluation = false
				if let promise = context?.refresh() {
					lock.lock()
					refreshes.append(promise)
					lock.unlock()
				}
			}
			return true
		}
	}

	func stubRefreshData(completeOnAnotherThread: Bool, _ data: ContextData) {
		if !completeOnAnotherThread {
			provider.getContextDataReturnValue = Promise<ContextData>.value(data)
			return
		}
		provider.getContextDataClosure = {
			let (promise, seal) = Promise<ContextData>.pending()
			Thread.detachNewThread {
				Thread.sleep(forTimeInterval: 0.05)
				seal.fulfill(data)
			}
			return promise
		}
	}

	// Runs getTreatment on another thread and fails, rather than hanging the suite, if it does not
	// return within the bound.
	func getTreatmentWithin(_ context: Context, _ name: String, timeout: TimeInterval) -> Int? {
		let done = DispatchSemaphore(value: 0)
		let result = LockedBox<Int?>(nil)
		Thread.detachNewThread {
			result.value = context.getTreatment(name)
			done.signal()
		}
		guard done.wait(timeout: .now() + timeout) == .success else {
			XCTFail("getTreatment did not return: refresh from audience evaluation deadlocked")
			return nil
		}
		return result.value
	}

	func waitForRefreshes(_ matcher: RefreshingAudienceMatcher) {
		for promise in matcher.refreshes {
			let settled = expectation(description: "refresh settles")
			promise.ensure { settled.fulfill() }.catch { _ in }
			wait(for: [settled], timeout: 10)
		}
	}

	func refreshFromAudienceRevalidationCompletes(completeOnAnotherThread: Bool) {
		var unit = SB.switchback(arms: 2, periodMs: SB.hour)
		unit["randomizationType"] = "unit"
		unit["audience"] = Self.trueAudience
		let matcher = RefreshingAudienceMatcher()
		let context = createContext(SB.data([unit]), matcher: matcher)
		matcher.context = context
		stubRefreshData(completeOnAnotherThread: completeOnAnotherThread, SB.data([unit]))

		let primed = context.getTreatment("exp_sb")
		context.setAttribute(name: "country", value: JSON("PT"))
		matcher.refreshOnNextEvaluation = true

		XCTAssertEqual(primed, getTreatmentWithin(context, "exp_sb", timeout: 10))
		waitForRefreshes(matcher)
		XCTAssertEqual(1, provider.getContextDataCallsCount)
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testRefreshFromAudienceRevalidationWithACompletedProviderFutureDoesNotDeadlock() {
		refreshFromAudienceRevalidationCompletes(completeOnAnotherThread: false)
	}

	func testRefreshFromAudienceRevalidationWithAnAsyncProviderDoesNotDeadlock() {
		refreshFromAudienceRevalidationCompletes(completeOnAnotherThread: true)
	}

	// The first resolution evaluates the audience under `contextLock` too.
	func testRefreshFromAudienceEvaluationOnFirstResolutionWithAnAsyncProviderDoesNotDeadlock() {
		var unit = SB.switchback(arms: 2, periodMs: SB.hour)
		unit["randomizationType"] = "unit"
		unit["audience"] = Self.trueAudience
		let matcher = RefreshingAudienceMatcher()
		let context = createContext(SB.data([unit]), matcher: matcher)
		matcher.context = context
		stubRefreshData(completeOnAnotherThread: true, SB.data([unit]))
		matcher.refreshOnNextEvaluation = true

		XCTAssertNotNil(getTreatmentWithin(context, "exp_sb", timeout: 10))
		waitForRefreshes(matcher)
		XCTAssertEqual(1, provider.getContextDataCallsCount)
		XCTAssertEqual(1, context.getPendingCount())
	}

	// MARK: - Concurrent resolution

	// java-sdk holds both readers at a barrier inside audience evaluation, so both reject the cached
	// slot under a read lock before either takes the write lock. Swift resolves under one recursive
	// `contextLock`, so two readers can never be inside evaluation together and that barrier would only
	// time out. What it protects is ported instead: after the audience flips, two concurrent callers
	// re-resolve the period once, keep the cluster key read at first resolution, and expose once.
	final class FlippingAudienceMatcher: AudienceMatcher {
		private let lock = NSLock()
		private var evaluationsValue = 0

		var evaluations: Int {
			lock.lock()
			defer { lock.unlock() }
			return evaluationsValue
		}

		override func evaluate(_ audience: String, _ attributes: [String: JSON]) -> Bool? {
			lock.lock()
			evaluationsValue += 1
			let call = evaluationsValue
			lock.unlock()
			if call > 1 {
				// Widens the window in which the other threads contend for the slot.
				Thread.sleep(forTimeInterval: 0.01)
			}
			return call == 1
		}
	}

	func testConcurrentResolutionOfTheSamePeriodExposesOnce() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["audience"] = Self.trueAudience
		resolvePeriodOneConcurrently(experiment, concurrentCity: nil, expectedVariant: SB.expected2Arms[1])
	}

	// The cluster attribute changes before both readers re-resolve the slot, and a third worker keeps
	// writing it meanwhile. The slot keeps the key read at first resolution (Lisboa, variant 1 in
	// period 1); Faro is variant 0 there, so a re-read key is visible.
	func testConcurrentResolutionWithConcurrentSetAttributeExposesOnce() {
		XCTAssertEqual(1, SB.draw("Lisboa", 1, arms: 2))
		XCTAssertEqual(0, SB.draw("Faro", 1, arms: 2))
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour, clusters: [(SB.unitType, "city")])
		experiment["audience"] = Self.trueAudience
		resolvePeriodOneConcurrently(experiment, concurrentCity: "Faro", expectedVariant: 1)
	}

	func resolvePeriodOneConcurrently(_ experiment: [String: Any], concurrentCity: String?, expectedVariant: Int) {
		let matcher = FlippingAudienceMatcher()
		let context = createContext(SB.data([experiment]), matcher: matcher)
		clock.now = SB.anchor + SB.hour + 10
		context.setAttribute(name: "city", value: JSON("Lisboa"))

		// Caches period 1 without exposing it; the attribute change forces both callers to revalidate.
		XCTAssertEqual(expectedVariant, context.peekTreatment("exp_sb"))
		context.setAttribute(name: "country", value: JSON("PT"))
		if let city = concurrentCity {
			context.setAttribute(name: "city", value: JSON(city))
		}

		let variants = LockedBox<[Int]>([])
		let readersDone = LockedBox(0)
		let start = DispatchSemaphore(value: 0)
		let finished = DispatchGroup()
		for _ in 0..<2 {
			finished.enter()
			Thread.detachNewThread {
				start.wait()
				let variant = context.getTreatment("exp_sb")
				variants.update { $0.append(variant) }
				readersDone.update { $0 += 1 }
				finished.leave()
			}
		}
		if let city = concurrentCity {
			finished.enter()
			Thread.detachNewThread {
				start.wait()
				var writes = 0
				while writes < 100_000 {
					let done = readersDone.value == 2
					if done && writes >= 1000 {
						break
					}
					context.setAttribute(name: "city", value: JSON(city))
					writes += 1
				}
				finished.leave()
			}
		}
		for _ in 0..<(concurrentCity != nil ? 3 : 2) {
			start.signal()
		}
		XCTAssertEqual(.success, finished.wait(timeout: .now() + 10))

		XCTAssertEqual([expectedVariant, expectedVariant], variants.value)
		XCTAssertGreaterThanOrEqual(matcher.evaluations, 2)
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(
			[Exposure(1, "exp_sb", SB.unitType, expectedVariant, SB.anchor + SB.hour + 10, true, true, false, false, false, true)],
			publishExposures(context))
	}
}

extension ContextSwitchbackLifecycleTest {
	// A refresh that moves the anchor (or reorders the cluster map) while `now` stays in period 0 of
	// both grids re-resolves the slot and exposes again: the period index alone cannot tell them apart.
	func testSameIndexGridChangesReresolve() {
		clock.now = SB.anchor + 10
		let original = SB.switchback(arms: 2, periodMs: 2 * SB.hour)
		let context = createContext(
			SB.data([original]), units: [SB.unitType: SB.uid, "device_id": "d-1"])
		XCTAssertNotNil(context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		var moved = SB.switchback(arms: 2, periodMs: 2 * SB.hour)
		moved["switchbackStartAt"] = SB.anchor - SB.hour
		refresh(context, SB.data([moved]))
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(2, context.getPendingCount())

		var twoSources = moved
		twoSources["switchbackClusters"] = SB.OrderedObject([(SB.unitType, SB.clusterPath), ("device_id", SB.clusterPath)])
		refresh(context, SB.data([twoSources]))
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(3, context.getPendingCount())

		var reordered = moved
		reordered["switchbackClusters"] = SB.OrderedObject([("device_id", SB.clusterPath), (SB.unitType, SB.clusterPath)])
		refresh(context, SB.data([reordered]))
		XCTAssertNotNil(context.getTreatment("exp_sb"))
		XCTAssertEqual(4, context.getPendingCount())
		XCTAssertEqual(["store_id", "store_id", "store_id", "device_id"], publishExposures(context).map { $0.unit })
	}
}

extension ContextSwitchbackLifecycleTest {
	// A split rule revalidated after an unrelated setAttribute randomizes over the serving unit, as at
	// resolution, so the slot is kept and not exposed again.
	func testSplitRuleRevalidationUsesTheServingUnit() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["unitType"] = "user_id"
		experiment["assignmentRules"] =
			"{\"rules\":[{\"type\":\"split\",\"environments\":[],\"percentages\":\"50/50\"}]}"
		let userVariant = VariantAssigner(Hashing.hashBytes("fixed-user")).assign([0.5, 0.5], SB.seedHi, SB.seedLo)
		var checked = 0
		for u in 0..<32 {
			let uid = "store-\(u)"
			let expected = VariantAssigner(Hashing.hashBytes(uid)).assign([0.5, 0.5], SB.seedHi, SB.seedLo)
			if expected == userVariant { continue }
			checked += 1
			let context = createContext(SB.data([experiment]), units: [SB.unitType: uid, "user_id": "fixed-user"])
			XCTAssertEqual(expected, context.getTreatment("exp_sb"), uid)
			context.setAttribute(name: "unrelated", value: JSON("x"))
			XCTAssertEqual(expected, context.getTreatment("exp_sb"), uid)
			XCTAssertEqual(1, context.getPendingCount(), uid)
		}
		XCTAssertGreaterThan(checked, 0)
	}

	// A custom assignment set after a switchback slot resolved takes effect in that period.
	func testCustomAssignmentSetMidPeriodIsApplied() {
		let context = createContext(SB.data([SB.switchback(arms: 3, periodMs: SB.hour)]))
		clock.now = SB.anchor
		XCTAssertEqual(SB.expected3Arms[0], context.peekTreatment("exp_sb"))
		let custom = (SB.expected3Arms[0] + 1) % 3
		context.setCustomAssignment(experimentName: "exp_sb", variant: custom)
		XCTAssertEqual(custom, context.getTreatment("exp_sb"))
		XCTAssertEqual(
			[exposure(custom, SB.anchor, custom: true)], publishExposures(context))
	}
}

extension ContextSwitchbackLifecycleTest {
	// Before the anchor a switchback's slot is the bare experiment name. Refreshed into a unit
	// experiment, the name must not serve that silent control: the unit draw is resolved and exposed.
	func testPreAnchorSlotIsNotReusedByAUnitExperiment() {
		var preAnchor = SB.switchback(arms: 2, periodMs: SB.hour)
		preAnchor["switchbackStartAt"] = SB.anchor + 10 * SB.hour
		let context = createContext(SB.data([preAnchor]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())

		var toUnit = SB.switchback(arms: 2, periodMs: SB.hour)
		toUnit["randomizationType"] = "unit"
		toUnit["split"] = [0.0, 1.0]
		refresh(context, SB.data([toUnit]))
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual([exposure(1, SB.anchor + 10)], publishExposures(context))
	}
}

extension ContextSwitchbackLifecycleTest {
	// A unit experiment refreshed into a switchback before its anchor: the bare-name slot holds the
	// unit assignment, so the switchback must not reuse it (silent control, no second exposure).
	func testUnitSlotIsNotReusedByAPreAnchorSwitchback() {
		var unit = SB.switchback(arms: 2, periodMs: SB.hour)
		unit["randomizationType"] = "unit"
		unit["split"] = [0.0, 1.0]
		let context = createContext(SB.data([unit]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual([exposure(1, SB.anchor + 10)], publishExposures(context))

		var preAnchor = SB.switchback(arms: 2, periodMs: SB.hour)
		preAnchor["switchbackStartAt"] = SB.anchor + 10 * SB.hour
		preAnchor["split"] = [0.0, 1.0]
		refresh(context, SB.data([preAnchor]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	// The same with an override: the overridden unit assignment must be re-resolved as a switchback
	// override, published under the serving unit.
	func testOverriddenUnitSlotIsRepinnedAsSwitchback() {
		var unit = SB.switchback(arms: 2, periodMs: SB.hour)
		unit["randomizationType"] = "unit"
		unit["unitType"] = "user_id"
		let context = createContext(SB.data([unit]), units: [SB.unitType: SB.uid, "user_id": "u1"])
		context.setOverride(experimentName: "exp_sb", variant: 1)
		clock.now = SB.anchor + 10
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual(["user_id"], publishExposures(context).map { $0.unit })

		var preAnchor = SB.switchback(arms: 2, periodMs: SB.hour)
		preAnchor["unitType"] = "user_id"
		preAnchor["switchbackStartAt"] = SB.anchor + 10 * SB.hour
		refresh(context, SB.data([preAnchor]))
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual([SB.unitType], publishExposures(context).map { $0.unit })
	}
}

extension ContextSwitchbackLifecycleTest {
	// R2: the custom assignment recorded on the slot must survive pinSwitchbackConfig; otherwise every read
	// re-resolves the slot and queues another exposure.
	func testCustomAssignedSlotIsReusedWithinThePeriod() {
		let context = createContext(SB.data([SB.switchback(arms: 3, periodMs: SB.hour)]))
		let custom = (SB.expected3Arms[0] + 1) % 3
		context.setCustomAssignment(experimentName: "exp_sb", variant: custom)
		clock.now = SB.anchor
		XCTAssertEqual(custom, context.getTreatment("exp_sb"))
		XCTAssertEqual(custom, context.getTreatment("exp_sb"))
		XCTAssertEqual(custom, context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual([exposure(custom, SB.anchor, custom: true)], publishExposures(context))
	}

	// R10: an override resolved with no linked unit records an absent serving, so setUnit re-resolves it
	// and its exposure goes out under the unit now linked, not the first cluster's fallback.
	func testUnexposedAbsentOverrideIsReresolvedAfterSetUnit() {
		let experiment = SB.switchback(
			arms: 2, periodMs: SB.hour, clusters: [("first_id", "first_key"), (SB.unitType, SB.clusterPath)])
		let context = createContext(SB.data([experiment]), units: [:])
		context.setOverride(experimentName: "exp_sb", variant: 1)
		clock.now = SB.anchor
		XCTAssertEqual(1, context.peekTreatment("exp_sb"))
		context.setUnit(unitType: SB.unitType, uid: SB.uid)
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual([SB.unitType], publishExposures(context).map { $0.unit })
	}
}

extension ContextSwitchbackLifecycleTest {
	// M4: an override set after the period slot was resolved keeps that slot's serving unit, as in
	// java-sdk (Context.java:1858-1865 passes cachedServing on the override path): a cluster attribute set
	// after the first resolution must not move the exposure to another unit within the period.
	func testOverrideSetMidPeriodKeepsTheSlotsServingUnit() {
		let experiment = SB.switchback(
			arms: 2, periodMs: SB.hour, clusters: [("first_id", "first_key"), (SB.unitType, SB.clusterPath)])
		let context = createContext(SB.data([experiment]), units: [SB.unitType: SB.uid, "first_id": "f1"])
		clock.now = SB.anchor
		XCTAssertNotNil(context.peekTreatment("exp_sb"))
		context.setAttribute(name: "first_key", value: JSON("first-7"))
		context.setOverride(experimentName: "exp_sb", variant: 1)
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual([SB.unitType], publishExposures(context).map { $0.unit })
	}
}

extension ContextSwitchbackLifecycleTest {
	// M12: an exposed override resolved with no linked unit has published its exposure, so setUnit keeps it
	// (java-sdk Context.java:463-466) and a later read queues no second exposure.
	func testExposedAbsentOverrideIsKeptAcrossSetUnit() {
		let experiment = SB.switchback(
			arms: 2, periodMs: SB.hour, clusters: [("first_id", "first_key"), (SB.unitType, SB.clusterPath)])
		let context = createContext(SB.data([experiment]), units: [:])
		context.setOverride(experimentName: "exp_sb", variant: 1)
		clock.now = SB.anchor
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		context.setUnit(unitType: SB.unitType, uid: SB.uid)
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(["first_id"], publishExposures(context).map { $0.unit })
	}

	// M11: an absent serving is never reused: the kept exposed absent override, replaced after setUnit by
	// a new override, re-reads the serving and is published under the unit now linked.
	func testAbsentServingIsReresolvedWhenAKeptSlotIsReplaced() {
		let experiment = SB.switchback(
			arms: 2, periodMs: SB.hour, clusters: [("first_id", "first_key"), (SB.unitType, SB.clusterPath)])
		let context = createContext(SB.data([experiment]), units: [:])
		context.setOverride(experimentName: "exp_sb", variant: 1)
		clock.now = SB.anchor
		XCTAssertEqual(1, context.getTreatment("exp_sb"))
		context.setUnit(unitType: SB.unitType, uid: SB.uid)
		context.setOverride(experimentName: "exp_sb", variant: 0)
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(["first_id", SB.unitType], publishExposures(context).map { $0.unit })
	}
}
