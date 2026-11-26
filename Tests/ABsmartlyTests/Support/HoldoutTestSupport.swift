import Foundation
import Testing

@testable import ABsmartly

/// Payload builders for the holdout tests: the values of 1.5.0's `ContextHoldoutTest`, so both
/// majors pin the same arms.
///
/// A holdout arrives in `ContextData.holdouts`; an experiment declares the holdouts covering it in
/// `holdoutIds`. Arm 0 holds the unit out of every covered experiment; in a 3-arm holdout arm 1
/// holds out only experiments that are not full-on. A held-out unit gets control (variant 0) and no
/// exposure of its own; every covering holdout publishes one ordinary exposure per epoch.
enum Holdouts {
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

	static func experiment(
		_ id: Int, _ name: String, unitType: String = unitType, fullOnVariant: Int = 0, holdoutIds: [Int]? = nil,
		split: [Double] = [0.5, 0.5], configs: [String?] = [nil, nil], audience: String? = nil,
		audienceStrict: Bool = false, assignmentRules: String? = nil
	) -> [String: Any] {
		var experiment: [String: Any] = [
			"id": id, "name": name, "unitType": unitType, "iteration": 1, "seedHi": 100, "seedLo": 200,
			"split": split, "trafficSeedHi": 1, "trafficSeedLo": 2, "trafficSplit": [0.0, 1.0],
			"fullOnVariant": fullOnVariant, "applications": [["name": "website"]],
			"variants": configs.enumerated().map {
				["name": "\($0.offset)", "config": $0.element as Any? ?? NSNull()]
			},
			"audienceStrict": audienceStrict, "audience": audience as Any? ?? NSNull(),
		]
		if let holdoutIds {
			experiment["holdoutIds"] = holdoutIds
		}
		if let assignmentRules {
			experiment["assignmentRules"] = assignmentRules
		}
		return experiment
	}

	static func withVariables(_ key: String) -> [String?] {
		["{\"\(key)\":\"control\"}", "{\"\(key)\":\"treatment\"}"]
	}

	static func holdout(
		_ id: Int, _ name: String, unitType: String = unitType, seeds: (seedHi: Int, seedLo: Int),
		split: [Double] = [0.1, 0.9], holdoutType: String? = "full", iteration: Int = 1
	) -> [String: Any] {
		var holdout: [String: Any] = [
			"id": id, "name": name, "unitType": unitType, "iteration": iteration, "seedHi": seeds.seedHi,
			"seedLo": seeds.seedLo, "split": split, "trafficSplit": [0.0, 1.0], "fullOnVariant": 0,
			"applications": [] as [Any], "variants": split.indices.map { ["name": "\($0)", "config": NSNull()] },
			"audienceStrict": false, "audience": NSNull(),
		]
		if let holdoutType {
			holdout["holdoutType"] = holdoutType
		}
		return holdout
	}

	static func threeArmHoldout(_ id: Int, _ name: String, seeds: (seedHi: Int, seedLo: Int)) -> [String: Any] {
		holdout(id, name, seeds: seeds, split: threeArmSplit, holdoutType: "all_full_on")
	}

	static func payload(_ experiments: [[String: Any]], holdouts: [Any]? = nil) -> Data {
		var payload: [String: Any] = ["experiments": experiments]
		if let holdouts {
			payload["holdouts"] = holdouts
		}
		return try! JSONSerialization.data(withJSONObject: payload)
	}

	static func contextData(_ experiments: [[String: Any]], holdouts: [Any]? = nil) -> ContextData {
		decode(payload(experiments, holdouts: holdouts))
	}

	static func decode(_ json: Data) -> ContextData {
		do {
			return try JSONDecoder().decode(ContextData.self, from: json)
		} catch {
			Issue.record("ContextData failed to decode: \(error)")
			return ContextData()
		}
	}

	/// The exposure a holdout publishes for its arm.
	static func held(_ id: Int, _ name: String, _ variant: Int, unitType: String = unitType) -> Exposure {
		ABsmartlyTests.exposure(id, name, unitType, variant, true, true, false, false, false, false)
	}

	/// A covered experiment's own exposure.
	static func own(
		_ id: Int, _ name: String, _ variant: Int, unitType: String = unitType, assigned: Bool = true,
		overridden: Bool = false, fullOn: Bool = false, custom: Bool = false, audienceMismatch: Bool = false,
		ruleOverride: Bool = false
	) -> Exposure {
		ABsmartlyTests.exposure(
			id, name, unitType, variant, assigned, true, overridden, fullOn, custom, audienceMismatch,
			ruleOverride: ruleOverride)
	}
}

/// A `ContextEnv` with the holdout tests' helpers: contexts on one `session_id` unit, refreshes that
/// install a given payload, and publish assertions.
struct HoldoutEnv {
	let env: ContextEnv

	init(clock: Clock = FixedClock(value: Fixtures.now), options: Context.Options = Context.Options(publishDelay: -1)) {
		env = ContextEnv(options: options, clock: clock)
	}

	func context(
		_ data: ContextData, uid: String? = Holdouts.uid, units: [UnitType: String] = [:],
		attributes: [String: JSONValue] = [:], overrides: [String: Int] = [:], customAssignments: [String: Int] = [:]
	) -> Context {
		var all = units
		if let uid {
			all[UnitType(Holdouts.unitType)] = uid
		}
		return env.directContext(
			data: data, units: all, attributes: attributes, overrides: overrides, customAssignments: customAssignments)
	}

	/// Installs `data` through a refresh (1.5.0's `setData`).
	func refresh(_ context: Context, _ data: ContextData) async throws {
		env.serveNext(data)
		try await context.refresh()
	}

	var exposures: [Exposure] { env.log.exposures }

	/// The variable's value, or `"default"` when there is none.
	func value(_ context: Context, _ key: String, peek: Bool = false) -> JSONValue {
		context.variableValue(key, exposing: !peek) ?? "default"
	}
	var errors: [ABsmartlyError] { env.log.errors }

	/// Publishes and returns the exposures sent.
	func publishedExposures(_ context: Context) async throws -> [Exposure] {
		let before = env.publishCount
		try await context.publish()
		#expect(env.publishCount == before + 1)
		return env.log.publishes.last?.exposures ?? []
	}

	/// Publishes and expects exactly these exposures (and attributes) for one unit.
	func expectPublished(
		_ context: Context, _ exposures: [Exposure], unitType: String = Holdouts.unitType, uid: String = Holdouts.uid,
		attributes: [PublishEvent.Attribute] = [], sourceLocation: SourceLocation = #_sourceLocation
	) async throws {
		let before = env.publishCount
		try await context.publish()
		#expect(env.publishCount == before + 1, sourceLocation: sourceLocation)
		#expect(
			env.lastSentEvent
				== expectedBody(
					units: [PublishEvent.Unit(type: unitType, uid: unitHash(uid))], exposures: exposures,
					attributes: attributes), sourceLocation: sourceLocation)
	}
}
