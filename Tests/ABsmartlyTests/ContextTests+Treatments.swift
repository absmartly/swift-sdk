import Foundation
import Testing

@testable import ABsmartly

// Treatments and variables.
extension ContextTests {
	// MARK: - Peek

	@Test func peekTreatment() {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		for experiment in data.experiments {
			#expect(context.treatment(for: experiment.name, exposing: false) == ContextFixtures.expectedVariants[experiment.name])
		}
		#expect(context.treatment(for: "no_found", exposing: false) == 0)
		#expect(context.pendingEventCount == 0)
	}

	@Test func peekVariableValue() {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		for (name, experiments) in ContextFixtures.variableExperiments {
			let actual = context.variableValue(name, exposing: false) ?? 17
			let eligible = experiments[0] != "exp_test_not_eligible"
			if eligible && data.experiments.contains(where: { $0.name == experiments[0] }) {
				#expect(actual == ContextFixtures.expectedVariables[name], "\(name)")
			} else {
				#expect(actual == 17, "\(name)")
			}
		}
		#expect(context.pendingEventCount == 0)
	}

	@Test func peekVariableValueConflictingKeyDisjointAudiences() {
		let env = ContextEnv()
		let context = env.context("audience_key_conflict_disjoint_context")
		context.setAttribute("age", to: 20)
		#expect(context.variable("icon", default: "square", exposing: false) == "arrow")
		#expect(context.pendingEventCount == 0)

		let context2 = env.context("audience_key_conflict_disjoint_context")
		context2.setAttribute("age", to: 19)
		#expect(context2.variable("icon", default: "square", exposing: false) == "circle")
		#expect(context2.pendingEventCount == 0)
	}

	@Test func peekVariableValuePicksLowestExperimentIdOnConflictingKey() {
		let env = ContextEnv()
		let context = env.context("audience_key_conflict_context")
		#expect(context.variable("icon", default: "square", exposing: false) == "circle")
		#expect(context.pendingEventCount == 0)
	}

	@Test func peekVariableValueReturnsAssignedVariantOnAudienceMismatchNonStrictMode() {
		let env = ContextEnv()
		let context = env.context("audience_context")
		#expect(context.variable("banner.size", default: "small", exposing: false) == "large")
	}

	@Test func peekVariableValueReturnsControlVariantOnAudienceMismatchStrictMode() {
		let env = ContextEnv()
		let context = env.context("audience_strict_context")
		#expect(context.variable("banner.size", default: "small", exposing: false) == "small")
	}

	// MARK: - Variables

	@Test func getVariableValue() {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		for (name, experiments) in ContextFixtures.variableExperiments {
			let actual = context.variableValue(name) ?? 17
			let eligible = experiments[0] != "exp_test_not_eligible"
			if eligible && data.experiments.contains(where: { $0.name == experiments[0] }) {
				#expect(actual == ContextFixtures.expectedVariables[name], "\(name)")
			} else {
				#expect(actual == 17, "\(name)")
			}
		}
		#expect(context.pendingEventCount == data.experiments.count)
	}

	@Test func getVariableValueConflictingKeyDisjointAudiences() {
		let env = ContextEnv()
		let context = env.context("audience_key_conflict_disjoint_context")
		context.setAttribute("age", to: 20)
		#expect(context.variable("icon", default: "square") == "arrow")
		#expect(context.pendingEventCount == 1)

		let context2 = env.context("audience_key_conflict_disjoint_context")
		context2.setAttribute("age", to: 19)
		#expect(context2.variable("icon", default: "square") == "circle")
		// exp_test_ab (id 1) is checked first but not assigned (strict mismatch): only the winner is exposed.
		#expect(context2.pendingEventCount == 1)
	}

