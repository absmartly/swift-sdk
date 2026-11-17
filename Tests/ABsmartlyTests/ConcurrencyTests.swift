// Port of the 1.x ConcurrencyTests.swift (7 tests) to the 2.0 API. Work that 1.x dispatched onto a
// concurrent DispatchQueue runs in a task group here, which spreads it over the cooperative pool's
// threads in the same way. Every test is ported.

import Foundation
import Testing

@testable import ABsmartly

@Suite struct ConcurrencyTests {
	@Test func concurrentTreatmentAccess() async {
		let env = ContextEnv()
		let context = env.context()
		let experimentNames = ["exp_test_ab", "exp_test_abc", "exp_test_fullon", "exp_test_not_eligible"]

		let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
			for i in 0..<100 {
				group.addTask { context.treatment(for: experimentNames[i % experimentNames.count]) }
			}
			return await group.reduce(into: []) { $0.append($1) }
		}

		#expect(results.count == 100)
		#expect(results.allSatisfy { $0 >= 0 })
		#expect(context.pendingEventCount > 0)
	}

	@Test func concurrentGoalTracking() async {
		let env = ContextEnv()
		let context = env.context()
		let goalNames = ["goal_1", "goal_2", "goal_3", "goal_4", "goal_5"]

		await withTaskGroup(of: Void.self) { group in
			for i in 0..<100 {
				group.addTask {
					context.track(
						goalNames[i % goalNames.count],
						properties: ["iteration": i.jsonValue, "timestamp": Date().timeIntervalSince1970.jsonValue])
				}
			}
		}

		#expect(context.pendingEventCount == 100)
	}

	@Test func raceConditionStateChange() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<50 {
				group.addTask { context.track("goal_during_init", properties: nil) }
			}
			group.addTask {
				await pause(0.1)
				gate.fulfill(fixture: "context")
			}
		}

		try await context.ready()
		#expect(context.state == .ready)
		#expect(context.pendingEventCount == 50)
	}

	@Test func concurrentRefreshAndPublish() async throws {
		let env = ContextEnv()
		let context = env.context()

		context.track("test_goal", properties: nil)
		_ = context.treatment(for: "exp_test_ab")

		env.serveNext("refreshed")

		async let refreshed: Void = context.refresh()
		async let published: Void = context.publish()
		try await refreshed
		try await published

		#expect(context.state == .ready)
	}

	@Test func asyncAwaitEdgeCases() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()

		#expect(context.state == .loading)

		#expect(context.treatment(for: "exp_test_ab", exposing: false) == 0)
		#expect(env.log.last == .error(.notReady))
		#expect(env.log.errorMessages.last == "ABsmartly Context is not yet ready.")

		context.overrides["exp_test_override"] = 5
		context.setAttribute("test_attr", to: "test_value")

		gate.fulfill(fixture: "context")
		try await context.ready()

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(context.overrides["exp_test_override"] == 5)
		#expect(context.attribute("test_attr") == "test_value")
	}

	@Test func concurrentSetAndGetUnits() async {
		let env = ContextEnv()
		let context = env.context(units: [:])

		await withTaskGroup(of: Void.self) { group in
			for i in 0..<50 {
				group.addTask { try? context.setUnit(UnitType("user_\(i)"), to: "uid_\(i)") }
			}
			for _ in 0..<50 {
				group.addTask { _ = context.units }
			}
		}

		#expect(context.units.count == 50)
	}

	@Test func concurrentAttributeAccess() async {
		let env = ContextEnv()
		let context = env.context()

		await withTaskGroup(of: Void.self) { group in
			for i in 0..<100 {
				group.addTask { context.setAttribute("attr_\(i)", to: "value_\(i)") }
			}
			for _ in 0..<100 {
				group.addTask { _ = context.attributes }
			}
		}

		#expect(context.attributes.count == 100)
	}
}
