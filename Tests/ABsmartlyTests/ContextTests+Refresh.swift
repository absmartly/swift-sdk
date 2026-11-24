import Foundation
import Testing

@testable import ABsmartly

// Refresh.
extension ContextTests {
	@Test func refresh() async throws {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)

		let refreshed = Fixtures.contextData("refreshed")
		let gate = env.pendingRequest()
		let refreshing = Task { try await context.refresh() }
		gate.fulfill(fixture: "refreshed")
		try await refreshing.value

		#expect(env.getCount == 1)
		#expect(context.experiments == refreshed.experiments.map(\.name))
	}

	@Test func refreshCallsEventLogger() async throws {
		let env = ContextEnv()
		let context = env.context()
		env.log.clear()

		env.serveNext("refreshed")
		try await context.refresh()

		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .refresh(Fixtures.contextData("refreshed")))
	}

	@Test func refreshCallsEventLoggerOnError() async {
		let env = ContextEnv()
		let context = env.context()
		env.log.clear()

		env.failNextRequest("test")
		await #expect(throws: ABsmartlyError.transport("test")) { try await context.refresh() }

		#expect(env.log.count == 1)
		#expect(env.log.contexts.last == ObjectIdentifier(context))
		#expect(env.log.last == .error(.transport("test")))
	}

	@Test func refreshExceptionally() async {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		#expect(context.pendingEventCount == 1)

		let gate = env.pendingRequest()
		let refreshing = Task { try await context.refresh() }
		gate.reject(TestError("test"))
		await #expect(throws: ABsmartlyError.self) { try await refreshing.value }
		#expect(env.getCount == 1)
	}

	@Test func refreshKeepsAssignmentCacheWhenNotChanged() async throws {
		let env = ContextEnv()
		let data = Fixtures.contextData()
		let context = env.context(data: data)

		for experiment in data.experiments { _ = context.treatment(for: experiment.name) }
		_ = context.treatment(for: "not_found")
		#expect(context.pendingEventCount == 1 + data.experiments.count)

		env.serveNext("refreshed")
		try await context.refresh()
		#expect(env.getCount == 1)
		#expect(context.experiments == Fixtures.contextData("refreshed").experiments.map(\.name))

		for experiment in data.experiments { _ = context.treatment(for: experiment.name) }
		_ = context.treatment(for: "not_found")
		#expect(context.pendingEventCount == 1 + data.experiments.count)
	}

	@Test func refreshKeepsAssignmentCacheWhenNotChangedOnAudienceMismatch() async throws {
		let env = ContextEnv()
		let context = env.context("audience_strict_context")

		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(context.pendingEventCount == 1)

		env.serveNext("audience_strict_context")
		try await context.refresh()
		#expect(env.getCount == 1)
		#expect(context.treatment(for: "exp_test_ab") == 0)
		#expect(context.pendingEventCount == 1)
	}

	@Test func refreshKeepsAssignmentCacheWhenNotChangedWithOverride() async throws {
		let env = ContextEnv()
		let context = env.context()

		context.overrides["exp_test_ab"] = 3
		#expect(context.treatment(for: "exp_test_ab") == 3)
		#expect(context.pendingEventCount == 1)

		env.serveNext("context")
		try await context.refresh()
		#expect(env.getCount == 1)
		#expect(context.treatment(for: "exp_test_ab") == 3)
		#expect(context.pendingEventCount == 1)
	}

	@Test func refreshClearsAssignmentCacheForStoppedExperiment() async throws {
		let env = ContextEnv()
		let context = env.context()

		let experimentName = "exp_test_abc"
		#expect(context.treatment(for: experimentName) == 2)
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 2)

		let refreshed = ContextData(
			experiments: Fixtures.contextData("refreshed").experiments.filter { $0.name != experimentName })
		env.serveNext(refreshed)
		try await context.refresh()
		#expect(env.getCount == 1)
		#expect(context.experiments == refreshed.experiments.map(\.name))

		#expect(context.treatment(for: experimentName) == 0)
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 3)
	}

	@Test func refreshClearsAssignmentCacheForStartedExperiment() async throws {
		let env = ContextEnv()
		let context = env.context()

		let experimentName = "exp_test_new"
		#expect(context.treatment(for: experimentName) == 0)
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 2)

		env.serveNext("refreshed")
		try await context.refresh()
		#expect(env.getCount == 1)
		#expect(context.experiments == Fixtures.contextData("refreshed").experiments.map(\.name))

		#expect(context.treatment(for: experimentName) == 1)
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 3)
	}

	/// Refreshes with `fixture` after reading `experimentName` (expected `before`), then expects
	/// `after` and one more exposure: the shared shape of the cache-clearing refresh tests.
	private func refreshChangesAssignment(
		_ experimentName: String, before: Int, fixture: String, after: Int
	) async throws {
		let env = ContextEnv()
		let context = env.context()

		#expect(context.treatment(for: experimentName) == before)
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 2)

		env.serveNext(fixture)
		try await context.refresh()
		#expect(env.getCount == 1)
		#expect(context.experiments == Fixtures.contextData(fixture).experiments.map(\.name))

		#expect(context.treatment(for: experimentName) == after)
		#expect(context.treatment(for: "not_found") == 0)
		#expect(context.pendingEventCount == 3)
	}

	@Test func refreshClearsAssignmentCacheForFullOnExperiment() async throws {
		try await refreshChangesAssignment("exp_test_abc", before: 2, fixture: "refreshed_full_on", after: 1)
	}

	@Test func refreshClearsAssignmentCacheForTrafficSplitChange() async throws {
		try await refreshChangesAssignment("exp_test_not_eligible", before: 0, fixture: "refreshed_traffic_split", after: 2)
	}

	@Test func refreshClearsAssignmentCacheForExperimentIdChange() async throws {
		try await refreshChangesAssignment("exp_test_abc", before: 2, fixture: "refreshed_id", after: 2)
	}

	@Test func refreshClearsAssignmentCacheForIterationChange() async throws {
		try await refreshChangesAssignment("exp_test_abc", before: 2, fixture: "refreshed_iteration", after: 2)
	}

	@Test func recoveryAfterRefreshFailure() async throws {
		let env = ContextEnv()
		let context = env.context()
		#expect(context.state == .ready)

		env.failNextRequest("test refresh failure")
		await #expect(throws: ABsmartlyError.self) { try await context.refresh() }

		#expect(context.state == .ready)
		#expect(context.treatment(for: "exp_test_ab") == 1)

		context.track("goal_after_refresh_failure", properties: nil)
		#expect(context.pendingEventCount == 2)

		env.serveNext("refreshed")
		try await context.refresh()
		#expect(context.state == .ready)
		#expect(context.experiments == Fixtures.contextData("refreshed").experiments.map(\.name))
	}

	@Test func refreshDoesNotResetExposureForUnchangedExperiments() async throws {
		let env = ContextEnv()
		let context = env.context()

		_ = context.treatment(for: "exp_test_ab")
		#expect(context.pendingEventCount == 1)

		env.serveNext("context")
		try await context.refresh()
		_ = context.treatment(for: "exp_test_ab")
		#expect(context.pendingEventCount == 1)
	}

	@Test func refreshResetsExposureForChangedExperiments() async throws {
		let env = ContextEnv()
		let context = env.context()

		_ = context.treatment(for: "exp_test_abc")
		#expect(context.pendingEventCount == 1)

		env.serveNext("refreshed_iteration")
		try await context.refresh()
		_ = context.treatment(for: "exp_test_abc")
		#expect(context.pendingEventCount == 2)
	}

	@Test func concurrentRefreshReturnsSamePromise() async throws {
		let env = ContextEnv()
		let context = env.context()

		let gate = env.pendingRequest()
		let first = Task { try await context.refresh() }
		let second = Task { try await context.refresh() }

		#expect(await eventually(timeout: 5) { env.getCount == 1 })
		await pause(0.05)
		#expect(env.getCount == 1)

		gate.fulfill(fixture: "context")
		try await first.value
		try await second.value
		#expect(env.getCount == 1)
	}

	@Test func waitUntilReadySettlesAfterOwnerReleasesContext() async throws {
		let env = ContextEnv()
		var (context, gate): (Context?, Gate<HTTPResponse>) = await env.loadingContext()
		// `var` (Swift 6.0 has no `weak let`), cleared below so newer compilers see it mutated.
		weak var weakContext = context
		// The test keeps only the waiting task, which holds the context weakly: the in-flight load is
		// what keeps it alive.
		let ready = Task { [weak context] () -> Context.State? in
			guard let context else { return nil }
			try await context.ready()
			return context.state
		}
		context = nil
		#expect(weakContext != nil, "the load keeps the context alive")
		weakContext = nil

		gate.fulfill(fixture: "context")
		#expect(try await ready.value == .ready)
	}

	@Test func refreshSettlesAfterOwnerReleasesContext() async throws {
		let env = ContextEnv()
		var context: Context? = env.context()
		let gate = env.pendingRequest()
		let refresh = Task { [weak context] in try await context?.refresh() }
		#expect(await eventually(timeout: 5) { env.getCount == 1 })
		context = nil

		gate.fulfill(fixture: "context")
		try await refresh.value
	}

	@Test func refreshBeforeReadyFetchesData() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		let loads = env.getCount

		env.serveNext("context")
		try await context.refresh()

		#expect(env.getCount == loads + 1)
		#expect(context.treatment(for: "exp_test_ab") == 1)
		gate.fulfill(fixture: "context")
	}
}

