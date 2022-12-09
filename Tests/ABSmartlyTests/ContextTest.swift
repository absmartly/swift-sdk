import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class ContextTest: XCTestCase {
	var provider: ContextDataProviderMock = ContextDataProviderMock()
	var handler: ContextEventHandlerMock = ContextEventHandlerMock()
	var logger: ContextEventLoggerMock = ContextEventLoggerMock()
	var parser: VariableParser = DefaultVariableParser()
	var scheduler: SchedulerMock = SchedulerMock()
	var clock: ClockMock = ClockMock()

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

	let expectedVariants: [String: Int] = [
		"exp_test_ab": 1,
		"exp_test_abc": 2,
		"exp_test_not_eligible": 0,
		"exp_test_fullon": 2,
		"exp_test_new": 1,
	]

	let variableExperiments: [String: [String]] = [
		"banner.border": ["exp_test_ab"],
		"banner.size": ["exp_test_ab"],
		"button.color": ["exp_test_abc"],
		"card.width": ["exp_test_not_eligible"],
		"submit.color": ["exp_test_fullon"],
		"submit.shape": ["exp_test_fullon"],
		"show-modal": ["exp_test_new"],
	]

	let expectedVariables: [String: JSON] = [
		"banner.border": 1,
		"banner.size": "large",
		"button.color": "red",
		"submit.color": "blue",
		"submit.shape": "rect",
		"show-modal": true,
	]

	let units = [
		"email": "bleh@absmartly.com",
		"session_id": "e791e240fcd3df7d238cfc285f475e8152fcc0ec",
		"user_id": "123456789",
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

	func testConstructorSetsOverrides() throws {
		let overrides: [String: Int] = ["exp_test": 2, "exp_test_1": 1]
		let contextConfig = getContextConfig(withUnits: true)
		contextConfig.setOverrides(overrides: overrides)

		let context = try createContext(config: contextConfig)

		overrides.forEach {
			XCTAssertEqual($0.value, context.getOverride(experimentName: $0.key))
		}
	}

	func testConstructorSetsCustomAssignments() throws {
		let cassignments: [String: Int] = ["exp_test": 2, "exp_test_1": 1]
		let contextConfig = getContextConfig(withUnits: true)
		contextConfig.setCustomAssignments(assignments: cassignments)

		let context = try createContext(config: contextConfig)

		cassignments.forEach {
			XCTAssertEqual($0.value, context.getCustomAssignment(experimentName: $0.key))
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

	func testCallsEventLoggerWhenReady() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		let expectation = XCTestExpectation()

		_ = context.waitUntilReady().done { _ in
			expectation.fulfill()
		}

		let data = try getContextData()
		resolver.fulfill(data)

		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(logger.handleEventContextEventCallsCount, 1)
		XCTAssertTrue(logger.handleEventContextEventReceivedArguments!.context === context)
		XCTAssertEqual(
			logger.handleEventContextEventReceivedArguments!.event, ContextEventLoggerEvent.ready(data: data))
	}

	func testCallsEventLoggerWithFulfilledPromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let data = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(data))

		XCTAssertEqual(logger.handleEventContextEventCallsCount, 1)
		XCTAssertTrue(logger.handleEventContextEventReceivedArguments!.context === context)
		XCTAssertEqual(
			logger.handleEventContextEventReceivedArguments!.event, ContextEventLoggerEvent.ready(data: data))
	}

	func testCallsEventLoggerWithErrorPromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		let expectation = XCTestExpectation()

		_ = context.waitUntilReady().done { _ in
			expectation.fulfill()
		}

		let error = ABSmartlyError("test")
		resolver.reject(error)

		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(logger.handleEventContextEventCallsCount, 1)
		XCTAssertTrue(logger.handleEventContextEventReceivedArguments!.context === context)
		XCTAssertEqual(
			logger.handleEventContextEventReceivedArguments!.event, ContextEventLoggerEvent.error(error: error))
	}

	func testCallsEventLoggerWithFulfilledErrorPromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let error = ABSmartlyError("test")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.init(error: error))

		XCTAssertEqual(logger.handleEventContextEventCallsCount, 1)
		XCTAssertTrue(logger.handleEventContextEventReceivedArguments!.context === context)
		XCTAssertEqual(
			logger.handleEventContextEventReceivedArguments!.event, ContextEventLoggerEvent.error(error: error))
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

	func testStartsRefreshTimerWhenReady() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.refreshInterval = 5

		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		provider.getContextDataReturnValue = Promise.value(try getContextData())

		let expectation = XCTestExpectation()

		_ = context.waitUntilReady().done { [self] _ in
			XCTAssertEqual(1, scheduler.scheduleWithFixedDelayAfterRepeatingExecuteCallsCount)
			XCTAssertEqual(
				contextConfig.refreshInterval,
				scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReceivedArguments!.repeating)

			XCTAssertEqual(0, provider.getContextDataCallsCount)

			scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReceivedArguments!.execute()

			XCTAssertEqual(1, provider.getContextDataCallsCount)

			expectation.fulfill()
		}

		resolver.fulfill(try getContextData())

		wait(for: [expectation], timeout: 1.0)
	}

	func testDoesNotStartRefreshTimerWhenFailed() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.refreshInterval = 5

		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		let expectation = XCTestExpectation()

		_ = context.waitUntilReady().done { [self] _ in
			XCTAssertEqual(0, scheduler.scheduleWithFixedDelayAfterRepeatingExecuteCallsCount)
			XCTAssertEqual(0, provider.getContextDataCallsCount)
			expectation.fulfill()
		}

		resolver.reject(ABSmartlyError("test"))

		wait(for: [expectation], timeout: 1.0)
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

		_ = context.waitUntilReady().done { [self] _ in
			XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testSetUnits() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		let context = try createContext(config: contextConfig, data: Promise.value(getContextData()))

		context.setUnit(unitType: "anonymous_id", uid: "0ab1e-23f4-feee")
		XCTAssertEqual("0ab1e-23f4-feee", context.getUnit(unitType: "anonymous_id"))

		context.setUnits(["session_id": "0ab1e23f4eee", "user_id": "1234567890"])

		XCTAssertEqual(["session_id": "0ab1e23f4eee", "user_id": "1234567890", "anonymous_id": "0ab1e-23f4-feee"], context.getUnits())
	}

	func testSetUnitsBeforeReady() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())

		let expectation = XCTestExpectation()

		context.setUnits(units)

		resolver.fulfill(try getContextData())

		_ = context.waitUntilReady().done { [self] _ in
			_ = context.getTreatment("exp_test_ab")

			let (promise, resolver) = Promise<Void>.pending()
			handler.publishEventReturnValue = promise

			let expected = PublishEvent()
			expected.hashed = true
			expected.units = publishUnits
			expected.publishedAt = clock.millis()
			expected.exposures = [
				Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false)
			]

			_ = context.publish().done { [self] in
				XCTAssertEqual(1, handler.publishEventCallsCount)

				// sort so array equality works
				handler.publishEventReceivedEvent?.units.sort(by: {
					$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
				})
				XCTAssertEqual(expected, handler.publishEventReceivedEvent)

				expectation.fulfill()
			}

			resolver.fulfill(())
		}

		resolver.fulfill(try getContextData())

		wait(for: [expectation], timeout: 1.0)
	}

	func testSetAttributes() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		let context = try createContext(config: contextConfig, data: Promise.value(getContextData()))

		context.setAttribute(name: "attr1", value: "value1")
		XCTAssertEqual("value1", context.getAttribute(name: "attr1"))

		context.setAttributes(["attr2": "value2", "attr3": 3])

		XCTAssertEqual(["attr1": "value1", "attr2": "value2", "attr3": 3], context.getAttributes())
	}

	func testSetAttributesBeforeReady() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())
		XCTAssertFalse(context.isFailed())
		context.setAttribute(name: "attr1", value: "value1")
		context.setAttributes(["attr2": "value2"])
		XCTAssertEqual(["attr1":"value1", "attr2": "value2"], context.getAttributes())

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

	func testSetCustomAssignment() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())

		let expectation = XCTestExpectation()

		context.setCustomAssignment(experimentName: "exp_test", variant: 2)
		XCTAssertEqual(2, context.getCustomAssignment(experimentName: "exp_test"))

		context.setCustomAssignment(experimentName: "exp_test", variant: 3)
		XCTAssertEqual(3, context.getCustomAssignment(experimentName: "exp_test"))

		context.setCustomAssignment(experimentName: "exp_test_2", variant: 1)
		XCTAssertEqual(1, context.getCustomAssignment(experimentName: "exp_test_2"))

		let cassignments = ["exp_test_new": 3, "exp_test_new_2": 5]
		context.setCustomAssignments(cassignments)

		XCTAssertEqual(3, context.getCustomAssignment(experimentName: "exp_test_new"))
		XCTAssertEqual(5, context.getCustomAssignment(experimentName: "exp_test_new_2"))
		XCTAssertEqual(nil, context.getCustomAssignment(experimentName: "exp_test_not_found"))

		resolver.fulfill(try getContextData())

		_ = context.waitUntilReady().done { _ in
			XCTAssertEqual(3, context.getCustomAssignment(experimentName: "exp_test"))
			XCTAssertEqual(1, context.getCustomAssignment(experimentName: "exp_test_2"))
			XCTAssertEqual(3, context.getCustomAssignment(experimentName: "exp_test_new"))
			XCTAssertEqual(5, context.getCustomAssignment(experimentName: "exp_test_new_2"))
			XCTAssertEqual(nil, context.getCustomAssignment(experimentName: "exp_test_not_found"))

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testSetCustomAssignmentDoesNotOverrideFullOnOrNotEligibleAssignments() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let cassignments: [String: Int] = ["exp_test_not_eligible": 3, "exp_test_fullon": 3]
		context.setCustomAssignments(cassignments)

		XCTAssertEqual(0, context.getTreatment("exp_test_not_eligible"))
		XCTAssertEqual(2, context.getTreatment("exp_test_fullon"))
	}

	func testSetCustomAssignmentClearsAssignmentCache() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let cassignments: [String: Int] = ["exp_test_ab": 2, "exp_test_abc": 3]

		cassignments.forEach { XCTAssertEqual(expectedVariants[$0.key], context.getTreatment($0.key)) }
		XCTAssertEqual(UInt(cassignments.count), context.getPendingCount())

		context.setCustomAssignments(cassignments)

		cassignments.forEach {
			context.setCustomAssignment(experimentName: $0.key, variant: $0.value)
			XCTAssertEqual($0.value, context.getTreatment($0.key))
		}
		XCTAssertEqual(2 * UInt(cassignments.count), context.getPendingCount())

		// overriding with the same variant shouldn't clear assignment cache
		cassignments.forEach {
			context.setCustomAssignment(experimentName: $0.key, variant: $0.value)
			XCTAssertEqual($0.value, context.getTreatment($0.key))
		}
		XCTAssertEqual(2 * UInt(cassignments.count), context.getPendingCount())

		// overriding with the different variant should clear assignment cache
		cassignments.forEach {
			context.setCustomAssignment(experimentName: $0.key, variant: $0.value + 11)
			XCTAssertEqual($0.value + 11, context.getTreatment($0.key))
		}

		XCTAssertEqual(3 * UInt(cassignments.count), context.getPendingCount())
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

		variableExperiments.forEach { variableName, experimentNames in
			let actual = context.peekVariableValue(variableName, defaultValue: 17)
			let eligible = experimentNames[0] != "exp_test_not_eligible"

			if eligible
				&& contextData.experiments.contains(where: { experiment in
					experiment.name == experimentNames[0]
				})
			{
				let expected = expectedVariables[variableName]
				XCTAssertEqual(expected, actual)
				XCTAssertEqual(expected, actual)
			} else {
				XCTAssertEqual(17, actual)
			}
		}

		XCTAssertEqual(0, context.getPendingCount())
	}

	func testPeekVariableValueConflictingKeyDisjointAudiences() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_key_conflict_disjoint_context")

		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		context.setAttribute(name: "age", value: 20)
		XCTAssertEqual("arrow", context.peekVariableValue("icon", defaultValue: "square"))
		XCTAssertEqual(0, context.getPendingCount())

		let context2 = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		context2.setAttribute(name: "age", value: 19)
		XCTAssertEqual("circle", context2.peekVariableValue("icon", defaultValue: "square"))
		XCTAssertEqual(0, context2.getPendingCount())
	}

	func testPeekVariableValuePicksLowestExperimentIdOnConflictingKey() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_key_conflict_context")

		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertEqual("circle", context.peekVariableValue("icon", defaultValue: "square"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testPeekVariableValueReturnsAssignedVariantOnAudienceMismatchNonStrictMode() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual("large", context.peekVariableValue("banner.size", defaultValue: "small"))
	}

	func testPeekVariableValueReturnsControlVariantOnAudienceMismatchStrictMode() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_strict_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual("small", context.peekVariableValue("banner.size", defaultValue: "small"))
	}

	func testGetVariableValue() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		variableExperiments.forEach { variableName, experimentNames in
			let actual = context.getVariableValue(variableName, defaultValue: 17)
			let eligible = experimentNames[0] != "exp_test_not_eligible"

			if eligible
				&& contextData.experiments.contains(where: { experiment in
					experiment.name == experimentNames[0]
				})
			{
				let expected = expectedVariables[variableName]
				XCTAssertEqual(expected, actual)
				XCTAssertEqual(expected, actual)
			} else {
				XCTAssertEqual(17, actual)
			}
		}

		XCTAssertEqual(UInt(contextData.experiments.count), context.getPendingCount())
	}

	func testGetVariableValueConflictingKeyDisjointAudiences() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_key_conflict_disjoint_context")

		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		context.setAttribute(name: "age", value: 20)
		XCTAssertEqual("arrow", context.getVariableValue("icon", defaultValue: "square"))
		XCTAssertEqual(1, context.getPendingCount())

		let context2 = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		context2.setAttribute(name: "age", value: 19)
		XCTAssertEqual("circle", context2.getVariableValue("icon", defaultValue: "square"))
		XCTAssertEqual(1, context2.getPendingCount())
	}

	func testGetVariableValueQueuesExposureWithAudienceMismatchFalseOnAudienceMatch() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		context.setAttribute(name: "age", value: 21)

		XCTAssertEqual("large", context.getVariableValue("banner.size", defaultValue: "small"))
		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()
		expected.attributes = [
			Attribute("age", value: 21, setAt: clock.millis())
		]
		expected.exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false)
		]

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetVariableValueQueuesExposureWithAudienceMismatchTrueOnAudienceMismatch() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual("large", context.getVariableValue("banner.size", defaultValue: "small"))
		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()
		expected.exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, true)
		]

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func
		testGetVariableValueDoesNotQueueExposureWithAudienceMismatchFalseAndControlVariantOnAudienceMismatchInStrictMode()
		throws
	{
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_strict_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual("small", context.getVariableValue("banner.size", defaultValue: "small"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testGetVariableValueCallsEventLogger() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		logger.clearInvocations()

		_ = context.getVariableValue("banner.border")
		_ = context.getVariableValue("banner.size")

		let exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false)
		]

		XCTAssertEqual(1, logger.handleEventContextEventCallsCount)

		for (i, exposure) in exposures.enumerated() {
			XCTAssertTrue(context === logger.handleEventContextEventReceivedInvocations[i].context)
			XCTAssertEqual(
				ContextEventLoggerEvent.exposure(exposure: exposure),
				logger.handleEventContextEventReceivedInvocations[i].event)
		}

		// verify not called again with the same exposure
		logger.clearInvocations()

		_ = context.getVariableValue("banner.border")
		_ = context.getVariableValue("banner.size")

		XCTAssertEqual(0, logger.handleEventContextEventCallsCount)
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

	func testPeekTreatmentReturnsAssignedVariantOnAudienceMismatchNonStrictMode() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual(1, context.peekTreatment("exp_test_ab"))
	}

	func testPeekTreatmentReturnsControlVariantOnAudienceMismatchStrictMode() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_strict_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual(0, context.peekTreatment("exp_test_ab"))
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
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false),
			Exposure(2, "exp_test_abc", "session_id", 2, clock.millis(), true, true, false, false, false, false),
			Exposure(3, "exp_test_not_eligible", "user_id", 0, clock.millis(), true, false, false, false, false, false),
			Exposure(4, "exp_test_fullon", "session_id", 2, clock.millis(), true, true, false, true, false, false),
			Exposure(0, "not_found", nil, 0, clock.millis(), false, true, false, false, false, false),
		]

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

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
			Exposure(1, "exp_test_ab", "session_id", 12, clock.millis(), false, true, true, false, false, false),
			Exposure(2, "exp_test_abc", "session_id", 13, clock.millis(), false, true, true, false, false, false),
			Exposure(3, "exp_test_not_eligible", "user_id", 11, clock.millis(), false, true, true, false, false, false),
			Exposure(4, "exp_test_fullon", "session_id", 13, clock.millis(), false, true, true, false, false, false),
			Exposure(0, "not_found", nil, 3, clock.millis(), false, true, true, false, false, false),
		]

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

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

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)
			XCTAssertEqual(0, context.getPendingCount())

			_ = context.getTreatment("not_found")
			XCTAssertEqual(0, context.getPendingCount())

			expectation.fulfill()
		}

		scheduler.scheduleAfterExecuteReceivedArguments?.execute()
		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetTreatmentQueuesExposureWithAudienceMismatchFalseOnAudienceMatch() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		context.setAttribute(name: "age", value: 21)

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()
		expected.attributes = [
			Attribute("age", value: 21, setAt: clock.millis())
		]

		expected.exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false)
		]

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetTreatmentQueuesExposureWithAudienceMismatchTrueOnAudienceMismatch() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()

		expected.exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, true)
		]

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetTreatmentQueuesExposureWithAudienceMismatchTrueAndControlVariantOnAudienceMismatchInStrictMode() throws
	{
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_strict_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		let expected = PublishEvent()
		expected.hashed = true
		expected.units = publishUnits
		expected.publishedAt = clock.millis()

		expected.exposures = [
			Exposure(1, "exp_test_ab", "session_id", 0, clock.millis(), false, true, false, false, false, true)
		]

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testGetTreatmentCallsEventLogger() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		logger.clearInvocations()

		_ = context.getTreatment("exp_test_ab")
		_ = context.getTreatment("not_found")

		let exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false),
			Exposure(0, "not_found", nil, 0, clock.millis(), false, true, false, false, false, false),
		]

		XCTAssertEqual(2, logger.handleEventContextEventCallsCount)

		for (i, exposure) in exposures.enumerated() {
			XCTAssertTrue(context === logger.handleEventContextEventReceivedInvocations[i].context)
			XCTAssertEqual(
				ContextEventLoggerEvent.exposure(exposure: exposure),
				logger.handleEventContextEventReceivedInvocations[i].event)
		}

		// verify not called again with the same exposure
		logger.clearInvocations()

		_ = context.getTreatment("exp_test_ab")
		_ = context.getTreatment("not_found")

		XCTAssertEqual(0, logger.handleEventContextEventCallsCount)
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

		_ = context.publish().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			// sort so array equality works
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			XCTAssertEqual(expected, handler.publishEventReceivedEvent)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testTrackCallsEventLogger() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		logger.clearInvocations()

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])

		XCTAssertEqual(2, logger.handleEventContextEventCallsCount)

		let goals = [
			GoalAchievement("goal1", achievedAt: clock.millis(), properties: ["amount": 125, "hours": 245]),
			GoalAchievement("goal2", achievedAt: clock.millis(), properties: ["tries": 7]),
		]

		XCTAssertEqual(2, logger.handleEventContextEventCallsCount)

		for (i, goal) in goals.enumerated() {
			XCTAssertTrue(context === logger.handleEventContextEventReceivedInvocations[i].context)
			XCTAssertEqual(
				ContextEventLoggerEvent.goal(goal: goal), logger.handleEventContextEventReceivedInvocations[i].event)
		}

		logger.clearInvocations()

		context.track("goal1", properties: ["amount": 125, "hours": 245])
		context.track("goal2", properties: ["tries": 7])

		XCTAssertEqual(2, logger.handleEventContextEventCallsCount)

		for (i, goal) in goals.enumerated() {
			XCTAssertTrue(context === logger.handleEventContextEventReceivedInvocations[i].context)
			XCTAssertEqual(
				ContextEventLoggerEvent.goal(goal: goal), logger.handleEventContextEventReceivedInvocations[i].event)
		}
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

		_ = context.publish().done { [self] in
			XCTAssertEqual(0, handler.publishEventCallsCount)
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishCallsEventLogger() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		logger.clearInvocations()

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

		_ = context.publish().done { [self] in
			// sort so array equality works
			// event is the same passed to logger
			handler.publishEventReceivedEvent?.units.sort(by: {
				$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
			})
			handler.publishEventReceivedEvent?.attributes.sort(by: {
				$0.name != $1.name ? $0.name < $1.name : $0.setAt < $1.setAt
			})
			XCTAssertEqual(1, logger.handleEventContextEventCallsCount)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedArguments!.context)
			XCTAssertEqual(
				ContextEventLoggerEvent.publish(event: expected), logger.handleEventContextEventReceivedArguments!.event
			)

			expectation.fulfill()
		}

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishCallsEventLoggerOnError() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		logger.clearInvocations()

		let expectation = XCTestExpectation()

		let error = ABSmartlyError("test")
		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		_ = context.publish().catch { [self] error in
			XCTAssertEqual(1, logger.handleEventContextEventCallsCount)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedArguments!.context)
			XCTAssertEqual(
				ContextEventLoggerEvent.error(error: error), logger.handleEventContextEventReceivedArguments!.event)

			expectation.fulfill()
		}

		resolver.reject(error)

		wait(for: [expectation], timeout: 1.0)
	}

	func testPublishResetsInternalQueuesAndKeepsAttributesOverridesAndCustomAssignments() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.setAttributes(attributes: ["attr1": "value1", "attr2": 2])
		contextConfig.setOverride(experimentName: "not_found", variant: 3)
		contextConfig.setCustomAssignment(experimentName: "exp_test_abc", variant: 3)
		let context = try createContext(config: contextConfig)

		XCTAssertEqual(0, context.getPendingCount())

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(3, context.getTreatment("exp_test_abc"))
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
				Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false),
				Exposure(2, "exp_test_abc", "session_id", 3, clock.millis(), true, true, false, false, true, false),
				Exposure(0, "not_found", nil, 3, clock.millis(), false, true, true, false, false, false),
			]
			expected.goals = [
				GoalAchievement("goal1", achievedAt: clock.millis(), properties: ["amount": 125, "hours": 245])
			]
			expected.attributes = [
				Attribute("attr1", value: "value1", setAt: clock.millis()),
				Attribute("attr2", value: 2, setAt: clock.millis()),
			]

			_ = context.publish().done { [self] in
				XCTAssertEqual(1, handler.publishEventCallsCount)

				// sort so array equality works
				handler.publishEventReceivedEvent?.units.sort(by: {
					$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
				})
				handler.publishEventReceivedEvent?.attributes.sort(by: {
					$0.name != $1.name ? $0.name < $1.name : $0.setAt < $1.setAt
				})
				XCTAssertEqual(expected, handler.publishEventReceivedEvent)

				expectation.fulfill()
			}

			resolver.fulfill(())

			wait(for: [expectation], timeout: 1.0)
		}

		XCTAssertEqual(0, context.getPendingCount())

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(3, context.getTreatment("exp_test_abc"))
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

			_ = context.publish().done { [self] in
				XCTAssertEqual(2, handler.publishEventCallsCount)

				// sort so array equality works
				handler.publishEventReceivedEvent?.units.sort(by: {
					$0.type != $1.type ? $0.type < $1.type : $0.uid < $0.uid
				})
				handler.publishEventReceivedEvent?.attributes.sort(by: {
					$0.name != $1.name ? $0.name < $1.name : $0.setAt < $1.setAt
				})
				XCTAssertEqual(expected, handler.publishEventReceivedEvent)

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

		_ = context.publish().done { [self] in
			XCTAssertEqual(0, handler.publishEventCallsCount)
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

		_ = context.publish().catch { [self] error in
			XCTAssertEqual(1, handler.publishEventCallsCount)
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

		_ = context.close().done { [self] in
			XCTAssertEqual(1, handler.publishEventCallsCount)

			expectation.fulfill()
		}

		XCTAssertTrue(context.isClosing())
		XCTAssertFalse(context.isClosed())

		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testCloseCallsEventLogger() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		logger.clearInvocations()

		let expectation = XCTestExpectation()

		_ = context.close().done { [self] in
			XCTAssertEqual(1, logger.handleEventContextEventCallsCount)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedArguments!.context)
			XCTAssertEqual(ContextEventLoggerEvent.close, logger.handleEventContextEventReceivedArguments!.event)

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testCloseCallsEventLoggerWithPendingEvents() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		logger.clearInvocations()

		let expectation = XCTestExpectation()

		handler.publishEventReturnValue = Promise<Void>.value(())

		_ = context.close().done { [self] in
			XCTAssertEqual(2, logger.handleEventContextEventCallsCount)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedInvocations[0].context)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedInvocations[1].context)
			XCTAssertEqual(ContextEventLoggerEvent.close, logger.handleEventContextEventReceivedInvocations[1].event)

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testCloseCallsEventLoggerOnError() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125, "hours": 245])

		logger.clearInvocations()

		let expectation = XCTestExpectation()

		let error = ABSmartlyError("test")
		handler.publishEventReturnValue = Promise<Void>.init(error: error)

		_ = context.close().catch { [self] error in
			XCTAssertEqual(1, logger.handleEventContextEventCallsCount)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedInvocations[0].context)
			XCTAssertEqual(
				ContextEventLoggerEvent.error(error: error), logger.handleEventContextEventReceivedInvocations[0].event)

			expectation.fulfill()
		}

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

		_ = context.close().catch { [self] error in
			XCTAssertEqual(1, handler.publishEventCallsCount)
			XCTAssertTrue(error is ABSmartlyError)

			expectation.fulfill()
		}

		XCTAssertTrue(context.isClosing())
		XCTAssertFalse(context.isClosed())

		resolver.reject(ABSmartlyError("test"))

		wait(for: [expectation], timeout: 1.0)
	}

	func testCloseStopsRefreshTimer() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.refreshInterval = 5

		let scheduledHandle = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = scheduledHandle

		let context = try createContext(config: contextConfig)
		XCTAssertTrue(context.isReady())

		let expectation = XCTestExpectation()

		XCTAssertTrue(context.isReady())
		XCTAssertTrue(scheduler.scheduleWithFixedDelayAfterRepeatingExecuteCalled)

		_ = context.close().done {
			XCTAssertEqual(1, scheduledHandle.cancelCallsCount)

			expectation.fulfill()
		}

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

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)
	}

	func testRefreshCallsEventLogger() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		logger.clearInvocations()

		let refreshedContextData = try getContextData(source: "refreshed")
		provider.getContextDataReturnValue = Promise<ContextData>.value(refreshedContextData)

		let expectation = XCTestExpectation()

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, logger.handleEventContextEventCallsCount)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedArguments!.context)
			XCTAssertEqual(
				ContextEventLoggerEvent.refresh(data: refreshedContextData),
				logger.handleEventContextEventReceivedArguments!.event)

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testRefreshCallsEventLoggerOnError() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		logger.clearInvocations()

		let error = ABSmartlyError("test")
		provider.getContextDataReturnValue = Promise<ContextData>.init(error: error)

		let expectation = XCTestExpectation()

		_ = context.refresh().catch { [self] error in
			XCTAssertEqual(1, logger.handleEventContextEventCallsCount)
			XCTAssertTrue(context === logger.handleEventContextEventReceivedArguments!.context)
			XCTAssertEqual(
				ContextEventLoggerEvent.error(error: error), logger.handleEventContextEventReceivedArguments!.event)

			expectation.fulfill()
		}

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

		_ = context.refresh().catch { [self] error in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
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

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
			XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())

			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)

		contextData.experiments.forEach { _ = context.getTreatment($0.name) }
		_ = context.getTreatment("not_found")

		XCTAssertEqual(1 + UInt(contextData.experiments.count), context.getPendingCount())
	}

	func testRefreshKeepsAssignmentCacheWhenNotChangedOnAudienceMismatch() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_strict_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())

		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
			XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
			XCTAssertEqual(1, context.getPendingCount())

			expectation.fulfill()
		}

		resolver.fulfill(contextData)

		wait(for: [expectation], timeout: 1.0)
	}

	func testRefreshKeepsAssignmentCacheWhenNotChangedWithOverride() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		context.setOverride(experimentName: "exp_test_ab", variant: 3)

		XCTAssertEqual(3, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())

		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
			XCTAssertEqual(3, context.getTreatment("exp_test_ab"))
			XCTAssertEqual(1, context.getPendingCount())

			expectation.fulfill()
		}

		resolver.fulfill(contextData)

		wait(for: [expectation], timeout: 1.0)
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

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
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

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
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

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
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

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
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

		_ = context.refresh().done { [self] in
			XCTAssertEqual(1, provider.getContextDataCallsCount)
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
