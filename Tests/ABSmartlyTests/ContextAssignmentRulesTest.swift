import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class ContextAssignmentRulesTest: XCTestCase {
	var handler = ContextEventHandlerMock()
	var logger = ContextEventLoggerMock()
	var scheduler = SchedulerMock()
	var clock = ClockMock()

	let seedHi = 3_603_515
	let seedLo = 233_373_850
	let trafficSeedHi = 449_867_249
	let trafficSeedLo = 455_443_629

	override func setUp() {
		handler = ContextEventHandlerMock()
		logger = ContextEventLoggerMock()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		clock.millisReturnValue = 1_620_000_000_000
	}

	// A three-variant experiment on `session_id`; each variant sets `color` to its index.
	func experimentJSON(
		rules: String?, name: String = "exp", split: [Double] = [0.34, 0.33, 0.33],
		trafficSplit: [Double] = [0, 1], fullOnVariant: Int = 0, audience: String? = nil,
		audienceStrict: Bool = false
	) -> String {
		func quoted(_ s: String) -> String {
			return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
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

	func contextData(_ experiments: String...) throws -> ContextData {
		let json = "{\"experiments\":[\(experiments.joined(separator: ","))]}"
		return try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
	}

	func rules(_ rules: String...) -> String {
		return "{\"rules\":[\(rules.joined(separator: ","))]}"
	}

	let countryNL = "{\"and\":[{\"eq\":[{\"var\":\"country\"},{\"value\":\"NL\"}]}]}"

	func createContext(
		_ data: ContextData, unit: String? = "unit-1", environment: String? = "production",
		configure: (ContextConfig) -> Void = { _ in }
	) -> Context {
		let config = ContextConfig()
		if let unit = unit {
			config.setUnit(unitType: "session_id", uid: unit)
		}
		configure(config)
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler,
			provider: ContextDataProviderMock(), logger: logger, parser: DefaultVariableParser(),
			matcher: AudienceMatcher(), promise: Promise<ContextData>.value(data), application: "website",
			environment: environment)
	}

	func exposures(_ context: Context) -> [Exposure] {
		return logger.handleEventContextEventReceivedInvocations.compactMap {
			if case let .exposure(exposure) = $0.event { return exposure }
			return nil
		}
	}

	func splitVariant(_ unit: String, _ split: [Double], seedHi: Int, seedLo: Int) -> Int {
		return VariantAssigner(Hashing.hashBytes(unit)).assign(split, seedHi, seedLo)
	}

	// MARK: - assign

	func testAssignRuleWinsAndFlagsExposure() throws {
		let data = try contextData(
			experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(countryNL)}")))
		let context = createContext(data) { $0.setAttribute(name: "country", value: "NL") }

		XCTAssertEqual(2, context.getTreatment("exp"))
		XCTAssertEqual(2, context.getVariableValue("color"))

		let exposure = try XCTUnwrap(exposures(context).first)
		XCTAssertTrue(exposure.ruleOverride)
		XCTAssertFalse(exposure.assigned)
		XCTAssertTrue(exposure.eligible)
		XCTAssertFalse(exposure.overridden)
		XCTAssertFalse(exposure.custom)
		XCTAssertFalse(exposure.fullOn)
	}

	func testNonMatchingRuleFallsBackToNormalAssignment() throws {
		let data = try contextData(
			experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(countryNL)}")))
		let context = createContext(data) { $0.setAttribute(name: "country", value: "DE") }

		let expected = splitVariant("unit-1", [0.34, 0.33, 0.33], seedHi: seedHi, seedLo: seedLo)
		XCTAssertEqual(expected, context.getTreatment("exp"))
		let exposure = try XCTUnwrap(exposures(context).first)
		XCTAssertFalse(exposure.ruleOverride)
		XCTAssertTrue(exposure.assigned)
	}

	func testRuleWithoutConditionsAlwaysMatches() throws {
		let data = try contextData(experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":1}")))
		XCTAssertEqual(1, createContext(data).getTreatment("exp"))
	}

	func testFirstMatchingRuleWins() throws {
		let data = try contextData(
			experimentJSON(
				rules: rules(
					"{\"type\":\"assign\",\"variant\":1,\"conditions\":{\"value\":false}}",
					"{\"type\":\"assign\",\"variant\":2,\"conditions\":\(countryNL)}",
					"{\"type\":\"assign\",\"variant\":0}")))
		let context = createContext(data) { $0.setAttribute(name: "country", value: "NL") }
		XCTAssertEqual(2, context.getTreatment("exp"))
	}

	func testOverrideBeatsRule() throws {
		let data = try contextData(experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2}")))
		let context = createContext(data) { $0.setOverride(experimentName: "exp", variant: 1) }

		XCTAssertEqual(1, context.getTreatment("exp"))
		let exposure = try XCTUnwrap(exposures(context).first)
		XCTAssertTrue(exposure.overridden)
		XCTAssertFalse(exposure.ruleOverride)
	}

	func testRuleBeatsStrictAudienceTrafficFullOnAndCustom() throws {
		let assign = rules("{\"type\":\"assign\",\"variant\":2}")
		let strict = try contextData(
			experimentJSON(rules: assign, audience: "{\"filter\":[{\"value\":false}]}", audienceStrict: true))
		let ineligible = try contextData(experimentJSON(rules: assign, trafficSplit: [1, 0]))
		let fullOn = try contextData(experimentJSON(rules: assign, fullOnVariant: 1))

		for data in [strict, ineligible, fullOn] {
			let context = createContext(data)
			XCTAssertEqual(2, context.getTreatment("exp"))
			let exposure = try XCTUnwrap(exposures(context).last)
			XCTAssertTrue(exposure.ruleOverride)
			XCTAssertFalse(exposure.audienceMismatch)
			XCTAssertTrue(exposure.eligible)
			XCTAssertFalse(exposure.fullOn)
		}

		let custom = createContext(try contextData(experimentJSON(rules: assign))) {
			$0.setCustomAssignment(experimentName: "exp", variant: 0)
		}
		XCTAssertEqual(2, custom.getTreatment("exp"))
		XCTAssertFalse(try XCTUnwrap(exposures(custom).last).custom)
	}

	// A rule winning over a different custom assignment must not look stale and queue an exposure
	// on every call.
	func testRuleWinningOverCustomAssignmentIsCached() throws {
		let data = try contextData(experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2}")))
		let context = createContext(data) { $0.setCustomAssignment(experimentName: "exp", variant: 1) }

		XCTAssertEqual(2, context.getTreatment("exp"))
		XCTAssertEqual(2, context.getTreatment("exp"))
		XCTAssertEqual(2, context.getVariableValue("color"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testEnvironments() throws {
		let data = try contextData(
			experimentJSON(
				rules: rules(
					"{\"type\":\"assign\",\"variant\":1,\"environments\":[\"staging\"]}",
					"{\"type\":\"assign\",\"variant\":2,\"environments\":[\"production\"]}")))
		XCTAssertEqual(2, createContext(data).getTreatment("exp"))
		XCTAssertEqual(1, createContext(data, environment: "staging").getTreatment("exp"))

		// A rule limited to environments never matches when the client has none; an empty list matches any.
		let none = try contextData(
			experimentJSON(
				rules: rules(
					"{\"type\":\"assign\",\"variant\":1,\"environments\":[\"production\"]}",
					"{\"type\":\"assign\",\"variant\":2,\"environments\":[]}")))
		XCTAssertEqual(2, createContext(none, environment: nil).getTreatment("exp"))
	}

	func testConditionsSeeSystemAttributesAndSemver() throws {
		let data = try contextData(
			experimentJSON(
				rules: rules(
					"{\"type\":\"assign\",\"variant\":1,\"conditions\":{\"and\":[{\"eq\":[{\"var\":\"application\"},{\"value\":\"website\"}]},{\"semver_gte\":[{\"var\":\"app_version\"},{\"value\":\"2.0.0\"}]}]}}"
				)))
		XCTAssertEqual(1, createContext(data) { $0.setAttribute(name: "app_version", value: "2.1") }.getTreatment("exp"))
		XCTAssertNotEqual(
			1,
			createContext(data, unit: "unit-2") { $0.setAttribute(name: "app_version", value: "1.9.9") }
				.getTreatment("exp"))
	}

	func testAttributeChangeReevaluatesRules() throws {
		let data = try contextData(
			experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2,\"conditions\":\(countryNL)}")))
		let context = createContext(data)

		let normal = context.getTreatment("exp")
		XCTAssertNotEqual(2, normal)
		context.setAttribute(name: "country", value: "NL")
		XCTAssertEqual(2, context.getTreatment("exp"))
		XCTAssertEqual([false, true], exposures(context).map { $0.ruleOverride })

		// An unrelated attribute change keeps the cached assignment and its exposure.
		context.setAttribute(name: "other", value: 1)
		XCTAssertEqual(2, context.getTreatment("exp"))
		XCTAssertEqual(2, exposures(context).count)
	}

	func testRefreshWithRemovedRulesRebuildsAssignment() throws {
		let context = createContext(
			try contextData(experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2}"))))
		XCTAssertEqual(2, context.getTreatment("exp"))

		let plain = try contextData(experimentJSON(rules: nil))
		context.setData(plain)

		let expected = splitVariant("unit-1", [0.34, 0.33, 0.33], seedHi: seedHi, seedLo: seedLo)
		XCTAssertEqual(expected, context.getTreatment("exp"))
		XCTAssertFalse(try XCTUnwrap(exposures(context).last).ruleOverride)
	}

	func testRefreshWithoutExperimentDropsRuleAssignment() throws {
		let context = createContext(
			try contextData(experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2}"))))
		XCTAssertEqual(2, context.getTreatment("exp"))

		context.setData(try contextData(experimentJSON(rules: nil, name: "other")))
		XCTAssertEqual(0, context.getTreatment("exp"))
		XCTAssertEqual(0, context.peekTreatment("exp"))
	}

	// MARK: - split

	func testSplitHashesWithExperimentSeed() throws {
		let split = [0.2, 0.3, 0.5]
		let data = try contextData(experimentJSON(rules: rules("{\"type\":\"split\",\"percentages\":\"20/30/50\"}")))

		var differsFromTrafficSeed = false
		for i in 0..<50 {
			let unit = "unit-\(i)"
			let expected = splitVariant(unit, split, seedHi: seedHi, seedLo: seedLo)
			if expected != splitVariant(unit, split, seedHi: trafficSeedHi, seedLo: trafficSeedLo) {
				differsFromTrafficSeed = true
			}
			let context = createContext(data, unit: unit)
			XCTAssertEqual(expected, context.getTreatment("exp"), unit)
			XCTAssertTrue(try XCTUnwrap(exposures(context).last).ruleOverride)
		}
		XCTAssertTrue(differsFromTrafficSeed)
	}

	func testSplitEqualToExperimentSplitKeepsVariant() throws {
		let data = try contextData(
			experimentJSON(rules: rules("{\"type\":\"split\",\"percentages\":\"34/33/33\"}")))
		let plain = try contextData(experimentJSON(rules: nil))
		for i in 0..<50 {
			XCTAssertEqual(
				createContext(plain, unit: "u\(i)").getTreatment("exp"),
				createContext(data, unit: "u\(i)").getTreatment("exp"))
		}
	}

	func testSplitWithoutUnitGivesNoUnitResultAndResolvesOnceUnitIsSet() throws {
		let split = rules("{\"type\":\"split\",\"percentages\":\"0/0/100\"}", "{\"type\":\"assign\",\"variant\":1}")
		let context = createContext(try contextData(experimentJSON(rules: split)), unit: nil)

		// First match wins: the split stops evaluation and gives the experiment's no-unit result.
		XCTAssertEqual(0, context.peekTreatment("exp"))
		context.setUnit(unitType: "session_id", uid: "unit-1")
		XCTAssertEqual(2, context.getTreatment("exp"))
		XCTAssertTrue(try XCTUnwrap(exposures(context).last).ruleOverride)

		let fullOn = createContext(
			try contextData(experimentJSON(rules: split, fullOnVariant: 1)), unit: nil)
		XCTAssertEqual(1, fullOn.peekTreatment("exp"))
	}

	func testExposedSplitWithoutUnitStaysPinned() throws {
		let split = rules("{\"type\":\"split\",\"percentages\":\"0/0/100\",\"conditions\":\(countryNL)}")
		let context = createContext(try contextData(experimentJSON(rules: split)), unit: nil) {
			$0.setAttribute(name: "country", value: "NL")
		}

		XCTAssertEqual(0, context.getTreatment("exp"))
		context.setUnit(unitType: "session_id", uid: "unit-1")
		XCTAssertEqual(0, context.getTreatment("exp"))

		// Even an attribute change that re-evaluates the (still matching) rule keeps the variant.
		context.setAttribute(name: "other", value: true)
		XCTAssertEqual(0, context.getTreatment("exp"))
		XCTAssertEqual(1, exposures(context).count)
	}

	func testAssignRuleWithoutUnitKeepsCachedAssignment() throws {
		let context = createContext(
			try contextData(experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":2}"))), unit: nil)
		XCTAssertEqual(2, context.getTreatment("exp"))
		context.setUnit(unitType: "session_id", uid: "unit-1")
		XCTAssertEqual(2, context.getTreatment("exp"))
		XCTAssertEqual(1, exposures(context).count)
	}

	// MARK: - malformed rules

	func testInvalidSplitIsSkipped() throws {
		for percentages in ["\"abc/50/50\"", "\"-10/60/50\"", "\"20/30/40\"", "[20,30,50]", "\"50/50.015/0\""] {
			let data = try contextData(
				experimentJSON(
					rules: rules(
						"{\"type\":\"split\",\"percentages\":\(percentages)}", "{\"type\":\"assign\",\"variant\":1}")))
			XCTAssertEqual(1, createContext(data).getTreatment("exp"), percentages)
		}
	}

	func testSplitWithinTolerance() throws {
		let data = try contextData(
			experimentJSON(
				rules: rules(
					"{\"type\":\"split\",\"percentages\":\"0/0/100.01\"}", "{\"type\":\"assign\",\"variant\":1}")))
		XCTAssertEqual(2, createContext(data).getTreatment("exp"))
	}

	func testWrongCountOrOutOfBoundsStopsRuleEvaluation() throws {
		let expected = splitVariant("unit-1", [0.34, 0.33, 0.33], seedHi: seedHi, seedLo: seedLo)
		for first in ["{\"type\":\"split\",\"percentages\":\"50/50\"}", "{\"type\":\"assign\",\"variant\":3}"] {
			let data = try contextData(
				experimentJSON(rules: rules(first, "{\"type\":\"assign\",\"variant\":\(expected == 2 ? 1 : 2)}")))
			let context = createContext(data)
			XCTAssertEqual(expected, context.getTreatment("exp"), first)
			XCTAssertFalse(try XCTUnwrap(exposures(context).last).ruleOverride)
		}
	}

	func testMalformedRulesAreSkipped() throws {
		let data = try contextData(
			experimentJSON(
				rules: rules(
					"null", "1", "{\"type\":\"unknown\",\"variant\":0}", "{\"type\":\"assign\",\"variant\":1.5}",
					"{\"type\":\"assign\",\"variant\":\"1\"}", "{\"type\":\"assign\",\"variant\":0,\"environments\":\"production\"}",
					"{\"type\":\"assign\",\"variant\":0,\"conditions\":[{\"value\":true}]}",
					"{\"type\":\"assign\",\"variant\":2.0}")))
		XCTAssertEqual(2, createContext(data).getTreatment("exp"))
	}

	func testHugeAssignVariantIsOutOfBounds() throws {
		let expected = splitVariant("unit-1", [0.34, 0.33, 0.33], seedHi: seedHi, seedLo: seedLo)
		for variant in ["2147483648", "1e300", "-1"] {
			let data = try contextData(
				experimentJSON(rules: rules("{\"type\":\"assign\",\"variant\":\(variant)}")))
			XCTAssertEqual(expected, createContext(data).getTreatment("exp"), variant)
		}
	}

	func testUnparseableRulesAreIgnored() throws {
		let expected = splitVariant("unit-1", [0.34, 0.33, 0.33], seedHi: seedHi, seedLo: seedLo)
		for raw in ["not json", "{\"rules\":{}}", "[]"] {
			XCTAssertEqual(expected, createContext(try contextData(experimentJSON(rules: raw))).getTreatment("exp"))
		}
	}

	func testNonStringAssignmentRulesOnlyDropThatExperimentsRules() throws {
		let json = experimentJSON(rules: nil).replacingOccurrences(
			of: "\"assignmentRules\":null", with: "\"assignmentRules\":{\"rules\":[]}")
		let data = try contextData(json)
		XCTAssertNil(data.experiments[0].assignmentRules)
		XCTAssertEqual("exp", data.experiments[0].name)
	}

	// MARK: - parsing

	func testParseSplitPercentages() {
		XCTAssertEqual([0.2, 0.3, 0.5], AudienceMatcher.parseSplitPercentages("20/30/50"))
		XCTAssertEqual([0.5, 0.50014], AudienceMatcher.parseSplitPercentages("50/50.014"))
		XCTAssertNil(AudienceMatcher.parseSplitPercentages("50/50.015"))
		XCTAssertEqual([0.4999, 0.5], AudienceMatcher.parseSplitPercentages("49.99/50"))
		XCTAssertNil(AudienceMatcher.parseSplitPercentages("49.98/50"))
		XCTAssertEqual([0.5, 0.5], AudienceMatcher.parseSplitPercentages(" 50abc/50"))
		XCTAssertEqual([1], AudienceMatcher.parseSplitPercentages("100"))
		XCTAssertNil(AudienceMatcher.parseSplitPercentages("100/"))
		XCTAssertNil(AudienceMatcher.parseSplitPercentages("Infinity/0"))
		XCTAssertNil(AudienceMatcher.parseSplitPercentages(100))
	}

	func testParseFloatMatchesJavaScript() {
		XCTAssertEqual(50, AudienceMatcher.parseFloat("50"))
		XCTAssertEqual(5, AudienceMatcher.parseFloat("5."))
		XCTAssertEqual(0.5, AudienceMatcher.parseFloat(".5"))
		XCTAssertEqual(-1.5, AudienceMatcher.parseFloat(" -1.5x"))
		XCTAssertEqual(1e2, AudienceMatcher.parseFloat("1e2"))
		XCTAssertEqual(1, AudienceMatcher.parseFloat("1e"))
		XCTAssertEqual(500, AudienceMatcher.parseFloat("5.e2"))
		XCTAssertEqual(.infinity, AudienceMatcher.parseFloat("Infinity"))
		XCTAssertTrue(AudienceMatcher.parseFloat("").isNaN)
		XCTAssertTrue(AudienceMatcher.parseFloat("abc").isNaN)
		XCTAssertTrue(AudienceMatcher.parseFloat(".").isNaN)
	}
}
