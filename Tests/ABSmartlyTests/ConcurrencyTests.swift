import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class ConcurrencyTests: XCTestCase {
	var provider: ContextDataProviderMock = ContextDataProviderMock()
	var handler: ContextEventHandlerMock = ContextEventHandlerMock()
	var logger: ContextEventLoggerMock = ContextEventLoggerMock()
	var parser: VariableParser = DefaultVariableParser()
	var scheduler: SchedulerMock = SchedulerMock()
	var clock: ClockMock = ClockMock()

	let units = [
		"email": "bleh@absmartly.com",
		"session_id": "e791e240fcd3df7d238cfc285f475e8152fcc0ec",
		"user_id": "123456789",
	]

	override func setUp() async throws {
		provider = ContextDataProviderMock()
		handler = ContextEventHandlerMock()
		logger = ContextEventLoggerMock()
		parser = DefaultVariableParser()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		clock.millisReturnValue = 1_620_000_000_000
	}

	func getContextData(source: String = "context") throws -> ContextData {
		let path = TestResources.path(forResource: source, ofType: "json")
		let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
		return try JSONDecoder().decode(ContextData.self, from: data)
	}

	func createContext(config: ContextConfig, data: Promise<ContextData>? = nil) throws -> Context {
		let data = try data ?? Promise<ContextData>.value(try getContextData())
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: parser, matcher: AudienceMatcher(),
			promise: data)
	}

	func getContextConfig(withUnits: Bool = false) -> ContextConfig {
		let contextConfig: ContextConfig = ContextConfig()

		if withUnits {
			contextConfig.setUnits(units: units)
		}

		return contextConfig
	}

	func testConcurrentTreatmentAccess() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let expectation = XCTestExpectation(description: "Concurrent treatment access completes")
		expectation.expectedFulfillmentCount = 100

		let concurrentQueue = DispatchQueue(label: "com.absmartly.concurrency.test", attributes: .concurrent)
		let experimentNames = ["exp_test_ab", "exp_test_abc", "exp_test_fullon", "exp_test_not_eligible"]

		for i in 0..<100 {
			concurrentQueue.async {
				let experimentName = experimentNames[i % experimentNames.count]
				do {
					XCTAssertGreaterThanOrEqual(try context.getTreatment(experimentName), 0)
				} catch {
					XCTFail("Unexpected error: \(error)")
				}
				expectation.fulfill()
			}
		}

		wait(for: [expectation], timeout: 10.0)

		XCTAssertTrue(context.getPendingCount() > 0)
	}

	func testConcurrentGoalTracking() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let expectation = XCTestExpectation(description: "Concurrent goal tracking completes")
		expectation.expectedFulfillmentCount = 100

		let concurrentQueue = DispatchQueue(label: "com.absmartly.goal.test", attributes: .concurrent)
		let goalNames = ["goal_1", "goal_2", "goal_3", "goal_4", "goal_5"]

		for i in 0..<100 {
			concurrentQueue.async {
				let goalName = goalNames[i % goalNames.count]
				do {
					try context.track(goalName, properties: ["iteration": JSON(i), "timestamp": JSON(Date().timeIntervalSince1970)])
				} catch {
					XCTFail("Unexpected error: \(error)")
				}
				expectation.fulfill()
			}
		}

		wait(for: [expectation], timeout: 10.0)

		XCTAssertEqual(context.getPendingCount(), 100)
	}

	func testRaceConditionStateChange() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		let expectation = XCTestExpectation(description: "Race condition state change completes")
		expectation.expectedFulfillmentCount = 51

		let concurrentQueue = DispatchQueue(label: "com.absmartly.state.test", attributes: .concurrent)

		for _ in 0..<50 {
			concurrentQueue.async {
				do {
					try context.track("goal_during_init", properties: nil)
				} catch {
					XCTFail("Unexpected error: \(error)")
				}
				expectation.fulfill()
			}
		}

		DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
			do {
				resolver.fulfill(try self.getContextData())
			} catch {
				XCTFail("Failed to load context data: \(error)")
			}
		}

		_ = context.waitUntilReady().done { ctx in
			XCTAssertTrue(ctx.isReady())
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 10.0)

		XCTAssertTrue(context.isReady())
		XCTAssertEqual(context.getPendingCount(), 50)
	}

	func testConcurrentRefreshAndPublish() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		try context.track("test_goal", properties: nil)
		_ = try context.getTreatment("exp_test_ab")

		let refreshExpectation = XCTestExpectation(description: "Refresh completes")
		let publishExpectation = XCTestExpectation(description: "Publish completes")

		let refreshedContextData = try getContextData(source: "refreshed")
		provider.getContextDataReturnValue = Promise.value(refreshedContextData)

		handler.publishEventReturnValue = Promise.value(())

		let concurrentQueue = DispatchQueue(label: "com.absmartly.refresh.test", attributes: .concurrent)

		concurrentQueue.async {
			_ = context.refresh().done {
				refreshExpectation.fulfill()
			}
		}

		concurrentQueue.async {
			_ = context.publish().done {
				publishExpectation.fulfill()
			}
		}

		wait(for: [refreshExpectation, publishExpectation], timeout: 10.0)

		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isFailed())
	}

	func testAsyncAwaitEdgeCases() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		let expectation = XCTestExpectation(description: "Async await edge cases complete")

		XCTAssertFalse(context.isReady())

		XCTAssertThrowsError(try context.peekTreatment("exp_test_ab")) { error in
			XCTAssertEqual((error as? ABSmartlyError)?.errorMessage, "ABsmartly Context is not yet ready.")
		}

		context.setOverride(experimentName: "exp_test_override", variant: 5)
		try context.setAttribute(name: "test_attr", value: JSON("test_value"))

		resolver.fulfill(try getContextData())

		_ = context.waitUntilReady().done { ctx in
			XCTAssertEqual(try ctx.getTreatment("exp_test_ab"), 1)

			XCTAssertEqual(ctx.getOverride(experimentName: "exp_test_override"), 5)
			XCTAssertEqual(ctx.getAttribute(name: "test_attr"), JSON("test_value"))

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)
	}

	func testConcurrentSetAndGetUnits() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		let context = try createContext(config: contextConfig)

		let expectation = XCTestExpectation(description: "Concurrent unit operations complete")
		expectation.expectedFulfillmentCount = 100

		let concurrentQueue = DispatchQueue(label: "com.absmartly.units.test", attributes: .concurrent)

		for i in 0..<50 {
			concurrentQueue.async {
				do {
					try context.setUnit(unitType: "user_\(i)", uid: "uid_\(i)")
				} catch {
					XCTFail("Unexpected error: \(error)")
				}
				expectation.fulfill()
			}
		}

		for _ in 0..<50 {
			concurrentQueue.async {
				_ = context.getUnits()
				expectation.fulfill()
			}
		}

		wait(for: [expectation], timeout: 10.0)

		let units = context.getUnits()
		XCTAssertEqual(units.count, 50)
	}

	func testConcurrentAttributeAccess() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let expectation = XCTestExpectation(description: "Concurrent attribute access completes")
		expectation.expectedFulfillmentCount = 200

		let concurrentQueue = DispatchQueue(label: "com.absmartly.attrs.test", attributes: .concurrent)

		for i in 0..<100 {
			concurrentQueue.async {
				do {
					try context.setAttribute(name: "attr_\(i)", value: JSON("value_\(i)"))
				} catch {
					XCTFail("Unexpected error: \(error)")
				}
				expectation.fulfill()
			}
		}

		for _ in 0..<100 {
			concurrentQueue.async {
				_ = context.getAttributes()
				expectation.fulfill()
			}
		}

		wait(for: [expectation], timeout: 10.0)

		let attrs = context.getAttributes()
		XCTAssertEqual(attrs.count, 100)
	}
}
