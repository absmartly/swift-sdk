import Foundation
import Testing

@testable import ABsmartly

@Suite struct SmokeTests {
	@Test func treatmentsMatch1x() async throws {
		let harness = Harness()
		let context = harness.context()
		let expected = ["exp_test_ab": 1, "exp_test_abc": 2, "exp_test_not_eligible": 0, "exp_test_fullon": 2]
		for (name, variant) in expected {
			#expect(context.treatment(for: name) == variant, "\(name)")
		}
		#expect(context.pendingEventCount == 4)
		try await context.publish()
		#expect(harness.transport.publishes.count == 1)
		let fetched = try await harness.client.context(units: Fixtures.units)
		#expect(fetched.treatment(for: "exp_test_abc") == 2)
		#expect(fetched.variable("button.color", default: "x") == "red")
		try await fetched.close()
		#expect(fetched.state == .closed)
	}
}
