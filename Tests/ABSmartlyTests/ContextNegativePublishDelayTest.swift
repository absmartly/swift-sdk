import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// A negative publishDelay disables the automatic publish, as in the Java and JavaScript SDKs and
// main: events wait for an explicit publish() or close(). This differs from 1.4.0, which scheduled
// a publish with the negative delay (see CHANGELOG "Changed").
final class ContextNegativePublishDelayTest: XCTestCase {
	let clock = FixedClock(1_620_000_000_000)
	var scheduler = SchedulerMock()
	var handler = ContextEventHandlerMock()
	var provider = ContextDataProviderMock()
	var logger = ContextEventLoggerMock()

	override func setUp() {
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
	}

	private func contextData() throws -> ContextData {
		let path = TestResources.path(forResource: "context", ofType: "json")
		return try JSONDecoder().decode(ContextData.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
	}

	private func makeContext(_ data: Promise<ContextData>, publishDelay: TimeInterval = -1) -> Context {
		let config = ContextConfig()
		config.setUnit(unitType: "session_id", uid: "e791e240fcd3df7d238cfc285f475e8152fcc0ec")
		config.publishDelay = publishDelay
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: DefaultVariableParser(), matcher: AudienceMatcher(), promise: data)
	}

	func testTrackSchedulesNoPublish() throws {
		let context = makeContext(Promise.value(try contextData()))

		context.track("goal1", properties: nil)
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))

		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(0, handler.publishEventCallsCount)
	}

	func testFractionalNegativeDelaySchedulesNoPublish() throws {
		let context = makeContext(Promise.value(try contextData()), publishDelay: -0.001)

		context.track("goal1", properties: nil)

		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
	}

	func testExplicitPublishStillSends() throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)

		handler.publishEventReturnValue = Promise.value(())
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)

		XCTAssertEqual(["goal1"], handler.publishEventReceivedEvent?.goals.map { $0.name })
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testCloseStillSends() throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)

		handler.publishEventReturnValue = Promise.value(())
		let closed = expectation(description: "closed")
		_ = context.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 2)

		XCTAssertEqual(["goal1"], handler.publishEventReceivedEvent?.goals.map { $0.name })
		XCTAssertTrue(context.isClosed())
	}

	func testSuccessfulRefreshWithQueuedEventsSchedulesNoPublish() throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
	}

	func testGoalTrackedInSynchronousReadyCallbackSchedulesNoPublish() throws {
		logger.handleEventContextEventClosure = { ctx, event in
			if case .ready = event { ctx.track("goal_in_ready", properties: nil) }
		}
		let context = makeContext(Promise.value(try contextData()))

		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
	}

	func testGoalQueuedWhileLoadingSchedulesNoPublishOnceReady() throws {
		let (initial, seal) = Promise<ContextData>.pending()
		let context = makeContext(initial)
		context.track("before_ready", properties: nil)

		let ready = expectation(description: "ready")
		_ = context.waitUntilReady().done { _ in ready.fulfill() }
		seal.fulfill(try contextData())
		wait(for: [ready], timeout: 2)

		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
	}

	func testFailedCloseRequeuesWithoutSchedulingPublish() throws {
		let context = makeContext(Promise.value(try contextData()))
		context.track("goal1", properties: nil)

		handler.publishEventReturnValue = Promise(error: ABSmartlyError("collector down"))
		let rejected = expectation(description: "close rejected")
		_ = context.close().catch { _ in rejected.fulfill() }
		wait(for: [rejected], timeout: 2)

		XCTAssertFalse(context.isClosed())
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
	}

	func testZeroPublishDelayStillSchedules() throws {
		let context = makeContext(Promise.value(try contextData()), publishDelay: 0)

		context.track("goal1", properties: nil)

		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteReceivedArguments?.after)
	}
}
