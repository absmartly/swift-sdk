import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// Ported from java-sdk ContextHoldoutTest (79 cases) and the javascript-sdk holdout tests.
//
// A holdout arrives in `ContextData.holdouts`; an experiment declares the holdouts covering it in
// `holdoutIds`. Arm 0 holds the unit out of every covered experiment; in a 3-arm holdout arm 1
// holds out only experiments that are not full-on. A held-out unit gets control (variant 0) and no
// exposure of its own; every covering holdout publishes one ordinary exposure per epoch.
final class ContextHoldoutTest: XCTestCase {
	static let unitType = "session_id"
	static let uid = "e791e240fcd3df7d238cfc285f475e8152fcc0ec"
	static let uidNotHeldOut = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"

	// split [0.5, 0.5], seedHi 100, seedLo 200: variant 1 for `uid`, variant 0 for `uidNotHeldOut`.
	static let normalVariant = 1

	// split [0.1, 0.9]: seeds A hold `uid` out (variant 0) and not `uidNotHeldOut`; seeds B hold
	// neither out (variant 1).
	static let holdoutA = (seedHi: 13, seedLo: 111)
	static let holdoutB = (seedHi: 1, seedLo: 222)

	// A 3-arm holdout: the split's length selects the arm-1 rule, never `holdoutType`. For `uid`,
	// seedLo 1 gives arm 0, seedLo 3 arm 1 and seedLo 0 arm 2.
	static let threeArmSplit = [0.3, 0.3, 0.4]
	static let threeArm0 = (seedHi: 0, seedLo: 1)
	static let threeArm1 = (seedHi: 0, seedLo: 3)
	static let threeArm2 = (seedHi: 0, seedLo: 0)

	static let usRule =
		"{\"rules\":[{\"name\":\"US Internal Users\",\"type\":\"assign\",\"conditions\":{\"and\":[{\"eq\":[{\"var\":\"country\"},{\"value\":\"US\"}]}]},\"environments\":[],\"variant\":1}]}"

	var handler = ContextEventHandlerMock()
	var logger = ContextEventLoggerMock()
	var scheduler = SchedulerMock()
	var clock = ClockMock()
	var now: Int64 { return clock.millis() }

	override func setUp() {
		handler = ContextEventHandlerMock()
		handler.publishEventReturnValue = Promise<Void>.value(())
		logger = ContextEventLoggerMock()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		clock = ClockMock()
		clock.millisReturnValue = 1_620_000_000_000
	}

	// MARK: - Fixtures

	func experiment(
		_ id: Int, _ name: String, unitType: String = unitType, fullOnVariant: Int = 0, holdoutIds: [Int]? = nil,
		split: [Double] = [0.5, 0.5], configs: [String?] = [nil, nil], audience: String? = nil,
		audienceStrict: Bool = false, assignmentRules: String? = nil
	) -> [String: Any] {
		var experiment: [String: Any] = [
			"id": id, "name": name, "unitType": unitType, "iteration": 1, "seedHi": 100, "seedLo": 200,
			"split": split, "trafficSeedHi": 1, "trafficSeedLo": 2, "trafficSplit": [0.0, 1.0],
			"fullOnVariant": fullOnVariant, "applications": [["name": "website"]],
			"variants": configs.enumerated().map { ["name": "\($0.offset)", "config": $0.element as Any? ?? NSNull()] },
			"audienceStrict": audienceStrict, "audience": audience as Any? ?? NSNull(),
		]
		if let holdoutIds = holdoutIds {
			experiment["holdoutIds"] = holdoutIds
		}
		if let assignmentRules = assignmentRules {
			experiment["assignmentRules"] = assignmentRules
		}
		return experiment
	}

	// `configs` gives each variant a `key` variable with the values "control" and "treatment".
	func withVariables(_ key: String) -> [String?] {
		return ["{\"\(key)\":\"control\"}", "{\"\(key)\":\"treatment\"}"]
	}

	func holdout(
		_ id: Int, _ name: String, unitType: String = unitType, seeds: (seedHi: Int, seedLo: Int),
		split: [Double] = [0.1, 0.9], holdoutType: String? = "full", iteration: Int = 1
	) -> [String: Any] {
		var holdout: [String: Any] = [
			"id": id, "name": name, "unitType": unitType, "iteration": iteration, "seedHi": seeds.seedHi,
			"seedLo": seeds.seedLo, "split": split, "trafficSplit": [0.0, 1.0], "fullOnVariant": 0,
			"applications": [] as [Any], "variants": split.indices.map { ["name": "\($0)", "config": NSNull()] },
			"audienceStrict": false, "audience": NSNull(),
		]
		if let holdoutType = holdoutType {
			holdout["holdoutType"] = holdoutType
		}
		return holdout
	}

	func threeArmHoldout(_ id: Int, _ name: String, seeds: (seedHi: Int, seedLo: Int)) -> [String: Any] {
		return holdout(id, name, seeds: seeds, split: Self.threeArmSplit, holdoutType: "all_full_on")
	}

	func contextData(_ experiments: [[String: Any]], holdouts: [Any]? = nil) -> ContextData {
		var payload: [String: Any] = ["experiments": experiments]
		if let holdouts = holdouts {
			payload["holdouts"] = holdouts
		}
		return decode(try! JSONSerialization.data(withJSONObject: payload))
	}

	func decode(_ json: Data, file: StaticString = #filePath, line: UInt = #line) -> ContextData {
		do {
			return try JSONDecoder().decode(ContextData.self, from: json)
		} catch {
			XCTFail("ContextData failed to decode: \(error)", file: file, line: line)
			return ContextData()
		}
	}

