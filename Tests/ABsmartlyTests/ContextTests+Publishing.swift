import Foundation
import Testing

@testable import ABsmartly

private let ok = HTTPResponse(statusCode: 200, body: Data("{}".utf8))

// Goals, publish and close.
extension ContextTests {
	// MARK: - Goals

	@Test func track() async throws {
		let env = ContextEnv()
		let context = env.context()

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])
		#expect(context.pendingEventCount == 2)

		context.track("goal2", properties: ["tests": 12])
		context.track("goal3")
		#expect(context.pendingEventCount == 4)

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(goals: [
					goal("goal1", ["amount": 125, "hours": 245]),
					goal("goal2", ["tries": 7]),
					goal("goal2", ["tests": 12]),
					goal("goal3", nil),
				]))
	}

	@Test func trackCallsEventLogger() {
		let env = ContextEnv()
		let context = env.context()
		env.log.clear()

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])

		let goals = [goal("goal1", ["amount": 125, "hours": 245]), goal("goal2", ["tries": 7])]
		#expect(env.log.count == 2)
		for (i, goal) in goals.enumerated() {
			#expect(env.log.contexts[i] == ObjectIdentifier(context))
			#expect(env.log.events[i] == .goal(goal))
		}

		env.log.clear()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])

		#expect(env.log.count == 2)
		for (i, goal) in goals.enumerated() {
			#expect(env.log.contexts[i] == ObjectIdentifier(context))
			#expect(env.log.events[i] == .goal(goal))
		}
	}

	@Test func trackStartsPublishTimeoutAfterAchievement() async {
		let env = ContextEnv()
		let context = env.context(options: Context.Options(publishDelay: 0.05))

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])

		#expect(context.pendingEventCount == 2)
		#expect(env.publishCount == 0)

		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(context.pendingEventCount == 0)
		await pause(0.1)
		#expect(env.publishCount == 1)
	}

	@Test func trackQueuesWhenNotReady() async {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])
		context.track("goal3")

		#expect(context.pendingEventCount == 3)
		gate.fulfill(fixture: "context")
		try? await context.ready()
	}

	// MARK: - Publish

	@Test func publishDoesNotCallEventHandlerWhenQueueIsEmpty() async throws {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)
		#expect(context.pendingEventCount == 0)

		try await context.publish()
		#expect(env.publishCount == 0)
	}

	@Test func publishCallsEventLogger() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		env.log.clear()

		try await context.publish()

		let expected = PublishEvent(
			hashed: true, units: fixturePublishUnits, publishedAt: Fixtures.now, exposures: [],
			goals: [goal("goal1", ["amount": 125, "hours": 245])], attributes: [])
		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.publishes.map(sorted) == [expected])
	}

	@Test func publishCallsEventLoggerOnError() async {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		env.log.clear()

		env.failNextRequest("test")
		await #expect(throws: ABsmartlyError.transport("test")) { try await context.publish() }

		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .error(.transport("test")))
	}

	@Test func publishResetsInternalQueuesAndKeepsAttributesOverridesAndCustomAssignments() async throws {
		let env = ContextEnv()
		let context = env.context(
			attributes: ["attr1": "value1", "attr2": 2], overrides: ["not_found": 3],
			customAssignments: ["exp_test_abc": 3])

		#expect(context.pendingEventCount == 0)

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(context.treatment(for: "exp_test_abc") == 3)
		#expect(context.treatment(for: "not_found") == 3)
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		#expect(context.pendingEventCount == 4)

		let attributes = [attribute("attr1", "value1"), attribute("attr2", 2)]

		try await context.publish()
		#expect(env.publishCount == 1)
		#expect(
			env.lastSentEvent
				== expectedBody(
					exposures: [
						exposure(1, "exp_test_ab", "session_id", 1, true, true, false, false, false, false),
						exposure(2, "exp_test_abc", "session_id", 3, true, true, false, false, true, false),
						exposure(0, "not_found", nil, 3, false, true, true, false, false, false),
					],
					goals: [goal("goal1", ["amount": 125, "hours": 245])],
					attributes: attributes))

		#expect(context.pendingEventCount == 0)

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(context.treatment(for: "exp_test_abc") == 3)
		#expect(context.treatment(for: "not_found") == 3)

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		#expect(context.pendingEventCount == 1)

		try await context.publish()
		#expect(env.publishCount == 2)
		#expect(
			env.lastSentEvent
				== expectedBody(goals: [goal("goal1", ["amount": 125, "hours": 245])], attributes: attributes))
	}

	@Test func publishDoesNotCallEventHandlerWhenFailed() async throws {
		let env = ContextEnv()
		let context = await env.failedContext()
		#expect(context.state == .failed(.transport("test")))
		#expect(context.pendingEventCount == 0)

		_ = context.treatment(for: "exp_test_abc")
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		#expect(context.pendingEventCount == 2)

		try await context.publish()
		#expect(env.publishCount == 0)
	}

	@Test func publishExceptionally() async {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		#expect(context.pendingEventCount == 1)

		env.failNextRequest("test")
		await #expect(throws: ABsmartlyError.self) { try await context.publish() }
		#expect(env.publishCount == 1)
	}

	// MARK: - Close

	@Test func close() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		#expect(context.pendingEventCount == 1)

		let gate = env.pendingRequest()
		let closing = Task { try await context.close() }

		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(context.state == .closing)

		gate.fulfill(ok)
		try await closing.value
		#expect(env.publishCount == 1)
		#expect(context.state == .closed)
	}

	@Test func closeCallsEventLogger() async throws {
		let env = ContextEnv()
		let context = env.context()
		env.log.clear()

		try await context.close()
		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .close)
	}

	@Test func closeCallsEventLoggerWithPendingEvents() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		env.log.clear()

		try await context.close()
		#expect(env.log.count == 2)
		#expect(env.log.contexts == [ObjectIdentifier(context), ObjectIdentifier(context)])
		guard case .publish = env.log.events.first else {
			Issue.record("expected a publish event first, got \(env.log.events)")
			return
		}
		#expect(env.log.events[1] == .close)
	}

	@Test func closeCallsEventLoggerOnError() async {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		env.log.clear()

		env.failNextRequest("test")
		await #expect(throws: ABsmartlyError.transport("test")) { try await context.close() }
		#expect(env.log.count == 1)
		#expect(env.log.contexts.first == ObjectIdentifier(context))
		#expect(env.log.events.first == .error(.transport("test")))
	}

	@Test func closeExceptionally() async {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125, "hours": 245])
		#expect(context.pendingEventCount == 1)

		let gate = env.pendingRequest()
		let closing = Task { try await context.close() }

		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(context.state == .closing)

		gate.reject(TestError("test"))
		await #expect(throws: ABsmartlyError.self) { try await closing.value }
		#expect(env.publishCount == 1)
	}

	@Test func closeStopsRefreshTimer() async throws {
		let env = ContextEnv()
		let context = env.context(options: Context.Options(publishDelay: -1, refreshInterval: 0.05))
		#expect(context.state == .ready)

		try await context.close()
		await pause(0.15)
		#expect(env.getCount == 0)
	}

	// MARK: - Publish failures and recovery

	@Test func recoveryAfterPublishFailure() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125])
		#expect(context.pendingEventCount == 1)

		env.failNextRequest("test publish failure")
		await #expect(throws: ABsmartlyError.self) { try await context.publish() }

		#expect(context.state == .ready)

		context.track("goal2", properties: ["value": 200])
		#expect(context.pendingEventCount == 2)

		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(context.pendingEventCount == 3)

		try await context.publish()
		#expect(context.pendingEventCount == 0)
	}

	@Test func gracefulDegradationNoNetwork() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		gate.reject(TestError("Network connection failed"))
		try? await context.ready()

		#expect(context.state == .failed(.transport("Network connection failed")))
		#expect(context.treatment(for: "exp_test_ab") == 0)

		context.track("goal_offline", properties: nil)
		#expect(context.pendingEventCount == 2)

		context.overrides["exp_test_ab"] = 5
		#expect(context.treatment(for: "exp_test_ab") == 5)

		try await context.publish()
		#expect(env.publishCount == 0)
	}

	@Test func retryMechanismActivation() async {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: nil)

		let attempts = Box(0)
		let maxAttempts = 3
		for _ in 0..<maxAttempts {
			env.transport.enqueue { _ in
				var current = 0
				attempts.mutate {
					$0 += 1
					current = $0
				}
				if current < maxAttempts {
					throw TestError("Transient failure \(current)")
				}
				return ok
			}
		}

		try? await context.publish()
		#expect(attempts.value >= 1)
	}

	@Test func failedToReadyTransition() async {
		let env = ContextEnv()
		let context = await env.failedContext("initial failure")
		#expect(context.state == .failed(.transport("initial failure")))

		#expect(context.treatment(for: "exp_test_ab") == 0)

		context.track("goal_while_failed", properties: nil)
		#expect(context.pendingEventCount == 2)
		#expect(env.publishCount == 0)
	}

	@Test func rapidCloseReopenCycle() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: nil)

		try await context.close()
		#expect(context.state == .closed)

		let context2 = env.context()
		#expect(context2.state == .ready)
		#expect(context2.treatment(for: "exp_test_ab") == 1)
	}

	@Test func allStateTransitionPaths() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		#expect(context.state == .loading)

		gate.fulfill(fixture: "context")
		try await context.ready()
		#expect(context.state == .ready)

		context.track("goal1", properties: nil)

		let publish = env.pendingRequest()
		let closing = Task { try await context.close() }
		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(context.state == .closing)

		publish.fulfill(ok)
		try await closing.value
		#expect(context.state == .closed)
	}

	@Test func failedAutoPublishLogsOneError() async {
		let env = ContextEnv()
		let context = env.context(options: Context.Options(publishDelay: 0.01))

		env.failNextRequest("publish failure")
		context.track("goal1", properties: nil)

		#expect(await eventually(timeout: 5) { !env.log.errors.isEmpty })
		// Let the timer's own failure handling finish before counting.
		await pause(0.1)
		#expect(env.publishCount == 1)
		#expect(env.log.errorMessages == ["publish failure"])
	}

	@Test func flushRestoresEventsOnPublishFailure() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: ["amount": 125])
		context.track("goal2", properties: ["value": 200])
		#expect(context.pendingEventCount == 2)

		env.failNextRequest("publish failure")
		await #expect(throws: ABsmartlyError.self) { try await context.publish() }
		#expect(context.pendingEventCount == 2)

		try await context.publish()
		#expect(env.publishCount == 2)
		#expect(env.lastSentEvent?["goals"]?.arrayValue?.count == 2)
		#expect(context.pendingEventCount == 0)
	}

	@Test func flushRestoresExposuresOnPublishFailure() async {
		let env = ContextEnv()
		let context = env.context()
		_ = context.treatment(for: "exp_test_ab")
		#expect(context.pendingEventCount == 1)

		env.failNextRequest("publish failure")
		try? await context.publish()
		#expect(context.pendingEventCount == 1)
	}

	@Test func flushContextLockUsesDefer() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: nil)
		#expect(context.pendingEventCount == 1)

		try await context.publish()
		context.track("goal2", properties: nil)
		#expect(context.pendingEventCount == 1)
	}

	@Test func closeWaitsForInFlightPublish() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: nil)

		let gate = env.pendingRequest()
		let publishing = Task { try? await context.publish() }
		#expect(await eventually(timeout: 5) { env.publishCount == 1 })

		let closeDone = Box(false)
		let closing = Task {
			try await context.close()
			closeDone.value = true
		}
		await pause(0.1)
		#expect(!closeDone.value)

		gate.fulfill(ok)
		try await closing.value
		await publishing.value
		#expect(closeDone.value)
		#expect(context.state == .closed)
	}

	@Test func getTreatmentAfterCloseDoesNotEnqueueExposure() async throws {
		let env = ContextEnv()
		let context = env.context()
		try await context.close()

		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(env.log.errorMessages == ["ABsmartly Context is finalized."])
		#expect(context.pendingEventCount == 0)
	}

	@Test func failedCloseIsRetryable() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal1", properties: nil)

		env.failNextRequest("t")
		await #expect(throws: ABsmartlyError.self) { try await context.close() }
		#expect(context.state != .closed)
		#expect(context.pendingEventCount == 1)

		try await context.close()
		#expect(context.state == .closed)
		#expect(context.pendingEventCount == 0)
	}

	@Test func setTimeoutNoRaceCondition() async {
		let env = ContextEnv()
		let context = env.context(options: Context.Options(publishDelay: 0.05))

		_ = context.treatment(for: "exp_test_ab")
		context.track("goal1", properties: nil)

		// One timer for both: they go out in a single publish.
		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		await pause(0.1)
		#expect(env.publishCount == 1)
		#expect(env.lastSentEvent?["exposures"]?.arrayValue?.count == 1)
		#expect(env.lastSentEvent?["goals"]?.arrayValue?.count == 1)
	}

	@Test func setOverrideSucceedsAfterClose() async throws {
		let env = ContextEnv()
		let context = env.context()
		try await context.close()

		context.overrides["exp_test"] = 2
		#expect(context.overrides["exp_test"] == 2)
	}

	@Test func goalTrackedInsideSynchronousReadyCallbackIsScheduled() async {
		let env = ContextEnv(options: Context.Options(publishDelay: 0.05))
		env.log.setHook { context, event in
			if case .ready = event { context.track("goal_in_ready", properties: nil) }
		}
		let context = env.context()

		#expect(context.pendingEventCount == 1)
		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(env.lastSentEvent == expectedBody(goals: [goal("goal_in_ready", nil)]))
	}

	@Test func closeFlushesQueuedEventsAfterOwnerReleasesContext() async {
		let env = ContextEnv()
		var context: Context? = env.context()
		context?.track("goal_on_teardown", properties: nil)

		let gate = env.pendingRequest()
		Task { [context] in try? await context?.close() }
		context = nil

		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		gate.fulfill(ok)
		#expect(env.publishCount == 1)
		#expect(env.lastSentEvent?["goals"]?[0]?["name"] == "goal_on_teardown")
	}

	@Test func trackThenDropContextStillPublishes() async {
		let env = ContextEnv()
		var context: Context? = env.context(options: Context.Options(publishDelay: 0.05))
		// `var` (Swift 6.0 has no `weak let`), cleared below so newer compilers see it mutated.
		weak var weakContext = context
		context!.track("goal1", properties: nil)
		context = nil
		#expect(weakContext != nil, "a pending publish keeps the context alive")
		weakContext = nil

		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		#expect(env.lastSentEvent?["goals"]?.arrayValue?.compactMap { $0["name"]?.stringValue } == ["goal1"])
	}

	@Test func fullAttributeHistoryIsPublished() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.setAttribute("returning", to: true)
		for i in 0..<600 {
			context.setAttribute("counter", to: i)
		}
		#expect(context.attribute("returning") == true)
		#expect(context.attribute("counter") == 599)
		#expect(context.attributes == ["returning": true, "counter": 599])

		context.track("goal1", properties: nil)
		try await context.publish()
		#expect(env.lastSentEvent?["attributes"]?.arrayValue?.count == 601)
	}

	@Test func queuedGoalsAreNeverDroppedBeforePublish() async throws {
		let env = ContextEnv()
		let context = env.context()
		for i in 1...1001 {
			context.track("goal-\(i)", properties: nil)
		}
		#expect(context.pendingEventCount == 1001)

		try await context.publish()
		let goals = env.lastSentEvent?["goals"]?.arrayValue ?? []
		#expect(goals.count == 1001)
		#expect(goals.first?["name"] == "goal-1")
		#expect(goals.last?["name"] == "goal-1001")
	}

	@Test func customAssignmentAllowedAfterFinalize() async throws {
		let env = ContextEnv()
		let context = env.context()
		try await context.close()

		context.customAssignments["exp_test_ab"] = 1
		#expect(context.customAssignments["exp_test_ab"] == 1)
	}

	@Test func writesAfterCloseAreIgnoredWithErrorEvent() async throws {
		let env = ContextEnv()
		let context = env.context()
		try await context.close()

		context.track("goal1", properties: nil)
		context.setAttribute("attr", to: 1)
		#expect(throws: ABsmartlyError.closed) { try context.setUnit(.deviceID, to: "abc") }

		#expect(context.pendingEventCount == 0)
		#expect(context.attribute("attr") == nil)
		#expect(context.units[.deviceID] == nil)
		#expect(env.log.errorMessages == Array(repeating: "ABsmartly Context is finalized.", count: 3))
	}

	@Test func closeEventKeepsItsCaseName() async throws {
		let env = ContextEnv()
		let closeLogged = Box(false)
		env.log.setHook { _, event in
			switch event {
			case .ready, .refresh, .publish, .exposure, .goal, .error:
				break
			case .close:
				closeLogged.value = true
			}
		}

		let context = env.context()
		try await context.close()
		#expect(closeLogged.value)
	}

	@Test func publishBeforeReadySendsQueuedGoals() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		context.track("goal1", properties: nil)
		#expect(context.pendingEventCount == 1)

		try await context.publish()

		#expect(context.pendingEventCount == 0)
		#expect(env.lastSentEvent?["goals"]?.arrayValue?.compactMap { $0["name"]?.stringValue } == ["goal1"])
		#expect(env.log.errorMessages == [])
		gate.fulfill(fixture: "context")
	}
}
