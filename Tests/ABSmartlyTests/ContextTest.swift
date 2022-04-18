import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class ContextTest: XCTestCase {
	var provider: ContextDataProviderMock = ContextDataProviderMock()
	var handler: ContextEventHandlerMock = ContextEventHandlerMock()
	var parser: VariableParser = DefaultVariableParser()
	var scheduler: SchedulerMock = SchedulerMock()
	var clock: ClockMock = ClockMock()

	override func setUp() async throws {
		provider = ContextDataProviderMock()
		handler = ContextEventHandlerMock()
		parser = DefaultVariableParser()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = DefaultScheduledHandle(
			handle: DispatchWorkItem {
			})
		clock.millisReturnValue = 1_620_000_000_000
	}

	let expectedVariants: [String: Int] = [
		"exp_test_ab": 1,
		"exp_test_abc": 2,
		"exp_test_not_eligible": 0,
		"exp_test_fullon": 2,
		"exp_test_new": 1,
	]

	let variableExperiments: [String: String] = [
		"banner.border": "exp_test_ab",
		"banner.size": "exp_test_ab",
		"button.color": "exp_test_abc",
		"card.width": "exp_test_not_eligible",
		"submit.color": "exp_test_fullon",
		"submit.shape": "exp_test_fullon",
		"show-modal": "exp_test_new",
	]

	let expectedVariables: [String: Any] = [
		"banner.border": 1,
		"banner.size": "large",
		"button.color": "red",
		"submit.color": "blue",
		"submit.shape": "rect",
		"show-modal": true,
	]

	let publishUnits: [ABSmartly.Unit] = [
		Unit(type: "email", uid: "IuqYkNRfEx5yClel4j3NbA"),
		Unit(type: "session_id", uid: "pAE3a1i5Drs5mKRNq56adA"),
		Unit(type: "user_id", uid: "JfnnlDI7RTiF9RgfG2JNCw"),
	].sorted(by: { $0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid })

	func getContextData(source: String = "context") throws -> ContextData {
		let path = Bundle.module.path(forResource: source, ofType: "json", inDirectory: "Resources")!
		let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
		return try JSONDecoder().decode(ContextData.self, from: data)
	}

	func createContext(config: ContextConfig, data: Promise<ContextData>? = nil) throws -> Context {
		let data = try data ?? Promise<ContextData>.value(try getContextData())
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, parser: parser,
			promise: data)
	}

	func getContextConfig(withUnits: Bool = false) -> ContextConfig {
		let contextConfig: ContextConfig = ContextConfig()

		if withUnits {
			contextConfig.setUnit(unitType: "session_id", uid: "e791e240fcd3df7d238cfc285f475e8152fcc0ec")
			contextConfig.setUnit(unitType: "user_id", uid: "123456789")
			contextConfig.setUnit(unitType: "email", uid: "bleh@absmartly.com")
		}

		return contextConfig
	}

	func testConstructorSetsOverrides() throws {
		let overrides: [String: Int] = ["exp_test": 2, "exp_test_1": 1]
		let contextConfig = getContextConfig(withUnits: true)
		contextConfig.setOverrides(overrides: overrides)

		let context = try createContext(config: contextConfig)

		overrides.forEach {
			XCTAssertEqual($0.value, context.getOverride(experimentName: $0.key))
		}
	}

	func testBecomesReadyWithFulfilledPromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)
		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isFailed())
		XCTAssertEqual(context.getContextData(), try getContextData())
	}

	func testBecomesReadyAndFailedWithFulfilledErrorPromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(
			config: contextConfig, data: Promise<ContextData>.init(error: ABSmartlyError("test")))
		XCTAssertTrue(context.isReady())
		XCTAssertTrue(context.isFailed())
	}

	func testBecomesReadyAndFailedWithErrorPromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())
		XCTAssertFalse(context.isFailed())

		let expectation = XCTestExpectation()

		_ = context.waitUntilReady().done { context in
			XCTAssertTrue(context.isReady())
			XCTAssertTrue(context.isFailed())
			expectation.fulfill()
		}

		resolver.reject(ABSmartlyError("test"))

		wait(for: [expectation], timeout: 1.0)
	}

	func testWaitUntilReady() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())
		XCTAssertFalse(context.isFailed())

		let expectation = XCTestExpectation()

		_ = context.waitUntilReady().done { _ in
			XCTAssertTrue(context.isReady())
			XCTAssertFalse(context.isFailed())
			expectation.fulfill()
		}

		resolver.fulfill(try getContextData())

		wait(for: [expectation], timeout: 1.0)
	}

	func testWaitUntilReadyWithFulfilledPromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)
		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isFailed())

		let expectation = XCTestExpectation()

		_ = context.waitUntilReady().done { ctx in
			XCTAssertTrue(context === ctx)
			XCTAssertTrue(context.isReady())
			XCTAssertFalse(context.isFailed())
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetExperiments() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isFailed())
		XCTAssertEqual(contextData.experiments.map { $0.name }, context.getExperiments())
	}

	func testStartsPublishTimeoutWhenReadyWithQueueNotEmpty() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())
		XCTAssertFalse(context.isFailed())

		let expectation = XCTestExpectation()

		context.track("test_goal", properties: ["amount": 100])

		resolver.fulfill(try getContextData())

		_ = context.waitUntilReady().done { _ in
			XCTAssertEqual(1, self.scheduler.scheduleAfterExecuteCallsCount)

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testSetAttributesBeforeReady() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())
		XCTAssertFalse(context.isFailed())
		context.setAttribute(name: "attr1", value: "value1")
		context.setAttributes(["attr1": "value2"])
		resolver.fulfill(try getContextData())
	}

	func testSetOverride() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())

		let expectation = XCTestExpectation()

		context.setOverride(experimentName: "exp_test", variant: 2)
		XCTAssertEqual(2, context.getOverride(experimentName: "exp_test"))

		context.setOverride(experimentName: "exp_test", variant: 3)
		XCTAssertEqual(3, context.getOverride(experimentName: "exp_test"))

		context.setOverride(experimentName: "exp_test_2", variant: 1)
		XCTAssertEqual(1, context.getOverride(experimentName: "exp_test_2"))

		let overrides = ["exp_test_new": 3, "exp_test_new_2": 5]
		context.setOverrides(overrides)

		XCTAssertEqual(3, context.getOverride(experimentName: "exp_test_new"))
		XCTAssertEqual(5, context.getOverride(experimentName: "exp_test_new_2"))
		XCTAssertEqual(nil, context.getOverride(experimentName: "exp_test_not_found"))

		resolver.fulfill(try getContextData())

		_ = context.waitUntilReady().done { _ in
			XCTAssertEqual(3, context.getOverride(experimentName: "exp_test"))
			XCTAssertEqual(1, context.getOverride(experimentName: "exp_test_2"))
			XCTAssertEqual(3, context.getOverride(experimentName: "exp_test_new"))
			XCTAssertEqual(5, context.getOverride(experimentName: "exp_test_new_2"))
			XCTAssertEqual(nil, context.getOverride(experimentName: "exp_test_not_found"))

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testSetOverrideClearsAssignmentCache() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let overrides: [String: Int] = ["exp_test_new": 3, "exp_test_new_2": 5]
		context.setOverrides(overrides)

		overrides.forEach { XCTAssertEqual($0.value, context.getTreatment($0.key)) }
		XCTAssertEqual(UInt(overrides.count), context.getPendingCount())

		// overriding again with the same variant shouldn't clear assignment cache
		overrides.forEach {
			context.setOverride(experimentName: $0.key, variant: $0.value)
			XCTAssertEqual($0.value, context.getTreatment($0.key))
		}
		XCTAssertEqual(UInt(overrides.count), context.getPendingCount())

		// overriding with the different variant should clear assignment cache
		overrides.forEach {
			context.setOverride(experimentName: $0.key, variant: $0.value + 11)
			XCTAssertEqual($0.value + 11, context.getTreatment($0.key))
		}

		XCTAssertEqual(2 * UInt(overrides.count), context.getPendingCount())

		// overriding a computed assignment should clear assignment cache
		XCTAssertEqual(expectedVariants["exp_test_ab"], context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1 + 2 * UInt(overrides.count), context.getPendingCount())

		context.setOverride(experimentName: "exp_test_ab", variant: 9)
		XCTAssertEqual(9, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(2 + 2 * UInt(overrides.count), context.getPendingCount())
	}

	func testPeekTreatment() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		contextData.experiments.forEach {
			XCTAssertEqual(expectedVariants[$0.name], context.peekTreatment($0.name))
		}

		XCTAssertEqual(0, context.peekTreatment("no_found"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testPeekVariableValue() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		variableExperiments.forEach { variableName, experimentName in
			let actual = context.peekVariableValue(key: variableName, defaultValue: 17)
			let eligible = experimentName != "exp_test_not_eligible"

			if eligible
				&& contextData.experiments.contains(where: { experiment in
					experiment.name == experimentName
				})
			{
				let expected = expectedVariables[variableName]
				if let expected = expected as? Int {
					XCTAssertEqual(expected, actual as? Int)
				} else if let expected = expected as? String {
					XCTAssertEqual(expected, actual as? String)
				}
			} else {
				XCTAssertEqual(17, actual as! Int)
			}
		}

		XCTAssertEqual(0, context.getPendingCount())
	}

	func testGetVariableValue() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		variableExperiments.forEach { variableName, experimentName in
			let actual = context.getVariableValue(key: variableName, defaultValue: 17)
			let eligible = experimentName != "exp_test_not_eligible"

			if eligible
				&& contextData.experiments.contains(where: { experiment in
					experiment.name == experimentName
				})
			{
				let expected = expectedVariables[variableName]
				if let expected = expected as? Int {
					XCTAssertEqual(expected, actual as? Int)
				} else if let expected = expected as? String {
					XCTAssertEqual(expected, actual as? String)
				}
			} else {
				XCTAssertEqual(17, actual as! Int)
			}
		}

		XCTAssertEqual(UInt(contextData.experiments.count), context.getPendingCount())
	}

	func testGetVariableKeys() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "refreshed")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual(variableExperiments, context.getVariableKeys())
	}

	func testPeekTreatmentReturnsOverrideVariant() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		context.setOverrides(expectedVariants.mapValues { 11 + $0 })
		context.setOverride(experimentName: "not_found", variant: 3)

		contextData.experiments.forEach {
			if let variant = expectedVariants[$0.name] {
				XCTAssertEqual(variant + 11, context.peekTreatment($0.name))
			}
		}
		XCTAssertEqual(3, context.peekTreatment("not_found"))

		// call again
		contextData.experiments.forEach {
			if let variant = expectedVariants[$0.name] {
				XCTAssertEqual(variant + 11, context.peekTreatment($0.name))
			}
		}
		XCTAssertEqual(3, context.peekTreatment("not_found"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testGetTreatment() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		contextData.experiments.forEach {
			if let variant = expectedVariants[$0.name] {
				XCTAssertEqual(variant, context.getTreatment($0.name))
			}
		}
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(1 + UInt(contextData.experiments.count), context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()
		expected.exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false),
			Exposure(2, "exp_test_abc", "session_id", 2, clock.millis(), true, true, false, false),
			Exposure(3, "exp_test_not_eligible", "user_id", 0, clock.millis(), true, false, false, false),
			Exposure(4, "exp_test_fullon", "session_id", 2, clock.millis(), true, true, false, true),
			Exposure(0, "not_found", nil, 0, clock.millis(), false, true, false, false),
		]

		_ = context.publish().done {
			XCTAssertEqual(1, self.handler.publishEventCallsCount)

			// sort so array equality works
			self.handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, self.handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetTreatmentStartsPublishTimeoutAfterExposure() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		_ = context.getTreatment("exp_test_ab")
		_ = context.getTreatment("exp_test_abc")

		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(0.1, scheduler.scheduleAfterExecuteReceivedArguments?.after)
		XCTAssertEqual(0, handler.publishEventCallsCount)

		let (promise, _) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		scheduler.scheduleAfterExecuteReceivedArguments?.execute()

		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testGetTreatmentReturnsOverrideVariant() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		context.setOverrides(expectedVariants.mapValues { 11 + $0 })
		context.setOverride(experimentName: "not_found", variant: 3)

		contextData.experiments.forEach {
			if let variant = expectedVariants[$0.name] {
				XCTAssertEqual(variant + 11, context.getTreatment($0.name))
			}
		}
		XCTAssertEqual(3, context.getTreatment("not_found"))

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()
		expected.exposures = [
			Exposure(1, "exp_test_ab", "session_id", 12, clock.millis(), true, true, true, false),
			Exposure(2, "exp_test_abc", "session_id", 13, clock.millis(), true, true, true, false),
			Exposure(3, "exp_test_not_eligible", "user_id", 11, clock.millis(), true, true, true, false),
			Exposure(4, "exp_test_fullon", "session_id", 13, clock.millis(), true, true, true, false),
			Exposure(0, "not_found", nil, 3, clock.millis(), false, true, true, false),
		]

		_ = context.publish().done {
			XCTAssertEqual(1, self.handler.publishEventCallsCount)

			// sort so array equality works
			self.handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, self.handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetTreatmentQueuesExposureOnce() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		contextData.experiments.forEach {
			if let variant = expectedVariants[$0.name] {
				XCTAssertEqual(variant, context.getTreatment($0.name))
			}
		}
		XCTAssertEqual(0, context.getTreatment("not_found"))
		XCTAssertEqual(1 + UInt(contextData.experiments.count), context.getPendingCount())

		// call again
		contextData.experiments.forEach {
			if let variant = expectedVariants[$0.name] {
				XCTAssertEqual(variant, context.getTreatment($0.name))
			}
		}
		XCTAssertEqual(0, context.getTreatment("not_found"))

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		_ = context.publish().done {
			XCTAssertEqual(1, self.handler.publishEventCallsCount)
			XCTAssertEqual(0, context.getPendingCount())

			_ = context.getTreatment("not_found")
			XCTAssertEqual(0, context.getPendingCount())

			expectation.fulfill()
		}

		scheduler.scheduleAfterExecuteReceivedArguments?.execute()
		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testTrack() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])

		XCTAssertEqual(2, context.getPendingCount())

		context.track("goal2", properties: ["tests": 12])
		context.track("goal3")

		XCTAssertEqual(4, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()
		expected.goals = [
			GoalAchievement("goal1", achievedAt: clock.millis(), properties: ["amount": 125, "hours": 245]),
			GoalAchievement("goal2", achievedAt: clock.millis(), properties: ["tries": 7]),
			GoalAchievement("goal2", achievedAt: clock.millis(), properties: ["tests": 12]),
			GoalAchievement("goal3", achievedAt: clock.millis(), properties: nil),
		]

		_ = context.publish().done {
			XCTAssertEqual(1, self.handler.publishEventCallsCount)

			// sort so array equality works
			self.handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, self.handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testTrackStartsPublishTimeoutAfterAchievement() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])

		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(0.1, scheduler.scheduleAfterExecuteReceivedArguments?.after)
		XCTAssertEqual(0, handler.publishEventCallsCount)

		let (promise, _) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		scheduler.scheduleAfterExecuteReceivedArguments?.execute()

		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testTrackQueuesWhenNotReady() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, _) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])
		context.track("goal3")

		XCTAssertEqual(3, context.getPendingCount())
	}

	func testPublishDoesNotCallEventHandlerWhenQueueIsEmpty() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(0, context.getPendingCount())

		let expectation = XCTestExpectation()

		_ = context.publish().done {
			XCTAssertEqual(0, self.handler.publishEventCallsCount)
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishResetsInternalQueuesAndKeepsAttributesOverrides() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.setAttributes(attributes: ["attr1": "value1", "attr2": 2])
		contextConfig.setOverride(experimentName: "not_found", variant: 3)
		let context = try createContext(config: contextConfig)

		XCTAssertEqual(0, context.getPendingCount())

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(2, context.getTreatment("exp_test_abc"))
		XCTAssertEqual(3, context.getTreatment("not_found"))
		context.track("goal1", properties: ["amount": 125, "hours": 245])

		XCTAssertEqual(4, context.getPendingCount())

		do {
			let expectation = XCTestExpectation()

			let (promise, resolver) = Promise<Void>.pending()
			handler.publishEventReturnValue = promise

			let expected = PublishEvent()
			expected.hashed = true
			expected.units = publishUnits
			expected.publishedAt = clock.millis()
			expected.exposures = [
				Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false),
				Exposure(2, "exp_test_abc", "session_id", 2, clock.millis(), true, true, false, false),
				Exposure(0, "not_found", nil, 3, clock.millis(), false, true, true, false),
			]
			expected.goals = [
				GoalAchievement("goal1", achievedAt: clock.millis(), properties: ["amount": 125, "hours": 245])
			]
			expected.attributes = [
				Attribute("attr1", value: "value1", setAt: clock.millis()),
				Attribute("attr2", value: 2, setAt: clock.millis()),
			]

			_ = context.publish().done {
				XCTAssertEqual(1, self.handler.publishEventCallsCount)

				// sort so array equality works
				self.handler.publishEventReceivedEvent?.units.sort(by: {
					$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
				})
				self.handler.publishEventReceivedEvent?.attributes.sort(by: {
					$0.name != $1.name ? $0.name < $1.name : $0.setAt < $1.setAt
				})
				XCTAssertEqual(expected, self.handler.publishEventReceivedEvent)

				expectation.fulfill()
			}

			resolver.fulfill(())

			wait(for: [expectation], timeout: 1.0)
		}

		XCTAssertEqual(0, context.getPendingCount())

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(2, context.getTreatment("exp_test_abc"))
		XCTAssertEqual(3, context.getTreatment("not_found"))

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		XCTAssertEqual(1, context.getPendingCount())

		do {
			let expectation = XCTestExpectation()

			let (promise, resolver) = Promise<Void>.pending()
			handler.publishEventReturnValue = promise

			let expected = PublishEvent()
			expected.hashed = true
			expected.units = publishUnits
			expected.publishedAt = clock.millis()
			expected.goals = [
				GoalAchievement("goal1", achievedAt: clock.millis(), properties: ["amount": 125, "hours": 245])
			]
			expected.attributes = [
				Attribute("attr1", value: "value1", setAt: clock.millis()),
				Attribute("attr2", value: 2, setAt: clock.millis()),
			]

			_ = context.publish().done {
				XCTAssertEqual(2, self.handler.publishEventCallsCount)

				// sort so array equality works
				self.handler.publishEventReceivedEvent?.units.sort(by: {
					$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
				})
				self.handler.publishEventReceivedEvent?.attributes.sort(by: {
					$0.name != $1.name ? $0.name < $1.name : $0.setAt < $1.setAt
				})
				XCTAssertEqual(expected, self.handler.publishEventReceivedEvent)

				expectation.fulfill()
			}

			resolver.fulfill(())

			wait(for: [expectation], timeout: 1.0)
		}
	}

	func testPublishDoesNotCallEventHandlerWhenFailed() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(
			config: contextConfig, data: Promise<ContextData>.init(error: ABSmartlyError("test")))
		XCTAssertTrue(context.isReady())
		XCTAssertTrue(context.isFailed())
		XCTAssertEqual(0, context.getPendingCount())

		_ = context.getTreatment("exp_test_abc")
		context.track("goal1", properties: ["amount": 125, "hours": 245])

		XCTAssertEqual(2, context.getPendingCount())

		let expectation = XCTestExpectation()

		_ = context.publish().done {
			XCTAssertEqual(0, self.handler.publishEventCallsCount)
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishExceptionally() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		_ = context.publish().catch { error in
			XCTAssertEqual(1, self.handler.publishEventCallsCount)
			XCTAssertTrue(error is ABSmartlyError)

			expectation.fulfill()
		}

		resolver.reject(ABSmartlyError("test"))

		wait(for: [expectation], timeout: 1.0)
	}

	func testClose() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		_ = context.close().done {
			XCTAssertEqual(1, self.handler.publishEventCallsCount)

			expectation.fulfill()
		}

		XCTAssertTrue(context.isClosing())
		XCTAssertFalse(context.isClosed())

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testCloseExceptionally() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		_ = context.close().catch { error in
			XCTAssertEqual(1, self.handler.publishEventCallsCount)
			XCTAssertTrue(error is ABSmartlyError)

			expectation.fulfill()
		}

		XCTAssertTrue(context.isClosing())
		XCTAssertFalse(context.isClosed())

		resolver.reject(ABSmartlyError("test"))

		wait(for: [expectation], timeout: 1.0)
	}

	func testRefresh() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let refreshedContextData = try getContextData(source: "refreshed")
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)
	}

	func testRefreshExceptionally() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		XCTAssertEqual(1, context.getPendingCount())

		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().catch { error in
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertTrue(error is ABSmartlyError)

			expectation.fulfill()
		}

		resolver.reject(ABSmartlyError("test"))

		wait(for: [expectation], timeout: 1.0)
	}

	func testRefreshKeepsAssignmentCacheWhenNotChanged() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		contextData.experiments.forEach { _ = context.getTreatment($0.name) }
		_ = context.getTreatment("not_found")

		XCTAssertEqual(1 + UInt(contextData.experiments.count), context.getPendingCount())

		let refreshedContextData = try getContextData(source: "refreshed")
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)

		contextData.experiments.forEach { _ = context.getTreatment($0.name) }
		_ = context.getTreatment("not_found")

		XCTAssertEqual(1 + UInt(contextData.experiments.count), context.getPendingCount())
	}

	func testRefreshClearsAssignmentCacheForStoppedExperiment() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let experimentName = "exp_test_abc"
		XCTAssertEqual(2, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(2, context.getPendingCount())

		let refreshedContextData = ContextData(
			experiments: try getContextData(source: "refreshed").experiments.filter { $0.name != experimentName })
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(0, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(3, context.getPendingCount())  // stopped experiment triggered a new exposure
	}

	func testRefreshClearsAssignmentCacheForStartedExperiment() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let experimentName = "exp_test_new"
		XCTAssertEqual(0, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(2, context.getPendingCount())

		let refreshedContextData = try getContextData(source: "refreshed")
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(1, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(3, context.getPendingCount())  // started experiment triggered a new exposure
	}

	func testRefreshClearsAssignmentCacheForFullOnExperiment() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let experimentName = "exp_test_abc"
		XCTAssertEqual(2, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(2, context.getPendingCount())

		let refreshedContextData = try getContextData(source: "refreshed_full_on")
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(1, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(3, context.getPendingCount())  // full-on experiment triggered a new exposure
	}

	func testRefreshClearsAssignmentCacheForTrafficSplitChange() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let experimentName = "exp_test_not_eligible"
		XCTAssertEqual(0, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(2, context.getPendingCount())

		let refreshedContextData = try getContextData(source: "refreshed_traffic_split")
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(2, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(3, context.getPendingCount())  // newly eligible experiment triggered a new exposure
	}

	func testRefreshClearsAssignmentCacheForExperimentIdChange() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let experimentName = "exp_test_abc"
		XCTAssertEqual(2, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(2, context.getPendingCount())

		let refreshedContextData = try getContextData(source: "refreshed_id")
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			XCTAssertEqual(1, self.provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(2, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(3, context.getPendingCount())  // newly eligible experiment triggered a new exposure
	}
}