extension ContextTests {
	// As in 1.5.0: a refresh whose fetch completes after close() started installs nothing and logs
	// nothing, so the closed context does not change.
	@Test func refreshCompletingAfterCloseIsDiscarded() async throws {
		let env = ContextEnv()
		let context = env.context()
		let gate = env.pendingRequest()
		let refreshing = Task { try await context.refresh() }
		#expect(await eventually(timeout: 5) { env.getCount == 1 })
		try await context.close()
		env.log.clear()

		gate.fulfill(fixture: "refreshed")
		try await refreshing.value
		await pause(0.05)
		#expect(context.state == .closed)
		#expect(context.contextData == Fixtures.contextData("context"))
		#expect(env.log.events == [])
	}

	// A refresh that lands while close() is still publishing is dropped too.
	@Test func refreshCompletingWhileClosingIsDiscarded() async throws {
		let env = ContextEnv()
		let context = env.context()
		context.track("goal", properties: nil)
		let refreshGate = env.pendingRequest()
		let refreshing = Task { try await context.refresh() }
		#expect(await eventually(timeout: 5) { env.getCount == 1 })
		let publishGate = env.pendingRequest()
		let closing = Task { try await context.close() }
		#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		env.log.clear()

		refreshGate.fulfill(fixture: "refreshed")
		try await refreshing.value
		#expect(context.contextData == Fixtures.contextData("context"))
		publishGate.fulfill(HTTPResponse(statusCode: 200, body: Data()))
		try await closing.value
		#expect(env.log.events.allSatisfy { if case .refresh = $0 { false } else { true } })
		#expect(context.state == .closed)
	}

