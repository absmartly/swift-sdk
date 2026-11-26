import Foundation
import Testing

@testable import ABsmartly

private typealias H = Holdouts

// Holdouts on the variable path, assignment rules over holdouts, and the event logger: the rest of
// 1.5.0's `ContextHoldoutTest`.
extension ContextHoldoutTests {
	// MARK: - Variables

	@Test(arguments: [(H.uid, 1), (H.uidNotHeldOut, 2)])
	func variableLookupFiresHoldoutExposureForBothHeldOutAndNonHeldOutUnits(uid: String, pending: Int) {
		let h = HoldoutEnv()
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_var", holdoutIds: [11], configs: [nil, "{\"var_a\":\"value_a\"}"])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]), uid: uid)

		#expect(h.value(context, "var_a") == "default")
		#expect(context.pendingEventCount == pending)
	}

	@Test func variableKeyResolutionSkipsSuppressedAssignmentInFavorOfAssignedOne() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_var_key_suppressed", holdoutIds: [11],
						configs: [nil, "{\"shared\":\"from_suppressed\"}"]),
					H.experiment(2, "exp_var_key_assigned", configs: [nil, "{\"shared\":\"from_assigned\"}"]),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(h.value(context, "shared") == "from_assigned")

		try await h.expectPublished(
			context, [H.held(11, "holdout_a", 0), H.own(2, "exp_var_key_assigned", H.normalVariant)])
	}

	@Test func peekVariableValueNeverTriggersHoldoutExposureForEvaluatedCandidates() {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_var_key_peek_suppressed", holdoutIds: [11],
						configs: [nil, "{\"shared_peek\":\"from_suppressed\"}"]),
					H.experiment(
						2, "exp_var_key_peek_assigned", configs: [nil, "{\"shared_peek\":\"from_assigned\"}"]),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(h.value(context, "shared_peek", peek: true) == "from_assigned")
		#expect(context.pendingEventCount == 0)
	}

	// A suppressed candidate's control value is the fallback for a shared key (scenario 226) and is
	// captured from the first suppressed candidate only.
	@Test func suppressedFallbackIsTheFirstSuppressedCandidatesControlValue() {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_first", holdoutIds: [11], configs: ["{\"other\":0}", "{\"k\":\"t1\"}"]),
					H.experiment(2, "exp_second", holdoutIds: [11], configs: ["{\"k\":\"c2\"}", "{\"k\":\"t2\"}"]),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		// exp_first is held out but its control lacks `k`; a later suppressed candidate cannot win.
		#expect(h.value(context, "k") == "default")

		let second = HoldoutEnv()
		let context2 = second.context(
			H.contextData(
				[H.experiment(2, "exp_second", holdoutIds: [11], configs: ["{\"k\":\"c2\"}", "{\"k\":\"t2\"}"])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))
		#expect(second.value(context2, "k", peek: true) == "c2")
		#expect(second.value(context2, "k") == "c2")
		#expect(second.exposures == [H.held(11, "holdout_a", 0)])
	}

	// H8: the first candidate is suppressed and the second is assigned; the assigned one wins and
	// both candidates' holdouts fire.
	@Test func sharedKeyAssignedCandidateWinsOverSuppressedAndBothHoldoutsFire() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_suppressed", holdoutIds: [11], configs: H.withVariables("k")),
					H.experiment(2, "exp_assigned", holdoutIds: [12], configs: H.withVariables("k")),
				],
				holdouts: [
					H.holdout(11, "holdout_a", seeds: H.holdoutA), H.holdout(12, "holdout_b", seeds: H.holdoutB),
				]))

		#expect(h.value(context, "k") == "treatment")

		try await h.expectPublished(
			context,
			[
				H.held(11, "holdout_a", 0), H.held(12, "holdout_b", 1), H.own(2, "exp_assigned", H.normalVariant),
			])
	}

	// One covered, not-held-out candidate: its holdout's exposure is queued before its own, as in
	// javascript-sdk and 1.5.0 (`treatment(for:)` queues the experiment first).
	@Test func variableReadQueuesTheWinnersHoldoutBeforeItsOwnExposure() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_single", holdoutIds: [12], configs: H.withVariables("k"))],
				holdouts: [H.holdout(12, "holdout_b", seeds: H.holdoutB)]))

		#expect(h.value(context, "k") == "treatment")

		try await h.expectPublished(context, [H.held(12, "holdout_b", 1), H.own(1, "exp_single", H.normalVariant)])
	}

	// A closing context queues nothing from a variable read, holdout exposures included, even from a
	// direct state lookup (the public reads reject a closing context before reaching it).
	@Test func closingContextQueuesNoHoldoutExposureFromAVariableRead() {
		var state = ContextState(application: "website", environment: "production")
		state.index = DataIndex(
			H.contextData(
				[
					H.experiment(1, "exp_held", holdoutIds: [11], configs: H.withVariables("k")),
					H.experiment(2, "exp_assigned", holdoutIds: [12], configs: H.withVariables("k")),
				],
				holdouts: [
					H.holdout(11, "holdout_a", seeds: H.holdoutA), H.holdout(12, "holdout_b", seeds: H.holdoutB),
				]))
		try? state.putUnit(H.unitType, .string(H.uid))
		state.ready = true
		state.closing = true

		let (value, exposures) = state.variableValue("k", peek: false, now: { 0 })
		#expect(value == "treatment")
		#expect(exposures.isEmpty)
		#expect(state.exposures.isEmpty)
		#expect(state.pendingCount == 0)
	}

	// MARK: - Event logger and publish scheduling

	// 1.5.0 ported Java's throwing-logger tests as a logger that re-enters the context while an
	// exposure is delivered; 2.x delivers exposures outside the lock, so the same re-entry applies.
	@Test func throwingLoggerDoesNotPermanentlyLoseSiblingHoldoutExposure() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_multi_holdout_reentrant_logger", holdoutIds: [11, 12])],
				holdouts: [
					H.holdout(11, "holdout_a", seeds: H.holdoutA), H.holdout(12, "holdout_b", seeds: H.holdoutB),
				]))
		h.env.log.setHook { context, event in
			if case .exposure(let exposure) = event, exposure.id == 11 {
				_ = context.treatment(for: "exp_multi_holdout_reentrant_logger")
			}
		}

		#expect(context.treatment(for: "exp_multi_holdout_reentrant_logger") == 0)
		#expect(context.pendingEventCount == 2)
	}

	@Test func throwingLoggerDoesNotMakeExperimentOrHoldoutExposureRetryable() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_reentrant_logger_terminal", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_terminal", seeds: H.holdoutB)]))
		h.env.log.setHook { context, event in
			if case .exposure(let exposure) = event, exposure.id == 1 {
				_ = context.treatment(for: "exp_reentrant_logger_terminal")
			}
		}

		#expect(context.treatment(for: "exp_reentrant_logger_terminal") == H.normalVariant)
		h.env.log.setHook(nil)
		#expect(context.treatment(for: "exp_reentrant_logger_terminal") == H.normalVariant)

		try await h.expectPublished(
			context,
			[H.own(1, "exp_reentrant_logger_terminal", H.normalVariant), H.held(11, "holdout_terminal", 1)])
	}

	// The suppressed experiment has no exposure of its own, so the holdout's must start the publish
	// timer: with a short delay, the holdout exposure is published without any other call.
	@Test func throwingLoggerOnSuppressedExperimentsOnlyHoldoutStillSchedulesFlush() async {
		let h = HoldoutEnv(options: Context.Options(publishDelay: 0))
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_stranded_flush", holdoutIds: [11])],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_stranded_flush") == 0)

		#expect(await eventually(timeout: 5) { h.env.publishCount == 1 })
		#expect(h.lastSentExposures == [H.held(11, "holdout_a", 0)])
	}

	@Test func variablePathHoldoutExposureSchedulesFlushWithoutAnyOtherEvent() async throws {
		let h = HoldoutEnv(options: Context.Options(publishDelay: 0))
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_var_flush_suppressed", holdoutIds: [11],
						configs: [nil, "{\"flush_key\":\"from_suppressed\"}"]),
					H.experiment(2, "exp_var_flush_assigned", configs: [nil, "{\"flush_key\":\"from_assigned\"}"]),
				], holdouts: [H.holdout(11, "holdout_flush", seeds: H.holdoutA)]))
		// The winner is exposed and published first, so only the suppressed candidate's holdout is
		// left for the variable read to queue.
		#expect(context.treatment(for: "exp_var_flush_assigned") == H.normalVariant)
		#expect(await eventually(timeout: 5) { h.env.publishCount == 1 })

		#expect(h.value(context, "flush_key") == "from_assigned")
		#expect(await eventually(timeout: 5) { h.env.publishCount == 2 })
		#expect(h.lastSentExposures == [H.held(11, "holdout_flush", 0)])
	}

	// Every exposure one read queues is in the queue before the logger hears of any, so a logger that
	// closes the context on the first one publishes them all in one batch.
	@Test func loggerClosingOnFirstExposurePublishesEveryHoldoutExposure() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_close", holdoutIds: [11, 12])],
				holdouts: [
					H.holdout(11, "holdout_a", seeds: H.holdoutB), H.holdout(12, "holdout_b", seeds: H.holdoutB),
				]))
		let closing = Box<Task<Void, Never>?>(nil)
		h.env.log.setHook { context, event in
			if case .exposure(let exposure) = event, exposure.id == 1, closing.value == nil {
				closing.value = Task { try? await context.close() }
			}
		}

		#expect(context.treatment(for: "exp_close") == H.normalVariant)
		await closing.value?.value

		#expect(h.env.publishCount == 1)
		#expect(
			h.lastSentExposures == [
				H.own(1, "exp_close", H.normalVariant), H.held(11, "holdout_a", 1), H.held(12, "holdout_b", 1),
			])
		#expect(context.pendingEventCount == 0)
	}

	// MARK: - Assignment rules

	@Test func matchingAssignmentRuleWinsOverHoldoutSuppression() async throws {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_rules", holdoutIds: [11], assignmentRules: H.usRule)],
				holdouts: [H.holdout(11, "holdout_rules_suppression", seeds: H.holdoutA)]))
		context.setAttribute("country", to: "US")

		#expect(context.treatment(for: "exp_holdout_rules") == 1)

		try await h.expectPublished(
			context,
			[
				H.own(1, "exp_holdout_rules", 1, assigned: false, ruleOverride: true),
				H.held(11, "holdout_rules_suppression", 0),
			], attributes: [attribute("country", "US")])
	}

	@Test func matchingSplitRuleWinsOverHoldoutSuppression() {
		let rules =
			"{\"rules\":[{\"name\":\"Everyone\",\"type\":\"split\",\"conditions\":null,\"environments\":[],\"percentages\":\"0/100\"}]}"
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_split_rule", holdoutIds: [11], assignmentRules: rules)],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		#expect(context.treatment(for: "exp_holdout_split_rule", exposing: false) == 1)
		#expect(context.treatment(for: "exp_holdout_split_rule") == 1)
		#expect(context.pendingEventCount == 2)
	}

	@Test func heldOutUnitIsSuppressedWhenRuleDoesNotMatch() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_rules", holdoutIds: [11], assignmentRules: H.usRule)],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))
		context.setAttribute("country", to: "GB")

		#expect(context.treatment(for: "exp_holdout_rules") == 0)
		#expect(context.pendingEventCount == 1)

		context.setAttribute("country", to: "US")
		#expect(context.treatment(for: "exp_holdout_rules") == 1)
		#expect(context.pendingEventCount == 2)
	}

	@Test func heldOutUnitIsSuppressedAgainWhenRuleStopsMatching() {
		let context = h.context(
			H.contextData(
				[H.experiment(1, "exp_holdout_rules", holdoutIds: [11], assignmentRules: H.usRule)],
				holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))
		context.setAttribute("country", to: "US")

		#expect(context.treatment(for: "exp_holdout_rules") == 1)
		#expect(context.pendingEventCount == 2)

		context.setAttribute("country", to: "GB")
		#expect(context.treatment(for: "exp_holdout_rules") == 0)
		#expect(context.treatment(for: "exp_holdout_rules", exposing: false) == 0)
		#expect(context.pendingEventCount == 2)
	}

	@Test func variableValueOnHeldOutRuleWonExperiment() async throws {
		let context = h.context(
			H.contextData(
				[
					H.experiment(
						1, "exp_holdout_rules", holdoutIds: [11], configs: H.withVariables("color"),
						assignmentRules: H.usRule)
				], holdouts: [H.holdout(11, "holdout_rules_suppression", seeds: H.holdoutA)]))
		context.setAttribute("country", to: "US")

		#expect(h.value(context, "color") == "treatment")

		try await h.expectPublished(
			context,
			[
				H.held(11, "holdout_rules_suppression", 0),
				H.own(1, "exp_holdout_rules", 1, assigned: false, ruleOverride: true),
			], attributes: [attribute("country", "US")])
	}

	@Test func sharedVariableKeyPrefersRuleWonOverSuppressedExperiment() {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_held_out", holdoutIds: [11], configs: H.withVariables("color")),
					H.experiment(
						2, "exp_rule_won", holdoutIds: [11], configs: H.withVariables("color"),
						assignmentRules: H.usRule),
				], holdouts: [H.holdout(11, "holdout_a", seeds: H.holdoutA)]))

		context.setAttribute("country", to: "GB")
		#expect(h.value(context, "color", peek: true) == "control")

		context.setAttribute("country", to: "US")
		#expect(h.value(context, "color", peek: true) == "treatment")
	}

	@Test func sharedVariableKeyPrefersEarlierAssignedOverLaterRuleWonExperiment() {
		let context = h.context(
			H.contextData(
				[
					H.experiment(1, "exp_assigned", split: [1.0, 0.0], configs: H.withVariables("color")),
					H.experiment(2, "exp_rule_won", configs: H.withVariables("color"), assignmentRules: H.usRule),
				], holdouts: []))
		context.setAttribute("country", to: "US")

		#expect(h.value(context, "color", peek: true) == "control")
		#expect(context.treatment(for: "exp_rule_won", exposing: false) == 1)
	}
}