	func createContext(
		_ data: ContextData, uid: String? = uid, configure: (ContextConfig) -> Void = { _ in }
	) -> Context {
		let config = ContextConfig()
		if let uid = uid {
			config.setUnit(unitType: Self.unitType, uid: uid)
		}
		configure(config)
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler,
			provider: ContextDataProviderMock(), logger: logger, parser: DefaultVariableParser(),
			matcher: AudienceMatcher(), promise: Promise<ContextData>.value(data), application: "website",
			environment: "production")
	}

	func holdoutExposure(_ id: Int, _ name: String, _ variant: Int, unitType: String = unitType) -> Exposure {
		return Exposure(id, name, unitType, variant, now, true, true, false, false, false, false)
	}

	func exposure(
		_ id: Int, _ name: String, _ variant: Int, unitType: String = unitType, assigned: Bool = true,
		overridden: Bool = false, fullOn: Bool = false, custom: Bool = false, audienceMismatch: Bool = false,
		ruleOverride: Bool = false
	) -> Exposure {
		return Exposure(
			id, name, unitType, variant, now, assigned, true, overridden, fullOn, custom, audienceMismatch,
			ruleOverride: ruleOverride)
	}

	// Exposures in the order they were queued, as delivered to the event logger.
	func loggedExposures() -> [Exposure] {
		return logger.handleEventContextEventReceivedInvocations.compactMap {
			if case let .exposure(exposure) = $0.event { return exposure }
			return nil
		}
	}

	func publish(_ context: Context) throws -> PublishEvent {
		handler.clearInvocations()
		try context.publish().wait()
		XCTAssertEqual(1, handler.publishEventCallsCount)
		return try XCTUnwrap(handler.publishEventReceivedEvent)
	}

	// Publishes and compares the whole payload for a context with a single unit.
	func assertPublished(
		_ context: Context, _ exposures: [Exposure], unitType: String = unitType, uid: String = uid,
		attributes: [Attribute] = [], file: StaticString = #filePath, line: UInt = #line
	) throws {
		let expected = PublishEvent(
			true, [Unit(type: unitType, uid: Hashing.hash(uid))], now, exposures, [], attributes)
		XCTAssertEqual(expected, try publish(context), file: file, line: line)
	}

	// MARK: - Two-arm holdouts

	func testHeldOutUnitGetsControlValuesAndEmitsNoExposureForCoveredExperiment() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_in", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.peekTreatment("exp_holdout_in"))
		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(0, context.getTreatment("exp_holdout_in"))

		try assertPublished(context, [holdoutExposure(11, "holdout_a", 0)])
	}

	func testNotHeldOutUnitEmitsHoldoutExposureVariantOneAndNormalExposure() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_out", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]), uid: Self.uidNotHeldOut)

		XCTAssertEqual(0, context.getTreatment("exp_holdout_out"))  // uidNotHeldOut's normal variant is 0

		try assertPublished(
			context, [exposure(1, "exp_holdout_out", 0), holdoutExposure(11, "holdout_a", 1)],
			uid: Self.uidNotHeldOut)
	}

	func testExperimentWithoutHoldoutIdsEmitsNormallyEvenForHeldOutUnit() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_in", holdoutIds: [11]), experiment(2, "exp_not_covered")],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_in"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_not_covered"))

		try assertPublished(
			context,
			[holdoutExposure(11, "holdout_a", 0), exposure(2, "exp_not_covered", Self.normalVariant)])
	}

	func testUnionOfApplicableHoldoutsSuppressesExperimentAndBothEmitOwnExposure() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_multi_holdout", holdoutIds: [11, 12])],
				holdouts: [
					holdout(11, "holdout_a", seeds: Self.holdoutA), holdout(12, "holdout_b", seeds: Self.holdoutB),
				]))

		XCTAssertEqual(0, context.getTreatment("exp_multi_holdout"))

		try assertPublished(context, [holdoutExposure(11, "holdout_a", 0), holdoutExposure(12, "holdout_b", 1)])
	}

	// The low-id holdout does not hold the unit out and the high-id one does: a union that stops at
	// the first holdout, or only reads holdouts[0], would not suppress.
	func testUnionRuleAppliesWhenTheHigherIdHoldoutIsTheOnlyOneHoldingUnitOut() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_union_high_id_decides", holdoutIds: [11, 12])],
				holdouts: [
					holdout(11, "holdout_low_id", seeds: Self.holdoutB),
					holdout(12, "holdout_high_id", seeds: Self.holdoutA),
				]))

		XCTAssertEqual(0, context.getTreatment("exp_union_high_id_decides"))

		try assertPublished(
			context, [holdoutExposure(11, "holdout_low_id", 1), holdoutExposure(12, "holdout_high_id", 0)])
	}

	func testUnitNotHeldOutByEitherHoldoutIsNotSuppressed() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_multi_holdout_miss", holdoutIds: [11, 12])],
				holdouts: [
					holdout(11, "holdout_a", seeds: Self.holdoutA), holdout(12, "holdout_b", seeds: Self.holdoutB),
				]), uid: Self.uidNotHeldOut)

		XCTAssertEqual(0, context.getTreatment("exp_multi_holdout_miss"))

		try assertPublished(
			context,
			[
				exposure(1, "exp_multi_holdout_miss", 0), holdoutExposure(11, "holdout_a", 1),
				holdoutExposure(12, "holdout_b", 1),
			], uid: Self.uidNotHeldOut)
	}

	func testHoldoutSuppressesFullOnExperimentRegardlessOfFullOnVariant() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_fullon_holdout", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_fullon_holdout"))
	}

	// MARK: - Three-arm holdouts

	func testThreeArmVariantZeroHoldsOutBothFullOnAndNonFullOnExperiments() throws {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_three_arm_0_non_fullon", holdoutIds: [21]),
					experiment(2, "exp_three_arm_0_fullon", fullOnVariant: 2, holdoutIds: [21]),
				], holdouts: [threeArmHoldout(21, "holdout_three_arm", seeds: Self.threeArm0)]))

		XCTAssertEqual(0, context.getTreatment("exp_three_arm_0_non_fullon"))
		XCTAssertEqual(0, context.getTreatment("exp_three_arm_0_fullon"))

		try assertPublished(context, [holdoutExposure(21, "holdout_three_arm", 0)])
	}

	func testThreeArmVariantOneForcesNonFullOnExperimentToControlButAssignsFullOnExperimentNormally() throws {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_three_arm_1_non_fullon", holdoutIds: [21]),
					experiment(2, "exp_three_arm_1_fullon", fullOnVariant: 2, holdoutIds: [21]),
				], holdouts: [threeArmHoldout(21, "holdout_three_arm", seeds: Self.threeArm1)]))

		XCTAssertEqual(0, context.getTreatment("exp_three_arm_1_non_fullon"))
		XCTAssertEqual(2, context.getTreatment("exp_three_arm_1_fullon"))

		try assertPublished(
			context,
			[holdoutExposure(21, "holdout_three_arm", 1), exposure(2, "exp_three_arm_1_fullon", 2, fullOn: true)])
	}

	func testThreeArmVariantTwoEvaluatesBothExperimentKindsNormally() throws {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_three_arm_2_non_fullon", holdoutIds: [21]),
					experiment(2, "exp_three_arm_2_fullon", fullOnVariant: 2, holdoutIds: [21]),
				], holdouts: [threeArmHoldout(21, "holdout_three_arm", seeds: Self.threeArm2)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_three_arm_2_non_fullon"))
		XCTAssertEqual(2, context.getTreatment("exp_three_arm_2_fullon"))

		try assertPublished(
			context,
			[
				exposure(1, "exp_three_arm_2_non_fullon", Self.normalVariant),
				holdoutExposure(21, "holdout_three_arm", 2), exposure(2, "exp_three_arm_2_fullon", 2, fullOn: true),
			])
	}

	func testTwoArmHoldoutWinsUnionEvenWhenThreeArmWouldNotHoldOut() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_union_two_arm_wins", holdoutIds: [11, 22])],
				holdouts: [
					holdout(11, "holdout_two_arm", seeds: Self.holdoutA),
					threeArmHoldout(22, "holdout_three_arm", seeds: Self.threeArm2),
				]))

		XCTAssertEqual(0, context.getTreatment("exp_union_two_arm_wins"))

		try assertPublished(
			context, [holdoutExposure(11, "holdout_two_arm", 0), holdoutExposure(22, "holdout_three_arm", 2)])
	}

	func testThreeArmHoldoutWinsUnionEvenWhenTwoArmWouldNotHoldOut() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_union_three_arm_wins", holdoutIds: [11, 22])],
				holdouts: [
					holdout(11, "holdout_two_arm", seeds: Self.holdoutB),
					threeArmHoldout(22, "holdout_three_arm", seeds: Self.threeArm1),
				]))

		XCTAssertEqual(0, context.getTreatment("exp_union_three_arm_wins"))

		try assertPublished(
			context, [holdoutExposure(11, "holdout_two_arm", 1), holdoutExposure(22, "holdout_three_arm", 1)])
	}

	// Arm 1 defers a full-on experiment to the normal path, so a strict audience mismatch still
	// gives control with its own exposure, exactly as under arm 2.
	func testThreeArmArmOneDefersToNormalPathSoAudienceMismatchStillWinsForFullOnExperiment() throws {
		let audience = "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}"
		for (seeds, arm) in [(Self.threeArm1, 1), (Self.threeArm2, 2)] {
			setUp()
			let context = createContext(
				contextData(
					[
						experiment(
							1, "exp_three_arm_audience_fullon", fullOnVariant: 2, holdoutIds: [21], audience: audience,
							audienceStrict: true)
					], holdouts: [threeArmHoldout(21, "holdout_three_arm", seeds: seeds)]))
			context.setAttribute(name: "age", value: 5)

			XCTAssertEqual(0, context.getTreatment("exp_three_arm_audience_fullon"))

			try assertPublished(
				context,
				[
					exposure(1, "exp_three_arm_audience_fullon", 0, assigned: false, audienceMismatch: true),
					holdoutExposure(21, "holdout_three_arm", arm),
				], attributes: [Attribute("age", value: 5, setAt: now)])
		}
	}

	// MARK: - Missing units, absent and malformed holdouts

	func testUnconfiguredUnitTypeGetsControlValuesAndEmitsNoExposureAtAll() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_user_holdout", unitType: "user_id", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_user", unitType: "user_id", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.peekTreatment("exp_user_holdout"))
		XCTAssertEqual(0, context.getTreatment("exp_user_holdout"))

		// The experiment's own exposure is the not-assigned one (no unit), and no holdout fires.
		XCTAssertEqual(
			[exposure(1, "exp_user_holdout", 0, unitType: "user_id", assigned: false)], loggedExposures())
	}

	func testAssignsNormallyWhenHoldoutsKeyIsAbsent() {
		let data = contextData([experiment(1, "exp_no_holdouts_key")])
		XCTAssertNil(data.holdouts)
		XCTAssertEqual(Self.normalVariant, createContext(data).peekTreatment("exp_no_holdouts_key"))
	}

	func testHoldoutIdAbsentFromHoldoutsArrayIsIgnoredAndExperimentAssignsNormally() {
		let context = createContext(contextData([experiment(1, "exp_dangling_holdout_id", holdoutIds: [999])]))

		XCTAssertEqual(Self.normalVariant, context.peekTreatment("exp_dangling_holdout_id"))
	}

	func testCustomAssignmentCannotOverrideHeldOutVariant() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_custom", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)])
		) { $0.setCustomAssignment(experimentName: "exp_holdout_custom", variant: 3) }

		XCTAssertEqual(0, context.peekTreatment("exp_holdout_custom"))
	}

	func testReusesCachedHeldOutAssignmentWithCustomAssignment() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_custom_cache", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)])
		) { $0.setCustomAssignment(experimentName: "exp_holdout_custom_cache", variant: 3) }

		XCTAssertEqual(0, context.getTreatment("exp_holdout_custom_cache"))
		XCTAssertEqual(0, context.getTreatment("exp_holdout_custom_cache"))
		XCTAssertEqual(1, context.getPendingCount())
		#if DEBUG
		// The custom variant differs from the held-out 0, but that is not staleness: it is a cache hit.
		XCTAssertEqual(
			context.cachedAssignmentIdentity("exp_holdout_custom_cache"),
			context.cachedAssignmentIdentity("exp_holdout_custom_cache"))
		#endif
	}

	func testOverrideTakesPrecedenceOverHoldout() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_override", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)])
		) { $0.setOverride(experimentName: "exp_holdout_override", variant: 3) }

		XCTAssertEqual(3, context.peekTreatment("exp_holdout_override"))
	}

	func testGetTreatmentOnOverriddenExperimentTriggersApplicableHoldoutExposureBothArms() throws {
		for (uid, arm) in [(Self.uid, 0), (Self.uidNotHeldOut, 1)] {
			setUp()
			let context = createContext(
				contextData(
					[experiment(1, "exp_holdout_override", holdoutIds: [11])],
					holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]), uid: uid
			) { $0.setOverride(experimentName: "exp_holdout_override", variant: 3) }

			XCTAssertEqual(3, context.getTreatment("exp_holdout_override"))

			try assertPublished(
				context,
				[
					exposure(1, "exp_holdout_override", 3, assigned: false, overridden: true),
					holdoutExposure(11, "holdout_a", arm),
				], uid: uid)
		}
	}

	func testHoldoutTakesPrecedenceOverAudienceMismatch() {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_holdout_audience", holdoutIds: [11],
						audience: "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}", audienceStrict: true)
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))
		context.setAttribute(name: "age", value: 5)

		XCTAssertEqual(0, context.peekTreatment("exp_holdout_audience"))
	}

	// MARK: - One exposure per holdout

	func testHoldoutExposureEmittedOncePerContextNotPerSuppressedExperiment() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_shared_a", holdoutIds: [11]), experiment(2, "exp_shared_b", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_shared_a"))
		XCTAssertEqual(0, context.getTreatment("exp_shared_b"))

		try assertPublished(context, [holdoutExposure(11, "holdout_a", 0)])
	}

	func testHoldoutExposureFiresOnceEvenWhenTriggeringExperimentIsNotSuppressed() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_shared_a", holdoutIds: [11]), experiment(2, "exp_shared_b", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]), uid: Self.uidNotHeldOut)

		_ = context.getTreatment("exp_shared_a")
		_ = context.getTreatment("exp_shared_b")

		try assertPublished(
			context,
			[exposure(1, "exp_shared_a", 0), holdoutExposure(11, "holdout_a", 1), exposure(2, "exp_shared_b", 0)],
			uid: Self.uidNotHeldOut)
	}

	func testReusesCachedSuppressedAssignmentAcrossRepeatedCalls() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_cache", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_cache"))
		XCTAssertEqual(0, context.getTreatment("exp_holdout_cache"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	// MARK: - Refresh

	// A same-iteration seed edit must not move an exposed unit into the other arm.
	func testRefreshWithSeedChangeSameIterationKeepsUnitInOriginalArmAndDoesNotReExpose() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_seed_thrash", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_seed_thrash"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setData(
			contextData(
				[experiment(1, "exp_holdout_seed_thrash", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_seed_thrash"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testRefreshWithCosmeticHoldoutEditDoesNotReExposeHeldOutUnit() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_cosmetic", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_cosmetic"))
		XCTAssertEqual(1, context.getPendingCount())

		var renamed = holdout(11, "holdout_a_renamed", seeds: Self.holdoutA)
		renamed["applications"] = [["name": "website"]]
		renamed["variants"] = [["name": "Control", "config": NSNull()], ["name": "HeldOut", "config": NSNull()]]
		context.setData(contextData([experiment(1, "exp_holdout_cosmetic", holdoutIds: [11])], holdouts: [renamed]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_cosmetic"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testRefreshWithCosmeticHoldoutEditDoesNotDuplicateCoveredExperimentExposure() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_cosmetic_covered", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]), uid: Self.uidNotHeldOut)

		XCTAssertEqual(0, context.getTreatment("exp_holdout_cosmetic_covered"))
		XCTAssertEqual(2, context.getPendingCount())

		context.setData(
			contextData(
				[experiment(1, "exp_holdout_cosmetic_covered", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a_renamed", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_cosmetic_covered"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	// An iteration bump is a new epoch: the unit is re-assigned once and exposed once in it.
	func testRefreshWithIterationBumpReassignsToExactlyOneNewArm() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_iteration", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_holdout_iteration"))
		XCTAssertEqual(2, context.getPendingCount())

		context.setData(
			contextData(
				[experiment(1, "exp_holdout_iteration", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA, iteration: 2)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_iteration"))
		XCTAssertEqual(3, context.getPendingCount())
		XCTAssertEqual(0, context.getTreatment("exp_holdout_iteration"))
		XCTAssertEqual(3, context.getPendingCount())
	}

	// A covered experiment first evaluated after a same-iteration seed edit reads the pinned arm.
	func testRefreshedSeedDoesNotDesyncSuppressionFromPinnedHoldoutArmForNewlyEvaluatedExperiment() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_desync_a", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_desync_a"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setData(
			contextData(
				[
					experiment(1, "exp_holdout_desync_a", holdoutIds: [11]),
					experiment(2, "exp_holdout_desync_b", holdoutIds: [11]),
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(0, context.getTreatment("exp_holdout_desync_b"))
		XCTAssertEqual(0, context.getTreatment("exp_holdout_desync_a"))

		try assertPublished(context, [holdoutExposure(11, "holdout_a", 0)])
	}

	// MARK: - Arm count pinned with the arm

	// Arm 1 under 2 arms defers to normal assignment; a same-iteration change to 3 arms must not
	// re-mean it as "full-on only".
	func testRefreshFromTwoArmToThreeArmSameIterationDoesNotReinterpretDeferringArmAsFullOnOnly() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_arity_2to3_a", holdoutIds: [31])],
				holdouts: [holdout(31, "holdout_arity", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_arity_2to3_a"))

		context.setData(
			contextData(
				[
					experiment(1, "exp_arity_2to3_a", holdoutIds: [31]),
					experiment(2, "exp_arity_2to3_b", holdoutIds: [31]),
				], holdouts: [threeArmHoldout(31, "holdout_arity", seeds: Self.threeArm1)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_arity_2to3_b"))

		try assertPublished(
			context,
			[
				exposure(1, "exp_arity_2to3_a", Self.normalVariant), holdoutExposure(31, "holdout_arity", 1),
				exposure(2, "exp_arity_2to3_b", Self.normalVariant),
			])
	}

	func testRefreshFromThreeArmToTwoArmSameIterationKeepsFullOnOnlyArmSuppressingNonFullOnExperiment() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_arity_3to2_a", holdoutIds: [41])],
				holdouts: [threeArmHoldout(41, "holdout_arity_rev", seeds: Self.threeArm1)]))

		XCTAssertEqual(0, context.getTreatment("exp_arity_3to2_a"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setData(
			contextData(
				[
					experiment(1, "exp_arity_3to2_a", holdoutIds: [41]),
					experiment(2, "exp_arity_3to2_b", holdoutIds: [41]),
				], holdouts: [holdout(41, "holdout_arity_rev", seeds: Self.holdoutB)]))

		XCTAssertEqual(0, context.getTreatment("exp_arity_3to2_b"))

		try assertPublished(context, [holdoutExposure(41, "holdout_arity_rev", 1)])
	}

	func testExperimentsEvaluatedBeforeAndAfterSameIterationArityChangeAgreeOnSuppression() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_arity_consistency_pre", holdoutIds: [71])],
				holdouts: [holdout(71, "holdout_arity_consistency", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_arity_consistency_pre"))

		context.setData(
			contextData(
				[
					experiment(1, "exp_arity_consistency_pre", holdoutIds: [71]),
					experiment(2, "exp_arity_consistency_post", holdoutIds: [71]),
				], holdouts: [threeArmHoldout(71, "holdout_arity_consistency", seeds: Self.threeArm1)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_arity_consistency_post"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_arity_consistency_pre"))
	}

	// A refresh landing between the suppression decision and the holdout trigger (here, from the
	// event logger while the experiment's own exposure is delivered) must not publish the new
	// epoch's arm next to a decision made with the old one.
	func testTriggerFiresHoldoutExposureFromDecisionEpochDespiteRefreshRacingBetweenDecisionAndTrigger() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_epoch_race", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_h", seeds: Self.holdoutB)]))
		let refreshed = contextData(
			[experiment(1, "exp_epoch_race", holdoutIds: [11])],
			holdouts: [holdout(11, "holdout_h", seeds: Self.holdoutA, iteration: 2)])
		logger.handleEventContextEventClosure = { context, event in
			if case let .exposure(exposure) = event, exposure.id == 1 {
				context.setData(refreshed)
			}
		}

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_epoch_race"))
		logger.handleEventContextEventClosure = nil

		try assertPublished(
			context, [exposure(1, "exp_epoch_race", Self.normalVariant), holdoutExposure(11, "holdout_h", 1)])
	}

	// MARK: - Late units

	// Peeking without the unit pins a missing holdout arm; setUnit must evict that so the holdout's
	// exposure is not lost forever.
	func testSetUnitInvalidatesNullHoldoutSnapshotSoTheHoldoutExposureIsNotLostForever() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_null_snapshot_fullon", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_user_id", unitType: "user_id", seeds: Self.holdoutB)]), uid: nil)

		XCTAssertEqual(2, context.peekTreatment("exp_null_snapshot_fullon"))

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(2, context.getTreatment("exp_null_snapshot_fullon"))
		XCTAssertEqual(2, context.getPendingCount())

		try assertPublished(
			context,
			[
				exposure(1, "exp_null_snapshot_fullon", 2, unitType: "user_id", fullOn: true),
				holdoutExposure(11, "holdout_user_id", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	func testSetUnitDoesNotEvictAlreadyExposedAssignmentSoNoDuplicateExposure() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_exposed_before_unit", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_user_id", unitType: "user_id", seeds: Self.holdoutB)]), uid: nil)

		XCTAssertEqual(2, context.getTreatment("exp_exposed_before_unit"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(2, context.getTreatment("exp_exposed_before_unit"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testSetUnitForUnrelatedUnitTypeDoesNotEvictExposedAssignment() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_unrelated_unit", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_unrelated_unit"))
		XCTAssertEqual(2, context.getPendingCount())

		context.setUnit(unitType: "other_unit_type", uid: "some-other-uid")

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_unrelated_unit"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testSetUnitEvictsOnlyTheAffectedEntryAndLeavesTheOtherUntouched() {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_late_unit", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11]),
					experiment(2, "exp_present_unit", holdoutIds: [12]),
				],
				holdouts: [
					holdout(11, "holdout_late", unitType: "user_id", seeds: Self.holdoutB),
					holdout(12, "holdout_present", seeds: Self.holdoutB),
				]))

		XCTAssertEqual(2, context.peekTreatment("exp_late_unit"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_present_unit"))
		XCTAssertEqual(2, context.getPendingCount())

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(2, context.getTreatment("exp_late_unit"))
		XCTAssertEqual(4, context.getPendingCount())
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_present_unit"))
		XCTAssertEqual(4, context.getPendingCount())
	}

	// The missing unit is the covered experiment's, not the holdout's declared unit type.
	func testSetUnitEvictsUsingTheCoveredExperimentsUnitTypeNotTheHoldoutsDeclaredUnitType() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_mismatched_unit_type", unitType: "A", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_declares_b", unitType: "B", seeds: Self.holdoutB)]), uid: nil)

		XCTAssertEqual(2, context.peekTreatment("exp_mismatched_unit_type"))

		context.setUnit(unitType: "A", uid: Self.uid)

		XCTAssertEqual(2, context.getTreatment("exp_mismatched_unit_type"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	// The late holdout holds the unit out: the whole decision is recomputed (full-on -> control), not
	// patched with a contradictory holdout exposure.
	func testSetUnitRecomputesSuppressionCoherentlyWhenLateResolvedHoldoutSuppresses() throws {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_null_snapshot_suppresses", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])
				],
				holdouts: [holdout(11, "holdout_user_id_suppress", unitType: "user_id", seeds: Self.holdoutA)]),
			uid: nil)

		XCTAssertEqual(2, context.peekTreatment("exp_null_snapshot_suppresses"))

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(0, context.getTreatment("exp_null_snapshot_suppresses"))
		XCTAssertEqual(1, context.getPendingCount())

		try assertPublished(
			context, [holdoutExposure(11, "holdout_user_id_suppress", 0, unitType: "user_id")], unitType: "user_id")
	}

	// Java's detached-assignment tests: Swift resolves and claims an assignment in one critical
	// section, so an assignment read before setUnit cannot be exposed beside its replacement. These
	// pin the same public sequences.
	func testDetachedTreatmentAssignmentCannotPublishBesideSuppressingReplacement() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_detached_suppressed", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_detached_suppressed", unitType: "user_id", seeds: Self.holdoutA)]),
			uid: nil)

		XCTAssertEqual(2, context.peekTreatment("exp_detached_suppressed"))
		context.setUnit(unitType: "user_id", uid: Self.uid)
		XCTAssertEqual(0, context.getTreatment("exp_detached_suppressed"))
		XCTAssertEqual(0, context.getTreatment("exp_detached_suppressed"))
		XCTAssertEqual(1, context.getPendingCount())

		try assertPublished(
			context, [holdoutExposure(11, "holdout_detached_suppressed", 0, unitType: "user_id")],
			unitType: "user_id")
	}

	func testDetachedTreatmentAssignmentRetriesCurrentEntryWithoutLosingExposure() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_detached_retry", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_detached_retry", unitType: "user_id", seeds: Self.holdoutB)]),
			uid: nil)

		XCTAssertEqual(2, context.peekTreatment("exp_detached_retry"))
		context.setUnit(unitType: "user_id", uid: Self.uid)
		XCTAssertEqual(2, context.getTreatment("exp_detached_retry"))
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(2, context.getTreatment("exp_detached_retry"))
		XCTAssertEqual(2, context.getPendingCount())

		try assertPublished(
			context,
			[
				exposure(1, "exp_detached_retry", 2, unitType: "user_id", fullOn: true),
				holdoutExposure(11, "holdout_detached_retry", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	func testDetachedTreatmentReturnsTheReplacementVariant() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_detached_variant", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_detached_variant", unitType: "user_id", seeds: Self.holdoutA)]),
			uid: nil)

		XCTAssertEqual(2, context.peekTreatment("exp_detached_variant"))
		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(0, context.getTreatment("exp_detached_variant"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	// Java's settlement-retry tests have no Swift counterpart (resolution and claim share one lock);
	// these pin the public guarantees they protect.
	func testRepeatedTreatmentReadsExposeOnce() {
		let context = createContext(
			contextData([
				experiment(1, "exp_first", fullOnVariant: 2), experiment(2, "exp_second", fullOnVariant: 1),
				experiment(3, "exp_settled", fullOnVariant: 1),
			]))

		for _ in 0..<3 {
			XCTAssertEqual(1, context.getTreatment("exp_settled"))
		}
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testPeekOnFullOnExperimentExposesNothing() {
		let context = createContext(contextData([experiment(1, "exp_bounded_retry", fullOnVariant: 1)]))

		XCTAssertEqual(1, context.peekTreatment("exp_bounded_retry"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testDetachedVariableAssignmentReresolvesTheKeyToANewWinningExperiment() throws {
		let original = experiment(
			2, "exp_detached_variable_old", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
			configs: [nil, "{\"detached_var\":\"old\"}"])
		let holdout = self.holdout(11, "holdout_detached_variable", unitType: "user_id", seeds: Self.holdoutB)
		let context = createContext(contextData([original], holdouts: [holdout]), uid: nil)

		XCTAssertEqual(JSON("old"), context.peekVariableValue("detached_var", defaultValue: JSON("default")))
		context.setUnit(unitType: "user_id", uid: Self.uid)

		let winner = experiment(
			1, "exp_detached_variable_winner", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
			configs: [nil, "{\"detached_var\":\"new winner\"}"])
		context.setData(contextData([winner, original], holdouts: [holdout]))

		XCTAssertEqual(JSON("new winner"), context.getVariableValue("detached_var", defaultValue: JSON("default")))
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(JSON("new winner"), context.getVariableValue("detached_var", defaultValue: JSON("default")))
		XCTAssertEqual(2, context.getPendingCount())

		try assertPublished(
			context,
			[
				exposure(1, "exp_detached_variable_winner", 1, unitType: "user_id", fullOn: true),
				holdoutExposure(11, "holdout_detached_variable", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	// An exposed assignment keeps its missing holdout arm: reading it again through a variable key
	// must not resolve the holdout live and publish a contradictory "held out" exposure.
	func testTriggerApplicableHoldoutExposuresNeverLiveResolvesAPinnedNullEntryForAnAlreadyExposedAssignment() {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_a_mutant_pinned_null", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
						configs: [nil, "{\"my_var\":\"value_from_variant\"}"])
				],
				holdouts: [holdout(11, "holdout_a_mutant_pinned_null", unitType: "user_id", seeds: Self.holdoutA)]),
			uid: nil)

		XCTAssertEqual(1, context.getTreatment("exp_a_mutant_pinned_null"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(
			JSON("value_from_variant"), context.getVariableValue("my_var", defaultValue: JSON("default")))
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testSetUnitEvictsAssignmentWithMultipleHoldoutsDeclaringDifferentUnitTypes() {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_multi_holdout_unit_types", unitType: "user_id", fullOnVariant: 2,
						holdoutIds: [11, 12, 13])
				],
				holdouts: [
					holdout(11, "holdout_11", unitType: "type_x", seeds: Self.holdoutB),
					holdout(12, "holdout_12", unitType: "type_y", seeds: Self.holdoutB),
					holdout(13, "holdout_13", unitType: "user_id", seeds: Self.holdoutB),
				]), uid: nil)

		XCTAssertEqual(2, context.peekTreatment("exp_multi_holdout_unit_types"))

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(2, context.getTreatment("exp_multi_holdout_unit_types"))
		XCTAssertEqual(4, context.getPendingCount())
	}

	// One holdout covering two unit types keeps an arm and exposure state per unit type: the A1 -> B
	// -> A2 alternation must publish the holdout once per unit type, not three times.
	func testOneHoldoutCoveringTwoUnitTypesKeepsIndependentExposureStatePerUnitType() throws {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_unit_a1", unitType: "user_id", holdoutIds: [11]),
					experiment(2, "exp_unit_b", unitType: "session_id", holdoutIds: [11]),
					experiment(3, "exp_unit_a2", unitType: "user_id", holdoutIds: [11]),
				], holdouts: [holdout(11, "holdout_shared", unitType: "user_id", seeds: Self.holdoutB)])
		) { $0.setUnit(unitType: "user_id", uid: Self.uid) }

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_unit_a1"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_unit_b"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_unit_a2"))
		XCTAssertEqual(5, context.getPendingCount())

		let exposures = try publish(context).exposures
		XCTAssertEqual(5, exposures.count)
		XCTAssertEqual(
			[holdoutExposure(11, "holdout_shared", 1, unitType: "user_id"),
			 holdoutExposure(11, "holdout_shared", 1, unitType: "session_id")],
			exposures.filter { $0.id == 11 })
	}

	func testSetUnitWithNoCachedAssignmentDoesNotThrowAndSubsequentAssignmentIsNormal() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_no_prior_assignment", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]), uid: nil)

		context.setUnit(unitType: Self.unitType, uid: Self.uid)

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_no_prior_assignment"))
	}

	func testSetUnitCalledTwiceWithSameUidIsANoOpAndDoesNotThrow() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_set_unit_twice", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_set_unit_twice"))
		XCTAssertEqual(2, context.getPendingCount())

		context.setUnit(unitType: Self.unitType, uid: Self.uid)

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_set_unit_twice"))
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertFalse(loggedEvents().contains { if case .error = $0 { return true } else { return false } })
	}

	// A fully resolved (no missing arm) unexposed assignment survives a redundant setUnit. The
	// same-iteration split edit makes a wrongly evicted entry land on a different variant.
	func testSetUnitRedundantCallDoesNotEvictFullyResolvedUnexposedHoldoutSnapshot() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_redundant_set_unit", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.peekTreatment("exp_redundant_set_unit"))
		XCTAssertEqual(0, context.getPendingCount())

		context.setData(
			contextData(
				[experiment(1, "exp_redundant_set_unit", holdoutIds: [11], split: [1.0, 0.0])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		context.setUnit(unitType: Self.unitType, uid: Self.uid)

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_redundant_set_unit"))
		XCTAssertEqual(2, context.getPendingCount())

		try assertPublished(
			context,
			[exposure(1, "exp_redundant_set_unit", Self.normalVariant), holdoutExposure(11, "holdout_a", 1)])
	}

	func testPeekVariableValueThenSetUnitThenGetVariableValueRecomputesUnderLateSuppressingHoldout() throws {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_var_late_unit_suppress", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
						configs: [nil, "{\"my_var\":\"value_from_variant\"}"])
				], holdouts: [holdout(11, "holdout_var_late", unitType: "user_id", seeds: Self.holdoutA)]),
			uid: nil)

		XCTAssertEqual(
			JSON("value_from_variant"), context.peekVariableValue("my_var", defaultValue: JSON("default")))
		XCTAssertEqual(0, context.getPendingCount())

		context.setUnit(unitType: "user_id", uid: Self.uid)

		// Suppressed: the control variant has no `my_var`, so the default is returned.
		XCTAssertEqual(JSON("default"), context.getVariableValue("my_var", defaultValue: JSON("default")))
		XCTAssertEqual(1, context.getPendingCount())

		try assertPublished(
			context, [holdoutExposure(11, "holdout_var_late", 0, unitType: "user_id")], unitType: "user_id")
	}

	// An override is not evicted by a late unit, but its holdout arms are resolved again when it is
	// exposed: like JavaScript, the override assignment is rebuilt because its arm was missing.
	func testSetUnitDoesNotEvictOverrideAssignmentAndHoldoutResolvesLiveAtExposureTime() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_override_late_unit", unitType: "user_id", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_override_late", unitType: "user_id", seeds: Self.holdoutB)]),
			uid: nil
		) { $0.setOverride(experimentName: "exp_override_late_unit", variant: 3) }

		XCTAssertEqual(3, context.peekTreatment("exp_override_late_unit"))

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(3, context.getTreatment("exp_override_late_unit"))
		XCTAssertEqual(2, context.getPendingCount())

		try assertPublished(
			context,
			[
				exposure(1, "exp_override_late_unit", 3, unitType: "user_id", assigned: false, overridden: true),
				holdoutExposure(11, "holdout_override_late", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	func testSetUnitEvictsNullSnapshotForCustomAssignmentAndCustomAppliesAfterRecompute() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_custom_late_unit", unitType: "user_id", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_custom_late", unitType: "user_id", seeds: Self.holdoutB)]),
			uid: nil
		) { $0.setCustomAssignment(experimentName: "exp_custom_late_unit", variant: 3) }

		XCTAssertEqual(0, context.peekTreatment("exp_custom_late_unit"))

		context.setUnit(unitType: "user_id", uid: Self.uid)

		XCTAssertEqual(3, context.getTreatment("exp_custom_late_unit"))
		XCTAssertEqual(2, context.getPendingCount())

		try assertPublished(
			context,
			[
				exposure(1, "exp_custom_late_unit", 3, unitType: "user_id", custom: true),
				holdoutExposure(11, "holdout_custom_late", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	// MARK: - Cross-SDK verdict vectors (also checked against the collector)

	static let verdictUnitType = "verdict_unit_type"

	func verdictContext(_ uid: String, _ holdouts: [[String: Any]]) -> Context {
		let ids = holdouts.map { $0["id"] as! Int }
		return createContext(
			contextData(
				[experiment(9, "verdict_vectors_experiment", unitType: Self.verdictUnitType, holdoutIds: ids)],
				holdouts: holdouts), uid: nil
		) { $0.setUnit(unitType: Self.verdictUnitType, uid: uid) }
	}

	func verdictHoldout(_ id: Int, seedHi: Int, seedLo: Int, split: [Double]) -> [String: Any] {
		return holdout(
			id, "holdout_\(id)", unitType: Self.verdictUnitType, seeds: (seedHi, seedLo), split: split)
	}

	func assertHeldOutBy(
		_ context: Context, _ holdoutId: Int, file: StaticString = #filePath, line: UInt = #line
	) throws {
		XCTAssertEqual(0, context.getTreatment("verdict_vectors_experiment"), file: file, line: line)
		XCTAssertEqual(
			[holdoutExposure(holdoutId, "holdout_\(holdoutId)", 0, unitType: Self.verdictUnitType)],
			try publish(context).exposures, file: file, line: line)
	}

	func assertNotHeldOut(
		_ context: Context, _ holdoutId: Int, file: StaticString = #filePath, line: UInt = #line
	) throws {
		_ = context.getTreatment("verdict_vectors_experiment")
		XCTAssertTrue(
			try publish(context).exposures.contains(
				holdoutExposure(holdoutId, "holdout_\(holdoutId)", 1, unitType: Self.verdictUnitType)),
			file: file, line: line)
	}

	func testUnicodeUnitIds() throws {
		try assertHeldOutBy(verdictContext("façade", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]), 107)
		try assertNotHeldOut(
			verdictContext("unicode_emoji_\u{1F680}_0", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]),
			107)
	}

	func testSignedSeedHalves() throws {
		// 0x8000000080000000 as a signed int64: both 32-bit halves have the sign bit set.
		let seed: Int64 = -9_223_372_034_707_292_160
		let seedHi = Int(Int32(truncatingIfNeeded: seed >> 32))
		let seedLo = Int(Int32(truncatingIfNeeded: seed))

		try assertHeldOutBy(
			verdictContext("signed_unit_4", [verdictHoldout(106, seedHi: seedHi, seedLo: seedLo, split: [0.1, 0.9])]),
			106)
		try assertNotHeldOut(
			verdictContext("signed_unit_b_1", [verdictHoldout(106, seedHi: seedHi, seedLo: seedLo, split: [0.1, 0.9])]),
			106)
	}

	func testPercentageBoundaryAtOnePercent() throws {
		try assertHeldOutBy(
			verdictContext("pct1_unit_188", [verdictHoldout(105, seedHi: 0, seedLo: 999_999, split: [0.01, 0.99])]), 105)
		try assertNotHeldOut(
			verdictContext("pct1_unit_0", [verdictHoldout(105, seedHi: 0, seedLo: 999_999, split: [0.01, 0.99])]), 105)
	}

	func testAssignmentProbabilityBoundaryAroundTenPercent() throws {
		try assertHeldOutBy(
			verdictContext("boundary_unit_175653", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]),
			107)
		try assertNotHeldOut(
			verdictContext("boundary_unit_75792", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]),
			107)
	}

	func testUnitHeldOutByTwoHoldoutsSimultaneously() throws {
		let context = verdictContext(
			"dual_holdout_unit_5",
			[
				verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9]),
				verdictHoldout(108, seedHi: 0, seedLo: 55, split: [0.1, 0.9]),
			])

		XCTAssertEqual(0, context.getTreatment("verdict_vectors_experiment"))

		try assertPublished(
			context,
			[
				holdoutExposure(107, "holdout_107", 0, unitType: Self.verdictUnitType),
				holdoutExposure(108, "holdout_108", 0, unitType: Self.verdictUnitType),
			], unitType: Self.verdictUnitType, uid: "dual_holdout_unit_5")
	}

	// MARK: - Variables

	func testVariableLookupFiresHoldoutExposureForBothHeldOutAndNonHeldOutUnits() {
		for (uid, pending) in [(Self.uid, 1), (Self.uidNotHeldOut, 2)] {
			setUp()
			let context = createContext(
				contextData(
					[experiment(1, "exp_var", holdoutIds: [11], configs: [nil, "{\"var_a\":\"value_a\"}"])],
					holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]), uid: uid)

			XCTAssertEqual(JSON("default"), context.getVariableValue("var_a", defaultValue: JSON("default")))
			XCTAssertEqual(UInt(pending), context.getPendingCount())
		}
	}

	func testVariableKeyResolutionSkipsSuppressedAssignmentInFavorOfAssignedOne() throws {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_var_key_suppressed", holdoutIds: [11], configs: [nil, "{\"shared\":\"from_suppressed\"}"]),
					experiment(2, "exp_var_key_assigned", configs: [nil, "{\"shared\":\"from_assigned\"}"]),
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(JSON("from_assigned"), context.getVariableValue("shared", defaultValue: JSON("default")))

		try assertPublished(
			context,
			[holdoutExposure(11, "holdout_a", 0), exposure(2, "exp_var_key_assigned", Self.normalVariant)])
	}

	func testPeekVariableValueNeverTriggersHoldoutExposureForEvaluatedCandidates() {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_var_key_peek_suppressed", holdoutIds: [11],
						configs: [nil, "{\"shared_peek\":\"from_suppressed\"}"]),
					experiment(2, "exp_var_key_peek_assigned", configs: [nil, "{\"shared_peek\":\"from_assigned\"}"]),
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(
			JSON("from_assigned"), context.peekVariableValue("shared_peek", defaultValue: JSON("default")))
		XCTAssertEqual(0, context.getPendingCount())
	}

	// MARK: - Event logger and flush scheduling
	// Java's throwing-logger tests: a Swift ContextEventLogger cannot throw, so these pin the same
	// guarantees with a logger that re-enters the context while an exposure is delivered.

	func testThrowingLoggerDoesNotPermanentlyLoseSiblingHoldoutExposure() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_multi_holdout_reentrant_logger", holdoutIds: [11, 12])],
				holdouts: [
					holdout(11, "holdout_a", seeds: Self.holdoutA), holdout(12, "holdout_b", seeds: Self.holdoutB),
				]))
		logger.handleEventContextEventClosure = { context, event in
			if case let .exposure(exposure) = event, exposure.id == 11 {
				_ = context.getTreatment("exp_multi_holdout_reentrant_logger")
			}
		}

		XCTAssertEqual(0, context.getTreatment("exp_multi_holdout_reentrant_logger"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testThrowingLoggerDoesNotMakeExperimentOrHoldoutExposureRetryable() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_reentrant_logger_terminal", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_terminal", seeds: Self.holdoutB)]))
		logger.handleEventContextEventClosure = { context, event in
			if case let .exposure(exposure) = event, exposure.id == 1 {
				_ = context.getTreatment("exp_reentrant_logger_terminal")
			}
		}

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_reentrant_logger_terminal"))
		logger.handleEventContextEventClosure = nil
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_reentrant_logger_terminal"))

		try assertPublished(
			context,
			[
				exposure(1, "exp_reentrant_logger_terminal", Self.normalVariant),
				holdoutExposure(11, "holdout_terminal", 1),
			])
	}

	// The suppressed experiment has no exposure of its own, so the holdout's must schedule the flush.
	func testThrowingLoggerOnSuppressedExperimentsOnlyHoldoutStillSchedulesFlush() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_stranded_flush", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_stranded_flush"))

		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
	}

	func testVariablePathHoldoutExposureSchedulesFlushWithoutAnyOtherEvent() {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_var_flush_suppressed", holdoutIds: [11], configs: [nil, "{\"flush_key\":\"from_suppressed\"}"]),
					experiment(2, "exp_var_flush_assigned", configs: [nil, "{\"flush_key\":\"from_assigned\"}"]),
				], holdouts: [holdout(11, "holdout_flush", seeds: Self.holdoutA)]))
		// The winner is already exposed, so only the suppressed candidate's holdout queues anything.
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_var_flush_assigned"))
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
		scheduler.scheduleAfterExecuteCallsCount = 0
		context.setData(context.getContextData()!)

		XCTAssertEqual(JSON("from_assigned"), context.getVariableValue("flush_key", defaultValue: JSON("default")))
		XCTAssertEqual(2, context.getPendingCount())
		// The timeout from the first exposure is still pending, so no second one is armed; the
		// holdout exposure rides on it.
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(
			[exposure(2, "exp_var_flush_assigned", Self.normalVariant), holdoutExposure(11, "holdout_flush", 0)],
			loggedExposures())
	}

	// MARK: - Malformed holdouts

	func testNullHoldoutArrayElementIsIgnoredAndExperimentAssignsNormally() throws {
		let data = contextData([experiment(1, "exp_null_holdout_entry")], holdouts: [NSNull()])
		XCTAssertEqual([], data.holdouts)
		let context = createContext(data)

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_null_holdout_entry"))

		try assertPublished(context, [exposure(1, "exp_null_holdout_entry", Self.normalVariant)])
	}

	func testHoldoutWithNullSplitIsIgnoredAndExperimentAssignsNormally() throws {
		var malformed = holdout(11, "holdout_null_split", seeds: Self.holdoutA)
		malformed["split"] = NSNull()
		let context = createContext(
			contextData([experiment(1, "exp_null_split_holdout", holdoutIds: [11])], holdouts: [malformed]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_null_split_holdout"))

		try assertPublished(context, [exposure(1, "exp_null_split_holdout", Self.normalVariant)])
	}

	func testHoldoutWithEmptySplitIsIgnoredAndExperimentAssignsNormally() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_empty_split_holdout", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_empty_split", seeds: Self.holdoutA, split: [])]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_empty_split_holdout"))

		try assertPublished(context, [exposure(1, "exp_empty_split_holdout", Self.normalVariant)])
	}

	// MARK: - Cache invariants

	// A stale holdout reference (an older iteration's seed) resolves against the live definition
	// and returns the already-exposed entry instead of overwriting it.
	func testStaleHoldoutReferenceNeverOverwritesNewerPinnedCacheEntry() throws {
		let context = createContext(
			contextData([experiment(1, "exp_f", holdoutIds: [11])], holdouts: [holdout(11, "holdout_h", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_f"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setData(
			contextData(
				[experiment(1, "exp_f", holdoutIds: [11]), experiment(2, "exp_g", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_h", seeds: Self.holdoutB, iteration: 2)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_g"))
		XCTAssertEqual(3, context.getPendingCount())

		#if DEBUG
		let stale = contextData([], holdouts: [holdout(11, "holdout_h", seeds: Self.holdoutA)]).holdouts![0]
		let resolved = try XCTUnwrap(context.resolveHoldoutArm(stale, unitType: Self.unitType))
		XCTAssertEqual(1, resolved.variant)
		XCTAssertEqual(2, resolved.iteration)
		XCTAssertTrue(resolved.exposed)
		#endif

		try assertPublished(
			context,
			[
				holdoutExposure(11, "holdout_h", 0), exposure(2, "exp_g", Self.normalVariant),
				holdoutExposure(11, "holdout_h", 1),
			])
	}

	// A stale reference draws against the live definition, and the arm count pinned with the arm is
	// the live split's: a 2-arm stale reference to a refreshed 3-arm holdout still reads arm 1 as
	// "full-on only".
	func testStaleHoldoutReferencePinsTheLiveArmCount() throws {
		let context = createContext(
			contextData([experiment(1, "exp_a")], holdouts: [holdout(21, "holdout_arity_stale", seeds: Self.holdoutB)]))

		context.setData(
			contextData(
				[experiment(1, "exp_a"), experiment(2, "exp_b", holdoutIds: [21])],
				holdouts: [
					holdout(
						21, "holdout_arity_stale", seeds: Self.threeArm1, split: Self.threeArmSplit, holdoutType: nil,
						iteration: 2)
				]))

		#if DEBUG
		let stale = contextData([], holdouts: [holdout(21, "holdout_arity_stale", seeds: Self.holdoutB)]).holdouts![0]
		let resolved = try XCTUnwrap(context.resolveHoldoutArm(stale, unitType: Self.unitType))
		XCTAssertEqual(1, resolved.variant)
		XCTAssertEqual(2, resolved.iteration)
		#endif

		XCTAssertEqual(0, context.getTreatment("exp_b"))
		try assertPublished(context, [holdoutExposure(21, "holdout_arity_stale", 1)])
	}

	// A refresh that lands after an assignment lookup read the experiment, but before its holdout arms
	// are drawn, waits for the lookup to finish. So the assignment never pairs one data install's
	// holdout definitions with another's arms: the refresh behaves as if it came after the first
	// read, as in JavaScript. Without that, the first read pinned iteration 1 beside the iteration-2
	// arm, and the next read re-exposed the experiment with no holdout exposure for its epoch.
	func testRefreshDuringAssignmentResolutionDoesNotReExposeTheExperiment() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_race", holdoutIds: [11])], holdouts: [holdout(11, "holdout_race", seeds: Self.holdoutB)]))
		let refreshed = contextData(
			[experiment(1, "exp_race", holdoutIds: [11])],
			holdouts: [holdout(11, "holdout_race", seeds: Self.holdoutB, iteration: 2)])

		#if DEBUG
		let installed = DispatchSemaphore(value: 0)
		var fired = false
		context.afterExperimentLookup = {
			guard !fired else { return }
			fired = true
			DispatchQueue.global().async {
				context.setData(refreshed)
				installed.signal()
			}
			// Give the refresh the chance to land inside this lookup; it must wait for the lookup.
			_ = installed.wait(timeout: .now() + 0.2)
		}
		#else
		let installed = DispatchSemaphore(value: 0)
		#endif

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_race"))
		#if !DEBUG
		context.setData(refreshed)
		installed.signal()
		#endif
		XCTAssertEqual(.success, installed.wait(timeout: .now() + 5))
		#if DEBUG
		context.afterExperimentLookup = nil
		#endif
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_race"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_race"))

		// Each epoch publishes the experiment's exposure with its own holdout exposure, and repeated
		// reads in the new epoch add nothing.
		XCTAssertEqual([1, 11, 1, 11], loggedExposures().map { $0.id })
	}

	// A logger that closes the context on the experiment's exposure still sees every holdout exposure
	// of that call published: they are all queued before the logger runs.
	func testLoggerClosingOnFirstExposurePublishesEveryHoldoutExposure() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_close", holdoutIds: [11, 12])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB), holdout(12, "holdout_b", seeds: Self.holdoutB)]))
		var closing: Promise<Void>?
		logger.handleEventContextEventClosure = { context, event in
			if case let .exposure(exposure) = event, exposure.id == 1, closing == nil {
				closing = context.close()
			}
		}

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_close"))
		try XCTUnwrap(closing).wait()

		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(
			[exposure(1, "exp_close", Self.normalVariant), holdoutExposure(11, "holdout_a", 1), holdoutExposure(12, "holdout_b", 1)],
			handler.publishEventReceivedEvent?.exposures)
		XCTAssertEqual(0, context.getPendingCount())
	}

	// An up-to-date override stays cached when a refresh removes its experiment, as in JavaScript and
	// Java: an exposed one is not exposed again, and a peeked one still publishes its pinned exposures.
	func testOverrideKeepsItsCachedAssignmentWhenTheExperimentIsRemoved() {
		let data = contextData(
			[experiment(1, "exp_gone", holdoutIds: [11])], holdouts: [holdout(11, "holdout_gone", seeds: Self.holdoutA)])
		let own = exposure(1, "exp_gone", 1, assigned: false, overridden: true)

		let exposed = createContext(data) { $0.setOverride(experimentName: "exp_gone", variant: 1) }
		XCTAssertEqual(1, exposed.getTreatment("exp_gone"))
		exposed.setData(contextData([]))
		XCTAssertEqual(1, exposed.getTreatment("exp_gone"))
		XCTAssertEqual([own, holdoutExposure(11, "holdout_gone", 0)], loggedExposures())

		setUp()
		let peeked = createContext(data) { $0.setOverride(experimentName: "exp_gone", variant: 1) }
		XCTAssertEqual(1, peeked.peekTreatment("exp_gone"))
		peeked.setData(contextData([]))
		XCTAssertEqual(1, peeked.getTreatment("exp_gone"))
		XCTAssertEqual([own, holdoutExposure(11, "holdout_gone", 0)], loggedExposures())
	}

	// A same-iteration rename keeps the arm, and the exposure carries the name of the definition the
	// assignment was resolved with, as in JavaScript.
	func testHoldoutExposureUsesTheResolvedDefinitionsName() {
		let context = createContext(
			contextData([experiment(1, "exp_a", holdoutIds: [11])], holdouts: [holdout(11, "old_name", seeds: Self.holdoutA)]))
		XCTAssertEqual(0, context.peekTreatment("exp_a"))

		context.setData(
			contextData(
				[experiment(1, "exp_a", holdoutIds: [11]), experiment(2, "exp_b", holdoutIds: [11])],
				holdouts: [holdout(11, "new_name", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_b"))
		XCTAssertEqual([holdoutExposure(11, "new_name", 0)], loggedExposures())
	}

	// The publisher is called without holding the context's lock, so one that waits on a refresh (which
	// installs data under that lock) finishes.
	func testPublisherWaitingOnRefreshDoesNotDeadlock() throws {
		let provider = ContextDataProviderMock()
		provider.getContextDataReturnValue = Promise<ContextData>.value(contextData([experiment(1, "exp_a")]))
		let config = ContextConfig()
		config.setUnit(unitType: Self.unitType, uid: Self.uid)
		let context = Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: DefaultVariableParser(), matcher: AudienceMatcher(),
			promise: Promise<ContextData>.value(contextData([experiment(1, "exp_a")])))
		let refreshed = DispatchSemaphore(value: 0)
		handler.publishEventClosure = { _ in
			DispatchQueue.global().async {
				_ = context.refresh().done(on: DispatchQueue.global()) { refreshed.signal() }
			}
			XCTAssertEqual(.success, refreshed.wait(timeout: .now() + 5))
			return Promise<Void>.value(())
		}

		context.track("goal")
		try context.publish().wait()
		XCTAssertEqual(1, handler.publishEventCallsCount)
	}

	// The override fast path revalidates coverage too: a holdout added by a refresh rebuilds the
	// overridden assignment (re-exposing it) and fires the new holdout.
	func testHoldoutBecomingApplicableAfterRefreshStillFiresForOverriddenExperiment() throws {
		let context = createContext(contextData([experiment(1, "exp_override_late_holdout")])) {
			$0.setOverride(experimentName: "exp_override_late_holdout", variant: 3)
		}

		XCTAssertEqual(3, context.getTreatment("exp_override_late_holdout"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setData(
			contextData(
				[experiment(1, "exp_override_late_holdout", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_late", seeds: Self.holdoutA)]))

		XCTAssertEqual(3, context.getTreatment("exp_override_late_holdout"))
		XCTAssertEqual(3, context.getPendingCount())

		let own = exposure(1, "exp_override_late_holdout", 3, assigned: false, overridden: true)
		try assertPublished(context, [own, own, holdoutExposure(11, "holdout_late", 0)])
	}

	func testSetDataDoesNotMutateCallerSuppliedHoldoutIds() {
		let data = contextData(
			[experiment(1, "exp_holdout_no_mutate_in", holdoutIds: [12, 11]), experiment(2, "exp_not_covered")],
			holdouts: [holdout(11, "holdout_no_mutate", seeds: Self.holdoutA)])
		let context = createContext(data)

		XCTAssertEqual(0, context.getTreatment("exp_holdout_no_mutate_in"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_not_covered"))
		XCTAssertEqual([12, 11], data.experiments[0].holdoutIds)
	}

	// MARK: - Assignment rules beat holdout suppression

	func testMatchingAssignmentRuleWinsOverHoldoutSuppression() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_rules", holdoutIds: [11], assignmentRules: Self.usRule)],
				holdouts: [holdout(11, "holdout_rules_suppression", seeds: Self.holdoutA)]))
		context.setAttribute(name: "country", value: "US")

		XCTAssertEqual(1, context.getTreatment("exp_holdout_rules"))

		try assertPublished(
			context,
			[
				exposure(1, "exp_holdout_rules", 1, assigned: false, ruleOverride: true),
				holdoutExposure(11, "holdout_rules_suppression", 0),
			], attributes: [Attribute("country", value: "US", setAt: now)])
	}

	func testMatchingSplitRuleWinsOverHoldoutSuppression() {
		let rules =
			"{\"rules\":[{\"name\":\"Everyone\",\"type\":\"split\",\"conditions\":null,\"environments\":[],\"percentages\":\"0/100\"}]}"
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_split_rule", holdoutIds: [11], assignmentRules: rules)],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(1, context.peekTreatment("exp_holdout_split_rule"))
		XCTAssertEqual(1, context.getTreatment("exp_holdout_split_rule"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testHeldOutUnitIsSuppressedWhenRuleDoesNotMatch() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_rules", holdoutIds: [11], assignmentRules: Self.usRule)],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))
		context.setAttribute(name: "country", value: "GB")

		XCTAssertEqual(0, context.getTreatment("exp_holdout_rules"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setAttribute(name: "country", value: "US")
		XCTAssertEqual(1, context.getTreatment("exp_holdout_rules"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testHeldOutUnitIsSuppressedAgainWhenRuleStopsMatching() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_holdout_rules", holdoutIds: [11], assignmentRules: Self.usRule)],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))
		context.setAttribute(name: "country", value: "US")

		XCTAssertEqual(1, context.getTreatment("exp_holdout_rules"))
		XCTAssertEqual(2, context.getPendingCount())

		context.setAttribute(name: "country", value: "GB")
		XCTAssertEqual(0, context.getTreatment("exp_holdout_rules"))
		XCTAssertEqual(0, context.peekTreatment("exp_holdout_rules"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testVariableValueOnHeldOutRuleWonExperiment() throws {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_holdout_rules", holdoutIds: [11], configs: withVariables("color"),
						assignmentRules: Self.usRule)
				], holdouts: [holdout(11, "holdout_rules_suppression", seeds: Self.holdoutA)]))
		context.setAttribute(name: "country", value: "US")

		XCTAssertEqual(JSON("treatment"), context.getVariableValue("color", defaultValue: JSON("default")))

		try assertPublished(
			context,
			[
				exposure(1, "exp_holdout_rules", 1, assigned: false, ruleOverride: true),
				holdoutExposure(11, "holdout_rules_suppression", 0),
			], attributes: [Attribute("country", value: "US", setAt: now)])
	}

	func testSharedVariableKeyPrefersRuleWonOverSuppressedExperiment() {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_held_out", holdoutIds: [11], configs: withVariables("color")),
					experiment(
						2, "exp_rule_won", holdoutIds: [11], configs: withVariables("color"), assignmentRules: Self.usRule),
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		context.setAttribute(name: "country", value: "GB")
		XCTAssertEqual(JSON("control"), context.peekVariableValue("color", defaultValue: JSON("default")))

		context.setAttribute(name: "country", value: "US")
		XCTAssertEqual(JSON("treatment"), context.peekVariableValue("color", defaultValue: JSON("default")))
	}

	func testSharedVariableKeyPrefersEarlierAssignedOverLaterRuleWonExperiment() {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_assigned", split: [1.0, 0.0], configs: withVariables("color")),
					experiment(2, "exp_rule_won", configs: withVariables("color"), assignmentRules: Self.usRule),
				], holdouts: []))
		context.setAttribute(name: "country", value: "US")

		XCTAssertEqual(JSON("control"), context.peekVariableValue("color", defaultValue: JSON("default")))
		XCTAssertEqual(1, context.peekTreatment("exp_rule_won"))
	}

	// MARK: - Payload: deserialization, forward compatibility, no cost without holdouts

	// holdouts_context.json is java-sdk core-api/src/test/resources/holdouts_context.json at 34716f8,
	// byte-identical: holdout_a carries the legacy full-experiment shape, holdout_b the slim one.
	func testDeserializesHoldoutsFixture() throws {
		let path = TestResources.path(forResource: "holdouts_context", ofType: "json")
		let data = decode(try Data(contentsOf: URL(fileURLWithPath: path)))

		XCTAssertEqual(1, data.experiments.count)
		XCTAssertEqual([11], data.experiments[0].holdoutIds)
		XCTAssertNil(data.experiments[0].holdoutType)

		let holdouts = try XCTUnwrap(data.holdouts)
		XCTAssertEqual([11, 12], holdouts.map { $0.id })
		XCTAssertEqual(["holdout_a", "holdout_b"], holdouts.map { $0.name })
		XCTAssertEqual([1, 1], holdouts.map { $0.iteration })
		XCTAssertEqual(["session_id", "session_id"], holdouts.map { $0.unitType })
		XCTAssertEqual([13, 1], holdouts.map { $0.seedHi })
		XCTAssertEqual([111, 222], holdouts.map { $0.seedLo })
		XCTAssertEqual([[0.1, 0.9], [0.05, 0.05, 0.9]], holdouts.map { $0.split })
		XCTAssertEqual(["full", nil], holdouts.map { $0.holdoutType })
		XCTAssertNil(holdouts[1].holdoutIds)

		// Variant 0 of 3-arm holdout_b would also hold the unit out, so check against holdout_a only.
		let context = createContext(data)
		let expected = VariantAssigner(Hashing.hashBytes(Self.uid)).assign([0.1, 0.9], 13, 111)
		XCTAssertEqual(0, expected)
		XCTAssertEqual(0, context.getTreatment("exp_test_holdout"))
		XCTAssertEqual([holdoutExposure(11, "holdout_a", 0)], loggedExposures())
	}

	// Unknown scalar, object and array keys at the root, inside experiments and inside holdout
	// entries, across two covered experiments: both still resolve, and nothing is logged.
	func testUnknownFieldsInsideHoldoutObjectsAreIgnored() throws {
		let unknown: [String: Any] = [
			"futureScalar": 42, "futureString": "x", "futureObject": ["nested": ["deep": true]],
			"futureArray": [1, ["a": NSNull()], [2, 3]], "futureNull": NSNull(),
		]
		var first = experiment(1, "exp_fc_held_out", holdoutIds: [11])
		var second = experiment(2, "exp_fc_other", holdoutIds: [12], configs: [nil, "{\"k\":1}"])
		var held = holdout(11, "holdout_fc_a", seeds: Self.holdoutA)
		var notHeld = holdout(12, "holdout_fc_b", seeds: Self.holdoutB, holdoutType: nil)
		for (key, value) in unknown {
			first[key] = value
			second[key] = value
			held[key] = value
			notHeld[key] = value
		}
		notHeld["switchbackClusters"] = ["user_id": "/company"]
		var payload: [String: Any] = ["experiments": [first, second], "holdouts": [held, notHeld]]
		for (key, value) in unknown {
			payload[key] = value
		}
		let data = decode(try JSONSerialization.data(withJSONObject: payload))

		XCTAssertEqual([11, 12], data.holdouts?.map { $0.id })
		let context = createContext(data)
		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isFailed())
		XCTAssertEqual(0, context.getTreatment("exp_fc_held_out"))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_fc_other"))
		XCTAssertEqual(
			[
				holdoutExposure(11, "holdout_fc_a", 0), exposure(2, "exp_fc_other", Self.normalVariant),
				holdoutExposure(12, "holdout_fc_b", 1),
			], loggedExposures())
		XCTAssertFalse(loggedEvents().contains { if case .error = $0 { return true } else { return false } })
	}

	// A malformed `holdouts` field or entry only uncovers what referenced it; the context still loads.
	func testMalformedHoldoutsDegradeOnlyThemselves() throws {
		for holdouts in ["\"oops\"", "{\"id\":11}", "[1, \"x\", {\"id\":11}]", "null"] {
			let json = """
				{"experiments":[\(String(data: try JSONSerialization.data(withJSONObject: experiment(1, "exp", holdoutIds: [11])), encoding: .utf8)!)],\
				"holdouts":\(holdouts)}
				"""
			let data = decode(Data(json.utf8))
			XCTAssertEqual(1, data.experiments.count, holdouts)
			XCTAssertEqual(
				Self.normalVariant, createContext(data).peekTreatment("exp"), "holdouts: \(holdouts)")
		}
		// A holdout entry without a name is skipped on its own; the valid sibling still applies.
		let data = contextData(
			[experiment(1, "exp", holdoutIds: [10, 11])],
			holdouts: [["id": 10, "split": [1.0, 0.0]], holdout(11, "holdout_a", seeds: Self.holdoutA)])
		XCTAssertEqual([11], data.holdouts?.map { $0.id })
		XCTAssertEqual(0, createContext(data).getTreatment("exp"))
	}

	// With no holdouts, the published bytes are the same as for the same payload before this
	// feature: no holdout key reaches the wire, and holdout fields on the payload change nothing.
	func testPublishBytesUnchangedWithoutHoldouts() throws {
		func publishedBytes(_ data: ContextData) throws -> Data {
			setUp()
			let context = createContext(data) { $0.setAttribute(name: "country", value: "NL") }
			_ = context.getTreatment("exp_a")
			_ = context.getTreatment("exp_b")
			_ = context.getVariableValue("k")
			context.track("goal", properties: ["amount": 1])
			let encoder = JSONEncoder()
			if #available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *) {
				encoder.outputFormatting = .sortedKeys
			}
			return try encoder.encode(try publish(context))
		}

		let experiments = [
			experiment(1, "exp_a", configs: [nil, "{\"k\":1}"]), experiment(2, "exp_b", fullOnVariant: 1),
		]
		let baseline = try publishedBytes(contextData(experiments))
		// The pre-holdout wire, written out: any holdout field added to the publish shows up here.
		let expected =
			"{\"attributes\":[{\"name\":\"country\",\"setAt\":1620000000000,\"value\":\"NL\"}],\"exposures\":["
			+ "{\"assigned\":true,\"audienceMismatch\":false,\"custom\":false,\"eligible\":true,\"exposedAt\":1620000000000,\"fullOn\":false,\"id\":1,\"name\":\"exp_a\",\"overridden\":false,\"ruleOverride\":false,\"unit\":\"session_id\",\"variant\":1},"
			+ "{\"assigned\":true,\"audienceMismatch\":false,\"custom\":false,\"eligible\":true,\"exposedAt\":1620000000000,\"fullOn\":true,\"id\":2,\"name\":\"exp_b\",\"overridden\":false,\"ruleOverride\":false,\"unit\":\"session_id\",\"variant\":1}],"
			+ "\"goals\":[{\"achievedAt\":1620000000000,\"name\":\"goal\",\"properties\":{\"amount\":1}}],"
			+ "\"hashed\":true,\"publishedAt\":1620000000000,\"units\":[{\"type\":\"session_id\",\"uid\":\"\(Hashing.hash(Self.uid))\"}]}"
		XCTAssertEqual(expected, String(data: baseline, encoding: .utf8))

		// Empty holdouts, a dangling id, and holdouts nothing references: the same bytes.
		XCTAssertEqual(baseline, try publishedBytes(contextData(experiments, holdouts: [])))
		var dangling = experiments
		dangling[0]["holdoutIds"] = [999]
		dangling[1]["holdoutIds"] = [] as [Int]
		XCTAssertEqual(
			baseline,
			try publishedBytes(contextData(dangling, holdouts: [holdout(11, "unreferenced", seeds: Self.holdoutA)])))
	}

	// A malformed id in `holdoutIds` is dropped on its own (JavaScript skips ids with no holdout); the
	// valid ids still cover the experiment.
	func testMalformedHoldoutIdIsDroppedAlone() throws {
		var covered = experiment(1, "exp_mixed_ids", holdoutIds: [])
		covered["holdoutIds"] = [11, "x", NSNull(), 1.5, ["id": 12]] as [Any]
		let data = contextData([covered], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)])

		XCTAssertEqual([11], data.experiments[0].holdoutIds)
		let context = createContext(data)
		XCTAssertEqual(0, context.getTreatment("exp_mixed_ids"))
		XCTAssertEqual([holdoutExposure(11, "holdout_a", 0)], loggedExposures())
	}

	// The plain constructors are unchanged and the holdouts overload defaults to none.
	func testContextDataConstructorsAndEquality() {
		let experiments = contextData([experiment(1, "exp", holdoutIds: [11])]).experiments
		let holdouts = contextData([], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]).holdouts

		XCTAssertNil(ContextData().holdouts)
		XCTAssertNil(ContextData(experiments: experiments).holdouts)
		XCTAssertEqual(ContextData(experiments: experiments), ContextData(experiments: experiments, holdouts: nil))
		XCTAssertEqual(holdouts, ContextData(experiments: experiments, holdouts: holdouts).holdouts)
		XCTAssertNotEqual(ContextData(experiments: experiments), ContextData(experiments: experiments, holdouts: holdouts))

		let withIds = contextData([experiment(1, "exp", holdoutIds: [11])]).experiments[0]
		let withOtherIds = contextData([experiment(1, "exp", holdoutIds: [12])]).experiments[0]
		let typed = contextData([], holdouts: [holdout(1, "exp", seeds: Self.holdoutA)]).holdouts![0]
		let untyped = contextData([], holdouts: [holdout(1, "exp", seeds: Self.holdoutA, holdoutType: nil)]).holdouts![0]
		XCTAssertNotEqual(withIds, withOtherIds)
		XCTAssertNotEqual(typed, untyped)
	}

	// MARK: - JavaScript contracts beyond the Java suite

	// H1: a duplicated holdout id is one holdout (JS dedups with insertUniqueSorted): one exposure.
	func testDuplicateHoldoutIdsPublishOneExposure() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_dup", holdoutIds: [11, 11, 11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_dup"))

		try assertPublished(context, [exposure(1, "exp_dup", Self.normalVariant), holdoutExposure(11, "holdout_a", 1)])
	}

	// Deduplicated coverage is the same coverage: dropping the duplicate on refresh is not a change
	// and must not re-expose the experiment.
	func testRefreshDroppingDuplicateHoldoutIdDoesNotReExpose() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_dup", holdoutIds: [11, 11])], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_dup"))
		XCTAssertEqual(2, context.getPendingCount())

		context.setData(
			contextData([experiment(1, "exp_dup", holdoutIds: [11])], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_dup"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	// Exposures follow holdout id order, whatever the order of `holdoutIds` and `holdouts`.
	func testHoldoutExposuresAreInIdOrder() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_order", holdoutIds: [12, 11])],
				holdouts: [holdout(12, "holdout_b", seeds: Self.holdoutB), holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_order"))

		try assertPublished(context, [holdoutExposure(11, "holdout_a", 0), holdoutExposure(12, "holdout_b", 1)])
	}

	// H7: a strict audience mismatch on a covered, not-held-out experiment still fires the holdout.
	func testStrictAudienceMismatchOnNotHeldOutExperimentStillFiresHoldout() throws {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_strict", holdoutIds: [11],
						audience: "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}", audienceStrict: true)
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))
		context.setAttribute(name: "age", value: 5)

		XCTAssertEqual(0, context.getTreatment("exp_strict"))

		try assertPublished(
			context,
			[
				exposure(1, "exp_strict", 0, assigned: false, audienceMismatch: true),
				holdoutExposure(11, "holdout_a", 1),
			], attributes: [Attribute("age", value: 5, setAt: now)])
	}

	// A suppressed experiment skips the audience entirely, like JavaScript and the collector: a
	// later attribute change cannot rebuild it and its exposure stays the holdout's alone.
	func testSuppressedExperimentSkipsAudienceEvaluation() {
		let context = createContext(
			contextData(
				[
					experiment(
						1, "exp_held_audience", holdoutIds: [11],
						audience: "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}", audienceStrict: true)
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))
		context.setAttribute(name: "age", value: 5)

		XCTAssertEqual(0, context.getTreatment("exp_held_audience"))
		context.setAttribute(name: "age", value: 50)
		XCTAssertEqual(0, context.getTreatment("exp_held_audience"))
		XCTAssertEqual([holdoutExposure(11, "holdout_a", 0)], loggedExposures())
	}

	// The arm is hashed with the covered experiment's unit type, never the holdout's own (scenario 227).
	func testHoldoutArmUsesTheCoveredExperimentsUnitType() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_session", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_user", unitType: "user_id", seeds: Self.holdoutA)])
		) { $0.setUnit(unitType: "user_id", uid: Self.uidNotHeldOut) }

		// `uid` (session_id) is held out by these seeds; `uidNotHeldOut` (user_id) would not be.
		XCTAssertEqual(0, context.getTreatment("exp_session"))
		XCTAssertEqual([holdoutExposure(11, "holdout_user", 0, unitType: "session_id")], loggedExposures())
	}

	// Arity comes from the split's length, never `holdoutType` (scenario 222).
	func testArityComesFromSplitNotHoldoutType() {
		for holdoutType in [nil, "full", "all_full_on", "unknown"] as [String?] {
			setUp()
			let context = createContext(
				contextData(
					[
						experiment(1, "exp_non_fullon", holdoutIds: [21]),
						experiment(2, "exp_fullon", fullOnVariant: 2, holdoutIds: [21]),
					],
					holdouts: [
						holdout(21, "h", seeds: Self.threeArm1, split: Self.threeArmSplit, holdoutType: holdoutType)
					]))
			XCTAssertEqual(0, context.getTreatment("exp_non_fullon"), "\(String(describing: holdoutType))")
			XCTAssertEqual(2, context.getTreatment("exp_fullon"), "\(String(describing: holdoutType))")
		}
		// A two-arm split read as "all_full_on" keeps arm 1 as "not held out".
		let context = createContext(
			contextData(
				[experiment(1, "exp_two_arm", holdoutIds: [11])],
				holdouts: [holdout(11, "h", seeds: Self.holdoutB, holdoutType: "all_full_on")]))
		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_two_arm"))
	}

	// A 4-arm holdout: only arm 0 holds out (arm 1's full-on rule is for exactly 3 arms).
	func testIsHeldOutByTable() {
		for fullOnVariant in [0, 2] {
			XCTAssertTrue(Context.isHeldOutBy(0, armCount: 2, fullOnVariant: fullOnVariant))
			XCTAssertTrue(Context.isHeldOutBy(0, armCount: 3, fullOnVariant: fullOnVariant))
			XCTAssertTrue(Context.isHeldOutBy(0, armCount: 4, fullOnVariant: fullOnVariant))
			XCTAssertFalse(Context.isHeldOutBy(1, armCount: 2, fullOnVariant: fullOnVariant))
			XCTAssertFalse(Context.isHeldOutBy(1, armCount: 4, fullOnVariant: fullOnVariant))
			XCTAssertFalse(Context.isHeldOutBy(2, armCount: 3, fullOnVariant: fullOnVariant))
		}
		XCTAssertTrue(Context.isHeldOutBy(1, armCount: 3, fullOnVariant: 0))
		XCTAssertFalse(Context.isHeldOutBy(1, armCount: 3, fullOnVariant: 2))
	}

	// Removing coverage on refresh re-resolves the experiment (scenario 225).
	func testRefreshRemovingCoverageReResolvesExperiment() {
		let context = createContext(
			contextData(
				[experiment(1, "exp_cov", holdoutIds: [11])], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(0, context.getTreatment("exp_cov"))
		XCTAssertEqual(1, context.getPendingCount())

		context.setData(contextData([experiment(1, "exp_cov")], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		XCTAssertEqual(Self.normalVariant, context.getTreatment("exp_cov"))
		XCTAssertEqual(
			[holdoutExposure(11, "holdout_a", 0), exposure(1, "exp_cov", Self.normalVariant)], loggedExposures())
	}

	// Exposure state survives a publish (scenario 223).
	func testPublishKeepsHoldoutExposureState() throws {
		let context = createContext(
			contextData(
				[experiment(1, "exp_a", holdoutIds: [11]), experiment(2, "exp_b", holdoutIds: [11])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutB)]))

		_ = context.getTreatment("exp_a")
		_ = try publish(context)
		_ = context.getTreatment("exp_a")
		_ = context.getTreatment("exp_b")

		try assertPublished(context, [exposure(2, "exp_b", Self.normalVariant)])
	}

	// A suppressed candidate's control value is the fallback for a shared key (scenario 226) and is
	// captured from the first suppressed candidate only.
	func testSuppressedFallbackIsTheFirstSuppressedCandidatesControlValue() {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_first", holdoutIds: [11], configs: ["{\"other\":0}", "{\"k\":\"t1\"}"]),
					experiment(2, "exp_second", holdoutIds: [11], configs: ["{\"k\":\"c2\"}", "{\"k\":\"t2\"}"]),
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))

		// exp_first is held out but its control lacks `k`; a later suppressed candidate cannot win.
		XCTAssertEqual(JSON("default"), context.getVariableValue("k", defaultValue: JSON("default")))

		setUp()
		let second = createContext(
			contextData(
				[experiment(2, "exp_second", holdoutIds: [11], configs: ["{\"k\":\"c2\"}", "{\"k\":\"t2\"}"])],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)]))
		XCTAssertEqual(JSON("c2"), second.peekVariableValue("k", defaultValue: JSON("default")))
		XCTAssertEqual(JSON("c2"), second.getVariableValue("k", defaultValue: JSON("default")))
		XCTAssertEqual([holdoutExposure(11, "holdout_a", 0)], loggedExposures())
	}

	// H8: the first candidate is suppressed and the second is assigned; the assigned one wins and
	// both candidates' holdouts fire.
	func testSharedKeyAssignedCandidateWinsOverSuppressedAndBothHoldoutsFire() throws {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_suppressed", holdoutIds: [11], configs: withVariables("k")),
					experiment(2, "exp_assigned", holdoutIds: [12], configs: withVariables("k")),
				],
				holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA), holdout(12, "holdout_b", seeds: Self.holdoutB)]))

		XCTAssertEqual(JSON("treatment"), context.getVariableValue("k", defaultValue: JSON("default")))

		try assertPublished(
			context,
			[
				holdoutExposure(11, "holdout_a", 0), exposure(2, "exp_assigned", Self.normalVariant),
				holdoutExposure(12, "holdout_b", 1),
			])
	}

	// H6: one holdout covering experiments with two unit types publishes one exposure per unit type.
	func testSharedHoldoutAcrossUnitTypesPublishesPerUnitType() {
		let context = createContext(
			contextData(
				[
					experiment(1, "exp_session", holdoutIds: [11]),
					experiment(2, "exp_user", unitType: "user_id", holdoutIds: [11]),
				], holdouts: [holdout(11, "holdout_a", seeds: Self.holdoutA)])
		) { $0.setUnit(unitType: "user_id", uid: Self.uidNotHeldOut) }

		XCTAssertEqual(0, context.getTreatment("exp_session"))
		XCTAssertEqual(0, context.getTreatment("exp_user"))
		XCTAssertEqual(
			[
				holdoutExposure(11, "holdout_a", 0), exposure(2, "exp_user", 0, unitType: "user_id"),
				holdoutExposure(11, "holdout_a", 1, unitType: "user_id"),
			], loggedExposures())
	}

	// A failed context drops the holdout index with the rest of the data.
	func testFailedContextHasNoHoldouts() {
		let config = ContextConfig()
		config.setUnit(unitType: Self.unitType, uid: Self.uid)
		let context = Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler,
			provider: ContextDataProviderMock(), logger: logger, parser: DefaultVariableParser(),
			matcher: AudienceMatcher(), promise: Promise<ContextData>(error: ABSmartlyError("boom")))

		XCTAssertNil(context.getContextData()?.holdouts)
		XCTAssertEqual(0, context.getTreatment("exp"))
	}

	func loggedEvents() -> [ContextEventLoggerEvent] {
		return logger.handleEventContextEventReceivedInvocations.map { $0.event }
	}
}