	// As in 1.5.0: a refresh failing after close() started is thrown to the caller but logs no event.
	@Test(arguments: [false, true])
	func refreshFailingAfterCloseStartedLogsNoEvent(whileClosing: Bool) async throws {
		let env = ContextEnv()
		let context = env.context()
		if whileClosing {
			context.track("goal", properties: nil)
		}
		let refreshGate = env.pendingRequest()
		let refreshing = Task { () -> ABsmartlyError? in await sdkError { try await context.refresh() } }
		#expect(await eventually(timeout: 5) { env.getCount == 1 })
		let publishGate = whileClosing ? env.pendingRequest() : nil
		let closing = Task { try await context.close() }
		if whileClosing {
			#expect(await eventually(timeout: 5) { env.publishCount == 1 })
		} else {
			try await closing.value
		}
		env.log.clear()

		let marker = "late failure \(UUID().uuidString)"
		LogCapture.install()
		refreshGate.reject(TestError(marker))
		#expect(await refreshing.value == .transport(marker))
		#expect(LogCapture.entries(containing: marker).count == 1)
		publishGate?.fulfill(HTTPResponse(statusCode: 200, body: Data()))
		try await closing.value
		#expect(env.log.errors == [])
		#expect(context.state == .closed)
	}
}

// Start-up readiness when a refresh overlaps the first fetch: whichever settles first decides, and
// every `ready()` caller (before and after) gets that one result.
extension ContextTests {
	@Test func refreshWinningStartupSettlesReadyAndTheLateLoadFailureIsIgnored() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()
		let early = Box<Result<Void, ABsmartlyError>?>(nil)
		Task {
			do throws(ABsmartlyError) {
				try await context.ready()
				early.value = .success(())
			} catch {
				early.value = .failure(error)
			}
		}
		await pause(0.05)

