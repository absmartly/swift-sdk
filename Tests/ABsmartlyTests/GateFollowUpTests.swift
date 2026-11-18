import Foundation
import Testing

@testable import ABsmartly

// Contracts pinned after the independent review of fe05bcd: atomic single-key overrides, the
// setOverrides merge direction, refresh on a failed context, and a JSON-null custom field.
@Suite struct GateFollowUpTests {
	// 1.5.0's setOverride/setCustomAssignment never lost a concurrent write; the 2.0 single-key
	// mutators must not either.
	@Test func concurrentSingleKeyOverridesAreNotLost() {
		let context = Harness().context()
		DispatchQueue.concurrentPerform(iterations: 400) { i in
			context.setOverride(i % 3, for: "exp_\(i)")
			context.setCustomAssignment(i % 2, for: "exp_\(i)")
		}
		#expect(context.overrides.count == 400)
		#expect(context.customAssignments.count == 400)
		#expect(context.overrides["exp_7"] == 1)
		#expect(context.customAssignments["exp_7"] == 1)
	}

	@Test func setOverrideNilRemovesIt() {
		let context = Harness().context()
		context.setOverride(2, for: "exp_test_ab")
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 2)
		context.setOverride(nil, for: "exp_test_ab")
		#expect(context.overrides["exp_test_ab"] == nil)
		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 1)
		context.setCustomAssignment(2, for: "exp_test_ab")
		context.setCustomAssignment(nil, for: "exp_test_ab")
		#expect(context.customAssignments.isEmpty)
	}

	// setOverrides/setCustomAssignments replace an existing value for the same experiment.
	@Test func setOverridesReplacesExistingValues() {
		let context = Harness().context()
		context.setOverride(1, for: "exp_test_ab")
		context.setOverrides(["exp_test_ab": 2])
		#expect(context.treatment(for: "exp_test_ab") == 2)
		context.setCustomAssignment(0, for: "exp_test_abc")
		context.setCustomAssignments(["exp_test_abc": 1])
		#expect(context.customAssignments["exp_test_abc"] == 1)
		#expect(context.treatment(for: "exp_test_abc") == 1)
	}

	// 1.5.0 (JS context.ts _refresh): a failed context stays failed; refresh succeeds without fetching.
	@Test func refreshOnFailedContextDoesNotFetch() async throws {
		let env = ContextEnv()
		let context = await env.failedContext()
		let requestsBefore = env.transport.requests.count
		env.serveNext("refreshed")
		try await context.refresh()
		#expect(env.transport.requests.count == requestsBefore)
		#expect(context.state == .failed(.transport("test")))
		#expect(context.experiments.isEmpty)
	}

	// 1.5.0: a `json` custom field whose value is JSON `null` has no value.
	@Test func jsonNullCustomFieldHasNoValue() throws {
		let json = #"""
			{"experiments":[{"id":1,"name":"exp","unitType":"session_id","iteration":1,"seedHi":1,"seedLo":2,
			"split":[0.5,0.5],"trafficSeedHi":3,"trafficSeedLo":4,"trafficSplit":[0,1],"fullOnVariant":0,
			"variants":[{"name":"A","config":null},{"name":"B","config":null}],
			"customFieldValues":[{"name":"empty","type":"json","value":"null"},{"name":"list","type":"json","value":"[1]"}]}]}
			"""#
		let data = try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
		let context = Harness().context(data: data)
		#expect(context.customFieldValue("empty", in: "exp") == nil)
		#expect(context.customFieldType("empty", in: "exp") == "json")
		#expect(context.customFieldKeys(in: "exp").sorted() == ["empty", "list"])
		#expect(context.customFieldValue("list", in: "exp") == [1])
	}
}
