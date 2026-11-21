import Foundation
import Testing

@testable import ABsmartly

#if DEBUG
	private let countsAssignmentWork = true
#else
	private let countsAssignmentWork = false
#endif

@Suite struct ContextAssignmentRulesTests {
	static let seedHi = 3_603_515
	static let seedLo = 233_373_850
	static let trafficSeedHi = 449_867_249
	static let trafficSeedLo = 455_443_629

	// A three-variant experiment on `session_id`; each variant sets `color` to its index.
	static func experimentJSON(
		rules: String?, name: String = "exp", split: [Double] = [0.34, 0.33, 0.33], trafficSplit: [Double] = [0, 1],
		fullOnVariant: Int = 0, audience: String? = nil, audienceStrict: Bool = false
	) -> String {
		func quoted(_ s: String) -> String {
			"\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
		}
		let variants = (0..<3).map { "{\"name\":\"\($0)\",\"config\":\(quoted("{\"color\":\($0)}"))}" }
		return """
			{"id":1,"name":"\(name)","iteration":1,"unitType":"session_id","seedHi":\(seedHi),"seedLo":\(seedLo),\
			"split":\(split),"trafficSeedHi":\(trafficSeedHi),"trafficSeedLo":\(trafficSeedLo),\
			"trafficSplit":\(trafficSplit),"fullOnVariant":\(fullOnVariant),"variants":[\(variants.joined(separator: ","))],\
			"audienceStrict":\(audienceStrict),"audience":\(audience.map(quoted) ?? "null"),\
			"assignmentRules":\(rules.map(quoted) ?? "null")}
			"""
	}

	static func contextData(_ experiments: String...) -> ContextData {
		ContextFixtures.decode("{\"experiments\":[\(experiments.joined(separator: ","))]}")
	}

	static func rules(_ rules: String...) -> String {
		"{\"rules\":[\(rules.joined(separator: ","))]}"
	}

	static let countryNL = "{\"and\":[{\"eq\":[{\"var\":\"country\"},{\"value\":\"NL\"}]}]}"

	static func splitVariant(_ unit: String, _ split: [Double], seedHi: Int, seedLo: Int) -> Int {
		VariantAssigner(unitHash: Hashing.hashUnit(unit)).assign(split, seedHi: seedHi, seedLo: seedLo)
	}

	static var defaultVariant: Int { splitVariant("unit-1", [0.34, 0.33, 0.33], seedHi: seedHi, seedLo: seedLo) }

	let env = ContextEnv()

	/// A context with application "website", the given environment (or none), one
	/// `session_id` unit unless `unit` is nil.
	func createContext(
		_ data: ContextData, unit: String? = "unit-1", environment: String? = "production",
		attributes: [String: JSONValue] = [:], overrides: [String: Int] = [:], customAssignments: [String: Int] = [:]
	) -> Context {
		env.directContext(
			data: data, units: unit.map { [.sessionID: $0] } ?? [:], attributes: attributes, overrides: overrides,
			customAssignments: customAssignments, environment: environment)
	}

	/// The exposures logged so far for `context`.
	func exposures(_ context: Context) -> [Exposure] {
		zip(env.log.contexts, env.log.events).compactMap { id, event in
			guard id == ObjectIdentifier(context), case .exposure(let exposure) = event else { return nil }
			return exposure
		}
	}

	// MARK: - assign

	@Test func assignRuleWinsAndFlagsExposure() throws {
		let data = Self.contextData(
			Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(Self.countryNL)}")))
		let context = createContext(data, attributes: ["country": "NL"])

		#expect(context.treatment(for: "exp") == 2)
		#expect(context.variableValue("color") == 2)

		let exposure = try #require(exposures(context).first)
		#expect(exposure.ruleOverride)
		#expect(!exposure.assigned)
		#expect(exposure.eligible)
		#expect(!exposure.overridden)
		#expect(!exposure.custom)
		#expect(!exposure.fullOn)
	}

	@Test func nonMatchingRuleFallsBackToNormalAssignment() throws {
		let data = Self.contextData(
			Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(Self.countryNL)}")))
		let context = createContext(data, attributes: ["country": "DE"])

		#expect(context.treatment(for: "exp") == Self.defaultVariant)
		let exposure = try #require(exposures(context).first)
		#expect(!exposure.ruleOverride)
		#expect(exposure.assigned)
	}

	@Test func ruleWithoutConditionsAlwaysMatches() {
		let data = Self.contextData(Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":1}")))
		#expect(createContext(data).treatment(for: "exp") == 1)
	}

	@Test func firstMatchingRuleWins() {
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"assign\",\"variant\":1,\"conditions\":{\"value\":false}}",
					"{\"type\":\"assign\",\"variant\":2,\"conditions\":\(Self.countryNL)}",
					"{\"type\":\"assign\",\"variant\":0}")))
		let context = createContext(data, attributes: ["country": "NL"])
		#expect(context.treatment(for: "exp") == 2)
	}

	@Test func overrideBeatsRule() throws {
		let data = Self.contextData(Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2}")))
		let context = createContext(data, overrides: ["exp": 1])

		#expect(context.treatment(for: "exp") == 1)
		let exposure = try #require(exposures(context).first)
		#expect(exposure.overridden)
		#expect(!exposure.ruleOverride)
	}

	@Test func ruleBeatsStrictAudienceTrafficFullOnAndCustom() throws {
		let assign = Self.rules("{\"type\":\"assign\",\"variant\":2}")
		let strict = Self.contextData(
			Self.experimentJSON(rules: assign, audience: "{\"filter\":[{\"value\":false}]}", audienceStrict: true))
		let ineligible = Self.contextData(Self.experimentJSON(rules: assign, trafficSplit: [1, 0]))
		let fullOn = Self.contextData(Self.experimentJSON(rules: assign, fullOnVariant: 1))

		for data in [strict, ineligible, fullOn] {
			let context = createContext(data)
			#expect(context.treatment(for: "exp") == 2)
			let exposure = try #require(exposures(context).last)
			#expect(exposure.ruleOverride)
			#expect(!exposure.audienceMismatch)
			#expect(exposure.eligible)
			#expect(!exposure.fullOn)
		}

		let custom = createContext(Self.contextData(Self.experimentJSON(rules: assign)), customAssignments: ["exp": 0])
		#expect(custom.treatment(for: "exp") == 2)
		#expect(try #require(exposures(custom).last).custom == false)
	}

	// A rule winning over a different custom assignment must not look stale and queue an exposure
	// on every call.
	@Test func ruleWinningOverCustomAssignmentIsCached() {
		let data = Self.contextData(Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2}")))
		let context = createContext(data, customAssignments: ["exp": 1])

		#expect(context.treatment(for: "exp") == 2)
		#expect(context.treatment(for: "exp") == 2)
		#expect(context.variableValue("color") == 2)
		#expect(context.pendingEventCount == 1)
	}

	@Test func environments() {
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"assign\",\"variant\":1,\"environments\":[\"staging\"]}",
					"{\"type\":\"assign\",\"variant\":2,\"environments\":[\"production\"]}")))
		#expect(createContext(data).treatment(for: "exp") == 2)
		#expect(createContext(data, environment: "staging").treatment(for: "exp") == 1)

		// A rule limited to environments never matches when the client has none; an empty list matches any.
		let none = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"assign\",\"variant\":1,\"environments\":[\"production\"]}",
					"{\"type\":\"assign\",\"variant\":2,\"environments\":[]}")))
		#expect(createContext(none, environment: nil).treatment(for: "exp") == 2)
	}

	@Test func conditionsSeeSystemAttributesAndSemver() {
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"assign\",\"variant\":1,\"conditions\":{\"and\":[{\"eq\":[{\"var\":\"application\"},{\"value\":\"website\"}]},{\"semver_gte\":[{\"var\":\"app_version\"},{\"value\":\"2.0.0\"}]}]}}"
				)))
		#expect(createContext(data, attributes: ["app_version": "2.1"]).treatment(for: "exp") == 1)
		#expect(createContext(data, unit: "unit-2", attributes: ["app_version": "1.9.9"]).treatment(for: "exp") != 1)
	}

	@Test func conditionOnConfiguredEnvironment() throws {
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"assign\",\"variant\":2,\"conditions\":{\"eq\":[{\"var\":\"environment\"},{\"value\":\"production\"}]}}"
				)))
		let context = createContext(data)
		#expect(context.treatment(for: "exp") == 2)
		#expect(try #require(exposures(context).last).ruleOverride)

		let staging = createContext(data, environment: "staging")
		_ = staging.treatment(for: "exp")
		#expect(try #require(exposures(staging).last).ruleOverride == false)
	}

	@Test func attributeChangeReevaluatesRules() {
		let data = Self.contextData(
			Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(Self.countryNL)}")))
		let context = createContext(data)

		#expect(context.treatment(for: "exp") != 2)
		context.setAttribute("country", to: "NL")
		#expect(context.treatment(for: "exp") == 2)
		#expect(exposures(context).map(\.ruleOverride) == [false, true])

		// An unrelated attribute change keeps the cached assignment and its exposure.
		context.setAttribute("other", to: 1)
		#expect(context.treatment(for: "exp") == 2)
		#expect(exposures(context).count == 2)
	}

	@Test func refreshWithRemovedRulesRebuildsAssignment() throws {
		let context = createContext(
			Self.contextData(Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2}"))))
		#expect(context.treatment(for: "exp") == 2)

		context.install(Self.contextData(Self.experimentJSON(rules: nil)))

		#expect(context.treatment(for: "exp") == Self.defaultVariant)
		#expect(try #require(exposures(context).last).ruleOverride == false)
	}

	@Test func refreshWithoutExperimentDropsRuleAssignment() {
		let context = createContext(
			Self.contextData(Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2}"))))
		#expect(context.treatment(for: "exp") == 2)

		context.install(Self.contextData(Self.experimentJSON(rules: nil, name: "other")))
		#expect(context.treatment(for: "exp") == 0)
		#expect(context.treatment(for: "exp", exposing: false) == 0)
	}

	// MARK: - split

	@Test func splitHashesWithExperimentSeed() throws {
		let split = [0.2, 0.3, 0.5]
		let data = Self.contextData(
			Self.experimentJSON(rules: Self.rules("{\"type\":\"split\",\"percentages\":\"20/30/50\"}")))

		var differsFromTrafficSeed = false
		for i in 0..<50 {
			let unit = "unit-\(i)"
			let expected = Self.splitVariant(unit, split, seedHi: Self.seedHi, seedLo: Self.seedLo)
			if expected != Self.splitVariant(unit, split, seedHi: Self.trafficSeedHi, seedLo: Self.trafficSeedLo) {
				differsFromTrafficSeed = true
			}
			let context = createContext(data, unit: unit)
			#expect(context.treatment(for: "exp") == expected, "\(unit)")
			#expect(try #require(exposures(context).last).ruleOverride)
		}
		#expect(differsFromTrafficSeed)
	}

	@Test func splitEqualToExperimentSplitKeepsVariant() {
		let data = Self.contextData(
			Self.experimentJSON(rules: Self.rules("{\"type\":\"split\",\"percentages\":\"34/33/33\"}")))
		let plain = Self.contextData(Self.experimentJSON(rules: nil))
		for i in 0..<50 {
			#expect(
				createContext(plain, unit: "u\(i)").treatment(for: "exp") == createContext(data, unit: "u\(i)").treatment(for: "exp"))
		}
	}

	@Test func splitWithoutUnitGivesNoUnitResultAndResolvesOnceUnitIsSet() throws {
		let split = Self.rules(
			"{\"type\":\"split\",\"percentages\":\"0/0/100\"}", "{\"type\":\"assign\",\"variant\":1}")
		let context = createContext(Self.contextData(Self.experimentJSON(rules: split)), unit: nil)

		// First match wins: the split stops evaluation and gives the experiment's no-unit result.
		#expect(context.treatment(for: "exp", exposing: false) == 0)
		try context.setUnit(.sessionID, to: "unit-1")
		#expect(context.treatment(for: "exp") == 2)
		#expect(try #require(exposures(context).last).ruleOverride)

		let fullOn = createContext(Self.contextData(Self.experimentJSON(rules: split, fullOnVariant: 1)), unit: nil)
		#expect(fullOn.treatment(for: "exp", exposing: false) == 1)
	}

	@Test func exposedSplitWithoutUnitStaysPinned() throws {
		let split = Self.rules("{\"type\":\"split\",\"percentages\":\"0/0/100\",\"conditions\":\(Self.countryNL)}")
		let context = createContext(
			Self.contextData(Self.experimentJSON(rules: split)), unit: nil, attributes: ["country": "NL"])

		#expect(context.treatment(for: "exp") == 0)
		try context.setUnit(.sessionID, to: "unit-1")
		#expect(context.treatment(for: "exp") == 0)

		// Even an attribute change that re-evaluates the (still matching) rule keeps the variant.
		context.setAttribute("other", to: true)
		#expect(context.treatment(for: "exp") == 0)
		#expect(exposures(context).count == 1)
	}

	// The pin is also taken when a re-evaluation keeps the variant but now resolves it through a
	// split without the unit, so the unit set afterwards still cannot switch it.
	@Test func exposedVariantKeptBySplitWithoutUnitStaysPinned() throws {
		let rules = Self.rules(
			"{\"type\":\"split\",\"percentages\":\"0/0/100\",\"conditions\":{\"eq\":[{\"var\":\"country\"},{\"value\":\"GB\"}]}}",
			"{\"type\":\"assign\",\"variant\":0}")
		let context = createContext(
			Self.contextData(Self.experimentJSON(rules: rules)), unit: nil, attributes: ["country": "US"])

		#expect(context.treatment(for: "exp") == 0)
		context.setAttribute("country", to: "GB")
		#expect(context.treatment(for: "exp") == 0)
		try context.setUnit(.sessionID, to: "unit-1")
		context.setAttribute("other", to: true)
		#expect(context.treatment(for: "exp") == 0)
		#expect(exposures(context).count == 1)
	}

	@Test func assignRuleWithoutUnitKeepsCachedAssignment() throws {
		let context = createContext(
			Self.contextData(Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2}"))), unit: nil)
		#expect(context.treatment(for: "exp") == 2)
		try context.setUnit(.sessionID, to: "unit-1")
		#expect(context.treatment(for: "exp") == 2)
		#expect(exposures(context).count == 1)
	}

	// MARK: - malformed rules

	@Test func invalidSplitIsSkipped() {
		for percentages in ["\"abc/50/50\"", "\"-10/60/50\"", "\"20/30/40\"", "[20,30,50]", "\"50/50.015/0\""] {
			let data = Self.contextData(
				Self.experimentJSON(
					rules: Self.rules(
						"{\"type\":\"split\",\"percentages\":\(percentages)}", "{\"type\":\"assign\",\"variant\":1}")))
			#expect(createContext(data).treatment(for: "exp") == 1, "\(percentages)")
		}
	}

	// parseFloat skips ECMAScript WhiteSpace and LineTerminator characters only: a split led by
	// U+FEFF (or another of them) is applied, one led by U+001E or U+0085 (Unicode whitespace that
	// ECMAScript does not skip) is invalid, so the next rule decides.
	@Test func splitSkipsOnlyEcmaScriptWhitespace() {
		// Escaped in the rules JSON, since control characters are not allowed raw in a JSON string.
		let applied = ["\\ufeff", "\\u000b", "\\u000c", "\\u00a0", "\\u1680", "\\u2028", "\\u3000", "\\t", "\\n"]
		let invalid = ["\\u001e", "\\u0085", "\\u180e", "\\u200b"]
		for (prefixes, expected) in [(applied, 2), (invalid, 1)] {
			for prefix in prefixes {
				let data = Self.contextData(
					Self.experimentJSON(
						rules: Self.rules(
							"{\"type\":\"split\",\"percentages\":\"\(prefix)0/0/100\"}",
							"{\"type\":\"assign\",\"variant\":1}")))
				let context = createContext(data)
				#expect(context.treatment(for: "exp") == expected, "\(prefix)")
				#expect(exposures(context).last?.ruleOverride == true, "\(prefix)")
			}
		}
	}

	@Test func splitWithinTolerance() {
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"split\",\"percentages\":\"0/0/100.01\"}", "{\"type\":\"assign\",\"variant\":1}")))
		#expect(createContext(data).treatment(for: "exp") == 2)
	}

	@Test func wrongCountOrOutOfBoundsStopsRuleEvaluation() throws {
		let expected = Self.defaultVariant
		for first in ["{\"type\":\"split\",\"percentages\":\"50/50\"}", "{\"type\":\"assign\",\"variant\":3}"] {
			let data = Self.contextData(
				Self.experimentJSON(
					rules: Self.rules(first, "{\"type\":\"assign\",\"variant\":\(expected == 2 ? 1 : 2)}")))
			let context = createContext(data)
			#expect(context.treatment(for: "exp") == expected, "\(first)")
			#expect(try #require(exposures(context).last).ruleOverride == false)
		}
	}

	@Test func ruleWinIsVisibleThroughAPeekedVariable() {
		let data = Self.contextData(
			Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2}"), trafficSplit: [1, 0]))
		let context = createContext(data)
		#expect(context.variableValue("color", exposing: false) == 2)
		#expect(context.pendingEventCount == 0)
	}

	@Test func ruleWithUnknownOperatorFallsThroughToTheNextRule() {
		let next = (Self.defaultVariant + 1) % 3
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"assign\",\"variant\":\(Self.defaultVariant),\"conditions\":{\"futureOp\":[1]}}",
					"{\"type\":\"assign\",\"variant\":\(next)}")))
		#expect(createContext(data).treatment(for: "exp") == next)
	}

	@Test func nonFiniteAssignVariantIsSkipped() {
		let rules: [ExprValue] = [["type": "assign", "variant": .double(.infinity)], ["type": "assign", "variant": 1]]
		#expect(AudienceMatcher.evaluateRules(rules, environmentName: nil, attributes: [:]) == .assign(variant: 1))
	}

	// Reachable from variableValue when close() starts between listing a key's experiments and
	// walking them.
	@Test func closingContextQueuesNoExposure() {
		var state = ContextState(application: "website", environment: "production")
		state.index = DataIndex(Self.contextData(Self.experimentJSON(rules: nil)))
		state.ready = true
		state.closing = true
		let (_, exposure) = state.lookupExposing("exp", now: { 0 })
		#expect(exposure == nil)
		#expect(state.exposures.isEmpty)
		#expect(state.pendingCount == 0)
	}

	@Test func malformedRulesAreSkipped() {
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"null", "1", "{\"type\":\"unknown\",\"variant\":0}", "{\"type\":\"assign\",\"variant\":1.5}",
					"{\"type\":\"assign\",\"variant\":\"1\"}",
					"{\"type\":\"assign\",\"variant\":0,\"environments\":\"production\"}",
					"{\"type\":\"assign\",\"variant\":0,\"conditions\":[{\"value\":true}]}",
					"{\"type\":\"assign\",\"variant\":2.0}")))
		#expect(createContext(data).treatment(for: "exp") == 2)
	}

	@Test func hugeAssignVariantIsOutOfBounds() {
		for variant in ["2147483648", "1e300", "-1"] {
			let data = Self.contextData(
				Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":\(variant)}")))
			#expect(createContext(data).treatment(for: "exp") == Self.defaultVariant, "\(variant)")
		}
	}

	@Test func unparseableRulesAreIgnored() {
		for raw in ["not json", "{\"rules\":{}}", "[]"] {
			#expect(
				createContext(Self.contextData(Self.experimentJSON(rules: raw))).treatment(for: "exp") == Self.defaultVariant)
		}
	}

	@Test func nonStringAssignmentRulesOnlyDropThatExperimentsRules() {
		let json = Self.experimentJSON(rules: nil).replacingOccurrences(
			of: "\"assignmentRules\":null", with: "\"assignmentRules\":{\"rules\":[]}")
		let data = Self.contextData(json)
		#expect(data.experiments[0].assignmentRules == nil)
		#expect(data.experiments[0].name == "exp")
	}

	// MARK: - system attributes

	// Rule scope (`environments`) uses the configured environment, even when the user sets an
	// `environment` attribute; that attribute only feeds the rule's conditions.
	@Test func ruleScopeUsesConfiguredEnvironmentNotUserAttribute() {
		let stagingCondition = "{\"eq\":[{\"var\":\"environment\"},{\"value\":\"staging\"}]}"
		let productionScoped = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules(
					"{\"type\":\"assign\",\"variant\":2,\"environments\":[\"production\"],\"conditions\":\(stagingCondition)}"
				)))
		let context = createContext(productionScoped, environment: "production", attributes: ["environment": "staging"])
		#expect(context.treatment(for: "exp") == 2)
		#expect(exposures(context).last?.ruleOverride == true)

		let stagingScoped = Self.contextData(
			Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2,\"environments\":[\"staging\"]}")))
		let other = createContext(stagingScoped, environment: "production", attributes: ["environment": "staging"])
		#expect(other.treatment(for: "exp") != 2)
		#expect(exposures(other).last?.ruleOverride == false)
	}

	// MARK: - revalidation

	// A revalidation that keeps the outcome keeps the cached assignment: after an unrelated attribute
	// change, and after a refresh whose rules changed without changing the outcome, every read gives
	// the same variant and no new exposure is queued.
	@Test(.enabled(if: countsAssignmentWork)) func sameOutcomeRevalidationIsNotRepeated() async throws {
		#if DEBUG
			let audience = "{\"filter\":[{\"eq\":[{\"var\":\"country\"},{\"value\":\"DE\"}]}]}"
			let first = Self.contextData(
				Self.experimentJSON(
					rules: Self.rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(Self.countryNL)}"), audience: audience))
			let context = createContext(first, attributes: ["country": "DE"])

			let variant = context.treatment(for: "exp")
			#expect(variant == Self.defaultVariant)

			func readRepeatedly() {
				for _ in 0..<3 {
					#expect(context.treatment(for: "exp") == variant)
					#expect(context.treatment(for: "exp", exposing: false) == variant)
					#expect(context.variableValue("color") == JSONValue(integerLiteral: Int64(variant)))
				}
			}

			context.setAttribute("unrelated", to: true)
			readRepeatedly()
			// One re-evaluation after the unrelated attribute, then the advanced attrsSeq stamp holds.
			#expect(context.revalidationCount == 1)

			env.serveNext(
				Self.contextData(
					Self.experimentJSON(
						rules: Self.rules(
							"{\"type\":\"assign\",\"variant\":1,\"conditions\":\(Self.countryNL)}",
							"{\"type\":\"assign\",\"variant\":2,\"environments\":[\"staging\"]}"),
						audience: audience)))
			try await context.refresh()

			readRepeatedly()
			// One more after the changed rule JSON, then the advanced ruleKey stamp holds.
			#expect(context.revalidationCount == 2)
			#expect(exposures(context).count == 1)
		#endif
	}

	// A rule-won assignment ignores the audience, so an attribute that flips the audience result
	// neither rebuilds it nor queues a second exposure.
	@Test func ruleWonAssignmentIgnoresAudienceFlips() {
		let audience = "{\"filter\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"gold\"}]}]}"
		let data = Self.contextData(
			Self.experimentJSON(
				rules: Self.rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(Self.countryNL)}"),
				audience: audience, audienceStrict: true))
		let context = createContext(data, attributes: ["country": "NL", "tier": "gold"])

		#expect(context.treatment(for: "exp") == 2)
		context.setAttribute("tier", to: "silver")
		#expect(context.treatment(for: "exp") == 2)
		context.setAttribute("tier", to: "gold")
		#expect(context.treatment(for: "exp") == 2)

		let exposed = exposures(context)
		#expect(exposed.count == 1)
		#expect(exposed.first?.ruleOverride == true)
		#expect(exposed.first?.audienceMismatch == false)
	}

	// Ordinary cached reads (no rules, no audience) never re-evaluate, even after attributes change.
	@Test(.enabled(if: countsAssignmentWork)) func cachedReadsWithoutRulesOrAudienceDoNotRevalidate() {
		#if DEBUG
			let context = env.context()
			_ = context.treatment(for: "exp_test_ab")
			context.setAttribute("age", to: 30)
			for _ in 0..<100 {
				_ = context.treatment(for: "exp_test_ab")
				_ = context.treatment(for: "exp_test_ab", exposing: false)
				_ = context.variableValue("banner.size")
			}
			#expect(context.revalidationCount == 0)
		#endif
	}

	@Test(.enabled(if: countsAssignmentWork)) func rulesAreParsedOnceAtInstall() {
		#if DEBUG
			let count = Locked(0)
			AudienceMatcher.$parseCount.withValue(count) {
				let data = Self.contextData(
					Self.experimentJSON(rules: Self.rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(Self.countryNL)}")))
				let context = createContext(data, attributes: ["country": "NL"])
				#expect(count.withLock { $0 } == 1)
				#expect(context.treatment(for: "exp") == 2)
				for i in 0..<10 {
					context.setAttribute("unrelated", to: i)
					#expect(context.treatment(for: "exp") == 2)
				}
				#expect(context.revalidationCount == 10)
			}
			#expect(count.withLock { $0 } == 1)
		#endif
	}

	@Test(.enabled(if: countsAssignmentWork)) func audiencesAreParsedOnceAtInstall() {
		#if DEBUG
			let count = Locked(0)
			AudienceMatcher.$audienceParseCount.withValue(count) {
				let data = Self.contextData(Self.experimentJSON(
					rules: nil, audience: "{\"filter\":[{\"value\":true}]}"))
				let context = createContext(data)
				#expect(count.withLock { $0 } == 1)
				let variant = context.treatment(for: "exp")
				for i in 0..<5 {
					context.setAttribute("unrelated", to: i)
					#expect(context.treatment(for: "exp") == variant)
					#expect(context.treatment(for: "exp", exposing: false) == variant)
					_ = context.variableValue("color")
				}
				#expect(context.revalidationCount == 5)
			}
			#expect(count.withLock { $0 } == 1)
		#endif
	}

	// MARK: - parsing

	@Test func parseSplitPercentages() {
		#expect(AudienceMatcher.parseSplitPercentages("20/30/50") == [0.2, 0.3, 0.5])
		#expect(AudienceMatcher.parseSplitPercentages("50/50.014") == [0.5, 0.50014])
		#expect(AudienceMatcher.parseSplitPercentages("50/50.015") == nil)
		#expect(AudienceMatcher.parseSplitPercentages("49.99/50") == [0.4999, 0.5])
		#expect(AudienceMatcher.parseSplitPercentages("49.98/50") == nil)
		#expect(AudienceMatcher.parseSplitPercentages(" 50abc/50") == [0.5, 0.5])
		#expect(AudienceMatcher.parseSplitPercentages("100") == [1])
		#expect(AudienceMatcher.parseSplitPercentages("100/") == nil)
		#expect(AudienceMatcher.parseSplitPercentages("Infinity/0") == nil)
		#expect(AudienceMatcher.parseSplitPercentages(100) == nil)
	}

	@Test func parseFloatMatchesJavaScript() {
		#expect(AudienceMatcher.parseFloat("50") == 50)
		#expect(AudienceMatcher.parseFloat("5.") == 5)
		#expect(AudienceMatcher.parseFloat(".5") == 0.5)
		#expect(AudienceMatcher.parseFloat(" -1.5x") == -1.5)
		#expect(AudienceMatcher.parseFloat("1e2") == 1e2)
		#expect(AudienceMatcher.parseFloat("1e") == 1)
		#expect(AudienceMatcher.parseFloat("5.e2") == 500)
		#expect(AudienceMatcher.parseFloat("Infinity") == .infinity)
		#expect(AudienceMatcher.parseFloat("").isNaN)
		#expect(AudienceMatcher.parseFloat("abc").isNaN)
		#expect(AudienceMatcher.parseFloat("\u{FEFF}0") == 0)
		#expect(AudienceMatcher.parseFloat("\u{2029}\u{205F}\u{202F}7") == 7)
		#expect(AudienceMatcher.parseFloat("\u{1E}0").isNaN)
		#expect(AudienceMatcher.parseFloat("\u{85}0").isNaN)
		#expect(AudienceMatcher.parseFloat("\u{200B}0").isNaN)
		#expect(AudienceMatcher.parseFloat(".").isNaN)
	}
}