	@Test func getVariableValueQueuesExposureWithAudienceMismatchFalseOnAudienceMatch() async throws {
		let env = ContextEnv()
		let context = env.context("audience_context")
		context.setAttribute("age", to: 21)

		#expect(context.variable("banner.size", default: "small") == "large")
		#expect(context.pendingEventCount == 1)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(
					exposures: [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false)],
					attributes: [attribute("age", 21)]))
	}

	@Test func getVariableValueQueuesExposureWithAudienceMismatchTrueOnAudienceMismatch() async throws {
		let env = ContextEnv()
		let context = env.context("audience_context")

		#expect(context.variable("banner.size", default: "small") == "large")
		#expect(context.pendingEventCount == 1)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(exposures: [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, true)]))
	}

	// A strict audience mismatch gives the control variant without assigning the unit, so the experiment
	// does not win the key and is not exposed.
	@Test func getVariableValueDoesNotQueueExposureOnAudienceMismatchInStrictMode() {
		let env = ContextEnv()
		let context = env.context("audience_strict_context")
		env.log.clear()

		#expect(context.variable("banner.size", default: "small") == "small")
		#expect(context.pendingEventCount == 0)
		#expect(env.log.exposures == [])
	}

	@Test func getVariableValueCallsEventLogger() {
		let env = ContextEnv()
		let context = env.context()
		env.log.clear()

		_ = context.variableValue("banner.border")
		_ = context.variableValue("banner.size")

		let exposures = [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false)]
		#expect(env.log.count == 1)
		for (i, exposure) in exposures.enumerated() {
			#expect(env.log.contexts[i] == ObjectIdentifier(context))
			#expect(env.log.events[i] == .exposure(exposure))
		}

		env.log.clear()
		_ = context.variableValue("banner.border")
		_ = context.variableValue("banner.size")
		#expect(env.log.count == 0)
	}

	// MARK: - Variables shared by several experiments

	private static func sharedKeyExperiment(
		id: Int, name: String, unitType: String = "session_id", fullOnVariant: Int = 1, configs: [String?]
	) -> String {
		let variants = configs.indices.map { i -> String in
			let escaped = configs[i].map { "\"" + $0.replacingOccurrences(of: "\"", with: "\\\"") + "\"" } ?? "null"
			return "{\"name\":\"\(i)\",\"config\":\(escaped)}"
		}
		return """
			{"id":\(id),"name":"\(name)","iteration":1,"unitType":"\(unitType)","seedHi":0,"seedLo":0,\
			"split":[0.5,0.5],"trafficSeedHi":0,"trafficSeedLo":0,"trafficSplit":[0.0,1.0],\
			"fullOnVariant":\(fullOnVariant),"applications":[{"name":"website"}],\
			"variants":[\(variants.joined(separator: ","))],"audience":null}
			"""
	}

	private static func sharedKeyContext(_ env: ContextEnv, _ experiments: [String]) -> Context {
		let data = ContextFixtures.decode("{\"experiments\":[\(experiments.joined(separator: ","))]}")
		let context = env.context(data: data)
		env.log.clear()
		return context
	}

	private static func sharedKeyBothAssigned(lowestFirst: Bool) -> [String] {
		let one = sharedKeyExperiment(id: 1, name: "exp_one", configs: [nil, "{\"icon\":\"one\"}"])
		let two = sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"])
		return lowestFirst ? [one, two] : [two, one]
	}

	// exp_one is not assigned: its unit type has no unit in the context.
	private static func sharedKeyFirstUnassigned() -> [String] {
		[
			sharedKeyExperiment(
				id: 1, name: "exp_one", unitType: "device_id", fullOnVariant: 0,
				configs: ["{\"icon\":\"zero\"}", "{\"icon\":\"one\"}"]),
			sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
		]
	}

	// exp_one is assigned variant 1, which does not define the key.
	private static func sharedKeyAssignedVariantLacksKey() -> [String] {
		[
			sharedKeyExperiment(id: 1, name: "exp_one", configs: ["{\"icon\":\"zero\"}", "{\"other\":1}"]),
			sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
		]
	}

	@Test func getVariableValueSharedKeyBothAssignedLowestIdWins() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyBothAssigned(lowestFirst: true))

		#expect(context.variable("icon", default: "default") == "one")
		#expect(env.log.exposures == [exposure(1, "exp_one", "session_id", 1, true, true, false, true, false, false)])
	}

	@Test func getVariableValueSharedKeyHigherIdFirstInPayloadLowestIdWins() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyBothAssigned(lowestFirst: false))

		#expect(context.variable("icon", default: "default") == "one")
		#expect(env.log.exposures == [exposure(1, "exp_one", "session_id", 1, true, true, false, true, false, false)])
	}

	@Test func getVariableValueSharedKeyFirstUnassignedLosesAndOnlyTheWinnerIsExposed() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyFirstUnassigned())

		#expect(context.variable("icon", default: "default") == "two")
		#expect(env.log.exposures == [exposure(2, "exp_two", "session_id", 1, true, true, false, true, false, false)])
		#expect(context.pendingEventCount == 1)
	}

	// exp_one has a strict audience the unit does not match, so it gives the control variant without
	// being assigned; exp_two is assigned.
	private static func sharedKeyFirstStrictAudienceMismatch() -> [String] {
		let one = sharedKeyExperiment(
			id: 1, name: "exp_one", fullOnVariant: 0, configs: ["{\"icon\":\"zero\"}", "{\"icon\":\"one\"}"]
		).replacingOccurrences(
			of: "\"audience\":null",
			with: "\"audienceStrict\":true,\"audience\":\"{\\\"filter\\\":[{\\\"value\\\":false}]}\"")
		return [one, sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"])]
	}

	@Test func getVariableValueSharedKeyStrictAudienceMismatchLosesAndOnlyTheWinnerIsExposed() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyFirstStrictAudienceMismatch())
		#expect(context.treatment(for: "exp_one", exposing: false) == 0)

		#expect(context.variable("icon", default: "default") == "two")
		#expect(env.log.exposures == [exposure(2, "exp_two", "session_id", 1, true, true, false, true, false, false)])
		#expect(context.pendingEventCount == 1)
	}

	// A candidate that was only checked is not marked exposed: reading its treatment later exposes it once.
	@Test func sharedKeyLosingCandidateIsExposedByALaterTreatmentRead() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyFirstStrictAudienceMismatch())

		#expect(context.variable("icon", default: "default") == "two")
		#expect(context.treatment(for: "exp_one") == 0)
		#expect(context.treatment(for: "exp_one") == 0)
		#expect(env.log.exposures.map(\.name) == ["exp_two", "exp_one"])
	}

	@Test func getVariableValueSharedKeyFirstUnassignedButOverriddenWins() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyFirstUnassigned())
		context.overrides["exp_one"] = 1

		#expect(context.variable("icon", default: "default") == "one")
		#expect(env.log.exposures == [exposure(1, "exp_one", "device_id", 1, false, true, true, false, false, false)])
	}

	// The override wins even onto a variant without the key: the default, never a later candidate's value.
	@Test func getVariableValueSharedKeyOverrideToAVariantLackingTheKeyGivesTheDefault() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(
			env,
			[
				Self.sharedKeyExperiment(
					id: 1, name: "exp_one", unitType: "device_id", fullOnVariant: 0,
					configs: ["{\"other\":0}", "{\"icon\":\"one\"}"]),
				Self.sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
			])
		context.overrides["exp_one"] = 0

		#expect(context.variable("icon", default: "default") == "default")
		#expect(env.log.exposures == [exposure(1, "exp_one", "device_id", 0, false, true, true, false, false, false)])
		#expect(context.pendingEventCount == 1)
	}

	// An override onto a variant with no variables at all still wins: it is exposed once and the read
	// gives the default.
	@Test func getVariableValueSharedKeyOverrideToAVariantWithoutVariablesWinsAndIsExposedOnce() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyBothAssigned(lowestFirst: true))
		context.overrides["exp_one"] = 0

		#expect(context.variable("icon", default: "default") == "default")
		#expect(context.variable("icon", default: "default") == "default")
		#expect(env.log.exposures == [exposure(1, "exp_one", "session_id", 0, false, true, true, false, false, false)])
		#expect(context.pendingEventCount == 1)
	}

	// A matching assignment rule puts the unit in exp_one even though its unit is missing.
	@Test func getVariableValueSharedKeyRuleAssignedLowerIdWins() {
		let rule =
			"{\\\"rules\\\":[{\\\"name\\\":\\\"all\\\",\\\"type\\\":\\\"assign\\\",\\\"conditions\\\":{\\\"value\\\":true},\\\"environments\\\":[],\\\"variant\\\":1}]}"
		let one = Self.sharedKeyExperiment(
			id: 1, name: "exp_one", unitType: "device_id", fullOnVariant: 0,
			configs: ["{\"icon\":\"zero\"}", "{\"icon\":\"one\"}"]
		).replacingOccurrences(of: "\"audience\":null", with: "\"audience\":null,\"assignmentRules\":\"\(rule)\"")
		let env = ContextEnv()
		let context = Self.sharedKeyContext(
			env, [one, Self.sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"])])

		#expect(context.variable("icon", default: "default") == "one")
		#expect(
			env.log.exposures == [
				exposure(1, "exp_one", "device_id", 1, false, true, false, false, false, false, ruleOverride: true)
			])
		#expect(context.pendingEventCount == 1)
	}

	@Test func getVariableValueSharedKeyWinnersVariantLackingKeyGivesTheDefaultAndExposesOnlyTheWinner() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyAssignedVariantLacksKey())

		#expect(context.variable("icon", default: "default") == "default")
		#expect(env.log.exposures == [exposure(1, "exp_one", "session_id", 1, true, true, false, true, false, false)])
		#expect(context.pendingEventCount == 1)
	}

	@Test func getVariableValueSharedKeyNoCandidateAssignedGivesTheDefaultAndNoExposure() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(
			env,
			[
				Self.sharedKeyExperiment(
					id: 1, name: "exp_one", unitType: "device_id", fullOnVariant: 0, configs: [nil, "{\"icon\":\"one\"}"]),
				Self.sharedKeyExperiment(
					id: 2, name: "exp_two", unitType: "device_id", fullOnVariant: 0, configs: [nil, "{\"icon\":\"two\"}"]),
			])

		#expect(context.variable("icon", default: "default") == "default")
		#expect(env.log.exposures == [])
		#expect(context.pendingEventCount == 0)
	}

	// A key the winner defines as null, false, 0 or "" returns that value, not the default and not a
	// later candidate's value.
	@Test func getVariableValueSharedKeyFalsyValuesOfTheWinnerAreReturned() {
		let cases: [(String, JSONValue)] = [
			("{\"icon\":null}", .null), ("{\"icon\":false}", false), ("{\"icon\":0}", 0), ("{\"icon\":\"\"}", ""),
		]
		for (config, expected) in cases {
			let env = ContextEnv()
			let context = Self.sharedKeyContext(
				env,
				[
					Self.sharedKeyExperiment(id: 1, name: "exp_one", configs: [nil, config]),
					Self.sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
				])

			#expect(context.variableValue("icon", exposing: false) == expected, "\(config)")
			#expect(context.variableValue("icon") == expected, "\(config)")
			#expect(env.log.exposures.map(\.name) == ["exp_one"], "\(config)")
		}
	}

	// Concurrent reads of a shared key, interleaved with treatment reads of the losing candidate: the
	// winner and the loser are each exposed exactly once.
	@Test func concurrentSharedKeyReadsExposeTheWinnerOnce() {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(env, Self.sharedKeyFirstStrictAudienceMismatch())
		let values = Locked<[String]>([])
		DispatchQueue.concurrentPerform(iterations: 4) { reader in
			for _ in 0..<200 {
				let value = context.variable("icon", default: "default")
				values.withLock { $0.append(value) }
				if reader == 0 {
					_ = context.treatment(for: "exp_one")
				}
			}
		}

		#expect(Set(values.withLock { $0 }) == ["two"])
		#expect(env.log.exposures.map(\.name).sorted() == ["exp_one", "exp_two"])
		#expect(context.pendingEventCount == 2)
	}

	// As in the Java SDK, a config-only refresh with an unchanged iteration keeps a
	// cached assignment, including its variant variables. exp_one was resolved before the refresh added
	// the key to its variant, so it still wins without the key: the default is returned. A context that
	// never resolved exp_one reads the refreshed config.
	@Test(arguments: ["none", "peek", "treatment"])
	func configOnlyRefreshKeepsACachedAssignmentsVariables(resolvedBefore: String) async throws {
		let env = ContextEnv()
		let context = Self.sharedKeyContext(
			env,
			[
				Self.sharedKeyExperiment(id: 1, name: "exp_one", configs: [nil, "{\"other\":\"one\"}"]),
				Self.sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
			])
		if resolvedBefore == "peek" {
			#expect(context.treatment(for: "exp_one", exposing: false) == 1)
		} else if resolvedBefore == "treatment" {
			#expect(context.treatment(for: "exp_one") == 1)
		}
		env.serveNext(
			ContextFixtures.decode(
				"{\"experiments\":["
					+ [
						Self.sharedKeyExperiment(id: 1, name: "exp_one", configs: [nil, "{\"icon\":\"one\"}"]),
						Self.sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
					].joined(separator: ",") + "]}"))
		try await context.refresh()
		env.log.clear()

		let expected = resolvedBefore == "none" ? "one" : "default"
		#expect(context.variable("icon", default: "default", exposing: false) == expected)
		#expect(context.variable("icon", default: "default") == expected)
		#expect(env.log.exposures.map(\.name) == (resolvedBefore == "treatment" ? [] : ["exp_one"]))
		#expect(context.pendingEventCount == 1)
	}

	@Test func peekVariableValueSharedKeyMatchesGetAndQueuesNothing() {
		let scenarios: [([String], String?, String)] = [
			(Self.sharedKeyBothAssigned(lowestFirst: true), nil, "one"),
			(Self.sharedKeyBothAssigned(lowestFirst: false), nil, "one"),
			(Self.sharedKeyFirstUnassigned(), nil, "two"),
			(Self.sharedKeyFirstUnassigned(), "exp_one", "one"),
			(Self.sharedKeyFirstStrictAudienceMismatch(), nil, "two"),
			(Self.sharedKeyAssignedVariantLacksKey(), nil, "default"),
		]

		for (experiments, override, expected) in scenarios {
			let env = ContextEnv()
			let context = Self.sharedKeyContext(env, experiments)
			if let override {
				context.overrides[override] = 1
			}

			#expect(context.variable("icon", default: "default", exposing: false) == expected)
			#expect(context.pendingEventCount == 0)
			#expect(env.log.exposures == [])

			#expect(context.variable("icon", default: "default") == expected)
			#expect(context.pendingEventCount == 1)
		}
	}

	@Test func getVariableKeys() {
		let env = ContextEnv()
		let context = env.context("refreshed")
		#expect(context.variableKeys == ContextFixtures.variableExperiments)
	}

	// MARK: - Treatments

	@Test func peekTreatmentReturnsOverrideVariant() {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		context.setOverrides(ContextFixtures.expectedVariants.mapValues { 11 + $0 })
		context.overrides["not_found"] = 3

		for _ in 0..<2 {
			for experiment in data.experiments {
				if let variant = ContextFixtures.expectedVariants[experiment.name] {
					#expect(context.treatment(for: experiment.name, exposing: false) == variant + 11)
				}
			}
			#expect(context.treatment(for: "not_found", exposing: false) == 3)
		}
		#expect(context.pendingEventCount == 0)
	}

	@Test func peekTreatmentReturnsAssignedVariantOnAudienceMismatchNonStrictMode() {
		let env = ContextEnv()
		let context = env.context("audience_context")
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)
	}

	@Test func peekTreatmentReturnsControlVariantOnAudienceMismatchStrictMode() {
		let env = ContextEnv()
		let context = env.context("audience_strict_context")
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 0)
	}

	@Test func getTreatment() async throws {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		for experiment in data.experiments {
			if let variant = ContextFixtures.expectedVariants[experiment.name] {
				#expect(context.treatment(for: experiment.name) == variant)
			}
		}
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 1 + data.experiments.count)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(exposures: [
					exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false),
					exposure(2, "exp_test_abc", "session_id", 2, true, true, false, false, false, false),
					exposure(3, "exp_test_not_eligible", "user_id", 0, true, false, false, false, false, false),
					exposure(4, "exp_test_fullon", "session_id", 2, true, true, false, true, false, false),
					exposure(0, "not_found", nil, 0, false, true, false, false, false, false),
				]))
	}

	@Test func getTreatmentStartsPublishTimeoutAfterExposure() async {
		let env = ContextEnv()
		let context = env.context(options: Context.Options(publishDelay: 0.05))

		_ = context.treatment(for: "exp_test_ab")
		_ = context.treatment(for: "exp_test_abc")

		#expect(context.pendingEventCount == 2)
		#expect(env.publishCount == 0)

		// One timer for both exposures: a single publish.
		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(context.pendingEventCount == 0)
		await pause(0.1)
		#expect(env.publishCount == 1)
	}

	@Test func getTreatmentReturnsOverrideVariant() async throws {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		context.setOverrides(ContextFixtures.expectedVariants.mapValues { 11 + $0 })
		context.overrides["not_found"] = 3

		for experiment in data.experiments {
			if let variant = ContextFixtures.expectedVariants[experiment.name] {
				#expect(context.treatment(for: experiment.name) == variant + 11)
			}
		}
		#expect(context.treatment(for: "not_found") == 3)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(exposures: [
					exposure(1, "exp_test_ab", "session_id", 12, false, true, true, false, false, false),
					exposure(2, "exp_test_abc", "session_id", 13, false, true, true, false, false, false),
					exposure(3, "exp_test_not_eligible", "user_id", 11, false, true, true, false, false, false),
					exposure(4, "exp_test_fullon", "session_id", 13, false, true, true, false, false, false),
					exposure(0, "not_found", nil, 3, false, true, true, false, false, false),
				]))
	}

	@Test func getTreatmentQueuesExposureOnce() async throws {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		for experiment in data.experiments {
			if let variant = ContextFixtures.expectedVariants[experiment.name] {
				#expect(context.treatment(for: experiment.name) == variant)
			}
		}
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 1 + data.experiments.count)

		for experiment in data.experiments {
			if let variant = ContextFixtures.expectedVariants[experiment.name] {
				#expect(context.treatment(for: experiment.name) == variant)
			}
		}
		#expect(context.treatment(for: "not_found") == 0)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(context.pendingEventCount == 0)

		_ = context.treatment(for: "not_found")
		#expect(context.pendingEventCount == 0)
	}

	@Test func getTreatmentQueuesExposureWithAudienceMismatchFalseOnAudienceMatch() async throws {
		let env = ContextEnv()
		let context = env.context("audience_context")
		context.setAttribute("age", to: 21)

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(context.pendingEventCount == 1)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(
					exposures: [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false)],
					attributes: [attribute("age", 21)]))
	}

	@Test func getTreatmentQueuesExposureWithAudienceMismatchTrueOnAudienceMismatch() async throws {
		let env = ContextEnv()
		let context = env.context("audience_context")

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(context.pendingEventCount == 1)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(exposures: [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, true)]))
	}

	@Test func getTreatmentQueuesExposureWithAudienceMismatchTrueAndControlVariantOnAudienceMismatchInStrictMode()
		async throws
	{
		let env = ContextEnv()
		let context = env.context("audience_strict_context")

		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(context.pendingEventCount == 1)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(exposures: [exposure(1, "exp_test_ab", "session_id", 0, false, true, false, false, false, true)]))
	}

	@Test func getTreatmentCallsEventLogger() {
		let env = ContextEnv()
		let context = env.context()
		env.log.clear()

		_ = context.treatment(for: "exp_test_ab")
		_ = context.treatment(for: "not_found")

		let exposures = [
			exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false),
			exposure(0, "not_found", nil, 0, false, true, false, false, false, false),
		]
		#expect(env.log.count == 2)
		for (i, exposure) in exposures.enumerated() {
			#expect(env.log.contexts[i] == ObjectIdentifier(context))
			#expect(env.log.events[i] == .exposure(exposure))
		}

		env.log.clear()
		_ = context.treatment(for: "exp_test_ab")
		_ = context.treatment(for: "not_found")
		#expect(env.log.count == 0)
	}
}
