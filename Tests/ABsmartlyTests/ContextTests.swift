import Foundation
import Testing

@testable import ABsmartly

@Suite struct ContextTests {
	// MARK: - Construction and readiness

	@Test func constructorSetsOverrides() {
		let env = ContextEnv()
		let overrides = ["exp_test": 2, "exp_test_1": 1]
		let context = env.context(overrides: overrides)
		for (name, variant) in overrides {
			#expect(context.overrides[name] == variant)
		}
	}

	@Test func constructorSetsCustomAssignments() {
		let env = ContextEnv()
		let assignments = ["exp_test": 2, "exp_test_1": 1]
		let context = env.context(customAssignments: assignments)
		for (name, variant) in assignments {
			#expect(context.customAssignments[name] == variant)
		}
	}

	@Test func becomesReadyWithFulfilledPromise() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)
		#expect(context.contextData == Fixtures.contextData())
	}

	@Test func becomesReadyAndFailedWithFulfilledErrorPromise() async {
		let env = ContextEnv()
		let context = await env.failedContext()
		#expect(context.state.isSettled)
		#expect(context.state == .failed(.transport("test")))
	}

	@Test func failedContextHoldsEmptyDataAndReturnsDefaults() async {
		let env = ContextEnv()
		let context = await env.failedContext()
		#expect(context.state == .failed(.transport("test")))
		let data = context.contextData
		#expect(data != nil)
		#expect(data?.experiments.count == 0)
		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(context.variable("banner.size", default: 17) == 17)
	}

	@Test func becomesReadyAndFailedWithErrorPromise() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		gate.reject(TestError("test"))
		await #expect(throws: ABsmartlyError.transport("test")) { try await context.ready() }
		#expect(context.state.isSettled)
		#expect(context.state == .failed(.transport("test")))
	}

	@Test func readyErrorReturnsNilOnSuccess() {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)
	}

	@Test func readyErrorReturnsErrorOnFulfilledFailure() async {
		let env = ContextEnv()
		let context = await env.failedContext()
		guard case .failed = context.state else {
			Issue.record("expected a failed context, got \(context.state)")
			return
		}
	}

	@Test func readyErrorReturnsErrorOnAsyncFailure() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		gate.reject(TestError("test"))
		try? await context.ready()
		#expect(context.state == .failed(.transport("test")))
	}

	@Test func callsEventLoggerWhenReady() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		gate.fulfill(fixture: "context")
		try await context.ready()

		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .ready(Fixtures.contextData()))
	}

	@Test func callsEventLoggerWithFulfilledPromise() {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .ready(data))
	}

	@Test func callsEventLoggerWithErrorPromise() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		gate.reject(TestError("test"))
		try? await context.ready()

		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .error(.transport("test")))
	}

	@Test func callsEventLoggerWithFulfilledErrorPromise() async {
		let env = ContextEnv()
		let context = await env.failedContext()

		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .error(.transport("test")))
	}

	@Test func waitUntilReady() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		gate.fulfill(fixture: "context")
		try await context.ready()
		#expect(context.state == .ready)
	}

	@Test func waitUntilReadyWithFulfilledPromise() async throws {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)

		try await context.ready()
		#expect(context.state == .ready)
	}

	@Test func getExperiments() {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)
		#expect(context.state == .ready)
		#expect(context.experiments == data.experiments.map(\.name))
	}

	// MARK: - Timers

	@Test func startsRefreshTimerWhenReady() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext(options: Context.Options(publishDelay: -1, refreshInterval: 0.05))
		gate.fulfill(fixture: "context")
		try await context.ready()

		// The initial load only; the timer has not fired yet.
		#expect(env.getCount == 1)

		// The timer fires and refreshes.
		#expect(await eventually(timeout: 5) { env.getCount >= 2 })
		try await context.close()
	}

	@Test func doesNotStartRefreshTimerWhenFailed() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext(options: Context.Options(publishDelay: -1, refreshInterval: 0.05))
		gate.reject(TestError("test"))
		try? await context.ready()

		await pause(0.15)
		#expect(env.getCount == 1)
	}

	@Test func startsPublishTimeoutWhenReadyWithQueueNotEmpty() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext(options: Context.Options(publishDelay: 0.01))
		#expect(context.state == .loading)

		context.track("test_goal", properties: ["amount": 100])
		gate.fulfill(fixture: "context")
		try await context.ready()

		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(env.lastSentEvent == expectedBody(goals: [goal("test_goal", ["amount": 100])]))
	}

	// MARK: - Units and attributes

	@Test func setUnits() throws {
		let env = ContextEnv()
		let context = env.context(units: [:])

		try context.setUnit("anonymous_id", to: "0ab1e-23f4-feee")
		#expect(context.units["anonymous_id"] == "0ab1e-23f4-feee")

		try context.setUnits([.sessionID: "0ab1e23f4eee", .userID: "1234567890"])
		#expect(
			context.units == [.sessionID: "0ab1e23f4eee", .userID: "1234567890", "anonymous_id": "0ab1e-23f4-feee"])
	}

	@Test func setUnitsBeforeReady() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext(units: [:])
		#expect(context.state == .loading)

		try context.setUnits(Fixtures.units)
		gate.fulfill(fixture: "context")
		try await context.ready()

		_ = context.treatment(for: "exp_test_ab")
		try await context.publish()

		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(exposures: [exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false)]))
	}

	@Test func setAttributes() {
		let env = ContextEnv()
		let context = env.context(units: [:])

		context.setAttribute("attr1", to: "value1")
		#expect(context.attribute("attr1") == "value1")

		context.setAttributes(["attr2": "value2", "attr3": 3])
		#expect(context.attributes == ["attr1": "value1", "attr2": "value2", "attr3": 3])
	}

	@Test func setAttributesBeforeReady() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		context.setAttribute("attr1", to: "value1")
		context.setAttributes(["attr2": "value2"])
		#expect(context.attributes == ["attr1": "value1", "attr2": "value2"])

		gate.fulfill(fixture: "context")
		try? await context.ready()
	}

	// MARK: - Overrides and custom assignments

	@Test func setOverride() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		context.overrides["exp_test"] = 2
		#expect(context.overrides["exp_test"] == 2)

		context.overrides["exp_test"] = 3
		#expect(context.overrides["exp_test"] == 3)

		context.overrides["exp_test_2"] = 1
		#expect(context.overrides["exp_test_2"] == 1)

		context.setOverrides(["exp_test_new": 3, "exp_test_new_2": 5])
		#expect(context.overrides["exp_test_new"] == 3)
		#expect(context.overrides["exp_test_new_2"] == 5)
		#expect(context.overrides["exp_test_not_found"] == nil)

		gate.fulfill(fixture: "context")
		try await context.ready()

		#expect(context.overrides["exp_test"] == 3)
		#expect(context.overrides["exp_test_2"] == 1)
		#expect(context.overrides["exp_test_new"] == 3)
		#expect(context.overrides["exp_test_new_2"] == 5)
		#expect(context.overrides["exp_test_not_found"] == nil)
	}

	@Test func setOverrideClearsAssignmentCache() {
		let env = ContextEnv()
		let context = env.context()

		let overrides = ["exp_test_new": 3, "exp_test_new_2": 5]
		context.setOverrides(overrides)

		for (key, value) in overrides { #expect(context.treatment(for: key) == value) }
		#expect(context.pendingEventCount == overrides.count)

		// overriding again with the same variant shouldn't clear assignment cache
		for (key, value) in overrides {
			context.overrides[key] = value
			#expect(context.treatment(for: key) == value)
		}
		#expect(context.pendingEventCount == overrides.count)

		// overriding with the different variant should clear assignment cache
		for (key, value) in overrides {
			context.overrides[key] = value + 11
			#expect(context.treatment(for: key) == value + 11)
		}
		#expect(context.pendingEventCount == 2 * overrides.count)

		// overriding a computed assignment should clear assignment cache
		#expect(context.treatment(for: "exp_test_ab") == ContextFixtures.expectedVariants["exp_test_ab"])
		#expect(context.pendingEventCount == 1 + 2 * overrides.count)

		context.overrides["exp_test_ab"] = 9
		#expect(context.treatment(for: "exp_test_ab") == 9)
		#expect(context.pendingEventCount == 2 + 2 * overrides.count)
	}

	@Test func setCustomAssignment() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		context.customAssignments["exp_test"] = 2
		#expect(context.customAssignments["exp_test"] == 2)

		context.customAssignments["exp_test"] = 3
		#expect(context.customAssignments["exp_test"] == 3)

		context.customAssignments["exp_test_2"] = 1
		#expect(context.customAssignments["exp_test_2"] == 1)

		context.setCustomAssignments(["exp_test_new": 3, "exp_test_new_2": 5])
		#expect(context.customAssignments["exp_test_new"] == 3)
		#expect(context.customAssignments["exp_test_new_2"] == 5)
		#expect(context.customAssignments["exp_test_not_found"] == nil)

		gate.fulfill(fixture: "context")
		try await context.ready()

		#expect(context.customAssignments["exp_test"] == 3)
		#expect(context.customAssignments["exp_test_2"] == 1)
		#expect(context.customAssignments["exp_test_new"] == 3)
		#expect(context.customAssignments["exp_test_new_2"] == 5)
		#expect(context.customAssignments["exp_test_not_found"] == nil)
	}

	@Test func setCustomAssignmentDoesNotOverrideFullOnOrNotEligibleAssignments() {
		let env = ContextEnv()
		let context = env.context()

		context.setCustomAssignments(["exp_test_not_eligible": 3, "exp_test_fullon": 3])

		#expect(context.treatment(for: "exp_test_not_eligible") == 0)
		#expect(context.treatment(for: "exp_test_fullon") == 2)
	}

	@Test func setCustomAssignmentClearsAssignmentCache() {
		let env = ContextEnv()
		let context = env.context()

		let assignments = ["exp_test_ab": 2, "exp_test_abc": 3]

		for key in assignments.keys {
			#expect(context.treatment(for: key) == ContextFixtures.expectedVariants[key])
		}
		#expect(context.pendingEventCount == assignments.count)

		context.setCustomAssignments(assignments)

		for (key, value) in assignments {
			context.customAssignments[key] = value
			#expect(context.treatment(for: key) == value)
		}
		#expect(context.pendingEventCount == 2 * assignments.count)

		// overriding with the same variant shouldn't clear assignment cache
		for (key, value) in assignments {
			context.customAssignments[key] = value
			#expect(context.treatment(for: key) == value)
		}
		#expect(context.pendingEventCount == 2 * assignments.count)

		// overriding with the different variant should clear assignment cache
		for (key, value) in assignments {
			context.customAssignments[key] = value + 11
			#expect(context.treatment(for: key) == value + 11)
		}
		#expect(context.pendingEventCount == 3 * assignments.count)
	}
}