		env.serveNext("context")
		try await context.refresh()
		#expect(await eventually(timeout: 5) { early.value != nil })
		#expect(early.value.map { (try? $0.get()) != nil } == true)
		#expect(context.treatment(for: "exp_test_ab") == 1)

		gate.reject(TestError("late load failure"))
		await pause(0.05)
		try await context.ready()
		#expect(context.state == .ready)
		#expect(context.treatment(for: "exp_test_ab") == 1)
		#expect(context.variableValue("banner.size") == "large")
		#expect(env.log.errorMessages == [])
		#expect(env.log.events.filter { if case .ready = $0 { return true } else { return false } }.count == 1)
	}

	@Test func refreshWinningStartupIgnoresTheLateLoadData() async throws {
		let env = ContextEnv()
		let (context, gate) = await env.loadingContext()

		env.serveNext("refreshed")
		try await context.refresh()
		gate.fulfill(fixture: "context")
		await pause(0.05)

		// As in 1.5.0: the winning refresh logs `.ready`, then its own `.refresh`; the late load logs nothing.
		let refreshed = Fixtures.contextData("refreshed")
		#expect(context.contextData == refreshed)
		#expect(env.log.events == [.ready(refreshed), .refresh(refreshed)])
	}

	@Test func loadFailingFirstKeepsTheContextFailedWhenAnOverlappingRefreshSucceeds() async throws {
		let env = ContextEnv()
		let (context, loadGate) = await env.loadingContext()
		let refreshGate = env.pendingRequest()
		let refreshing = Task { try await context.refresh() }
		#expect(await eventually(timeout: 5) { env.getCount == 2 })

		loadGate.reject(TestError("load failed"))
		await #expect(throws: ABsmartlyError.transport("load failed")) { try await context.ready() }

		refreshGate.fulfill(fixture: "context")
		try await refreshing.value
		await #expect(throws: ABsmartlyError.transport("load failed")) { try await context.ready() }
		#expect(context.state == .failed(.transport("load failed")))
		#expect(context.contextData == ContextData())
		#expect(context.treatment(for: "exp_test_ab") == 0)
	}

	// The refresh completes while the first fetch's `.error` is being delivered, after the failure is
	// recorded but before the context reports failed: it must not install its data either.
	@Test func refreshCompletingWhileTheLoadFailureIsDeliveredDoesNotInstall() async throws {
		let env = ContextEnv()
		let (context, loadGate) = await env.loadingContext()
		let refreshGate = env.pendingRequest()
		let refreshed = Box(false)
		let refreshing = Task {
			try await context.refresh()
			refreshed.value = true
		}
		#expect(await eventually(timeout: 5) { env.getCount == 2 })
		env.log.setHook { _, event in
			guard case .error = event else { return }
			refreshGate.fulfill(fixture: "context")
			let deadline = Date().addingTimeInterval(5)
			while !refreshed.value && Date() < deadline {
				usleep(1000)
			}
		}

		loadGate.reject(TestError("load failed"))
		await #expect(throws: ABsmartlyError.transport("load failed")) { try await context.ready() }
		try await refreshing.value
		#expect(refreshed.value)
		#expect(context.state == .failed(.transport("load failed")))
		#expect(context.contextData == ContextData())
		#expect(context.treatment(for: "exp_test_ab") == 0)
	}
}
