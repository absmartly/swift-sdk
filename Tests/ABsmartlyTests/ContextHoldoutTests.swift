import Foundation
import Testing

@testable import ABsmartly

private typealias H = Holdouts

// Holdouts: the port of 1.5.0's `ContextHoldoutTest` (same names, fixtures and assertions), plus the
// JavaScript cases it lacks. Payload builders and seeds are in `HoldoutTestSupport.swift`.
@Suite struct ContextHoldoutTests {
	let h = HoldoutEnv()

	// MARK: - Two-arm holdouts

	@Test func heldOutUnitGetsControlValuesAndEmitsNoExposureForCoveredExperiment() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_in", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_in", exposing: false) == 0)
		#expect(context.pendingEventCount == 0)
		#expect(context.treatment(for: "exp_holdout_in") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_a", 0)])
	}

	@Test func notHeldOutUnitEmitsHoldoutExposureVariantOneAndNormalExposure() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_out", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), uid: H.uidNotHeldOut)

		#expect(context.treatment(for: "exp_holdout_out") == 0)  // uidNotHeldOut's normal variant is 0

		try await h.expectPublished(
			context, [H.own(1, "exp_holdout_out", 0), H.held(11, "holdout_a", 1)], uid: H.uidNotHeldOut)
	}

	@Test func experimentWithoutHoldoutIdsEmitsNormallyEvenForHeldOutUnit() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_in", holdoutIds: [11]), H.experiment(2, "exp_not_covered")],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_in") == 0)
		#expect(context.treatment(for: "exp_not_covered") == H.normalVariant)

		try await h.expectPublished(
			context, [H.held(11, "holdout_a", 0), H.own(2, "exp_not_covered", H.normalVariant)])
	}

	@Test func unionOfApplicableHoldoutsSuppressesExperimentAndBothEmitOwnExposure() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_multi_holdout", holdoutIds: [11, 12])],
				holdouts: [
					H.holdout(11, "holdout_a", seeds: H.holdoutA), H.holdout(12, "holdout_b", seeds: H.holdoutB),
				]))

		#expect(context.treatment(for: "exp_multi_holdout") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_a", 0), H.held(12, "holdout_b", 1)])
	}

	// The low-id holdout does not hold the unit out and the high-id one does: a union that stops at
	// the first holdout, or only reads holdouts[0], would not suppress.
	@Test func unionRuleAppliesWhenTheHigherIdHoldoutIsTheOnlyOneHoldingUnitOut() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_union_high_id_decides", holdoutIds: [11, 12])],
				holdouts: [
					H.holdout(11, "holdout_low_id", seeds: H.holdoutB),
					H.holdout(12, "holdout_high_id", seeds: H.holdoutA),
				]))

		#expect(context.treatment(for: "exp_union_high_id_decides") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_low_id", 1), H.held(12, "holdout_high_id", 0)])
	}

	@Test func unitNotHeldOutByEitherHoldoutIsNotSuppressed() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_multi_holdout_miss", holdoutIds: [11, 12])],
				holdouts: [
					H.holdout(11, "holdout_a", seeds: H.holdoutA), H.holdout(12, "holdout_b", seeds: H.holdoutB),
				]), uid: H.uidNotHeldOut)

		#expect(context.treatment(for: "exp_multi_holdout_miss") == 0)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_multi_holdout_miss", 0), H.held(11, "holdout_a", 1), H.held(12, "holdout_b", 1),
			], uid: H.uidNotHeldOut)
	}

	@Test func holdoutSuppressesFullOnExperimentRegardlessOfFullOnVariant() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_fullon_holdout", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_fullon_holdout") == 0)
	}

	// MARK: - Three-arm holdouts

	@Test func threeArmVariantZeroHoldsOutBothFullOnAndNonFullOnExperiments() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_three_arm_0_non_fullon", holdoutIds: [21]),
					H.experiment(2, "exp_three_arm_0_fullon", fullOnVariant: 2, holdoutIds: [21]),
				], holdouts: [H.threeArmHoldout(21, "holdout_three_arm", seeds: H.threeArm0)]))

		#expect(context.treatment(for: "exp_three_arm_0_non_fullon") == 0)
		#expect(context.treatment(for: "exp_three_arm_0_fullon") == 0)

		try await h.expectPublished(context, [H.held(21, "holdout_three_arm", 0)])
	}

	@Test func threeArmVariantOneForcesNonFullOnExperimentToControlButAssignsFullOnExperimentNormally() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_three_arm_1_non_fullon", holdoutIds: [21]),
					H.experiment(2, "exp_three_arm_1_fullon", fullOnVariant: 2, holdoutIds: [21]),
				], holdouts: [H.threeArmHoldout(21, "holdout_three_arm", seeds: H.threeArm1)]))

		#expect(context.treatment(for: "exp_three_arm_1_non_fullon") == 0)
		#expect(context.treatment(for: "exp_three_arm_1_fullon") == 2)

		try await h.expectPublished(
			context, [H.held(21, "holdout_three_arm", 1), H.own(2, "exp_three_arm_1_fullon", 2, fullOn: true)])
	}

	@Test func threeArmVariantTwoEvaluatesBothExperimentKindsNormally() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_three_arm_2_non_fullon", holdoutIds: [21]),
					H.experiment(2, "exp_three_arm_2_fullon", fullOnVariant: 2, holdoutIds: [21]),
				], holdouts: [H.threeArmHoldout(21, "holdout_three_arm", seeds: H.threeArm2)]))

		#expect(context.treatment(for: "exp_three_arm_2_non_fullon") == H.normalVariant)
		#expect(context.treatment(for: "exp_three_arm_2_fullon") == 2)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_three_arm_2_non_fullon", H.normalVariant), H.held(21, "holdout_three_arm", 2),
				H.own(2, "exp_three_arm_2_fullon", 2, fullOn: true),
			])
	}

	@Test func twoArmHoldoutWinsUnionEvenWhenThreeArmWouldNotHoldOut() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_union_two_arm_wins", holdoutIds: [11, 22])],
				holdouts: [
					H.holdout(11, "holdout_two_arm", seeds: H.holdoutA),
					H.threeArmHoldout(22, "holdout_three_arm", seeds: H.threeArm2),
				]))

		#expect(context.treatment(for: "exp_union_two_arm_wins") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_two_arm", 0), H.held(22, "holdout_three_arm", 2)])
	}

	@Test func threeArmHoldoutWinsUnionEvenWhenTwoArmWouldNotHoldOut() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_union_three_arm_wins", holdoutIds: [11, 22])],
				holdouts: [
					H.holdout(11, "holdout_two_arm", seeds: H.holdoutB),
					H.threeArmHoldout(22, "holdout_three_arm", seeds: H.threeArm1),
				]))

		#expect(context.treatment(for: "exp_union_three_arm_wins") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_two_arm", 1), H.held(22, "holdout_three_arm", 1)])
	}

	// Arm 1 defers a full-on experiment to the normal path, so a strict audience mismatch still
	// gives control with its own exposure, exactly as under arm 2.
	@Test(arguments: [(H.threeArm1, 1), (H.threeArm2, 2)] as [((seedHi: Int, seedLo: Int), Int)])
	func threeArmArmOneDefersToNormalPathSoAudienceMismatchStillWinsForFullOnExperiment(
		seeds: (seedHi: Int, seedLo: Int), arm: Int
	) async throws {
		let audience = "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}"
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_three_arm_audience_fullon", fullOnVariant: 2, holdoutIds: [21], audience: audience,
						audienceStrict: true)
				], holdouts: [H.threeArmHoldout(21, "holdout_three_arm", seeds: seeds)]))
		context.setAttribute("age", to: 5)

		#expect(context.treatment(for: "exp_three_arm_audience_fullon") == 0)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_three_arm_audience_fullon", 0, assigned: false, audienceMismatch: true),
				H.held(21, "holdout_three_arm", arm),
			], attributes: [attribute("age", 5)])
	}

	// MARK: - Missing units, absent and malformed holdouts

	@Test func unconfiguredUnitTypeGetsControlValuesAndEmitsNoExposureAtAll() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_user_holdout", unitType: "user_id", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_user", unitType: "user_id", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_user_holdout", exposing: false) == 0)
		#expect(context.treatment(for: "exp_user_holdout") == 0)

		// The experiment's own exposure is the not-assigned one (no unit), and no holdout fires.
		#expect(h.exposures == [H.own(1, "exp_user_holdout", 0, unitType: "user_id", assigned: false)])
	}

	@Test func assignsNormallyWhenHoldoutsKeyIsAbsent() {
		let data = H.contextData([H.experiment(1, "exp_no_holdouts_key")])
		#expect(data.holdouts == nil)
		#expect(h.context(data).treatment(for: "exp_no_holdouts_key", exposing: false) == H.normalVariant)
	}

	@Test func holdoutIdAbsentFromHoldoutsArrayIsIgnoredAndExperimentAssignsNormally() {
		let context = h.context(H.contextData([H.experiment(1, "exp_dangling_holdout_id", holdoutIds: [999])]))

		#expect(context.treatment(for: "exp_dangling_holdout_id", exposing: false) == H.normalVariant)
	}

	@Test func customAssignmentCannotOverrideHeldOutVariant() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_custom", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), customAssignments: ["exp_holdout_custom": 3]
		)

		#expect(context.treatment(for: "exp_holdout_custom", exposing: false) == 0)
	}

	@Test func reusesCachedHeldOutAssignmentWithCustomAssignment() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_custom_cache", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]),
			customAssignments: ["exp_holdout_custom_cache": 3])

		#expect(context.treatment(for: "exp_holdout_custom_cache") == 0)
		#if DEBUG
			let writes = context.assignmentCacheWriteCount
		#endif
		#expect(context.treatment(for: "exp_holdout_custom_cache") == 0)
		#expect(context.pendingEventCount == 1)
		#if DEBUG
			// The custom variant differs from the held-out 0, but that is not staleness: it is a cache hit.
			#expect(context.assignmentCacheWriteCount == writes)
		#endif
	}

	@Test func overrideTakesPrecedenceOverHoldout() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_override", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), overrides: ["exp_holdout_override": 3])

		#expect(context.treatment(for: "exp_holdout_override", exposing: false) == 3)
	}

	@Test(arguments: [(H.uid, 0), (H.uidNotHeldOut, 1)])
	func getTreatmentOnOverriddenExperimentTriggersApplicableHoldoutExposureBothArms(uid: String, arm: Int)
		async throws
	{
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_override", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), uid: uid,
			overrides: ["exp_holdout_override": 3])

		#expect(context.treatment(for: "exp_holdout_override") == 3)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_holdout_override", 3, assigned: false, overridden: true),
				H.held(11, "holdout_a", arm),
			], uid: uid)
	}

	@Test func holdoutTakesPrecedenceOverAudienceMismatch() {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_holdout_audience", holdoutIds: [11],
						audience: "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}", audienceStrict: true)
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))
		context.setAttribute("age", to: 5)

		#expect(context.treatment(for: "exp_holdout_audience", exposing: false) == 0)
	}

	// MARK: - One exposure per holdout

	@Test func holdoutExposureEmittedOncePerContextNotPerSuppressedExperiment() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_shared_a", holdoutIds: [11]),
					H.experiment(2, "exp_shared_b", holdoutIds: [11]),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_shared_a") == 0)
		#expect(context.treatment(for: "exp_shared_b") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_a", 0)])
	}

	@Test func holdoutExposureFiresOnceEvenWhenTriggeringExperimentIsNotSuppressed() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_shared_a", holdoutIds: [11]),
					H.experiment(2, "exp_shared_b", holdoutIds: [11]),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), uid: H.uidNotHeldOut)

		_ = context.treatment(for: "exp_shared_a")
		_ = context.treatment(for: "exp_shared_b")

		try await h.expectPublished(
			context, [H.own(1, "exp_shared_a", 0), H.held(11, "holdout_a", 1), H.own(2, "exp_shared_b", 0)],
			uid: H.uidNotHeldOut)
	}

	@Test func reusesCachedSuppressedAssignmentAcrossRepeatedCalls() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_cache", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_cache") == 0)
		#expect(context.treatment(for: "exp_holdout_cache") == 0)
		#expect(context.pendingEventCount == 1)
	}

	// MARK: - Cross-SDK verdict vectors (also checked against the collector)

	static let verdictUnitType = "verdict_unit_type"

	func verdictContext(_ uid: String, _ holdouts: [[String: Any]]) -> Context {
		let ids = holdouts.map { $0["id"] as! Int }
		return h.context(
			H.contextData(
				[H.experiment(9, "verdict_vectors_experiment", unitType: Self.verdictUnitType, holdoutIds: ids)],
				holdouts: holdouts), uid: nil, units: [UnitType(Self.verdictUnitType): uid])
	}

	func verdictHoldout(_ id: Int, seedHi: Int, seedLo: Int, split: [Double]) -> [String: Any] {
		H.holdout(id, "holdout_\(id)", unitType: Self.verdictUnitType, seeds: (seedHi, seedLo), split: split)
	}

	func expectHeldOutBy(
		_ context: Context, _ holdoutId: Int, sourceLocation: SourceLocation = #_sourceLocation
	) async throws {
		#expect(context.treatment(for: "verdict_vectors_experiment") == 0, sourceLocation: sourceLocation)
		#expect(
			try await h.publishedExposures(context)
				== [H.held(holdoutId, "holdout_\(holdoutId)", 0, unitType: Self.verdictUnitType)],
			sourceLocation: sourceLocation)
	}

	func expectNotHeldOut(
		_ context: Context, _ holdoutId: Int, sourceLocation: SourceLocation = #_sourceLocation
	) async throws {
		let variant = context.treatment(for: "verdict_vectors_experiment")
		let published = try await h.publishedExposures(context)
		// Not held out: the experiment publishes its own exposure as well as the holdout's arm 1.
		#expect(
			published.contains(H.held(holdoutId, "holdout_\(holdoutId)", 1, unitType: Self.verdictUnitType)),
			sourceLocation: sourceLocation)
		#expect(
			published.contains(H.own(9, "verdict_vectors_experiment", variant, unitType: Self.verdictUnitType)),
			sourceLocation: sourceLocation)
	}

	@Test func unicodeUnitIds() async throws {
		try await expectHeldOutBy(
			verdictContext("façade", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]), 107)
		try await expectNotHeldOut(
			verdictContext(
				"unicode_emoji_\u{1F680}_0", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]),
			107)
	}

	@Test func signedSeedHalves() async throws {
		// 0x8000000080000000 as a signed int64: both 32-bit halves have the sign bit set.
		let seed: Int64 = -9_223_372_034_707_292_160
		let seedHi = Int(Int32(truncatingIfNeeded: seed >> 32))
		let seedLo = Int(Int32(truncatingIfNeeded: seed))

		try await expectHeldOutBy(
			verdictContext("signed_unit_4", [verdictHoldout(106, seedHi: seedHi, seedLo: seedLo, split: [0.1, 0.9])]),
			106)
		try await expectNotHeldOut(
			verdictContext(
				"signed_unit_b_1", [verdictHoldout(106, seedHi: seedHi, seedLo: seedLo, split: [0.1, 0.9])]),
			106)
	}

	@Test func percentageBoundaryAtOnePercent() async throws {
		try await expectHeldOutBy(
			verdictContext("pct1_unit_188", [verdictHoldout(105, seedHi: 0, seedLo: 999_999, split: [0.01, 0.99])]),
			105)
		try await expectNotHeldOut(
			verdictContext("pct1_unit_0", [verdictHoldout(105, seedHi: 0, seedLo: 999_999, split: [0.01, 0.99])]), 105)
	}

	@Test func assignmentProbabilityBoundaryAroundTenPercent() async throws {
		try await expectHeldOutBy(
			verdictContext("boundary_unit_175653", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]),
			107)
		try await expectNotHeldOut(
			verdictContext("boundary_unit_75792", [verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9])]),
			107)
	}

	@Test func unitHeldOutByTwoHoldoutsSimultaneously() async throws {
		let context = verdictContext(
			"dual_holdout_unit_5",
			[
				verdictHoldout(107, seedHi: 0, seedLo: 42, split: [0.1, 0.9]),
				verdictHoldout(108, seedHi: 0, seedLo: 55, split: [0.1, 0.9]),
			])

		#expect(context.treatment(for: "verdict_vectors_experiment") == 0)

		try await h.expectPublished(
			context,
			[
				H.held(107, "holdout_107", 0, unitType: Self.verdictUnitType),
				H.held(108, "holdout_108", 0, unitType: Self.verdictUnitType),
			], unitType: Self.verdictUnitType, uid: "dual_holdout_unit_5")
	}

	// MARK: - Malformed holdouts

	@Test func nullHoldoutArrayElementIsIgnoredAndExperimentAssignsNormally() async throws {
		let data = H.contextData([H.experiment(1, "exp_null_holdout_entry")], holdouts: [NSNull()])
		#expect(data.holdouts == [])
		let context = h.context(data)

		#expect(context.treatment(for: "exp_null_holdout_entry") == H.normalVariant)

		try await h.expectPublished(context, [H.own(1, "exp_null_holdout_entry", H.normalVariant)])
	}

	@Test func holdoutWithNullSplitIsIgnoredAndExperimentAssignsNormally() async throws {
		var malformed = H.holdout(11, "holdout_null_split", seeds: H.holdoutA)
		malformed["split"] = NSNull()
		let context = h.context(
			H.contextData([H.experiment(1, "exp_null_split_holdout", holdoutIds: [11])], holdouts: [malformed]))

		#expect(context.treatment(for: "exp_null_split_holdout") == H.normalVariant)

		try await h.expectPublished(context, [H.own(1, "exp_null_split_holdout", H.normalVariant)])
	}

	@Test func holdoutWithEmptySplitIsIgnoredAndExperimentAssignsNormally() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_empty_split_holdout", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_empty_split", seeds: H.holdoutA, split: [])]))

		#expect(context.treatment(for: "exp_empty_split_holdout") == H.normalVariant)

		try await h.expectPublished(context, [H.own(1, "exp_empty_split_holdout", H.normalVariant)])
	}

	// MARK: - Payload: deserialization, forward compatibility, no cost without holdouts

	// holdouts_context.json is java-sdk core-api/src/test/resources/holdouts_context.json at 34716f8,
	// byte-identical: holdout_a carries the legacy full-experiment shape, holdout_b the slim one.
	@Test func deserializesHoldoutsFixture() throws {
		let data = Fixtures.contextData("holdouts_context")

		try #require(data.experiments.count == 1)
		#expect(data.experiments[0].holdoutIds == [11])
		#expect(data.experiments[0].holdoutType == nil)

		let holdouts = try #require(data.holdouts)
		try #require(holdouts.count == 2)
		#expect(holdouts.map(\.id) == [11, 12])
		#expect(holdouts.map(\.name) == ["holdout_a", "holdout_b"])
		#expect(holdouts.map(\.iteration) == [1, 1])
		#expect(holdouts.map(\.unitType) == ["session_id", "session_id"])
		#expect(holdouts.map(\.seedHi) == [13, 1])
		#expect(holdouts.map(\.seedLo) == [111, 222])
		#expect(holdouts.map(\.split) == [[0.1, 0.9], [0.05, 0.05, 0.9]])
		#expect(holdouts.map(\.holdoutType) == ["full", nil])
		#expect(holdouts[1].holdoutIds == nil)

		// Variant 0 of 3-arm holdout_b would also hold the unit out, so check against holdout_a only.
		let context = h.context(data)
		#expect(VariantAssigner(unitHash: Hashing.hashUnit(H.uid)).assign([0.1, 0.9], seedHi: 13, seedLo: 111) == 0)
		#expect(context.treatment(for: "exp_test_holdout") == 0)
		#expect(h.exposures == [H.held(11, "holdout_a", 0)])
	}

	// Unknown scalar, object and array keys at the root, inside experiments and inside holdout
	// entries, across two covered experiments: both still resolve, and nothing is logged.
	@Test func unknownFieldsInsideHoldoutObjectsAreIgnored() throws {
		let unknown: [String: Any] = [
			"futureScalar": 42, "futureString": "x", "futureObject": ["nested": ["deep": true]],
			"futureArray": [1, ["a": NSNull()], [2, 3]] as [Any], "futureNull": NSNull(),
		]
		var first = H.experiment(1, "exp_fc_held_out", holdoutIds: [11])
		var second = H.experiment(2, "exp_fc_other", holdoutIds: [12], configs: [nil, "{\"k\":1}"])
		var held = H.holdout(11, "holdout_fc_a", seeds: H.holdoutA)
		var notHeld = H.holdout(12, "holdout_fc_b", seeds: H.holdoutB, holdoutType: nil)
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
		let data = H.decode(try JSONSerialization.data(withJSONObject: payload))

		#expect(data.holdouts?.map(\.id) == [11, 12])
		let context = h.context(data)
		#expect(context.state == .ready)
		#expect(context.treatment(for: "exp_fc_held_out") == 0)
		#expect(context.treatment(for: "exp_fc_other") == H.normalVariant)
		#expect(
			h.exposures == [
				H.held(11, "holdout_fc_a", 0), H.own(2, "exp_fc_other", H.normalVariant), H.held(12, "holdout_fc_b", 1),
			])
		#expect(h.errors.isEmpty)
	}

	@Test(arguments: ["\"oops\"", "{\"id\":11}", "[1, \"x\", {\"id\":11}]", "null"])
	func malformedHoldoutsDegradeOnlyThemselves(holdouts: String) throws {
		let experiment = String(
			decoding: try JSONSerialization.data(withJSONObject: H.experiment(1, "exp", holdoutIds: [11])),
			as: UTF8.self)
		let data = H.decode(Data("{\"experiments\":[\(experiment)],\"holdouts\":\(holdouts)}".utf8))
		#expect(data.experiments.count == 1)
		#expect(h.context(data).treatment(for: "exp", exposing: false) == H.normalVariant)
	}

	@Test func malformedHoldoutEntryIsDroppedAlone() {
		let data = H.contextData(
			[H.experiment(1, "exp", holdoutIds: [10, 11])],
			holdouts: [["id": 10, "split": [1.0, 0.0]], H.holdout(11, "holdout_a", seeds: H.holdoutA)])
		#expect(data.holdouts?.map(\.id) == [11])
		#expect(h.context(data).treatment(for: "exp") == 0)
	}

	// With no holdouts, the published bytes are the same as for the same payload before this
	// feature: no holdout key reaches the wire, and holdout fields on the payload change nothing.
	@Test func publishBytesUnchangedWithoutHoldouts() async throws {
		func publishedBody(_ data: ContextData) async throws -> Data {
			let h = HoldoutEnv()
			let context = h.context(data, attributes: ["country": "NL"])
			_ = context.treatment(for: "exp_a")
			_ = context.treatment(for: "exp_b")
			_ = context.variableValue("k")
			context.track("goal", properties: ["amount": 1])
			try await context.publish()
			let body = try #require(h.env.transport.publishes.last?.body)
			// Key-sorted, so two encodings of the same payload compare equal byte for byte.
			return try JSONSerialization.data(
				withJSONObject: JSONSerialization.jsonObject(with: body), options: [.sortedKeys])
		}

		let experiments = [
			H.experiment(1, "exp_a", configs: [nil, "{\"k\":1}"]), H.experiment(2, "exp_b", fullOnVariant: 1),
		]
		let baseline = try await publishedBody(H.contextData(experiments))
		// The pre-holdout wire: any holdout field added to the publish shows up here.
		let expected =
			"{\"attributes\":[{\"name\":\"country\",\"setAt\":1620000000000,\"value\":\"NL\"}],\"exposures\":["
			+ "{\"assigned\":true,\"audienceMismatch\":false,\"custom\":false,\"eligible\":true,\"exposedAt\":1620000000000,\"fullOn\":false,\"id\":1,\"name\":\"exp_a\",\"overridden\":false,\"ruleOverride\":false,\"unit\":\"session_id\",\"variant\":1},"
			+ "{\"assigned\":true,\"audienceMismatch\":false,\"custom\":false,\"eligible\":true,\"exposedAt\":1620000000000,\"fullOn\":true,\"id\":2,\"name\":\"exp_b\",\"overridden\":false,\"ruleOverride\":false,\"unit\":\"session_id\",\"variant\":1}],"
			+ "\"goals\":[{\"achievedAt\":1620000000000,\"name\":\"goal\",\"properties\":{\"amount\":1}}],"
			+ "\"hashed\":true,\"publishedAt\":1620000000000,\"units\":[{\"type\":\"session_id\",\"uid\":\"\(unitHash(H.uid))\"}]}"
		#expect(String(decoding: baseline, as: UTF8.self) == expected)

		// An empty holdouts list, and holdout metadata that covers nothing, publish the same bytes.
		#expect(try await publishedBody(H.contextData(experiments, holdouts: [])) == baseline)
		var dangling = experiments
		dangling[0]["holdoutIds"] = [999]
		dangling[1]["holdoutIds"] = [] as [Int]
		#expect(
			try await publishedBody(
				H.contextData(dangling, holdouts: [H.holdout(11, "unreferenced", seeds: H.holdoutA)])) == baseline)
	}

	// A malformed id in `holdoutIds` is dropped on its own (JavaScript skips ids with no holdout); the
	// valid ids still cover the experiment.
	@Test func malformedHoldoutIdIsDroppedAlone() {
		var covered = H.experiment(1, "exp_mixed_ids", holdoutIds: [])
		covered["holdoutIds"] = [11, "x", NSNull(), 1.5, ["id": 12]] as [Any]
		let data = H.contextData([covered], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)])

		#expect(data.experiments[0].holdoutIds == [11])
		let context = h.context(data)
		#expect(context.treatment(for: "exp_mixed_ids") == 0)
		#expect(h.exposures == [H.held(11, "holdout_a", 0)])
	}

	@Test func contextDataConstructorsAndEquality() {
		let experiments = H.contextData([H.experiment(1, "exp", holdoutIds: [11])]).experiments
		let holdouts = H.contextData([], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]).holdouts

		#expect(ContextData().holdouts == nil)
		#expect(ContextData(experiments: experiments).holdouts == nil)
		#expect(ContextData(experiments: experiments) == ContextData(experiments: experiments, holdouts: nil))
		#expect(ContextData(experiments: experiments, holdouts: holdouts).holdouts == holdouts)
		#expect(ContextData(experiments: experiments) != ContextData(experiments: experiments, holdouts: holdouts))

		let withIds = H.contextData([H.experiment(1, "exp", holdoutIds: [11])]).experiments[0]
		let withOtherIds = H.contextData([H.experiment(1, "exp", holdoutIds: [12])]).experiments[0]
		let typed = H.contextData([], holdouts: [H.holdout(1, "exp", seeds: H.holdoutA)]).holdouts![0]
		let untyped = H.contextData([], holdouts: [H.holdout(1, "exp", seeds: H.holdoutA, holdoutType: nil)]).holdouts![
			0]
		#expect(withIds != withOtherIds)
		#expect(typed != untyped)
	}

	// The 2.0.0 initializers keep their exact signatures (a binary built against 2.0.0 still links), and
	// give no holdout fields; the holdout overloads carry them.
	@Test func twoZeroInitializersAreKeptAndGiveNoHoldoutFields() {
		let make: ([Experiment]) -> ContextData = ContextData.init(experiments:)
		#expect(make([]).holdouts == nil)
		let twoZero:
			(
				Int, String, String?, Int, Int, Int, [Double], Int, Int, [Double], Int, [ExperimentApplication],
				[ExperimentVariant], Bool, String?, [CustomFieldValue], String?
			) -> Experiment = Experiment.init(
				id:name:unitType:iteration:seedHi:seedLo:split:trafficSeedHi:trafficSeedLo:trafficSplit:fullOnVariant:
				applications:variants:audienceStrict:audience:customFieldValues:assignmentRules:)
		let experiment = twoZero(1, "exp", "session_id", 1, 0, 0, [1], 0, 0, [0, 1], 0, [], [], false, nil, [], nil)
		#expect(experiment.holdoutIds == nil)
		#expect(experiment.holdoutType == nil)
		#expect(
			Experiment(id: 1, name: "exp", unitType: "session_id", split: [1], variants: [])
				== Experiment(
					id: 1, name: "exp", unitType: "session_id", split: [1], variants: [], holdoutIds: nil,
					holdoutType: nil))
	}

	// The public initializers carry the holdout fields, and a context built from them applies the
	// holdout like a decoded payload.
	@Test func publicInitializersCarryHoldoutFields() {
		let experiment = Experiment(
			id: 1, name: "exp_init", unitType: H.unitType, seedHi: 100, seedLo: 200, split: [0.5, 0.5],
			trafficSeedHi: 1, trafficSeedLo: 2,
			variants: [.init(name: "0", config: nil), .init(name: "1", config: nil)],
			holdoutIds: [11], holdoutType: nil)
		let holdout = Experiment(
			id: 11, name: "holdout_a", unitType: H.unitType, seedHi: H.holdoutA.seedHi, seedLo: H.holdoutA.seedLo,
			split: [0.1, 0.9], variants: [], holdoutIds: nil, holdoutType: "full")
		#expect(experiment.holdoutIds == [11])
		#expect(holdout.holdoutType == "full")

		let data = ContextData(experiments: [experiment], holdouts: [holdout])
		#expect(data.holdouts == [holdout])
		let context = h.context(data)
		#expect(context.treatment(for: "exp_init") == 0)
		#expect(h.exposures == [H.held(11, "holdout_a", 0)])
	}

	// Encoding writes the holdout fields, so a `ContextData` survives an encode/decode round trip.
	@Test func holdoutFieldsSurviveEncodeDecodeRoundTrip() throws {
		let data = Fixtures.contextData("holdouts_context")
		let decoded = try JSONDecoder().decode(ContextData.self, from: JSONEncoder().encode(data))
		#expect(decoded == data)
		#expect(decoded.holdouts?.map(\.id) == [11, 12])
		#expect(decoded.experiments[0].holdoutIds == [11])

		let bare = try JSONDecoder().decode(ContextData.self, from: JSONEncoder().encode(ContextData(experiments: [])))
		#expect(bare.holdouts == nil)
	}

	// MARK: - JavaScript contracts beyond the Java suite

	// H1: a duplicated holdout id is one holdout (JS dedups with insertUniqueSorted): one exposure.
	@Test func duplicateHoldoutIdsPublishOneExposure() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_dup", holdoutIds: [11, 11, 11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_dup") == H.normalVariant)

		try await h.expectPublished(context, [H.own(1, "exp_dup", H.normalVariant), H.held(11, "holdout_a", 1)])
	}

	// Two holdout entries with one id: the last one wins, as in javascript-sdk and 1.5.0.
	@Test func lastEntryWinsWhenTwoHoldoutsShareAnId() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_dup_holdout_id", holdoutIds: [11])],
				holdouts: [
					H.holdout(11, "holdout_first", seeds: H.holdoutA), H.holdout(11, "holdout_last", seeds: H.holdoutB),
				]))

		#expect(context.treatment(for: "exp_dup_holdout_id") == H.normalVariant)
		try await h.expectPublished(
			context, [H.own(1, "exp_dup_holdout_id", H.normalVariant), H.held(11, "holdout_last", 1)])
	}

	@Test func holdoutExposuresAreInIdOrder() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_order", holdoutIds: [12, 11])],
				holdouts: [
					H.holdout(12, "holdout_b", seeds: H.holdoutB), H.holdout(11, "holdout_a", seeds: H.holdoutA),
				]
			))

		#expect(context.treatment(for: "exp_order") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_a", 0), H.held(12, "holdout_b", 1)])
	}

	// H7: a strict audience mismatch on a covered, not-held-out experiment still fires the holdout.
	@Test func strictAudienceMismatchOnNotHeldOutExperimentStillFiresHoldout() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_strict", holdoutIds: [11],
						audience: "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}", audienceStrict: true)
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))
		context.setAttribute("age", to: 5)

		#expect(context.treatment(for: "exp_strict") == 0)

		try await h.expectPublished(
			context,
			[H.own(1, "exp_strict", 0, assigned: false, audienceMismatch: true), H.held(11, "holdout_a", 1)],
			attributes: [attribute("age", 5)])
	}

	// A suppressed experiment skips the audience entirely, like JavaScript and the collector: a
	// later attribute change cannot rebuild it and its exposure stays the holdout's alone.
	@Test func suppressedExperimentSkipsAudienceEvaluation() {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_held_audience", holdoutIds: [11],
						audience: "{\"filter\":[{\"gte\":[{\"var\":\"age\"},{\"value\":20}]}]}", audienceStrict: true)
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))
		context.setAttribute("age", to: 5)

		#expect(context.treatment(for: "exp_held_audience") == 0)
		context.setAttribute("age", to: 50)
		#expect(context.treatment(for: "exp_held_audience") == 0)
		#expect(h.exposures == [H.held(11, "holdout_a", 0)])
	}

	// The arm is hashed with the covered experiment's unit type, never the holdout's own (scenario 227).
	@Test func holdoutArmUsesTheCoveredExperimentsUnitType() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_session", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_user", unitType: "user_id", seeds: H.holdoutA)]),
			units: [UnitType.userID: H.uidNotHeldOut])

		// `uid` (session_id) is held out by these seeds; `uidNotHeldOut` (user_id) would not be.
		#expect(context.treatment(for: "exp_session") == 0)
		#expect(h.exposures == [H.held(11, "holdout_user", 0, unitType: "session_id")])
	}

	// Arity comes from the split's length, never `holdoutType` (scenario 222).
	@Test(arguments: [nil, "full", "all_full_on", "unknown"] as [String?])
	func arityComesFromSplitNotHoldoutType(holdoutType: String?) {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_non_fullon", holdoutIds: [21]),
					H.experiment(2, "exp_fullon", fullOnVariant: 2, holdoutIds: [21]),
				],
				holdouts: [H.holdout(21, "h", seeds: H.threeArm1, split: H.threeArmSplit, holdoutType: holdoutType)]))
		#expect(context.treatment(for: "exp_non_fullon") == 0)
		#expect(context.treatment(for: "exp_fullon") == 2)
	}

	// A two-arm split read as "all_full_on" keeps arm 1 as "not held out".
	@Test func twoArmSplitTypedAllFullOnKeepsArmOneNotHeldOut() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_two_arm", holdoutIds: [11])],
				holdouts: [H.holdout(11, "h", seeds: H.holdoutB, holdoutType: "all_full_on")]))
		#expect(context.treatment(for: "exp_two_arm") == H.normalVariant)
	}

	// A 4-arm holdout: only arm 0 holds out (arm 1's full-on rule is for exactly 3 arms).
	@Test func isHeldOutByTable() {
		for fullOnVariant in [0, 2] {
			#expect(ContextState.isHeldOutBy(0, armCount: 2, fullOnVariant: fullOnVariant))
			#expect(ContextState.isHeldOutBy(0, armCount: 3, fullOnVariant: fullOnVariant))
			#expect(ContextState.isHeldOutBy(0, armCount: 4, fullOnVariant: fullOnVariant))
			#expect(!ContextState.isHeldOutBy(1, armCount: 2, fullOnVariant: fullOnVariant))
			#expect(!ContextState.isHeldOutBy(1, armCount: 4, fullOnVariant: fullOnVariant))
			#expect(!ContextState.isHeldOutBy(2, armCount: 3, fullOnVariant: fullOnVariant))
		}
		#expect(ContextState.isHeldOutBy(1, armCount: 3, fullOnVariant: 0))
		#expect(!ContextState.isHeldOutBy(1, armCount: 3, fullOnVariant: 2))
	}

	// A 4-arm holdout through a context: arm 1 does not hold out a non-full-on experiment.
	@Test func fourArmHoldoutArmOneDoesNotHoldOut() {
		let split = [0.25, 0.25, 0.25, 0.25]
		let assigner = VariantAssigner(unitHash: Hashing.hashUnit(H.uid))
		let seedLo = try! #require((0..<200).first { assigner.assign(split, seedHi: 0, seedLo: $0) == 1 })
		let context = HoldoutEnv().context(
			H.contextData(
				[H.experiment(1, "exp_four_arm", holdoutIds: [31])],
				holdouts: [H.holdout(31, "holdout_four_arm", seeds: (0, seedLo), split: split)]))
		#expect(context.treatment(for: "exp_four_arm") == H.normalVariant)
	}

	// H6: one holdout covering experiments with two unit types publishes one exposure per unit type.
	@Test func sharedHoldoutAcrossUnitTypesPublishesPerUnitType() {
		let env = HoldoutEnv()
		let context = env.context(
			H.contextData(
				[
					H.experiment(1, "exp_session", holdoutIds: [11]),
					H.experiment(2, "exp_user", unitType: "user_id", holdoutIds: [11]),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), units: [UnitType.userID: H.uidNotHeldOut]
		)

		#expect(context.treatment(for: "exp_session") == 0)
		#expect(context.treatment(for: "exp_user") == 0)
		#expect(
			env.exposures == [
				H.held(11, "holdout_a", 0), H.own(2, "exp_user", 0, unitType: "user_id"),
				H.held(11, "holdout_a", 1, unitType: "user_id"),
			])
	}

	@Test func failedContextHasNoHoldouts() async {
		let context = await HoldoutEnv().env.failedContext("boom", units: [UnitType.sessionID: H.uid])

		#expect(context.contextData?.holdouts == nil)
		#expect(context.treatment(for: "exp") == 0)
	}

	@Test func setDataDoesNotMutateCallerSuppliedHoldoutIds() {
		let data = H.contextData(
			[H.experiment(1, "exp_holdout_no_mutate_in", holdoutIds: [12, 11]), H.experiment(2, "exp_not_covered")],
			holdouts: [H.holdout(11, "holdout_no_mutate", seeds: H.holdoutA)])
		let env = HoldoutEnv()
		let context = env.context(data)

		#expect(context.treatment(for: "exp_holdout_no_mutate_in") == 0)
		#expect(context.treatment(for: "exp_not_covered") == H.normalVariant)
		#expect(data.experiments[0].holdoutIds == [12, 11])
		#expect(context.contextData?.experiments[0].holdoutIds == [12, 11])
	}

	// MARK: - Switchbacks

	// Holdouts never apply to a switchback (cross-sdk scenario 417's data): the holdout's split [1, 0]
	// holds every unit out, yet the switchback is neither suppressed nor fires the holdout. This SDK
	// does not serve switchbacks yet, so the experiment resolves on its ordinary path.
	@Test func holdoutsNeverApplyToASwitchback() {
		var switchback = H.experiment(410, "exp_sb_holdout_ignored", holdoutIds: [1], split: [0.0, 1.0])
		switchback["randomizationType"] = "switchback"
		switchback["switchbackClusters"] = ["session_id": "city"]
		var plain = H.experiment(411, "exp_plain_covered", holdoutIds: [1], split: [0.0, 1.0])
		plain["randomizationType"] = "unit"
		let data = H.contextData(
			[switchback, plain], holdouts: [H.holdout(1, "holdout_sb_everyone", seeds: H.holdoutA, split: [1.0, 0.0])])
		let env = HoldoutEnv()
		let context = env.context(data)

		#expect(context.treatment(for: "exp_sb_holdout_ignored") == 1)
		#expect(env.exposures == [H.own(410, "exp_sb_holdout_ignored", 1)])
		// The same holdout still applies to a covered experiment of another randomization type.
		#expect(context.treatment(for: "exp_plain_covered") == 0)
		#expect(env.exposures == [H.own(410, "exp_sb_holdout_ignored", 1), H.held(1, "holdout_sb_everyone", 0)])
	}
}
