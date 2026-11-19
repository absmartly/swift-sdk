import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// Cross-sdk-tests switchback scenario shapes that no java-sdk test covers directly: three or more
// sources whose JSON order is not alphabetical (425), a switchback with a covering holdout and an
// assignment rule in one payload (424), and a publish byte probe for unit experiments carrying every
// R33 field (420/421).
final class SwitchbackScenarioTest: SwitchbackTestCase {
	// Scenario 425's grid: a 400,000 h period keeps "now" in period 0 for decades.
	static let periodMs: Int64 = 1_440_000_000_000
	static let anchor: Int64 = 1_704_067_200_000

	func scenarioSwitchback(
		_ id: Int, _ name: String, unitType: String, clusters: [(String, Any)], trafficSeedLo: Int = 2,
		trafficSplit: [Double] = [0, 1], extra: [String: Any] = [:]
	) -> [String: Any] {
		var experiment: [String: Any] = [
			"id": id, "name": name, "iteration": 1, "unitType": unitType, "seedHi": -559_038_737,
			"seedLo": 1_234_567_890, "split": [0.34, 0.33, 0.33], "trafficSeedHi": 1, "trafficSeedLo": trafficSeedLo,
			"trafficSplit": trafficSplit, "fullOnVariant": 0, "applications": [["name": "website"]],
			"variants": [["name": "A", "config": NSNull()], ["name": "B", "config": NSNull()], ["name": "C", "config": NSNull()]],
			"audience": NSNull(), "audienceStrict": false, "customFieldValues": NSNull(), "randomizationType": "switchback",
			"switchbackClusters": SB.OrderedObject(clusters), "switchbackStartAt": Self.anchor,
			"switchbackPeriodMs": Self.periodMs, "switchbackCarryoverDurationMs": 0, "switchbackBurnInDurationMs": 0,
			"switchbackBurnOutDurationMs": 0, "switchbackDesignType": "balanced_block",
			"switchbackEstimand": "global_average_treatment_effect",
		]
		for (key, value) in extra {
			experiment[key] = value
		}
		return experiment
	}

	func scenarioExposure(_ id: Int, _ name: String, _ unit: String, _ variant: Int, assigned: Bool = true,
		ruleOverride: Bool = false) -> Exposure
	{
		return Exposure(id, name, unit, variant, clock.now, assigned, true, false, false, false, false, ruleOverride: ruleOverride)
	}

	// Scenario 425: three sources in a declared order that is neither alphabetical nor reverse
	// alphabetical. Every source has the same value, so the first declared unit serves; each traffic
	// split admits only that unit's uid, so a sorted map would serve another unit and miss traffic.
	func testManySourcesKeepTheDeclaredOrder() {
		let userFirst = scenarioSwitchback(
			480, "exp_sb_many_user_first", unitType: "user_id",
			clusters: [("user_id", "profile/city"), ("device_id", "device/city"), ("store_id", "store_city")],
			trafficSeedLo: 1, trafficSplit: [0.5, 0.5])
		let storeFirst = scenarioSwitchback(
			481, "exp_sb_many_store_first", unitType: "store_id",
			clusters: [("store_id", "store_city"), ("user_id", "profile/city"), ("device_id", "device/city")],
			trafficSeedLo: 3, trafficSplit: [0.5, 0.5])
		clock.now = Self.anchor + 1000
		let context = createContext(
			SB.data([userFirst, storeFirst]),
			units: ["store_id": "many-store-15", "device_id": "many-device-14", "user_id": "many-user-26"],
			clusterAttribute: false)
		context.setAttribute(name: "store_city", value: JSON("many-3"))
		context.setAttribute(name: "device", value: JSON(["city": "many-3"]))
		context.setAttribute(name: "profile", value: JSON(["city": "many-3"]))

		XCTAssertEqual(
			["user_id", "device_id", "store_id"],
			context.getContextData()?.experiments[0].switchbackClusters?.map { $0.unitType })
		XCTAssertEqual(1, context.getTreatment("exp_sb_many_user_first"))
		XCTAssertEqual(1, context.getTreatment("exp_sb_many_store_first"))
		XCTAssertEqual(
			[
				scenarioExposure(480, "exp_sb_many_user_first", "user_id", 1),
				scenarioExposure(481, "exp_sb_many_store_first", "store_id", 1),
			], publishExposures(context))
	}

