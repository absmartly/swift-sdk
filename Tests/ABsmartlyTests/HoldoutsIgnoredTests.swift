import Foundation
import Testing

@testable import ABsmartly

// 2.0.0 does not support holdouts (1.5.x does; they come in a later 2.x). Holdout data in the
// payload is ignored, as 1.4.0 ignored it: units are assigned and exposed as if no holdout existed.
@Suite struct HoldoutsIgnoredTests {
	static let experiment = Fixtures.contextData("holdouts_context").experiments[0]

	// `holdout_a` (id 11) covers `exp_test_holdout`; its arm 0 (10%) would hold the unit out.
	static func heldOutUIDs() -> [String] {
		(0..<400).map { "uid-\($0)" }.filter { uid in
			let assigner = VariantAssigner(unitHash: Hashing.hashUnit(uid))
			return assigner.assign([0.1, 0.9], seedHi: 13, seedLo: 111) == 0
				&& assigner.assign(experiment.split, seedHi: experiment.seedHi, seedLo: experiment.seedLo) == 1
		}
	}

	@Test func holdoutPayloadDecodesLikeTheSamePayloadWithoutHoldouts() throws {
		var object = try #require(
			JSONSerialization.jsonObject(with: Fixtures.data("holdouts_context")) as? [String: Any])
		object["holdouts"] = nil
		var experiments = try #require(object["experiments"] as? [[String: Any]])
		experiments[0]["holdoutIds"] = nil
		object["experiments"] = experiments
		let stripped = try JSONDecoder().decode(
			ContextData.self, from: JSONSerialization.data(withJSONObject: object))

		#expect(Fixtures.contextData("holdouts_context") == stripped)
	}

	@Test func heldOutUnitIsAssignedAndExposedAsIfNoHoldoutExisted() async throws {
		let uids = Self.heldOutUIDs()
		try #require(!uids.isEmpty)
		for uid in uids {
			let env = ContextEnv()
			let context = env.context("holdouts_context", units: [.sessionID: uid])

			#expect(context.variable("banner.size", default: "small", exposing: false) == "large")
			#expect(context.treatment(for: "exp_test_holdout") == 1)
			#expect(context.variable("banner.size", default: "small") == "large")
			#expect(
				env.log.exposures == [
					exposure(1, "exp_test_holdout", "session_id", 1, true, true, false, false, false, false)
				])

			try await context.publish()
			let units = [PublishEvent.Unit(type: "session_id", uid: unitHash(uid))]
			#expect(
				env.lastSentEvent
					== expectedBody(
						units: units,
						exposures: [exposure(1, "exp_test_holdout", "session_id", 1, true, true, false, false, false, false)]))
		}
	}
}
