import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// Port of java-sdk ContextSwitchbackTest (07807b51): switchback serving through a Context, with the
// period grid driven by a test clock.
final class ContextSwitchbackTest: SwitchbackTestCase {
	static let assignVariant1 = "{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":1}]}"
	static let assignVariant2 = "{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":2}]}"
	// An audience the default context never matches (no "tier" attribute).
	static let strictGoldAudience = "{\"filter\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"gold\"}]}]}"

	private func variable(_ context: Context, _ key: String = "sb.arm") -> Int? {
		return context.getVariableValue(key, defaultValue: JSON(-1))?.int
	}

	private func peekVariable(_ context: Context, _ key: String = "sb.arm") -> Int? {
		return context.peekVariableValue(key, defaultValue: JSON(-1))?.int
	}

	// A rule win is published exactly like a unit experiment's: ruleOverride set, assigned false.
	private func ruleExposure(_ name: String, _ variant: Int, _ exposedAt: Int64) -> Exposure {
		return exposure(variant, exposedAt, name: name, assigned: false, ruleOverride: true)
	}

	private func strictMismatchExposure(_ exposedAt: Int64) -> Exposure {
		return exposure(0, exposedAt, assigned: false, audienceMismatch: true)
	}

	private func strictSwitchback() -> [String: Any] {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["audience"] = Self.strictGoldAudience
		experiment["audienceStrict"] = true
		return experiment
	}

	// The cluster identity is the raw attribute value, neither hashed nor the unit uid.
	func testClusterIdentityIsTheRawClusterValue() {
		XCTAssertEqual(SB.uidHash, Hashing.hash(SB.uid))

		let context = createContext(SB.data([SB.switchback(arms: 3, periodMs: SB.hour)]))
		let served = peekSchedule(context)

		XCTAssertEqual(SB.expected3Arms, served)
		XCTAssertNotEqual(SB.uidHash3Arms, served)
		XCTAssertNotEqual(SB.uid3Arms, served)
		let hashedKey: String = Hashing.hash(SB.clusterKey)
		var hashedDiffers = false
		for i in 0..<12 {
			XCTAssertEqual(SB.draw(SB.clusterKey, Int64(i), arms: 3), served[i])
			hashedDiffers = hashedDiffers || SB.draw(hashedKey, Int64(i), arms: 3) != served[i]
		}
		XCTAssertTrue(hashedDiffers)
	}

	func testServesTwoThreeAndTenArmPermutations() {
		let context = createContext(
			SB.data([
				SB.switchback(1, "exp_2", arms: 2, periodMs: SB.hour), SB.switchback(2, "exp_3", arms: 3, periodMs: SB.hour),
				SB.switchback(3, "exp_10", arms: 10, periodMs: SB.hour),
			]))

		XCTAssertEqual(SB.expected2Arms, peekSchedule(context, "exp_2"))
		XCTAssertEqual(SB.expected3Arms, peekSchedule(context, "exp_3"))
		XCTAssertEqual(SB.expected10Arms, peekSchedule(context, "exp_10"))
	}

	func testOneHourBoundaryAtExactEdgeMilliseconds() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))

		clock.now = SB.anchor - 1
		XCTAssertEqual(0, context.peekTreatment("exp_sb"))
		clock.now = SB.anchor
		XCTAssertEqual(SB.expected2Arms[0], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + SB.hour - 1
		XCTAssertEqual(SB.expected2Arms[0], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(SB.expected2Arms[1], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + 3 * SB.hour - 1
		XCTAssertEqual(SB.expected2Arms[2], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + 3 * SB.hour
		XCTAssertEqual(SB.expected2Arms[3], context.peekTreatment("exp_sb"))
	}

	func testTwentyFourHourBoundaryAtExactEdgeMilliseconds() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.day)]))

		clock.now = SB.anchor - 1
		XCTAssertEqual(0, context.peekTreatment("exp_sb"))
		clock.now = SB.anchor
		XCTAssertEqual(SB.expected2Arms[0], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(SB.expected2Arms[0], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + SB.day - 1
		XCTAssertEqual(SB.expected2Arms[0], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + SB.day
		XCTAssertEqual(SB.expected2Arms[1], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + 4 * SB.day - 1
		XCTAssertEqual(SB.expected2Arms[3], context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + 4 * SB.day
		XCTAssertEqual(SB.expected2Arms[4], context.peekTreatment("exp_sb"))
	}

	// switchbackStartAt is the anchor, never rounded; before it the experiment is an ineligible control
	// that records no exposure. An anchor that is not hour aligned is unservable in every period.
	func testUnalignedStartIsUnservableAndPreAnchorIsIneligible() {
		var aligned = SB.switchback(1, "exp_aligned", arms: 2, periodMs: SB.hour)
		aligned["switchbackStartAt"] = SB.anchor + SB.hour
		var unaligned = SB.switchback(2, "exp_unaligned", arms: 2, periodMs: SB.hour)
		let start = SB.anchor + 1_234_567
		unaligned["switchbackStartAt"] = start
		let context = createContext(SB.data([aligned, unaligned]))

		for now in [SB.anchor, start - 1, start, SB.anchor + SB.hour - 1] {
			clock.now = now
			XCTAssertEqual(0, context.getTreatment("exp_aligned"))
			XCTAssertEqual(0, context.getTreatment("exp_unaligned"))
		}
		XCTAssertEqual(0, context.getPendingCount())
		for i in 1..<4 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(SB.expected2Arms[i - 1], context.getTreatment("exp_aligned"))
			XCTAssertEqual(0, context.getTreatment("exp_unaligned"))
			clock.now = start + Int64(i) * SB.hour
			XCTAssertEqual(0, context.getTreatment("exp_unaligned"))
		}

		XCTAssertEqual(
			[
				exposure(SB.expected2Arms[0], SB.anchor + SB.hour, name: "exp_aligned"),
				exposure(SB.expected2Arms[1], SB.anchor + 2 * SB.hour, name: "exp_aligned"),
				exposure(SB.expected2Arms[2], SB.anchor + 3 * SB.hour, name: "exp_aligned"),
			], publishExposures(context))
	}

	// The Collector Registry's anchor bounds: hour aligned and in [0, 10000-01-01T00:00:00Z). Unservable
	// means an ineligible control on resolution and no exposure on publish.
	func testAnchorNotOnAnHourBoundaryIsUnservableOnGetAndPost() {
		let maxAnchor: Int64 = 253_402_300_800_000
		let unservable: [Int64] = [
			SB.anchor + 1, SB.anchor - 1, SB.anchor + 30 * 60_000, SB.anchor + SB.hour - 1, -SB.hour, -1, maxAnchor,
			maxAnchor + SB.hour, Int64.max - (Int64.max % SB.hour),
		]
		for startAt in unservable {
			handler.clearInvocations()
			var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
			experiment["switchbackStartAt"] = startAt
			// The cluster attribute is set at context creation, before every resolution below.
			clock.now = 0
			let context = createContext(SB.data([experiment]))
			for now in [0, SB.anchor, SB.anchor + 2 * SB.hour + 1, startAt, startAt &+ SB.hour, maxAnchor + SB.day] {
				clock.now = now
				XCTAssertEqual(0, context.getTreatment("exp_sb"), "startAt \(startAt) now \(now)")
				XCTAssertEqual(0, variable(context))
			}
			XCTAssertEqual(0, context.getPendingCount(), "startAt \(startAt)")
			XCTAssertNoThrow(try context.publish().wait())
			XCTAssertEqual(0, handler.publishEventCallsCount)
		}

		// In-range hour-aligned anchors, including 0 and the last hour before the bound, serve.
		for startAt in [0, SB.anchor, maxAnchor - SB.hour] {
			var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
			experiment["switchbackStartAt"] = startAt
			clock.now = startAt + SB.hour
			let context = createContext(SB.data([experiment]))
			XCTAssertEqual(SB.expected2Arms[1], context.getTreatment("exp_sb"), "startAt \(startAt)")
			XCTAssertEqual(1, context.getPendingCount())
		}
	}

	func testNullStartAtIsIneligibleAndNeverFallsBackToUnitAssignment() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["switchbackStartAt"] = NSNull()
		let context = createContext(SB.data([experiment]))

		for i in 0..<4 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(0, context.getTreatment("exp_sb"))
			// Variant 0's own config, like any ineligible assignment.
			XCTAssertEqual(0, variable(context))
		}

		XCTAssertEqual(0, context.getPendingCount())
	}

	func testSamePeriodIsCachedAndNextPeriodRollsOverWithOneExposureEach() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))

		clock.now = SB.anchor + 10
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())
		clock.now = SB.anchor + SB.hour - 1
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(SB.expected2Arms[0], context.peekTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(SB.expected2Arms[1], context.peekTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(SB.expected2Arms[1], context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())
		clock.now = SB.anchor + SB.hour + 30 * 60_000
		XCTAssertEqual(SB.expected2Arms[1], context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())

		XCTAssertEqual(
			[exposure(SB.expected2Arms[0], SB.anchor + 10), exposure(SB.expected2Arms[1], SB.anchor + SB.hour)],
			publishExposures(context))
	}

	func testVariableLookupsFollowThePeriodAndExposeOncePerPeriod() {
		let context = createContext(SB.data([SB.switchback(arms: 3, periodMs: SB.hour)]))

		XCTAssertEqual(["sb.arm": ["exp_sb"]], context.getVariableKeys())
		XCTAssertEqual(["exp_sb"], context.getExperiments())

		for i in 0..<3 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(SB.expected3Arms[i], peekVariable(context))
			XCTAssertEqual(SB.expected3Arms[i], variable(context))
			XCTAssertEqual(SB.expected3Arms[i], variable(context))
			XCTAssertEqual(SB.expected3Arms[i], context.getTreatment("exp_sb"))
		}
		XCTAssertEqual(3, context.getPendingCount())
	}

	// No unit of a linked type: the experiment does not apply and records nothing. unitType is never
	// a fallback.
	func testMissingClusterUnitIsUnassignedWithoutFallback() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["unitType"] = "user_id"
		let context = createContext(SB.data([experiment]), units: ["user_id": SB.uid])

		for i in 0..<3 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(0, context.peekTreatment("exp_sb"))
			XCTAssertEqual(0, context.getTreatment("exp_sb"))
			XCTAssertEqual(-1, variable(context))
		}
		XCTAssertEqual(0, context.getPendingCount())

		// Setting a linked unit later makes the experiment apply.
		context.setUnit(unitType: SB.unitType, uid: SB.uid)
		XCTAssertEqual(SB.expected2Arms[2], context.getTreatment("exp_sb"))
		XCTAssertEqual([exposure(SB.expected2Arms[2], SB.anchor + 2 * SB.hour)], publishExposures(context))
	}

	func testFullOnServesTheFullOnVariantInEveryPeriod() {
		var experiment = SB.switchback(arms: 3, periodMs: SB.hour)
		experiment["fullOnVariant"] = 2
		let context = createContext(SB.data([experiment]))

		for i in 0..<4 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(2, context.getTreatment("exp_sb"))
		}
		let exposures = publishExposures(context)
		XCTAssertFalse(exposures.isEmpty)
		for exposure in exposures {
			XCTAssertEqual(2, exposure.variant)
			XCTAssertTrue(exposure.fullOn)
		}
	}

	func testOverrideAndCustomAssignmentWinInEveryPeriod() {
		let context = createContext(
			SB.data([
				SB.switchback(1, "exp_override", arms: 3, periodMs: SB.hour),
				SB.switchback(2, "exp_custom", arms: 3, periodMs: SB.hour),
			]))
		context.setOverride(experimentName: "exp_override", variant: 7)
		context.setCustomAssignment(experimentName: "exp_custom", variant: 2)

		for i in 0..<3 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(7, context.getTreatment("exp_override"))
			XCTAssertEqual(2, context.getTreatment("exp_custom"))
		}
		let exposures = publishExposures(context)
		XCTAssertFalse(exposures.isEmpty)
		for exposure in exposures {
			if exposure.name == "exp_override" {
				XCTAssertTrue(exposure.overridden)
				XCTAssertEqual(7, exposure.variant)
			} else {
				XCTAssertTrue(exposure.custom)
				XCTAssertEqual(2, exposure.variant)
			}
		}
	}

	// Traffic eligibility uses the per-unit traffic hash, so it matches a unit-randomized twin with the
	// same traffic seed and stays fixed across periods.
	func testTrafficEligibilityIsClusterSticky() {
		var eligibleCount = 0
		var ineligibleCount = 0
		for u in 0..<24 {
			handler.clearInvocations()

			var sb = SB.switchback(1, "exp_sb", arms: 2, periodMs: SB.hour)
			sb["trafficSplit"] = [0.5, 0.5]
			var twin = SB.switchback(2, "exp_unit", arms: 2, periodMs: SB.hour)
			twin["trafficSplit"] = [0.5, 0.5]
			twin["randomizationType"] = NSNull()
			twin["switchbackStartAt"] = NSNull()

			clock.now = SB.anchor
			let context = createContext(SB.data([sb, twin]), units: [SB.unitType: "store_\(u)"])
			_ = context.getTreatment("exp_unit")
			for i in 0..<4 {
				clock.now = SB.anchor + Int64(i) * SB.hour
				_ = context.getTreatment("exp_sb")
			}

			let exposures = publishExposures(context)
			XCTAssertEqual(5, exposures.count)
			guard exposures.count == 5 else { continue }
			let twinEligible = exposures[0].eligible
			for exposure in exposures[1...] {
				XCTAssertEqual("exp_sb", exposure.name)
				XCTAssertEqual(twinEligible, exposure.eligible)
				if !twinEligible {
					XCTAssertEqual(0, exposure.variant)
				}
			}
			if twinEligible {
				eligibleCount += 1
			} else {
				ineligibleCount += 1
			}
		}
		XCTAssertGreaterThan(eligibleCount, 0)
		XCTAssertGreaterThan(ineligibleCount, 0)
	}

	func testUnitExperimentsAreUnaffected() {
		var unit = SB.switchback(arms: 2, periodMs: SB.hour)
		unit["randomizationType"] = "unit"
		var absent = SB.switchback(2, "exp_absent", arms: 2, periodMs: SB.hour)
		absent["randomizationType"] = NSNull()

		let context = createContext(SB.data([unit, absent]))
		let variant = context.getTreatment("exp_sb")
		let absentVariant = context.getTreatment("exp_absent")
		for i in 1..<6 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(variant, context.getTreatment("exp_sb"))
			XCTAssertEqual(absentVariant, context.getTreatment("exp_absent"))
		}
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testRefreshInvalidatesWhenGridFieldsChangeButNotForAnalysisOnlyFields() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		var burnsChanged = SB.switchback(arms: 2, periodMs: SB.hour)
		burnsChanged["switchbackBurnInDurationMs"] = 600_000
		burnsChanged["switchbackBurnOutDurationMs"] = 300_000
		burnsChanged["switchbackCarryoverDurationMs"] = 900_000
		burnsChanged["switchbackEstimand"] = "other"
		refresh(context, SB.data([burnsChanged]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		// Same period index 0 under both grids, so only the config comparison can invalidate.
		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: 2 * SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())

		var designChanged = SB.switchback(arms: 2, periodMs: 2 * SB.hour)
		designChanged["switchbackDesignType"] = "other_design"
		refresh(context, SB.data([designChanged]))
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(3, context.getPendingCount())

		var toUnit = SB.switchback(arms: 2, periodMs: 2 * SB.hour)
		toUnit["randomizationType"] = "unit"
		refresh(context, SB.data([toUnit]))
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(4, context.getPendingCount())

		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: 2 * SB.hour)]))
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(5, context.getPendingCount())

		// The cluster map (types, paths and their order) and the allow-list are identity.
		let pathChanged = SB.switchback(arms: 2, periodMs: 2 * SB.hour, clusters: [(SB.unitType, "'store_key'")])
		refresh(context, SB.data([pathChanged]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(6, context.getPendingCount())

		let linkAdded = SB.switchback(
			arms: 2, periodMs: 2 * SB.hour, clusters: [(SB.unitType, "'store_key'"), ("device_id", "city")])
		refresh(context, SB.data([linkAdded]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(7, context.getPendingCount())

		let reordered: [(String, Any)] = [("device_id", "city"), (SB.unitType, "'store_key'")]
		let linksReordered = SB.switchback(arms: 2, periodMs: 2 * SB.hour, clusters: reordered)
		refresh(context, SB.data([linksReordered]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(8, context.getPendingCount())

		var valuesSet = SB.switchback(arms: 2, periodMs: 2 * SB.hour, clusters: reordered)
		valuesSet["switchbackClusterValues"] = [SB.clusterKey]
		refresh(context, SB.data([valuesSet]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(9, context.getPendingCount())

		// An unrelated unitType edit is not identity: switchbacks never read it.
		var unitTypeChanged = valuesSet
		unitTypeChanged["unitType"] = "anything"
		refresh(context, SB.data([unitTypeChanged]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(9, context.getPendingCount())
	}

	func testRefreshSettingStartAtStartsTheGrid() {
		var pending = SB.switchback(arms: 2, periodMs: SB.hour)
		pending["switchbackStartAt"] = NSNull()
		let context = createContext(SB.data([pending]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(0, context.getTreatment("exp_sb"))

		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	// Holdouts never apply to a switchback: a holdout that would hold the unit out neither suppresses
	// the switchback nor records its own exposure through it.
	func testHoldoutSuppressionAndExposureSpanPeriods() {
		// split [0.1, 0.9] -> variant 0 (held out) for uid.
		var covered = SB.switchback(arms: 2, periodMs: SB.hour)
		covered["holdoutIds"] = [11]
		let context = createContext(SB.data([covered], holdouts: [SB.holdout(split: [0.1, 0.9])]))
		for i in 0..<3 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(SB.expected2Arms[i], context.getTreatment("exp_sb"))
			XCTAssertEqual(SB.expected2Arms[i], variable(context))
		}

		XCTAssertEqual(
			[
				exposure(SB.expected2Arms[0], SB.anchor), exposure(SB.expected2Arms[1], SB.anchor + SB.hour),
				exposure(SB.expected2Arms[2], SB.anchor + 2 * SB.hour),
			], publishExposures(context))
	}

	// Assignment rules are evaluated first for every experiment, switchbacks included, so a matching rule
	// assigns its variant even before the anchor, with ruleOverride set and the exposure recorded.
	func testAssignmentRuleOverridesTheSchedule() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["assignmentRules"] = Self.assignVariant1
		for u in 0..<10 {
			handler.clearInvocations()
			clock.now = SB.anchor - 1
			let context = createContext(SB.data([experiment]), units: [SB.unitType: "user-\(u)"])
			XCTAssertEqual(1, context.getTreatment("exp_sb"))
			XCTAssertEqual(1, variable(context))
			// The rule also beats every period's schedule draw.
			for i in 0..<4 {
				clock.now = SB.anchor + Int64(i) * SB.hour
				XCTAssertEqual(1, context.getTreatment("exp_sb"))
			}
			let exposures = publishExposures(context)
			XCTAssertEqual(
				[ruleExposure("exp_sb", 1, SB.anchor - 1)]
					+ (0..<4).map { ruleExposure("exp_sb", 1, SB.anchor + Int64($0) * SB.hour) }, exposures)
		}
	}

	// An unservable schedule (no anchor, a bad period, an unaligned anchor) only replaces the schedule
	// draw, so full-on and a matching assignment rule still apply and are recorded.
	func testUnservableOnlyReplacesTheVariantDrawNotFullOnOrRules() {
		var fullOn = SB.switchback(1, "sb_full_on", arms: 2, periodMs: SB.hour)
		fullOn["switchbackStartAt"] = NSNull()
		fullOn["fullOnVariant"] = 1
		var rules = SB.switchback(2, "sb_rules", arms: 2, periodMs: 0)
		rules["assignmentRules"] = Self.assignVariant1
		var unalignedRules = SB.switchback(3, "sb_unaligned_rules", arms: 2, periodMs: SB.hour)
		unalignedRules["switchbackStartAt"] = SB.anchor + 1
		unalignedRules["assignmentRules"] = Self.assignVariant1
		let context = createContext(SB.data([fullOn, rules, unalignedRules]), units: [SB.unitType: "15"])

		XCTAssertEqual(1, context.getTreatment("sb_full_on"))
		XCTAssertEqual(1, context.getTreatment("sb_rules"))
		XCTAssertEqual(1, context.getTreatment("sb_unaligned_rules"))
		XCTAssertEqual(
			[
				exposure(1, SB.anchor, id: 1, name: "sb_full_on", fullOn: true),
				exposure(1, SB.anchor, id: 2, name: "sb_rules", assigned: false, ruleOverride: true),
				exposure(1, SB.anchor, id: 3, name: "sb_unaligned_rules", assigned: false, ruleOverride: true),
			], publishExposures(context))
	}

	// Rules are evaluated only for an eligible cluster: an ineligible cluster stays a silent control even
	// when a rule would match.
	func testAssignmentRulesDoNotApplyToAnIneligibleCluster() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["assignmentRules"] = Self.assignVariant1
		experiment["switchbackClusterValues"] = ["other-store"]
		let context = createContext(SB.data([experiment]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	// A split rule randomizes over the serving unit, not over the payload's unitType.
	func testSplitRuleRandomizesOverTheServingUnit() {
		var experiment = SB.switchback(arms: 2, periodMs: SB.hour)
		experiment["unitType"] = "user_id"
		experiment["assignmentRules"] =
			"{\"rules\":[{\"type\":\"split\",\"environments\":[],\"percentages\":\"50/50\"}]}"
		var ones = 0
		for u in 0..<32 {
			handler.clearInvocations()
			let uid = "store-\(u)"
			let expected = VariantAssigner(Hashing.hashBytes(uid)).assign([0.5, 0.5], SB.seedHi, SB.seedLo)
			let context = createContext(SB.data([experiment]), units: [SB.unitType: uid, "user_id": "fixed-user"])
			XCTAssertEqual(expected, context.getTreatment("exp_sb"), uid)
			XCTAssertEqual([ruleExposure("exp_sb", expected, SB.anchor)], publishExposures(context), uid)
			ones += expected
		}
		XCTAssertTrue(ones > 0 && ones < 32)
	}

	// Audience-strict mismatch: control, recorded with audienceMismatch and assigned=false, as for a unit
	// experiment.
	func testAudienceStrictMismatchIsRecordedAsControl() {
		let context = createContext(SB.data([strictSwitchback()]))
		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual([strictMismatchExposure(SB.anchor + SB.hour)], publishExposures(context))
	}

	// Exact wire form of a switchback strict audience mismatch. Runs in period 1, whose draw is 1, so the
	// variant 0 below is the strict mismatch's control and not a draw of arm 0. Keys are sorted here
	// (Java checks its serializer's field order).
	func testAudienceStrictMismatchExposureSerializesExactly() {
		let context = createContext(SB.data([strictSwitchback()]))
		XCTAssertEqual(1, SB.expected2Arms[1])
		clock.now = SB.anchor + SB.hour + 5
		_ = context.getTreatment("exp_sb")
		clock.now = SB.anchor + SB.hour + 9

		guard let event = publish(context) else {
			XCTFail("nothing published")
			return
		}
		XCTAssertEqual(
			"{\"attributes\":[{\"name\":\"\(SB.clusterPath)\",\"setAt\":\(SB.anchor),\"value\":\"\(SB.clusterKey)\"}],"
				+ "\"exposures\":[{\"assigned\":false,\"audienceMismatch\":true,\"custom\":false,\"eligible\":true,"
				+ "\"exposedAt\":\(SB.anchor + SB.hour + 5),\"fullOn\":false,\"id\":1,\"name\":\"exp_sb\","
				+ "\"overridden\":false,\"ruleOverride\":false,\"unit\":\"store_id\",\"variant\":0}],"
				+ "\"hashed\":true,\"publishedAt\":\(SB.anchor + SB.hour + 9),"
				+ "\"units\":[{\"type\":\"store_id\",\"uid\":\"\(SB.uidHash)\"}]}", encoded(event))
	}

	// The audience check comes before the period check, so a strict mismatch before the anchor is recorded.
	func testAudienceStrictMismatchBeforeTheAnchorIsRecorded() {
		clock.now = SB.anchor - 1
		let context = createContext(SB.data([strictSwitchback()]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual([strictMismatchExposure(SB.anchor - 1)], publishExposures(context))
	}

	// Likewise with an unservable schedule (no anchor): the strict mismatch is recorded.
	func testAudienceStrictMismatchWithAnUnservableScheduleIsRecorded() {
		var experiment = strictSwitchback()
		experiment["switchbackStartAt"] = NSNull()
		clock.now = SB.anchor + SB.hour + 3
		let context = createContext(SB.data([experiment]))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual([strictMismatchExposure(SB.anchor + SB.hour + 3)], publishExposures(context))
	}

	// A missing or unreadable cluster map takes the Collector's legacy path, an ineligible control before
	// the audience is evaluated, so a strict mismatch there records nothing.
	func testAudienceStrictMismatchWithAMissingOrUnreadableClusterMapRecordsNothing() {
		for clusters in [nil, [(SB.unitType, "'geo")]] as [[(String, Any)]?] {
			var experiment = SB.switchback(arms: 2, periodMs: SB.hour, clusters: clusters)
			experiment["audience"] = Self.strictGoldAudience
			experiment["audienceStrict"] = true
			clock.now = SB.anchor + SB.hour + 3
			let context = createContext(SB.data([experiment]))
			XCTAssertEqual(0, context.getTreatment("exp_sb"), String(describing: clusters))
			XCTAssertEqual(0, context.getPendingCount(), String(describing: clusters))
		}
	}
}