	// Scenario 424: a holdout whose split [1, 0] holds every store_id unit out covers two switchbacks.
	// The one with an assign rule serves the rule's variant (ruleOverride), the other the draw; the
	// holdout is never consulted and records no exposure.
	func testHoldoutAndAssignmentRuleTheRuleWinsAndTheHoldoutIsNeverConsulted() {
		let rule = scenarioSwitchback(
			470, "exp_sb_holdout_rule", unitType: "store_id", clusters: [("store_id", "city")],
			extra: [
				"holdoutIds": [2],
				"assignmentRules": "{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":1}]}",
			])
		let noRule = scenarioSwitchback(
			471, "exp_sb_holdout_no_rule", unitType: "store_id", clusters: [("store_id", "city")],
			extra: ["holdoutIds": [2]])
		let holdout: [String: Any] = [
			"id": 2, "name": "holdout_sb_rule", "iteration": 1, "unitType": "store_id", "seedHi": 13, "seedLo": 111,
			"split": [1.0, 0.0], "trafficSeedHi": 0, "trafficSeedLo": 0, "trafficSplit": [0, 1], "fullOnVariant": 0,
			"applications": [] as [Any], "variants": [["name": "A", "config": NSNull()], ["name": "B", "config": NSNull()]],
			"audience": NSNull(), "audienceStrict": false, "customFieldValues": NSNull(), "holdoutType": "full",
		]
		clock.now = Self.anchor + 1000
		let context = createContext(
			SB.data([rule, noRule], holdouts: [holdout]), units: ["store_id": "holdrule-20"], clusterAttribute: false)
		context.setAttribute(name: "city", value: JSON("hr-0"))

		// The period-0 draw for cluster "hr-0" is 2.
		XCTAssertEqual(2, SB.draw("hr-0", 0, arms: 3, seed: (Int64(-559_038_737) << 32) | 1_234_567_890))
		XCTAssertEqual(1, context.getTreatment("exp_sb_holdout_rule"))
		XCTAssertEqual(2, context.getTreatment("exp_sb_holdout_no_rule"))
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(
			[
				scenarioExposure(470, "exp_sb_holdout_rule", "store_id", 1, assigned: false, ruleOverride: true),
				scenarioExposure(471, "exp_sb_holdout_no_rule", "store_id", 2),
			], publishExposures(context))
	}

	// A unit experiment carrying every R33 field publishes byte-identical JSON to the plain one, and a
	// payload without switchbacks publishes the same bytes it did before.
	func testUnitExperimentWithEveryR33FieldPublishesTheSameBytes() {
		let plain: [String: Any] = [
			"id": 514, "name": "exp_unit", "iteration": 1, "unitType": "store_id", "seedHi": -559_038_737,
			"seedLo": 1_234_567_890, "split": [0.34, 0.33, 0.33], "trafficSeedHi": 1, "trafficSeedLo": 2,
			"trafficSplit": [0, 1], "fullOnVariant": 0, "applications": [["name": "website"]],
			"variants": [["name": "A", "config": NSNull()], ["name": "B", "config": NSNull()], ["name": "C", "config": NSNull()]],
			"audienceStrict": false,
		]
		var withFields = plain
		withFields["randomizationType"] = "unit"
		withFields["switchbackClusters"] = SB.OrderedObject([("store_id", "city"), ("user_id", "profile/city")])
		withFields["switchbackClusterValues"] = ["market_1"]
		withFields["switchbackStartAt"] = Self.anchor
		withFields["switchbackPeriodMs"] = Self.periodMs
		withFields["switchbackCarryoverDurationMs"] = 0
		withFields["switchbackBurnInDurationMs"] = 0
		withFields["switchbackBurnOutDurationMs"] = 0
		withFields["switchbackDesignType"] = "balanced_block"
		withFields["switchbackEstimand"] = "global_average_treatment_effect"

		func publishedBytes(_ experiment: [String: Any]) -> String {
			setUp()
			clock.now = Self.anchor + 1000
			let context = createContext(SB.data([experiment]), units: ["store_id": "serving-9"])
			context.setAttribute(name: "city", value: JSON("market_1"))
			let variant = context.getTreatment("exp_unit")
			clock.now = Self.anchor + 2000
			_ = context.getTreatment("exp_unit")
			XCTAssertEqual(variant, context.peekTreatment("exp_unit"))
			guard let event = publish(context) else {
				XCTFail("nothing published")
				return ""
			}
			return encoded(event)
		}

		let baseline = publishedBytes(plain)
		XCTAssertEqual(baseline, publishedBytes(withFields))
		// The exposure is the unit experiment's: exposed once, at the enqueue time, under its unitType.
		XCTAssertTrue(baseline.contains("\"exposedAt\":\(Self.anchor + 1000)"), baseline)
		XCTAssertTrue(baseline.contains("\"unit\":\"store_id\""), baseline)
		XCTAssertEqual(1, baseline.components(separatedBy: "\"exposedAt\"").count - 1, baseline)
		for field in ["randomizationType", "switchback", "cluster", "period"] {
			XCTAssertFalse(baseline.contains(field), "\(field) in \(baseline)")
		}
	}
}
