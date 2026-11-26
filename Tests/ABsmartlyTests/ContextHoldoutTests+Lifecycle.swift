import Foundation
import Testing

@testable import ABsmartly

private typealias H = Holdouts

// Holdouts over the life of a context: refreshes, late units and the arm pinned with each assignment.
extension ContextHoldoutTests {
	// MARK: - Refresh

	// A same-iteration seed edit must not move an exposed unit into the other arm.
	@Test func refreshWithSeedChangeSameIterationKeepsUnitInOriginalArmAndDoesNotReExpose() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_seed_thrash", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_seed_thrash") == 0)
		#expect(context.pendingEventCount == 1)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_holdout_seed_thrash", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_holdout_seed_thrash") == 0)
		#expect(context.pendingEventCount == 1)
	}

	@Test func refreshWithCosmeticHoldoutEditDoesNotReExposeHeldOutUnit() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_cosmetic", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_cosmetic") == 0)
		#expect(context.pendingEventCount == 1)

		var renamed = H.holdout(11, "holdout_a_renamed", seeds: H.holdoutA)
		renamed["applications"] = [["name": "website"]]
		renamed["variants"] = [["name": "Control", "config": NSNull()], ["name": "HeldOut", "config": NSNull()]]
		try await h.refresh(
			context, H.contextData([H.experiment(1, "exp_holdout_cosmetic", holdoutIds: [11])], holdouts: [renamed]))

		#expect(context.treatment(for: "exp_holdout_cosmetic") == 0)
		#expect(context.pendingEventCount == 1)
	}

	@Test func refreshWithCosmeticHoldoutEditDoesNotDuplicateCoveredExperimentExposure() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_cosmetic_covered", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), uid: H.uidNotHeldOut)

		#expect(context.treatment(for: "exp_holdout_cosmetic_covered") == 0)
		#expect(context.pendingEventCount == 2)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_holdout_cosmetic_covered", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a_renamed", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_cosmetic_covered") == 0)
		#expect(context.pendingEventCount == 2)
	}

	// An iteration bump is a new epoch: the unit is re-assigned once and exposed once in it.
	@Test func refreshWithIterationBumpReassignsToExactlyOneNewArm() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_iteration", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_holdout_iteration") == H.normalVariant)
		#expect(context.pendingEventCount == 2)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_holdout_iteration", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA, iteration: 2)]))

		#expect(context.treatment(for: "exp_holdout_iteration") == 0)
		#expect(context.pendingEventCount == 3)
		#expect(context.treatment(for: "exp_holdout_iteration") == 0)
		#expect(context.pendingEventCount == 3)
	}

	// A covered experiment first evaluated after a same-iteration seed edit reads the pinned arm.
	@Test func refreshedSeedDoesNotDesyncSuppressionFromPinnedHoldoutArmForNewlyEvaluatedExperiment() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_desync_a", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_desync_a") == 0)
		#expect(context.pendingEventCount == 1)

		try await h.refresh(
			context,
			H.contextData(
				[
					H.experiment(1, "exp_holdout_desync_a", holdoutIds: [11]),
					H.experiment(2, "exp_holdout_desync_b", holdoutIds: [11]),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_holdout_desync_b") == 0)
		#expect(context.treatment(for: "exp_holdout_desync_a") == 0)

		try await h.expectPublished(context, [H.held(11, "holdout_a", 0)])
	}

	// Arm 1 under 2 arms defers to normal assignment; a same-iteration change to 3 arms must not
	// re-mean it as "full-on only".
	@Test func refreshFromTwoArmToThreeArmSameIterationDoesNotReinterpretDeferringArmAsFullOnOnly() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_arity_2to3_a", holdoutIds: [31])],
				holdouts: [H.holdout(31, "holdout_arity", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_arity_2to3_a") == H.normalVariant)

		try await h.refresh(
			context,
			H.contextData(
				[
					H.experiment(1, "exp_arity_2to3_a", holdoutIds: [31]),
					H.experiment(2, "exp_arity_2to3_b", holdoutIds: [31]),
				], holdouts: [H.threeArmHoldout(31, "holdout_arity", seeds: H.threeArm1)]))

		#expect(context.treatment(for: "exp_arity_2to3_b") == H.normalVariant)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_arity_2to3_a", H.normalVariant), H.held(31, "holdout_arity", 1),
				H.own(2, "exp_arity_2to3_b", H.normalVariant),
			])
	}

	@Test func refreshFromThreeArmToTwoArmSameIterationKeepsFullOnOnlyArmSuppressingNonFullOnExperiment()
		async throws
	{
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_arity_3to2_a", holdoutIds: [41])],
				holdouts: [H.threeArmHoldout(41, "holdout_arity_rev", seeds: H.threeArm1)]))

		#expect(context.treatment(for: "exp_arity_3to2_a") == 0)
		#expect(context.pendingEventCount == 1)

		try await h.refresh(
			context,
			H.contextData(
				[
					H.experiment(1, "exp_arity_3to2_a", holdoutIds: [41]),
					H.experiment(2, "exp_arity_3to2_b", holdoutIds: [41]),
				], holdouts: [H.holdout(41, "holdout_arity_rev", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_arity_3to2_b") == 0)

		try await h.expectPublished(context, [H.held(41, "holdout_arity_rev", 1)])
	}

	@Test func experimentsEvaluatedBeforeAndAfterSameIterationArityChangeAgreeOnSuppression() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_arity_consistency_pre", holdoutIds: [71])],
				holdouts: [H.holdout(71, "holdout_arity_consistency", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_arity_consistency_pre") == H.normalVariant)

		try await h.refresh(
			context,
			H.contextData(
				[
					H.experiment(1, "exp_arity_consistency_pre", holdoutIds: [71]),
					H.experiment(2, "exp_arity_consistency_post", holdoutIds: [71]),
				], holdouts: [H.threeArmHoldout(71, "holdout_arity_consistency", seeds: H.threeArm1)]))

		#expect(context.treatment(for: "exp_arity_consistency_post") == H.normalVariant)
		#expect(context.treatment(for: "exp_arity_consistency_pre") == H.normalVariant)
	}

	// 1.5.0 refreshed from the logger while the experiment's own exposure was delivered (between the
	// suppression decision and the holdout trigger). In 2.x every exposure of a read is queued in the
	// read's critical section before the logger runs, so a refresh started by the logger lands after
	// both; the published pair still comes from one epoch.
	@Test func triggerFiresHoldoutExposureFromDecisionEpochDespiteRefreshRacingBetweenDecisionAndTrigger()
		async throws
	{
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_epoch_race", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_h", seeds: H.holdoutB)]))
		let refreshed = H.contextData(
			[H.experiment(1, "exp_epoch_race", holdoutIds: [11])],
			holdouts: [H.holdout(11, "holdout_h", seeds: H.holdoutA, iteration: 2)])
		h.env.serveNext(refreshed)
		let refreshing = Box<Task<Void, any Error>?>(nil)
		h.env.log.setHook { context, event in
			if case .exposure(let exposure) = event, exposure.id == 1 {
				refreshing.value = Task { try await context.refresh() }
			}
		}

		#expect(context.treatment(for: "exp_epoch_race") == H.normalVariant)
		h.env.log.setHook(nil)
		// The logger-started refresh must have run and succeeded, or this pins nothing.
		try await #require(refreshing.value).value
		#expect(h.env.getCount == 1)

		try await h.expectPublished(
			context, [H.own(1, "exp_epoch_race", H.normalVariant), H.held(11, "holdout_h", 1)])
	}

	// 1.5.0 injected a refresh between an assignment lookup's experiment read and its arm draw
	// (`afterExperimentLookup`). In 2.x the whole lookup runs under the context's one lock and a
	// refresh installs its index under the same lock, so they cannot interleave; this pins the
	// epoch accounting of a refresh between two reads, from many threads at once.
	@Test func refreshDuringAssignmentResolutionDoesNotPairEpochs() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_race", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_race", seeds: H.holdoutB)]))
		let refreshed = H.contextData(
			[H.experiment(1, "exp_race", holdoutIds: [11])],
			holdouts: [H.holdout(11, "holdout_race", seeds: H.holdoutB, iteration: 2)])

		h.env.serveNext(refreshed)
		async let refresh: Void = context.refresh()
		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<8 {
				group.addTask { _ = context.treatment(for: "exp_race") }
			}
		}
		try await refresh
		#expect(context.treatment(for: "exp_race") == H.normalVariant)
		#expect(context.treatment(for: "exp_race") == H.normalVariant)

		// Each epoch publishes the experiment's exposure with its own holdout exposure, and repeated
		// reads in an epoch add nothing. The reads may all land before or after the refresh.
		// Checked on the published batch: logger delivery order across threads is not the queue order.
		let published = try await h.publishedExposures(context)
		let ids = published.map(\.id)
		#expect(ids == [1, 11, 1, 11] || ids == [1, 11])
		#expect(published.filter { $0.id == 11 }.allSatisfy { $0.variant == 1 })
	}

	// The refresh variant of the race above, deterministic: an iteration-2 holdout installed between
	// two reads gives a second (experiment, holdout) pair, never a lone holdout exposure.
	@Test func refreshBetweenReadsPublishesOnePairPerEpoch() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_race", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_race", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_race") == H.normalVariant)
		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_race", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_race", seeds: H.holdoutB, iteration: 2)]))
		#expect(context.treatment(for: "exp_race") == H.normalVariant)
		#expect(context.treatment(for: "exp_race") == H.normalVariant)

		#expect(h.exposures.map(\.id) == [1, 11, 1, 11])
	}

	// MARK: - Late units

	// Peeking without the unit pins a missing holdout arm; setUnit must evict that so the holdout's
	// exposure is not lost forever.
	@Test func setUnitInvalidatesNullHoldoutSnapshotSoTheHoldoutExposureIsNotLostForever() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_null_snapshot_fullon", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_user_id", unitType: "user_id", seeds: H.holdoutB)]), uid: nil)

		#expect(context.treatment(for: "exp_null_snapshot_fullon", exposing: false) == 2)

		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_null_snapshot_fullon") == 2)
		#expect(context.pendingEventCount == 2)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_null_snapshot_fullon", 2, unitType: "user_id", fullOn: true),
				H.held(11, "holdout_user_id", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	@Test func setUnitDoesNotEvictAlreadyExposedAssignmentSoNoDuplicateExposure() throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_exposed_before_unit", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_user_id", unitType: "user_id", seeds: H.holdoutB)]), uid: nil)

		#expect(context.treatment(for: "exp_exposed_before_unit") == 2)
		#expect(context.pendingEventCount == 1)

		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_exposed_before_unit") == 2)
		#expect(context.pendingEventCount == 1)
	}

	@Test func setUnitForUnrelatedUnitTypeDoesNotEvictExposedAssignment() throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_unrelated_unit", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_unrelated_unit") == H.normalVariant)
		#expect(context.pendingEventCount == 2)

		try context.setUnit("other_unit_type", to: "some-other-uid")

		#expect(context.treatment(for: "exp_unrelated_unit") == H.normalVariant)
		#expect(context.pendingEventCount == 2)
	}

	@Test func setUnitEvictsOnlyTheAffectedEntryAndLeavesTheOtherUntouched() throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_late_unit", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11]),
					H.experiment(2, "exp_present_unit", holdoutIds: [12]),
				],
				holdouts: [
					H.holdout(11, "holdout_late", unitType: "user_id", seeds: H.holdoutB),
					H.holdout(12, "holdout_present", seeds: H.holdoutB),
				]))

		#expect(context.treatment(for: "exp_late_unit", exposing: false) == 2)
		#expect(context.treatment(for: "exp_present_unit") == H.normalVariant)
		#expect(context.pendingEventCount == 2)

		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_late_unit") == 2)
		#expect(context.pendingEventCount == 4)
		#expect(context.treatment(for: "exp_present_unit") == H.normalVariant)
		#expect(context.pendingEventCount == 4)
	}

	// The missing unit is the covered experiment's, not the holdout's declared unit type.
	@Test func setUnitEvictsUsingTheCoveredExperimentsUnitTypeNotTheHoldoutsDeclaredUnitType() throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_mismatched_unit_type", unitType: "A", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_declares_b", unitType: "B", seeds: H.holdoutB)]), uid: nil)

		#expect(context.treatment(for: "exp_mismatched_unit_type", exposing: false) == 2)

		try context.setUnit("A", to: H.uid)

		#expect(context.treatment(for: "exp_mismatched_unit_type") == 2)
		#expect(context.pendingEventCount == 2)
	}

	// The late holdout holds the unit out: the whole decision is recomputed (full-on -> control), not
	// patched with a contradictory holdout exposure.
	@Test func setUnitRecomputesSuppressionCoherentlyWhenLateResolvedHoldoutSuppresses() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_null_snapshot_suppresses", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])
				],
				holdouts: [H.holdout(11, "holdout_user_id_suppress", unitType: "user_id", seeds: H.holdoutA)]),
			uid: nil)

		#expect(context.treatment(for: "exp_null_snapshot_suppresses", exposing: false) == 2)

		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_null_snapshot_suppresses") == 0)
		#expect(context.pendingEventCount == 1)

		try await h.expectPublished(
			context, [H.held(11, "holdout_user_id_suppress", 0, unitType: "user_id")], unitType: "user_id")
	}

	// Java's detached-assignment tests: Swift resolves and claims an assignment in one critical
	// section, so an assignment read before setUnit cannot be exposed beside its replacement. These
	// pin the same public sequences.
	@Test func detachedTreatmentAssignmentCannotPublishBesideSuppressingReplacement() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_detached_suppressed", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_detached_suppressed", unitType: "user_id", seeds: H.holdoutA)]),
			uid: nil)

		#expect(context.treatment(for: "exp_detached_suppressed", exposing: false) == 2)
		try context.setUnit(.userID, to: H.uid)
		#expect(context.treatment(for: "exp_detached_suppressed") == 0)
		#expect(context.treatment(for: "exp_detached_suppressed") == 0)
		#expect(context.pendingEventCount == 1)

		try await h.expectPublished(
			context, [H.held(11, "holdout_detached_suppressed", 0, unitType: "user_id")], unitType: "user_id")
	}

	@Test func detachedTreatmentAssignmentRetriesCurrentEntryWithoutLosingExposure() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_detached_retry", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_detached_retry", unitType: "user_id", seeds: H.holdoutB)]),
			uid: nil)

		#expect(context.treatment(for: "exp_detached_retry", exposing: false) == 2)
		try context.setUnit(.userID, to: H.uid)
		#expect(context.treatment(for: "exp_detached_retry") == 2)
		#expect(context.pendingEventCount == 2)
		#expect(context.treatment(for: "exp_detached_retry") == 2)
		#expect(context.pendingEventCount == 2)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_detached_retry", 2, unitType: "user_id", fullOn: true),
				H.held(11, "holdout_detached_retry", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	@Test func detachedTreatmentReturnsTheReplacementVariant() throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_detached_variant", unitType: "user_id", fullOnVariant: 2, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_detached_variant", unitType: "user_id", seeds: H.holdoutA)]),
			uid: nil)

		#expect(context.treatment(for: "exp_detached_variant", exposing: false) == 2)
		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_detached_variant") == 0)
		#expect(context.pendingEventCount == 1)
	}

	// Java's settlement-retry tests have no Swift counterpart (resolution and claim share one lock);
	// these pin the public guarantees they protect.
	@Test func repeatedTreatmentReadsExposeOnce() {
		let context = h.context(
			H.contextData([
				H.experiment(1, "exp_first", fullOnVariant: 2), H.experiment(2, "exp_second", fullOnVariant: 1),
				H.experiment(3, "exp_settled", fullOnVariant: 1),
			]))

		for _ in 0..<3 {
			#expect(context.treatment(for: "exp_settled") == 1)
		}
		#expect(context.pendingEventCount == 1)
	}

	@Test func peekOnFullOnExperimentExposesNothing() {
		let context = h.context(H.contextData([H.experiment(1, "exp_bounded_retry", fullOnVariant: 1)]))

		#expect(context.treatment(for: "exp_bounded_retry", exposing: false) == 1)
		#expect(context.pendingEventCount == 0)
	}

	@Test func detachedVariableAssignmentReresolvesTheKeyToANewWinningExperiment() async throws {
		let original = H.experiment(
			2, "exp_detached_variable_old", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
			configs: [nil, "{\"detached_var\":\"old\"}"])
		let holdout = H.holdout(11, "holdout_detached_variable", unitType: "user_id", seeds: H.holdoutB)
		let context = h.context(H.contextData([original], holdouts: [holdout]), uid: nil)

		#expect(h.value(context, "detached_var", peek: true) == "old")
		try context.setUnit(.userID, to: H.uid)

		let winner = H.experiment(
			1, "exp_detached_variable_winner", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
			configs: [nil, "{\"detached_var\":\"new winner\"}"])
		try await h.refresh(context, H.contextData([winner, original], holdouts: [holdout]))

		#expect(h.value(context, "detached_var") == "new winner")
		#expect(context.pendingEventCount == 2)
		#expect(h.value(context, "detached_var") == "new winner")
		#expect(context.pendingEventCount == 2)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_detached_variable_winner", 1, unitType: "user_id", fullOn: true),
				H.held(11, "holdout_detached_variable", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	// An exposed assignment keeps its missing holdout arm: reading it again through a variable key
	// must not resolve the holdout live and publish a contradictory "held out" exposure.
	@Test func triggerApplicableHoldoutExposuresNeverLiveResolvesAPinnedNullEntryForAnAlreadyExposedAssignment()
		throws
	{
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_a_mutant_pinned_null", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
						configs: [nil, "{\"my_var\":\"value_from_variant\"}"])
				],
				holdouts: [H.holdout(11, "holdout_a_mutant_pinned_null", unitType: "user_id", seeds: H.holdoutA)]),
			uid: nil)

		#expect(context.treatment(for: "exp_a_mutant_pinned_null") == 1)
		#expect(context.pendingEventCount == 1)

		try context.setUnit(.userID, to: H.uid)

		#expect(h.value(context, "my_var") == "value_from_variant")
		#expect(context.pendingEventCount == 1)
	}

	@Test func setUnitEvictsAssignmentWithMultipleHoldoutsDeclaringDifferentUnitTypes() throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_multi_holdout_unit_types", unitType: "user_id", fullOnVariant: 2,
						holdoutIds: [11, 12, 13])
				],
				holdouts: [
					H.holdout(11, "holdout_11", unitType: "type_x", seeds: H.holdoutB),
					H.holdout(12, "holdout_12", unitType: "type_y", seeds: H.holdoutB),
					H.holdout(13, "holdout_13", unitType: "user_id", seeds: H.holdoutB),
				]), uid: nil)

		#expect(context.treatment(for: "exp_multi_holdout_unit_types", exposing: false) == 2)

		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_multi_holdout_unit_types") == 2)
		#expect(context.pendingEventCount == 4)
	}

	// One holdout covering two unit types keeps an arm and exposure state per unit type: the A1 -> B
	// -> A2 alternation must publish the holdout once per unit type, not three times.
	@Test func oneHoldoutCoveringTwoUnitTypesKeepsIndependentExposureStatePerUnitType() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_unit_a1", unitType: "user_id", holdoutIds: [11]),
					H.experiment(2, "exp_unit_b", unitType: "session_id", holdoutIds: [11]),
					H.experiment(3, "exp_unit_a2", unitType: "user_id", holdoutIds: [11]),
				], holdouts: [H.holdout(11, "holdout_shared", unitType: "user_id", seeds: H.holdoutB)]),
			units: [.userID: H.uid])

		#expect(context.treatment(for: "exp_unit_a1") == H.normalVariant)
		#expect(context.treatment(for: "exp_unit_b") == H.normalVariant)
		#expect(context.treatment(for: "exp_unit_a2") == H.normalVariant)
		#expect(context.pendingEventCount == 5)

		let exposures = try await h.publishedExposures(context)
		#expect(exposures.count == 5)
		#expect(
			exposures.filter { $0.id == 11 } == [
				H.held(11, "holdout_shared", 1, unitType: "user_id"),
				H.held(11, "holdout_shared", 1, unitType: "session_id"),
			])
	}

	@Test func setUnitWithNoCachedAssignmentDoesNotThrowAndSubsequentAssignmentIsNormal() throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_no_prior_assignment", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]), uid: nil)

		try context.setUnit(.sessionID, to: H.uid)

		#expect(context.treatment(for: "exp_no_prior_assignment") == H.normalVariant)
	}

	@Test func setUnitCalledTwiceWithSameUidIsANoOpAndDoesNotThrow() throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_set_unit_twice", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_set_unit_twice") == H.normalVariant)
		#expect(context.pendingEventCount == 2)

		try context.setUnit(.sessionID, to: H.uid)

		#expect(context.treatment(for: "exp_set_unit_twice") == H.normalVariant)
		#expect(context.pendingEventCount == 2)
		#expect(h.errors.isEmpty)
	}

	// A fully resolved (no missing arm) unexposed assignment survives a redundant setUnit. The
	// same-iteration split edit makes a wrongly evicted entry land on a different variant.
	@Test func setUnitRedundantCallDoesNotEvictFullyResolvedUnexposedHoldoutSnapshot() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_redundant_set_unit", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_redundant_set_unit", exposing: false) == H.normalVariant)
		#expect(context.pendingEventCount == 0)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_redundant_set_unit", holdoutIds: [11], split: [1.0, 0.0])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		try context.setUnit(.sessionID, to: H.uid)

		#expect(context.treatment(for: "exp_redundant_set_unit") == H.normalVariant)
		#expect(context.pendingEventCount == 2)

		try await h.expectPublished(
			context, [H.own(1, "exp_redundant_set_unit", H.normalVariant), H.held(11, "holdout_a", 1)])
	}

	@Test func peekVariableValueThenSetUnitThenGetVariableValueRecomputesUnderLateSuppressingHoldout()
		async throws
	{
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_var_late_unit_suppress", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11],
						configs: [nil, "{\"my_var\":\"value_from_variant\"}"])
				], holdouts: [H.holdout(11, "holdout_var_late", unitType: "user_id", seeds: H.holdoutA)]),
			uid: nil)

		#expect(h.value(context, "my_var", peek: true) == "value_from_variant")
		#expect(context.pendingEventCount == 0)

		try context.setUnit(.userID, to: H.uid)

		// Suppressed: the control variant has no `my_var`, so the default is returned.
		#expect(h.value(context, "my_var") == "default")
		#expect(context.pendingEventCount == 1)

		try await h.expectPublished(
			context, [H.held(11, "holdout_var_late", 0, unitType: "user_id")], unitType: "user_id")
	}

	// An override is not evicted by a late unit, but its holdout arms are resolved again when it is
	// exposed: like JavaScript, the override assignment is rebuilt because its arm was missing.
	@Test func setUnitDoesNotEvictOverrideAssignmentAndHoldoutResolvesLiveAtExposureTime() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_override_late_unit", unitType: "user_id", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_override_late", unitType: "user_id", seeds: H.holdoutB)]),
			uid: nil, overrides: ["exp_override_late_unit": 3])

		#expect(context.treatment(for: "exp_override_late_unit", exposing: false) == 3)

		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_override_late_unit") == 3)
		#expect(context.pendingEventCount == 2)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_override_late_unit", 3, unitType: "user_id", assigned: false, overridden: true),
				H.held(11, "holdout_override_late", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	@Test func setUnitEvictsNullSnapshotForCustomAssignmentAndCustomAppliesAfterRecompute() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_custom_late_unit", unitType: "user_id", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_custom_late", unitType: "user_id", seeds: H.holdoutB)]),
			uid: nil, customAssignments: ["exp_custom_late_unit": 3])

		#expect(context.treatment(for: "exp_custom_late_unit", exposing: false) == 0)

		try context.setUnit(.userID, to: H.uid)

		#expect(context.treatment(for: "exp_custom_late_unit") == 3)
		#expect(context.pendingEventCount == 2)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_custom_late_unit", 3, unitType: "user_id", custom: true),
				H.held(11, "holdout_custom_late", 1, unitType: "user_id"),
			], unitType: "user_id")
	}

	// MARK: - Cache invariants

	// 1.5.0 resolved a stale holdout reference (an older iteration's definition) through a DEBUG hook
	// and checked it returned the live, exposed entry. In 2.x an assignment draws arms from the
	// definitions of the index it was resolved with, and the arm cache is keyed by (id, unit type) and
	// checked by iteration, so the observable invariant is that the iteration-2 arm, once exposed, is
	// never redrawn or re-exposed by a later read of either experiment.
	@Test func staleHoldoutReferenceNeverOverwritesNewerPinnedCacheEntry() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_f", holdoutIds: [11])], holdouts: [H.holdout(11, "holdout_h", seeds: H.holdoutA)])
		)

		#expect(context.treatment(for: "exp_f") == 0)
		#expect(context.pendingEventCount == 1)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_f", holdoutIds: [11]), H.experiment(2, "exp_g", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_h", seeds: H.holdoutB, iteration: 2)]))

		#expect(context.treatment(for: "exp_g") == H.normalVariant)
		#expect(context.pendingEventCount == 3)
		// exp_f is rebuilt for iteration 2 and reuses the exposed iteration-2 arm.
		#expect(context.treatment(for: "exp_f") == H.normalVariant)
		#expect(context.pendingEventCount == 4)

		try await h.expectPublished(
			context,
			[
				H.held(11, "holdout_h", 0), H.own(2, "exp_g", H.normalVariant), H.held(11, "holdout_h", 1),
				H.own(1, "exp_f", H.normalVariant),
			])
	}

	// The arm count is pinned with the arm from the live split: a 3-arm iteration-2 holdout reads arm 1
	// as "full-on only" even though the context first saw it with 2 arms (1.5.0 checked this through a
	// stale-reference DEBUG hook; 2.x never holds a stale reference).
	@Test func staleHoldoutReferencePinsTheLiveArmCount() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_a")], holdouts: [H.holdout(21, "holdout_arity_stale", seeds: H.holdoutB)]))

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_a"), H.experiment(2, "exp_b", holdoutIds: [21])],
				holdouts: [
					H.holdout(
						21, "holdout_arity_stale", seeds: H.threeArm1, split: H.threeArmSplit, holdoutType: nil,
						iteration: 2)
				]))

		#expect(context.treatment(for: "exp_b") == 0)
		try await h.expectPublished(context, [H.held(21, "holdout_arity_stale", 1)])
	}

	// An up-to-date override stays cached when a refresh removes its experiment, as in JavaScript and
	// Java: an exposed one is not exposed again, and a peeked one still publishes its pinned exposures.
	@Test(arguments: [false, true])
	func overrideKeepsItsCachedAssignmentWhenTheExperimentIsRemoved(peekFirst: Bool) async throws {
		let data = H.contextData(
			[H.experiment(1, "exp_gone", holdoutIds: [11])],
			holdouts: [H.holdout(11, "holdout_gone", seeds: H.holdoutA)])
		let own = H.own(1, "exp_gone", 1, assigned: false, overridden: true)

		let context = h.context(data, overrides: ["exp_gone": 1])
		#expect(context.treatment(for: "exp_gone", exposing: !peekFirst) == 1)
		try await h.refresh(context, H.contextData([]))
		#expect(context.treatment(for: "exp_gone") == 1)
		#expect(h.exposures == [own, H.held(11, "holdout_gone", 0)])
	}

	// A same-iteration rename keeps the arm, and the exposure carries the name of the definition the
	// assignment was resolved with, as in JavaScript.
	@Test func holdoutExposureUsesTheResolvedDefinitionsName() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_a", holdoutIds: [11])], holdouts: [H.holdout(11, "old_name", seeds: H.holdoutA)]))
		#expect(context.treatment(for: "exp_a", exposing: false) == 0)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_a", holdoutIds: [11]), H.experiment(2, "exp_b", holdoutIds: [11])],
				holdouts: [H.holdout(11, "new_name", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_b") == 0)
		#expect(h.exposures == [H.held(11, "new_name", 0)])
		// exp_a was resolved with the old definition, whose name its pinned arm is published under; the
		// arm is already exposed, so nothing more is queued.
		#expect(context.treatment(for: "exp_a") == 0)
		#expect(h.exposures == [H.held(11, "new_name", 0)])
	}

	// 1.5.0's publisher (handler) waited on a refresh from inside publish. In 2.x the transport is
	// called outside the context's lock, so a transport that waits for a refresh to finish completes.
	@Test func publisherWaitingOnRefreshDoesNotDeadlock() async throws {
		let context = h.context(H.contextData([H.experiment(1, "exp_a")]))
		h.env.transport.enqueue { _ in
			// The refresh's GET is served by the default handler.
			try await context.refresh()
			return HTTPResponse(statusCode: 200, body: Data("{}".utf8))
		}
		context.track("goal")
		try await withTimeout(10) { try await context.publish() }
		#expect(h.env.publishCount == 1)
		#expect(h.env.getCount == 1)
	}

	// The override fast path revalidates coverage too: a holdout added by a refresh rebuilds the
	// overridden assignment (re-exposing it) and fires the new holdout.
	@Test func holdoutBecomingApplicableAfterRefreshStillFiresForOverriddenExperiment() async throws {
		let context = h.context(
			H.contextData([H.experiment(1, "exp_override_late_holdout")]), overrides: ["exp_override_late_holdout": 3])

		#expect(context.treatment(for: "exp_override_late_holdout") == 3)
		#expect(context.pendingEventCount == 1)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_override_late_holdout", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_late", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_override_late_holdout") == 3)
		#expect(context.pendingEventCount == 3)

		let own = H.own(1, "exp_override_late_holdout", 3, assigned: false, overridden: true)
		try await h.expectPublished(context, [own, own, H.held(11, "holdout_late", 0)])
	}

	// Deduplicated coverage is the same coverage: dropping the duplicate on refresh is not a change
	// and must not re-expose the experiment.
	@Test func refreshDroppingDuplicateHoldoutIdDoesNotReExpose() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_dup", holdoutIds: [11, 11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_dup") == H.normalVariant)
		#expect(context.pendingEventCount == 2)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_dup", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		#expect(context.treatment(for: "exp_dup") == H.normalVariant)
		#expect(context.pendingEventCount == 2)
	}

	@Test func refreshRemovingCoverageReResolvesExperiment() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_cov", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_cov") == 0)
		#expect(context.pendingEventCount == 1)

		try await h.refresh(
			context,
			H.contextData([H.experiment(1, "exp_cov")], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_cov") == H.normalVariant)
		#expect(h.exposures == [H.held(11, "holdout_a", 0), H.own(1, "exp_cov", H.normalVariant)])
	}

	// JavaScript: a refresh adding a holdout that does not hold the unit out still rebuilds the
	// exposed experiment (the coverage changed) and re-publishes its own exposure, plus the holdout's.
	@Test func duplicatesTheCoveredExperimentsOwnExposureWhenARefreshAddsANonSuppressingHoldout() async throws {
		let context = h.context(H.contextData([H.experiment(1, "exp_holdout_added_non_suppressing", fullOnVariant: 1)]))

		#expect(context.treatment(for: "exp_holdout_added_non_suppressing") == 1)
		#expect(context.pendingEventCount == 1)

		try await h.refresh(
			context,
			H.contextData(
				[H.experiment(1, "exp_holdout_added_non_suppressing", fullOnVariant: 1, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_non_suppressing", seeds: H.holdoutA, split: [0.0, 1.0])]))

		#expect(context.treatment(for: "exp_holdout_added_non_suppressing") == 1)
		let exposures = try await h.publishedExposures(context)
		#expect(exposures.filter { $0.name == "exp_holdout_added_non_suppressing" }.count == 2)
		#expect(exposures.filter { $0.name == "holdout_non_suppressing" }.count == 1)
	}

	// JavaScript: treatment() (not a peek) on a full-on experiment before its unit is set exposes it
	// with a missing holdout arm; the exposed assignment is kept on setUnit, so the holdout exposure
	// for that unit is never published (java-sdk parity, documented in JavaScript).
	@Test func permanentlyLosesAHoldoutsExposureWhenTreatmentResolvesAFullOnExperimentBeforeItsUnitIsSet() throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_lost", unitType: "user_id", fullOnVariant: 1, holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_lost", unitType: "user_id", seeds: H.holdoutB)]), uid: nil)

		#expect(context.treatment(for: "exp_lost") == 1)
		try context.setUnit(.userID, to: H.uid)
		#expect(context.treatment(for: "exp_lost") == 1)
		#expect(h.exposures == [H.own(1, "exp_lost", 1, unitType: "user_id", fullOn: true)])
	}

	@Test func publishKeepsHoldoutExposureState() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_a", holdoutIds: [11]), H.experiment(2, "exp_b", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutB)]))

		_ = context.treatment(for: "exp_a")
		try await context.publish()
		_ = context.treatment(for: "exp_a")
		_ = context.treatment(for: "exp_b")

		try await h.expectPublished(context, [H.own(2, "exp_b", H.normalVariant)])
	}
}
