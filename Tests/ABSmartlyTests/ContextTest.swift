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
	let clock = FixedClock(1_620_000_000_000)

	override func setUp() async throws {
		provider = ContextDataProviderMock()
		handler = ContextEventHandlerMock()
		logger = ContextEventLoggerMock()
		parser = DefaultVariableParser()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
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

	// A context seeded with the application/environment names the client would supply, so audiences
	// and assignment-rule conditions can target them.
	func createSystemContext(
		config: ContextConfig, data: Promise<ContextData>? = nil, application: String? = "website",
		environment: String? = "production"
	) throws -> Context {
		let data = try data ?? Promise<ContextData>.value(try getContextData())
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: parser, matcher: AudienceMatcher(),
			promise: data, application: application, environment: environment)
	}

	// exp_test_ab with a strict audience and a 0/100 split to variant 1, so a match yields 1 and a
	// mismatch (strict) yields the control variant 0. `filter` is the plain-JSON filter array text,
	// e.g. `[{"eq":[{"var":"environment"},{"value":"production"}]}]`.
	func strictAudienceContextData(filter: String) throws -> ContextData {
		let audience = "{\"filter\":\(filter)}"
		let escapedAudience = audience
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		let json = """
			{"experiments":[{"id":1,"name":"exp_test_ab","iteration":1,"unitType":"session_id",\
			"seedHi":3603515,"seedLo":233373850,"split":[0.0,1.0],"trafficSeedHi":449867249,\
			"trafficSeedLo":455443629,"trafficSplit":[0.0,1.0],"fullOnVariant":0,\
			"applications":[{"name":"website"}],"variants":[{"name":"A","config":null},\
			{"name":"B","config":"{\\"banner.border\\":1,\\"banner.size\\":\\"large\\"}"}],\
			"audienceStrict":true,"audience":"\(escapedAudience)"}]}
			"""
		return try JSONDecoder().decode(ContextData.self, from: json.data(using: .utf8)!)
	}

	func loggedErrorMessages() -> [String] {
		return logger.handleEventContextEventReceivedInvocations.compactMap {
			if case let .error(error) = $0.event { return error.safeLocalizedDescription }
			return nil
		}
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

	func testFailedContextHasNoDataAndReturnsDefaults() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(
			config: contextConfig, data: Promise<ContextData>.init(error: ABSmartlyError("test")))
		XCTAssertTrue(context.isReady())
		XCTAssertTrue(context.isFailed())
		// As in v1.4.0, a failed context has no data.
		XCTAssertNil(context.getContextData())
		XCTAssertEqual([], context.getExperiments())
		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(17, context.getVariableValue("banner.size", defaultValue: 17))
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

	func testReadyErrorReturnsNilOnSuccess() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)
		XCTAssertNil(context.readyError())
	}

	func testReadyErrorReturnsErrorOnFulfilledFailure() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let error = ABSmartlyError("test")
		let context = try createContext(
			config: contextConfig, data: Promise<ContextData>.init(error: error))
		XCTAssertTrue(context.isFailed())
		XCTAssertNotNil(context.readyError())
	}

	func testReadyErrorReturnsErrorOnAsyncFailure() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		let expectation = XCTestExpectation()
		let error = ABSmartlyError("test")

		_ = context.waitUntilReady().done { ctx in
			XCTAssertTrue(ctx.isFailed())
			XCTAssertNotNil(ctx.readyError())
			expectation.fulfill()
		}

		resolver.reject(error)

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

		for (key, value) in overrides { XCTAssertEqual(value, context.getTreatment(key)) }
		XCTAssertEqual(UInt(overrides.count), context.getPendingCount())

		// overriding again with the same variant shouldn't clear assignment cache
		for (key, value) in overrides {
			context.setOverride(experimentName: key, variant: value)
			XCTAssertEqual(value, context.getTreatment(key))
		}
		XCTAssertEqual(UInt(overrides.count), context.getPendingCount())

		// overriding with the different variant should clear assignment cache
		for (key, value) in overrides {
			context.setOverride(experimentName: key, variant: value + 11)
			XCTAssertEqual(value + 11, context.getTreatment(key))
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

		for (key, _) in cassignments { XCTAssertEqual(expectedVariants[key], context.getTreatment(key)) }
		XCTAssertEqual(UInt(cassignments.count), context.getPendingCount())

		context.setCustomAssignments(cassignments)

		for (key, value) in cassignments {
			context.setCustomAssignment(experimentName: key, variant: value)
			XCTAssertEqual(value, context.getTreatment(key))
		}
		XCTAssertEqual(2 * UInt(cassignments.count), context.getPendingCount())

		// overriding with the same variant shouldn't clear assignment cache
		for (key, value) in cassignments {
			context.setCustomAssignment(experimentName: key, variant: value)
			XCTAssertEqual(value, context.getTreatment(key))
		}
		XCTAssertEqual(2 * UInt(cassignments.count), context.getPendingCount())

		// overriding with the different variant should clear assignment cache
		for (key, value) in cassignments {
			context.setCustomAssignment(experimentName: key, variant: value + 11)
			XCTAssertEqual(value + 11, context.getTreatment(key))
		}

		XCTAssertEqual(3 * UInt(cassignments.count), context.getPendingCount())
	}

	func testPeekTreatment() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		for element in contextData.experiments {
			XCTAssertEqual(expectedVariants[element.name], context.peekTreatment(element.name))
		}

		XCTAssertEqual(0, context.peekTreatment("no_found"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testPeekVariableValue() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		for (variableName, experimentNames) in variableExperiments {
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

		for (variableName, experimentNames) in variableExperiments {
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
		// exp_test_ab (id 1) is visited first and exposed with its control variant
		XCTAssertEqual(2, context2.getPendingCount())
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

	func testGetVariableValueQueuesExposureWithControlVariantOnAudienceMismatchInStrictMode() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData(source: "audience_strict_context")
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		logger.clearInvocations()

		XCTAssertEqual("small", context.getVariableValue("banner.size", defaultValue: "small"))
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 0, clock.millis(), false, true, false, false, false, true)],
			loggedExposures())
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

	func sharedKeyExperiment(
		id: Int, name: String, unitType: String = "session_id", fullOnVariant: Int = 1, configs: [String?]
	) -> String {
		let variants = configs.indices.map { i -> String in
			let escaped = configs[i].map { "\"" + $0.replacingOccurrences(of: "\"", with: "\\\"") + "\"" } ?? "null"
			return "{\"name\":\"\(i)\",\"config\":\(escaped)}"
		}
		return """
			{"id":\(id),"name":"\(name)","iteration":1,"unitType":"\(unitType)","seedHi":0,"seedLo":0,\
			"split":[0.5,0.5],"trafficSeedHi":0,"trafficSeedLo":0,"trafficSplit":[0.0,1.0],\
			"fullOnVariant":\(fullOnVariant),"applications":[{"name":"website"}],\
			"variants":[\(variants.joined(separator: ","))],"audience":null}
			"""
	}

	func createSharedKeyContext(_ experiments: [String]) throws -> Context {
		let json = "{\"experiments\":[\(experiments.joined(separator: ","))]}"
		let data = try JSONDecoder().decode(ContextData.self, from: json.data(using: .utf8)!)
		let context = try createContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))
		logger.clearInvocations()
		return context
	}

	func loggedExposures() -> [Exposure] {
		return logger.handleEventContextEventReceivedInvocations.compactMap {
			if case let .exposure(exposure) = $0.event { return exposure }
			return nil
		}
	}

	func sharedKeyBothAssigned(lowestFirst: Bool) -> [String] {
		let one = sharedKeyExperiment(id: 1, name: "exp_one", configs: [nil, "{\"icon\":\"one\"}"])
		let two = sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"])
		return lowestFirst ? [one, two] : [two, one]
	}

	// exp_one is not assigned: its unit type has no unit in the context.
	func sharedKeyFirstUnassigned() -> [String] {
		return [
			sharedKeyExperiment(
				id: 1, name: "exp_one", unitType: "device_id", fullOnVariant: 0,
				configs: ["{\"icon\":\"zero\"}", "{\"icon\":\"one\"}"]),
			sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
		]
	}

	// exp_one is assigned variant 1, which does not define the key.
	func sharedKeyAssignedVariantLacksKey() -> [String] {
		return [
			sharedKeyExperiment(id: 1, name: "exp_one", configs: ["{\"icon\":\"zero\"}", "{\"other\":1}"]),
			sharedKeyExperiment(id: 2, name: "exp_two", configs: [nil, "{\"icon\":\"two\"}"]),
		]
	}

	func testGetVariableValueSharedKeyBothAssignedLowestIdWins() throws {
		let context = try createSharedKeyContext(sharedKeyBothAssigned(lowestFirst: true))

		XCTAssertEqual("one", context.getVariableValue("icon", defaultValue: "default"))
		XCTAssertEqual(
			[Exposure(1, "exp_one", "session_id", 1, clock.millis(), true, true, false, true, false, false)],
			loggedExposures())
	}

	func testGetVariableValueSharedKeyHigherIdFirstInPayloadLowestIdWins() throws {
		let context = try createSharedKeyContext(sharedKeyBothAssigned(lowestFirst: false))

		XCTAssertEqual("one", context.getVariableValue("icon", defaultValue: "default"))
		XCTAssertEqual(
			[Exposure(1, "exp_one", "session_id", 1, clock.millis(), true, true, false, true, false, false)],
			loggedExposures())
	}

	func testGetVariableValueSharedKeyFirstUnassignedFallsThroughAndExposesBoth() throws {
		let context = try createSharedKeyContext(sharedKeyFirstUnassigned())

		XCTAssertEqual("two", context.getVariableValue("icon", defaultValue: "default"))
		XCTAssertEqual(
			[
				Exposure(1, "exp_one", "device_id", 0, clock.millis(), false, true, false, false, false, false),
				Exposure(2, "exp_two", "session_id", 1, clock.millis(), true, true, false, true, false, false),
			],
			loggedExposures())
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testGetVariableValueSharedKeyFirstUnassignedButOverriddenWins() throws {
		let context = try createSharedKeyContext(sharedKeyFirstUnassigned())
		context.setOverride(experimentName: "exp_one", variant: 1)

		XCTAssertEqual("one", context.getVariableValue("icon", defaultValue: "default"))
		XCTAssertEqual(
			[Exposure(1, "exp_one", "device_id", 1, clock.millis(), false, true, true, false, false, false)],
			loggedExposures())
	}

	func testGetVariableValueSharedKeyAssignedVariantLackingKeyFallsThrough() throws {
		let context = try createSharedKeyContext(sharedKeyAssignedVariantLacksKey())

		XCTAssertEqual("two", context.getVariableValue("icon", defaultValue: "default"))
		XCTAssertEqual(
			[
				Exposure(1, "exp_one", "session_id", 1, clock.millis(), true, true, false, true, false, false),
				Exposure(2, "exp_two", "session_id", 1, clock.millis(), true, true, false, true, false, false),
			],
			loggedExposures())
	}

	func testPeekVariableValueSharedKeyMatchesGetAndQueuesNothing() throws {
		let scenarios: [([String], String?, JSON)] = [
			(sharedKeyBothAssigned(lowestFirst: true), nil, "one"),
			(sharedKeyBothAssigned(lowestFirst: false), nil, "one"),
			(sharedKeyFirstUnassigned(), nil, "two"),
			(sharedKeyFirstUnassigned(), "exp_one", "one"),
			(sharedKeyAssignedVariantLacksKey(), nil, "two"),
		]

		for (experiments, override, expected) in scenarios {
			let context = try createSharedKeyContext(experiments)
			if let override = override {
				context.setOverride(experimentName: override, variant: 1)
			}

			XCTAssertEqual(expected, context.peekVariableValue("icon", defaultValue: "default"))
			XCTAssertEqual(0, context.getPendingCount())
			XCTAssertEqual([], loggedExposures())

			XCTAssertEqual(expected, context.getVariableValue("icon", defaultValue: "default"))
		}
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

		for element in contextData.experiments {
			if let variant = expectedVariants[element.name] {
				XCTAssertEqual(variant + 11, context.peekTreatment(element.name))
			}
		}
		XCTAssertEqual(3, context.peekTreatment("not_found"))

		// call again
		for element in contextData.experiments {
			if let variant = expectedVariants[element.name] {
				XCTAssertEqual(variant + 11, context.peekTreatment(element.name))
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

		for element in contextData.experiments {
			if let variant = expectedVariants[element.name] {
				XCTAssertEqual(variant, context.getTreatment(element.name))
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

		for element in contextData.experiments {
			if let variant = expectedVariants[element.name] {
				XCTAssertEqual(variant + 11, context.getTreatment(element.name))
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

		for element in contextData.experiments {
			if let variant = expectedVariants[element.name] {
				XCTAssertEqual(variant, context.getTreatment(element.name))
			}
		}
		XCTAssertEqual(0, context.getTreatment("not_found"))
		XCTAssertEqual(1 + UInt(contextData.experiments.count), context.getPendingCount())

		// call again
		for element in contextData.experiments {
			if let variant = expectedVariants[element.name] {
				XCTAssertEqual(variant, context.getTreatment(element.name))
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

	func testFailedTimerRefreshLogsOneErrorEvent() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.refreshInterval = 5
		let context = try createContext(config: contextConfig)
		logger.clearInvocations()

		let firstError = XCTestExpectation(description: "first .error")
		let secondError = XCTestExpectation(description: "second .error")
		secondError.isInverted = true
		let lock = NSLock()
		var errorCount = 0
		logger.handleEventContextEventClosure = { _, event in
			guard case .error = event else { return }
			lock.lock()
			errorCount += 1
			let count = errorCount
			lock.unlock()
			if count == 1 {
				firstError.fulfill()
			} else {
				secondError.fulfill()
			}
		}

		let (failed, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = failed
		// The refresh timer holds the context weakly, so keep it alive explicitly: in optimized
		// builds `_ = context` at the end would not.
		withExtendedLifetime(context) {
			scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReceivedArguments?.execute()
			resolver.reject(ABSmartlyError("refresh failed"))

			wait(for: [firstError], timeout: 2.0)
			// Any duplicate would come from the same completion chain, well within this window.
			wait(for: [secondError], timeout: 0.5)
		}
		lock.lock()
		XCTAssertEqual(1, errorCount)
		lock.unlock()
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

		for exp in contextData.experiments { _ = context.getTreatment(exp.name) }
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

		for exp in contextData.experiments { _ = context.getTreatment(exp.name) }
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

		XCTAssertEqual(3, context.getPendingCount())
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

		XCTAssertEqual(3, context.getPendingCount())
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

		XCTAssertEqual(3, context.getPendingCount())
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

		XCTAssertEqual(3, context.getPendingCount())
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

		XCTAssertEqual(3, context.getPendingCount())
	}

	func testRefreshClearsAssignmentCacheForIterationChange() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let experimentName = "exp_test_abc"
		XCTAssertEqual(2, context.getTreatment(experimentName))
		XCTAssertEqual(0, context.getTreatment("not_found"))

		XCTAssertEqual(2, context.getPendingCount())

		let refreshedContextData = try getContextData(source: "refreshed_iteration")
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

		XCTAssertEqual(3, context.getPendingCount())
	}

	func testGetCustomFieldKeys() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(["country", "languages", "overrides"], context.getCustomFieldKeys())
	}

	func testGetCustomFieldValues() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())
		XCTAssertNil(context.getCustomFieldValue(experimentName: "not_found", key: "not_found"))
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_test_ab", key: "not_found"))
		XCTAssertEqual("US,PT,ES,DE,FR", context.getCustomFieldValue(experimentName: "exp_test_ab", key: "country") as! String)
		XCTAssertEqual("string", context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "country"))

		let data: [String: JSON] = ["123": 1, "456": 0]
		XCTAssertEqual(data, context.getCustomFieldValue(experimentName: "exp_test_ab", key: "overrides") as! [String: JSON])
		XCTAssertEqual("json", context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "overrides"));

		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_test_ab", key: "languages"));
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "languages"));

		XCTAssertEqual("US,PT,ES", context.getCustomFieldValue(experimentName: "exp_test_abc", key: "country") as? String);
		XCTAssertEqual("string", context.getCustomFieldValueType(experimentName: "exp_test_abc", key: "country"));
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_test_abc", key: "overrides"));
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "exp_test_abc", key: "overrides"));
		XCTAssertEqual("en-US,en-GB,pt-PT,pt-BR,es-ES,es-MX", context.getCustomFieldValue(experimentName: "exp_test_abc", key: "languages") as? String);
		XCTAssertEqual("string", context.getCustomFieldValueType(experimentName: "exp_test_abc", key: "languages"));

		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_test_no_custom_fields", key: "country"));
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "exp_test_no_custom_fields", key: "country"));
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_test_no_custom_fields", key: "overrides"));
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "exp_test_no_custom_fields", key: "overrides"));
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_test_no_custom_fields", key: "languages"));
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "exp_test_no_custom_fields", key: "languages"));
	}

	func testRecoveryAfterPublishFailure() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125])

		XCTAssertEqual(1, context.getPendingCount())

		let failExpectation = XCTestExpectation(description: "Publish fails")

		let (failPromise, failResolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = failPromise

		_ = context.publish().catch { error in
			XCTAssertTrue(error is ABSmartlyError)
			failExpectation.fulfill()
		}

		failResolver.reject(ABSmartlyError("test publish failure"))

		wait(for: [failExpectation], timeout: 1.0)

		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isClosed())
		XCTAssertFalse(context.isFailed())

		context.track("goal2", properties: ["value": 200])
		XCTAssertEqual(2, context.getPendingCount())

		let treatment = context.getTreatment("exp_test_ab")
		XCTAssertEqual(1, treatment)
		XCTAssertEqual(3, context.getPendingCount())

		let successExpectation = XCTestExpectation(description: "Publish succeeds")

		handler.publishEventReturnValue = Promise.value(())

		_ = context.publish().done {
			successExpectation.fulfill()
		}

		wait(for: [successExpectation], timeout: 1.0)

		XCTAssertEqual(0, context.getPendingCount())
	}

	func testRecoveryAfterRefreshFailure() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)
		XCTAssertTrue(context.isReady())

		let failExpectation = XCTestExpectation(description: "Refresh fails")

		let (failPromise, failResolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = failPromise

		_ = context.refresh().catch { error in
			XCTAssertTrue(error is ABSmartlyError)
			failExpectation.fulfill()
		}

		failResolver.reject(ABSmartlyError("test refresh failure"))

		wait(for: [failExpectation], timeout: 1.0)

		XCTAssertTrue(context.isReady())
		XCTAssertFalse(context.isFailed())
		XCTAssertFalse(context.isClosed())

		let treatment = context.getTreatment("exp_test_ab")
		XCTAssertEqual(1, treatment)

		context.track("goal_after_refresh_failure", properties: nil)
		XCTAssertEqual(2, context.getPendingCount())

		let successExpectation = XCTestExpectation(description: "Refresh succeeds")

		let refreshedContextData = try getContextData(source: "refreshed")
		provider.getContextDataReturnValue = Promise.value(refreshedContextData)

		_ = context.refresh().done {
			successExpectation.fulfill()
		}

		wait(for: [successExpectation], timeout: 1.0)

		XCTAssertTrue(context.isReady())
		XCTAssertEqual(refreshedContextData.experiments.map { $0.name }, context.getExperiments())
	}

	func testGracefulDegradationNoNetwork() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)
		XCTAssertFalse(context.isReady())

		let expectation = XCTestExpectation(description: "Context handles network failure")

		resolver.reject(ABSmartlyError("Network connection failed"))

		_ = context.waitUntilReady().done { ctx in
			XCTAssertTrue(ctx.isReady())
			XCTAssertTrue(ctx.isFailed())

			let treatment = ctx.getTreatment("exp_test_ab")
			XCTAssertEqual(0, treatment)

			ctx.track("goal_offline", properties: nil)
			XCTAssertEqual(2, ctx.getPendingCount())

			ctx.setOverride(experimentName: "exp_test_ab", variant: 5)
			XCTAssertEqual(5, ctx.getTreatment("exp_test_ab"))

			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)

		let publishExpectation = XCTestExpectation(description: "Publish completes without calling handler")

		_ = context.publish().done { [self] in
			XCTAssertEqual(0, handler.publishEventCallsCount)
			publishExpectation.fulfill()
		}

		wait(for: [publishExpectation], timeout: 1.0)
	}

	func testRetryMechanismActivation() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: nil)

		var publishAttempts = 0
		let maxAttempts = 3

		let expectation = XCTestExpectation(description: "Retry mechanism test")

		handler.publishEventClosure = { _ in
			publishAttempts += 1
			if publishAttempts < maxAttempts {
				return Promise(error: ABSmartlyError("Transient failure \(publishAttempts)"))
			} else {
				return Promise.value(())
			}
		}

		_ = context.publish().done {
			expectation.fulfill()
		}.catch { _ in
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 5.0)

		XCTAssertGreaterThanOrEqual(publishAttempts, 1)
	}

	func testFailedToReadyTransition() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(
			config: contextConfig, data: Promise<ContextData>.init(error: ABSmartlyError("initial failure")))

		XCTAssertTrue(context.isReady())
		XCTAssertTrue(context.isFailed())

		let treatment = context.getTreatment("exp_test_ab")
		XCTAssertEqual(0, treatment)

		context.track("goal_while_failed", properties: nil)
		XCTAssertEqual(2, context.getPendingCount())

		XCTAssertEqual(0, handler.publishEventCallsCount)
	}

	func testRapidCloseReopenCycle() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: nil)

		handler.publishEventReturnValue = Promise.value(())

		let closeExpectation = XCTestExpectation(description: "Close completes")

		_ = context.close().done {
			closeExpectation.fulfill()
		}

		wait(for: [closeExpectation], timeout: 1.0)

		XCTAssertTrue(context.isClosed())

		let context2 = try createContext(config: contextConfig)
		XCTAssertTrue(context2.isReady())
		XCTAssertFalse(context2.isClosed())

		let treatment = context2.getTreatment("exp_test_ab")
		XCTAssertEqual(1, treatment)
	}

	func testAllStateTransitionPaths() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		XCTAssertFalse(context.isReady())
		XCTAssertFalse(context.isFailed())
		XCTAssertFalse(context.isClosing())
		XCTAssertFalse(context.isClosed())

		let readyExpectation = XCTestExpectation(description: "Ready state reached")

		resolver.fulfill(try getContextData())

		_ = context.waitUntilReady().done { ctx in
			XCTAssertTrue(ctx.isReady())
			XCTAssertFalse(ctx.isFailed())
			XCTAssertFalse(ctx.isClosing())
			XCTAssertFalse(ctx.isClosed())
			readyExpectation.fulfill()
		}

		wait(for: [readyExpectation], timeout: 1.0)

		context.track("goal1", properties: nil)

		let (publishPromise, publishResolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = publishPromise

		let closePromise = context.close()

		XCTAssertTrue(context.isClosing())
		XCTAssertFalse(context.isClosed())

		let closeExpectation = XCTestExpectation(description: "Close state reached")

		_ = closePromise.done {
			closeExpectation.fulfill()
		}

		publishResolver.fulfill(())

		wait(for: [closeExpectation], timeout: 1.0)

		XCTAssertTrue(context.isClosed())
		XCTAssertFalse(context.isClosing())
	}

	func testCustomFieldValueAllTypes() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let stringValue = context.getCustomFieldValue(experimentName: "exp_test_ab", key: "country")
		XCTAssertNotNil(stringValue)
		XCTAssertTrue(stringValue is String)
		XCTAssertEqual("string", context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "country"))

		let jsonValue = context.getCustomFieldValue(experimentName: "exp_test_ab", key: "overrides")
		XCTAssertNotNil(jsonValue)
		XCTAssertEqual("json", context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "overrides"))
	}

	func testCustomFieldNullHandling() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let missingExperimentValue = context.getCustomFieldValue(experimentName: "non_existent_experiment", key: "any_key")
		XCTAssertNil(missingExperimentValue)
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "non_existent_experiment", key: "any_key"))

		let missingKeyValue = context.getCustomFieldValue(experimentName: "exp_test_ab", key: "non_existent_key")
		XCTAssertNil(missingKeyValue)
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "non_existent_key"))

		let existingValue = context.getCustomFieldValue(experimentName: "exp_test_ab", key: "languages")
		XCTAssertNil(existingValue)
	}

	func testCustomFieldTypeCoercion() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))
		XCTAssertTrue(context.isReady())

		let keys = context.getCustomFieldKeys()
		XCTAssertTrue(keys.contains("country"))
		XCTAssertTrue(keys.contains("languages"))
		XCTAssertTrue(keys.contains("overrides"))

		let experimentKeys = context.getCustomFieldKeys(experimentName: "exp_test_ab")
		XCTAssertTrue(experimentKeys.contains("country"))
		XCTAssertTrue(experimentKeys.contains("overrides"))
	}

	// MARK: - Fix #1: setData visibility is internal

	func testSetDataIsNotPublic() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)
		XCTAssertTrue(context.isReady())
		let data = try getContextData()
		context.setData(data)
		XCTAssertNotNil(context.getContextData())
	}

	func testJsonCustomFieldObjectUsesConfiguredVariableParser() throws {
		class RecordingParser: VariableParser {
			var configs: [String] = []
			func parse(experimentName: String, config: String) -> [String: JSON]? {
				configs.append(config)
				return ["parsed_by": "custom"]
			}
		}
		let recording = RecordingParser()
		parser = recording
		let context = try createContext(config: getContextConfig(withUnits: true))

		XCTAssertEqual(
			["parsed_by": "custom"],
			context.getCustomFieldValue(experimentName: "exp_test_ab", key: "overrides") as? [String: JSON])
		XCTAssertTrue(recording.configs.contains("{\"123\":1,\"456\":0}"))
	}

	func testFailedAutoPublishLogsOneError() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		context.track("goal1", properties: nil)

		let failed = XCTestExpectation()
		logger.handleEventContextEventClosure = { _, event in
			if case .error = event { failed.fulfill() }
		}
		handler.publishEventReturnValue = Promise<Void>(error: ABSmartlyError("publish failure"))
		scheduler.scheduleAfterExecuteReceivedArguments?.execute()

		wait(for: [failed], timeout: 1.0)
		// Let the timer's own catch handler run (on any queue, including main) before counting.
		RunLoop.current.run(until: Date().addingTimeInterval(0.2))
		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(["publish failure"], loggedErrorMessages())
	}

	// MARK: - Fix #2: Flush events restored on publish failure

	func testFlushRestoresEventsOnPublishFailure() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: ["amount": 125])
		context.track("goal2", properties: ["value": 200])

		XCTAssertEqual(2, context.getPendingCount())

		let failExpectation = XCTestExpectation(description: "Publish fails")

		let (failPromise, failResolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = failPromise

		_ = context.publish().catch { error in
			XCTAssertTrue(error is ABSmartlyError)
			failExpectation.fulfill()
		}

		failResolver.reject(ABSmartlyError("publish failure"))

		wait(for: [failExpectation], timeout: 1.0)

		XCTAssertEqual(2, context.getPendingCount())

		let successExpectation = XCTestExpectation(description: "Publish succeeds with restored events")

		handler.publishEventReturnValue = Promise.value(())

		_ = context.publish().done { [self] in
			XCTAssertEqual(2, handler.publishEventCallsCount)
			let event = handler.publishEventReceivedInvocations.last!
			XCTAssertEqual(2, event.goals.count)
			successExpectation.fulfill()
		}

		wait(for: [successExpectation], timeout: 1.0)

		XCTAssertEqual(0, context.getPendingCount())
	}

	func testFlushRestoresExposuresOnPublishFailure() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		_ = context.getTreatment("exp_test_ab")
		XCTAssertEqual(1, context.getPendingCount())

		let failExpectation = XCTestExpectation(description: "Publish fails")

		let (failPromise, failResolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = failPromise

		_ = context.publish().catch { _ in
			failExpectation.fulfill()
		}

		failResolver.reject(ABSmartlyError("publish failure"))

		wait(for: [failExpectation], timeout: 1.0)

		XCTAssertEqual(1, context.getPendingCount())
	}

	// MARK: - Fix #6: Refresh only resets exposure for changed experiments

	func testRefreshDoesNotResetExposureForUnchangedExperiments() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		_ = context.getTreatment("exp_test_ab")
		XCTAssertEqual(1, context.getPendingCount())

		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			_ = context.getTreatment("exp_test_ab")
			XCTAssertEqual(1, context.getPendingCount())
			expectation.fulfill()
		}

		resolver.fulfill(contextData)

		wait(for: [expectation], timeout: 1.0)
	}

	func testRefreshResetsExposureForChangedExperiments() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let contextData = try getContextData()
		let context = try createContext(config: contextConfig, data: Promise<ContextData>.value(contextData))

		_ = context.getTreatment("exp_test_abc")
		XCTAssertEqual(1, context.getPendingCount())

		let refreshedContextData = try getContextData(source: "refreshed_iteration")
		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let expectation = XCTestExpectation()

		_ = context.refresh().done {
			_ = context.getTreatment("exp_test_abc")
			XCTAssertEqual(2, context.getPendingCount())
			expectation.fulfill()
		}

		resolver.fulfill(refreshedContextData)

		wait(for: [expectation], timeout: 1.0)
	}

	// MARK: - Fix #14/16: contextLock in flush uses defer

	func testFlushContextLockUsesDefer() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		context.track("goal1", properties: nil)
		XCTAssertEqual(1, context.getPendingCount())

		handler.publishEventReturnValue = Promise.value(())

		let expectation = XCTestExpectation()

		_ = context.publish().done {
			context.track("goal2", properties: nil)
			XCTAssertEqual(1, context.getPendingCount())
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	// MARK: - Fix #17: refreshPromise/closePromise protected by promiseLock

	func testConcurrentRefreshReturnsSamePromise() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		let (promise, resolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = promise

		let refreshPromise1 = context.refresh()
		let refreshPromise2 = context.refresh()

		XCTAssertEqual(1, provider.getContextDataCallsCount)

		let expectation = XCTestExpectation()
		expectation.expectedFulfillmentCount = 2

		_ = refreshPromise1.done { expectation.fulfill() }
		_ = refreshPromise2.done { expectation.fulfill() }

		resolver.fulfill(try getContextData())

		wait(for: [expectation], timeout: 1.0)
	}

	func testCloseWaitsForInFlightPublish() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		context.track("goal1", properties: nil)

		let (pending, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = pending

		_ = context.publish()
		let closeDone = XCTestExpectation(description: "close resolved")
		closeDone.isInverted = true
		_ = context.close().done { closeDone.fulfill() }
		wait(for: [closeDone], timeout: 0.3)

		let closeResolved = XCTestExpectation(description: "close resolved after publish")
		_ = context.close().done { closeResolved.fulfill() }
		resolver.fulfill(())
		wait(for: [closeResolved], timeout: 2.0)
		XCTAssertTrue(context.isClosed())
	}

	// The public entry point rejects a closing context (ensureReady); the closed/closing check in
	// getAssignmentExposing only covers a close() that starts between that check and the
	// claim, which a single-threaded test cannot interleave.
	func testGetTreatmentWhileClosingDoesNotEnqueueExposure() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		context.track("goal1", properties: nil)
		let (publish, resolver) = Promise<Void>.pending()
		let publishing = XCTestExpectation()
		handler.publishEventClosure = { _ in
			publishing.fulfill()
			return publish
		}

		let closed = XCTestExpectation()
		_ = context.close().done { closed.fulfill() }
		wait(for: [publishing], timeout: 2.0)
		XCTAssertTrue(context.isClosing())

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(0, context.getPendingCount())

		resolver.fulfill(())
		wait(for: [closed], timeout: 2.0)
		XCTAssertEqual(0, handler.publishEventReceivedEvent?.exposures.count)
	}

	func testGetTreatmentAfterCloseDoesNotEnqueueExposure() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		handler.publishEventReturnValue = Promise<Void>.value(())
		let closed = XCTestExpectation()
		_ = context.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 2.0)

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(["ABSmartly Context is closed."], loggedErrorMessages())
		XCTAssertEqual(0, context.getPendingCount())
	}

	func testFailedCloseIsRetryable() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		context.track("goal1", properties: nil)

		handler.publishEventReturnValue = Promise<Void>(error: NSError(domain: "t", code: 1))
		let failed = XCTestExpectation()
		_ = context.close().catch { _ in failed.fulfill() }
		wait(for: [failed], timeout: 2.0)
		XCTAssertFalse(context.isClosed())
		XCTAssertEqual(1, context.getPendingCount())

		handler.publishEventReturnValue = Promise<Void>.value(())
		let ok = XCTestExpectation()
		_ = context.close().done { ok.fulfill() }
		wait(for: [ok], timeout: 2.0)
		XCTAssertTrue(context.isClosed())
		XCTAssertEqual(0, context.getPendingCount())
	}

	// MARK: - Fix #18: setTimeout race condition removed

	func testSetTimeoutNoRaceCondition() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		_ = context.getTreatment("exp_test_ab")
		XCTAssertTrue(scheduler.scheduleAfterExecuteCalled)

		context.track("goal1", properties: nil)
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
	}

	// MARK: - Fix 4.1: setOverride succeeds after close

	func testSetOverrideSucceedsAfterClose() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let context = try createContext(config: contextConfig)

		handler.publishEventReturnValue = Promise.value(())

		let expectation = XCTestExpectation()
		_ = context.close().done {
			context.setOverride(experimentName: "exp_test", variant: 2)
			XCTAssertEqual(2, context.getOverride(experimentName: "exp_test"))
			expectation.fulfill()
		}

		wait(for: [expectation], timeout: 1.0)
	}

	func testContextIsReadyWhenReadyEventIsLogged() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		var readyWhenLogged: Bool?
		logger.handleEventContextEventClosure = { ctx, event in
			if case .ready = event { readyWhenLogged = ctx.isReady() }
		}

		let expectation = XCTestExpectation()
		_ = context.waitUntilReady().done { _ in expectation.fulfill() }
		resolver.fulfill(try getContextData())
		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(true, readyWhenLogged)
		XCTAssertTrue(context.isReady())
	}

	// As in v1.4.0, the context is already ready and failed when a load failure's `.error` event is
	// delivered, and on Apple platforms it arrives on the main thread.
	func testLoadFailureErrorEventSeesFailedContextOnMainThread() throws {
		let platformDefault = Context.deliversEventsOnMainThread
		Context.deliversEventsOnMainThread = true
		defer { Context.deliversEventsOnMainThread = platformDefault }

		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: contextConfig, data: promise)

		var stateWhenLogged: (ready: Bool, failed: Bool, onMain: Bool)?
		let logged = XCTestExpectation()
		logger.handleEventContextEventClosure = { ctx, event in
			if case .error = event {
				stateWhenLogged = (ctx.isReady(), ctx.isFailed(), Thread.isMainThread)
				logged.fulfill()
			}
		}

		DispatchQueue.global().async { resolver.reject(ABSmartlyError("load failed")) }
		wait(for: [logged], timeout: 1.0)

		XCTAssertEqual(true, stateWhenLogged?.ready)
		XCTAssertEqual(true, stateWhenLogged?.failed)
		XCTAssertEqual(true, stateWhenLogged?.onMain)
		XCTAssertTrue(context.isFailed())
	}

	func testAlreadyFailedLoadErrorEventSeesFailedContext() throws {
		var stateWhenLogged: (ready: Bool, failed: Bool)?
		logger.handleEventContextEventClosure = { ctx, event in
			if case .error = event { stateWhenLogged = (ctx.isReady(), ctx.isFailed()) }
		}

		_ = try createContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>(error: ABSmartlyError("load failed")))

		XCTAssertEqual(true, stateWhenLogged?.ready)
		XCTAssertEqual(true, stateWhenLogged?.failed)
	}

	func testPublishAndRefreshErrorEventsAreDeliveredOnTheMainThread() throws {
		let platformDefault = Context.deliversEventsOnMainThread
		Context.deliversEventsOnMainThread = true
		defer { Context.deliversEventsOnMainThread = platformDefault }

		let context = try createContext(config: getContextConfig(withUnits: true))
		var onMain: [Bool] = []
		let logged = XCTestExpectation()
		logged.expectedFulfillmentCount = 2
		logger.handleEventContextEventClosure = { _, event in
			if case .error = event {
				onMain.append(Thread.isMainThread)
				logged.fulfill()
			}
		}

		context.track("goal1", properties: nil)
		handler.publishEventClosure = { _ in
			Promise { seal in DispatchQueue.global().async { seal.reject(ABSmartlyError("publish failed")) } }
		}
		provider.getContextDataClosure = {
			Promise { seal in DispatchQueue.global().async { seal.reject(ABSmartlyError("refresh failed")) } }
		}
		_ = context.publish()
		_ = context.refresh()
		wait(for: [logged], timeout: 1.0)

		XCTAssertEqual([true, true], onMain)
	}

	func testCloseWithNothingPendingIsClosedWhenItReturns() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		logger.clearInvocations()

		_ = context.close()

		XCTAssertTrue(context.isClosed())
		XCTAssertFalse(context.isClosing())
		XCTAssertEqual(.close, logger.handleEventContextEventReceivedArguments?.event)
	}

	func testNumericUnitsKeepTheirTypeAndHashLikeJavaScript() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		contextConfig.setUnit(unitType: "user_id", uid: 125)
		contextConfig.setUnit(unitType: "float_id", uid: 125.75)
		let context = try createContext(config: contextConfig)
		context.setUnit(unitType: "session_id", uid: 12345)

		XCTAssertEqual(JSON(125), context.getUnitValue(unitType: "user_id"))
		XCTAssertEqual(.number, context.getUnitValue(unitType: "user_id")?.type)
		XCTAssertEqual(125.75, context.getUnitValue(unitType: "float_id")?.doubleValue)
		XCTAssertEqual(.number, context.getUnitValue(unitType: "session_id")?.type)
		XCTAssertEqual(.number, context.getUnitValues()["float_id"]?.type)

		// Same number again is not a change; a different one is.
		context.setUnit(unitType: "user_id", uid: 125)
		XCTAssertEqual([], loggedErrorMessages())
		context.setUnit(unitType: "user_id", uid: "125")
		XCTAssertEqual(["Unit 'user_id' already set."], loggedErrorMessages())
		XCTAssertEqual(JSON(125), context.getUnitValue(unitType: "user_id"))

		// JS hashes numbers with toFixed(0): 125.75 -> "126".
		XCTAssertEqual("BpBZt--EDwx0qBTskje27A", Hashing.hash(125.75))
		XCTAssertEqual(Hashing.hash("126"), Hashing.hash(125.75))
		XCTAssertEqual(Hashing.hash("12345"), Hashing.hash(12345))

		context.setUnit(unitType: "flag_id", value: JSON(true))
		XCTAssertEqual("Unit 'flag_id' must be a string or a number.", loggedErrorMessages().last)
		XCTAssertNil(context.getUnitValue(unitType: "flag_id"))
		context.setUnit(unitType: "json_id", value: JSON(7))
		XCTAssertEqual(.number, context.getUnitValue(unitType: "json_id")?.type)

		let stringConfig: ContextConfig = getContextConfig(withUnits: false)
		stringConfig.setUnit(unitType: "float_id", uid: "126")
		let stringContext = try createContext(config: stringConfig)
		XCTAssertEqual(.string, stringContext.getUnitValue(unitType: "float_id")?.type)
	}

	func testHashingHelpers() {
		XCTAssertEqual([97, 195, 167, 98, 226, 134, 147, 99], Hashing.utf8Bytes("a\u{e7}b\u{2193}c"))
		XCTAssertEqual("YWJj", Hashing.base64UrlNoPadding(Data("abc".utf8)))
		XCTAssertEqual("Pz8-", Hashing.base64UrlNoPadding(Data([0x3f, 0x3f, 0x3e])))
	}

	func testNumericUnitStringMatchesJavaScriptToFixed() throws {
		XCTAssertEqual("-0", Hashing.unitString(-0.1))
		XCTAssertEqual("0", Hashing.unitString(-0.0))
		XCTAssertEqual("1e+21", Hashing.unitString(1e21))
		XCTAssertEqual("-1.5e+22", Hashing.unitString(-1.5e22))
		XCTAssertEqual("3", Hashing.unitString(2.5))
		XCTAssertEqual("-3", Hashing.unitString(-2.5))

		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		contextConfig.setUnit(unitType: "neg_id", uid: -0.1)
		contextConfig.setUnit(unitType: "big_id", uid: 1e21)
		let context = try createContext(config: contextConfig)
		_ = context.getTreatment("exp_test_ab")
		handler.publishEventReturnValue = Promise<Void>.value(())
		let expectation = XCTestExpectation()
		_ = context.publish().done { expectation.fulfill() }
		wait(for: [expectation], timeout: 1.0)
		let published = Dictionary(uniqueKeysWithValues: (handler.publishEventReceivedEvent?.units ?? []).map { ($0.type, $0.uid) })
		XCTAssertEqual(Hashing.hash("-0"), published["neg_id"])
		XCTAssertEqual(Hashing.hash("1e+21"), published["big_id"])
	}

	func testGoalTrackedInsideSynchronousReadyCallbackIsScheduled() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.publishDelay = 0.1
		logger.handleEventContextEventClosure = { ctx, event in
			if case .ready = event { ctx.track("goal_in_ready", properties: nil) }
		}
		let context = try createContext(config: contextConfig)

		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
	}

	func testCloseFlushesQueuedEventsAfterOwnerReleasesContext() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.publishDelay = -1
		// No event logger: the logger mock would keep the context alive.
		var context: Context? = Context(
			config: contextConfig, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: nil,
			parser: parser, matcher: AudienceMatcher(), promise: Promise<ContextData>.value(try getContextData()))
		context?.track("goal_on_teardown", properties: nil)
		handler.publishEventReturnValue = Promise<Void>.value(())

		let closed = XCTestExpectation()
		_ = context?.close().done { closed.fulfill() }
		context = nil

		wait(for: [closed], timeout: 1.0)
		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual("goal_on_teardown", handler.publishEventReceivedEvent?.goals.first?.name)
	}

	private func contextWithoutLogger(_ config: ContextConfig, _ data: Promise<ContextData>) -> Context {
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: nil,
			parser: parser, matcher: AudienceMatcher(), promise: data)
	}

	func testWaitUntilReadySettlesAfterOwnerReleasesContext() throws {
		let (promise, resolver) = Promise<ContextData>.pending()
		var context: Context? = contextWithoutLogger(getContextConfig(withUnits: true), promise)
		let ready = context!.waitUntilReady()
		context = nil

		let settled = XCTestExpectation()
		var readyContext: Context?
		_ = ready.done { readyContext = $0; settled.fulfill() }
		resolver.fulfill(try getContextData())
		wait(for: [settled], timeout: 1.0)
		XCTAssertEqual(true, readyContext?.isReady())
	}

	func testRefreshSettlesAfterOwnerReleasesContext() throws {
		var context: Context? = contextWithoutLogger(getContextConfig(withUnits: true), Promise.value(try getContextData()))
		let (refreshData, refreshResolver) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = refreshData
		let refresh = context!.refresh()
		context = nil

		let settled = XCTestExpectation()
		_ = refresh.done { settled.fulfill() }
		refreshResolver.fulfill(try getContextData())
		wait(for: [settled], timeout: 1.0)
	}

	func testFullAttributeHistoryIsPublished() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.publishDelay = -1
		let context = try createContext(config: contextConfig)
		context.setAttribute(name: "returning", value: true)
		for i in 0..<600 {
			context.setAttribute(name: "counter", value: JSON(i))
		}
		XCTAssertEqual(JSON(true), context.getAttribute(name: "returning"))
		XCTAssertEqual(JSON(599), context.getAttribute(name: "counter"))
		XCTAssertEqual(["returning": JSON(true), "counter": JSON(599)], context.getAttributes())

		context.track("goal1", properties: nil)
		handler.publishEventReturnValue = Promise<Void>.value(())
		let published = XCTestExpectation()
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 1.0)
		XCTAssertEqual(601, handler.publishEventReceivedEvent?.attributes.count)
	}

	func testQueuedGoalsAreNeverDroppedBeforePublish() throws {
		let contextConfig: ContextConfig = getContextConfig(withUnits: true)
		contextConfig.publishDelay = -1
		let context = try createContext(config: contextConfig)
		for i in 1...1001 {
			context.track("goal-\(i)", properties: nil)
		}
		XCTAssertEqual(1001, context.getPendingCount())

		handler.publishEventReturnValue = Promise<Void>.value(())
		let published = XCTestExpectation()
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 1.0)
		let goals = handler.publishEventReceivedEvent?.goals ?? []
		XCTAssertEqual(1001, goals.count)
		XCTAssertEqual("goal-1", goals.first?.name)
		XCTAssertEqual("goal-1001", goals.last?.name)
	}

	func testCustomAssignmentAllowedAfterFinalize() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		let closed = XCTestExpectation()
		_ = context.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 1.0)
		XCTAssertNoThrow(context.setCustomAssignment(experimentName: "exp_test_ab", variant: 1))
		XCTAssertEqual(1, context.getCustomAssignment(experimentName: "exp_test_ab"))
	}

	func testPublicApiDoesNotThrowAndReturnsDefaultsBeforeReady() throws {
		let (promise, _) = Promise<ContextData>.pending()
		let context = try createContext(config: getContextConfig(withUnits: true), data: promise)

		let treatment: Int = context.getTreatment("exp_test_ab")
		XCTAssertEqual(0, treatment)
		XCTAssertEqual(0, context.peekTreatment("exp_test_ab"))
		XCTAssertEqual(JSON(5), context.getVariableValue("banner.size", defaultValue: JSON(5)))
		XCTAssertEqual(JSON(5), context.peekVariableValue("banner.size", defaultValue: JSON(5)))
		XCTAssertEqual([:], context.getVariableKeys())
		XCTAssertEqual([], context.getExperiments())
		XCTAssertEqual([], context.getCustomFieldKeys())
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp_test_ab", key: "country"))
		XCTAssertNil(context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "country"))
		XCTAssertNil(context.getContextData())
		XCTAssertEqual(0, context.getPendingCount())

		// getCustomFieldValue/getCustomFieldValueType return nil without an error event, as in v1.4.0.
		XCTAssertEqual(8, loggedErrorMessages().count)
		XCTAssertEqual(["ABSmartly Context is not yet ready."], Set(loggedErrorMessages()).sorted())
	}

	func testErrorHandlerReadingContextOnFailedLoadDoesNotRecurse() throws {
		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: getContextConfig(withUnits: true), data: promise)

		var nestedReads = 0
		logger.handleEventContextEventClosure = { ctx, event in
			guard case .error = event, nestedReads < 50 else { return }
			nestedReads += 1
			XCTAssertNil(ctx.getContextData())
		}

		let settled = XCTestExpectation()
		_ = context.waitUntilReady().ensure { settled.fulfill() }
		resolver.reject(ABSmartlyError("load failed"))
		wait(for: [settled], timeout: 1.0)

		XCTAssertEqual(1, nestedReads)
		XCTAssertEqual(["load failed"], loggedErrorMessages())
		XCTAssertTrue(context.isFailed())
	}

	func testErrorHandlerReadingContextBeforeReadyDoesNotRecurse() throws {
		let (promise, _) = Promise<ContextData>.pending()
		let context = try createContext(config: getContextConfig(withUnits: true), data: promise)

		var nestedReads = 0
		logger.handleEventContextEventClosure = { ctx, event in
			guard case .error = event, nestedReads < 50 else { return }
			nestedReads += 1
			XCTAssertEqual(0, ctx.getTreatment("exp_test_ab"))
		}

		// Each top-level misuse is still reported once; only the nested one is suppressed.
		XCTAssertNil(context.getContextData())
		XCTAssertNil(context.getContextData())
		XCTAssertEqual(2, nestedReads)
		XCTAssertEqual(Array(repeating: "ABSmartly Context is not yet ready.", count: 2), loggedErrorMessages())
	}

	func testWritesAfterCloseAreIgnoredWithErrorEvent() throws {
		let context = try createContext(config: getContextConfig(withUnits: true))
		let closed = XCTestExpectation()
		_ = context.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 1.0)

		context.track("goal1", properties: nil)
		context.setAttribute(name: "attr", value: JSON(1))
		context.setUnit(unitType: "device_id", uid: "abc")

		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertNil(context.getAttribute(name: "attr"))
		XCTAssertNil(context.getUnit(unitType: "device_id"))
		XCTAssertEqual(Array(repeating: "ABSmartly Context is closed.", count: 3), loggedErrorMessages())
	}

	func testReadsInsideReadyHandlerSeeTheData() throws {
		var treatmentInHandler: Int?
		var variableInHandler: JSON?
		logger.handleEventContextEventClosure = { ctx, event in
			if case .ready = event {
				treatmentInHandler = ctx.getTreatment("exp_test_ab")
				variableInHandler = ctx.getVariableValue("banner.size", defaultValue: nil)
			}
		}

		let context = try createContext(config: getContextConfig(withUnits: true))
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(1, treatmentInHandler)
		XCTAssertEqual(JSON("large"), variableInHandler)
		XCTAssertEqual([], loggedErrorMessages())
	}

	func testReadsInsideReadyHandlerSeeTheDataWhenLoadedAsynchronously() throws {
		var treatmentInHandler: Int?
		logger.handleEventContextEventClosure = { ctx, event in
			if case .ready = event { treatmentInHandler = ctx.getTreatment("exp_test_ab") }
		}

		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: getContextConfig(withUnits: true), data: promise)
		let expectation = XCTestExpectation()
		_ = context.waitUntilReady().done { _ in expectation.fulfill() }
		resolver.fulfill(try getContextData())
		wait(for: [expectation], timeout: 1.0)

		XCTAssertEqual(1, treatmentInHandler)
		XCTAssertEqual([], loggedErrorMessages())
	}

	func testLongUnitUIDIsAcceptedAndAssigned() throws {
		let longUID = String(repeating: "a", count: 300)
		let contextConfig: ContextConfig = getContextConfig(withUnits: false)
		contextConfig.setUnit(unitType: "session_id", uid: longUID)
		contextConfig.publishDelay = -1
		let context = try createContext(config: contextConfig)
		context.setUnit(unitType: "user_id", uid: String(repeating: "b", count: 1000))

		XCTAssertEqual(longUID, context.getUnit(unitType: "session_id"))
		XCTAssertEqual(1000, context.getUnit(unitType: "user_id")?.count)
		XCTAssertEqual([], loggedErrorMessages())

		_ = context.getTreatment("exp_test_ab")
		handler.publishEventReturnValue = Promise<Void>.value(())
		let published = XCTestExpectation()
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 1.0)

		let event = handler.publishEventReceivedEvent
		XCTAssertEqual(["session_id", "user_id"], event?.units.map { $0.type }.sorted())
		XCTAssertEqual(Hashing.hash(longUID), event?.units.first { $0.type == "session_id" }?.uid)
		XCTAssertEqual(true, event?.exposures.first?.assigned)
	}

	func testCloseEventKeepsItsCaseName() throws {
		var closeLogged = false
		logger.handleEventContextEventClosure = { _, event in
			switch event {
			case .ready, .refresh, .publish, .exposure, .goal, .error:
				break
			case .close:
				closeLogged = true
			}
		}

		let context = try createContext(config: getContextConfig(withUnits: true))
		let closed = XCTestExpectation()
		_ = context.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 1.0)

		XCTAssertTrue(closeLogged)
		XCTAssertEqual(ContextEventLoggerEvent.finalize, ContextEventLoggerEvent.close)
	}

	func testCustomFieldValuesHaveTheirV140Types() throws {
		let json = """
			{"experiments": [{"id": 1, "name": "exp", "customFieldValues": [
				{"name": "obj", "type": "json", "value": "{\\"a\\": [1, \\"x\\"]}"},
				{"name": "int", "type": "number", "value": "42"},
				{"name": "float", "type": "number", "value": "1.5"},
				{"name": "flag", "type": "boolean", "value": "true"}
			]}]}
			"""
		let contextData = try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
		let context = try createContext(config: getContextConfig(withUnits: true), data: Promise.value(contextData))

		let obj = context.getCustomFieldValue(experimentName: "exp", key: "obj") as? [String: JSON]
		XCTAssertEqual(["a": JSON([1, "x"])], obj)
		XCTAssertEqual(42.0, context.getCustomFieldValue(experimentName: "exp", key: "int") as? Double)
		XCTAssertEqual(1.5, context.getCustomFieldValue(experimentName: "exp", key: "float") as? Double)
		XCTAssertEqual(true, context.getCustomFieldValue(experimentName: "exp", key: "flag") as? Bool)
	}

	func testPublishBeforeReadySendsQueuedGoals() throws {
		let (promise, _) = Promise<ContextData>.pending()
		let context = try createContext(config: getContextConfig(withUnits: true), data: promise)
		context.track("goal1", properties: nil)
		XCTAssertEqual(1, context.getPendingCount())

		handler.publishEventReturnValue = Promise<Void>.value(())
		let published = XCTestExpectation()
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 1.0)

		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(["goal1"], handler.publishEventReceivedEvent?.goals.map { $0.name })
		XCTAssertEqual([], loggedErrorMessages())
	}

	func testRefreshBeforeReadyFetchesData() throws {
		let (promise, _) = Promise<ContextData>.pending()
		let context = try createContext(config: getContextConfig(withUnits: true), data: promise)

		provider.getContextDataReturnValue = Promise.value(try getContextData())
		let refreshed = XCTestExpectation()
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 1.0)

		XCTAssertEqual(1, provider.getContextDataCallsCount)
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
	}

	func testTrackThenDropContextStillPublishes() throws {
		var context: Context? = contextWithoutLogger(getContextConfig(withUnits: true), Promise.value(try getContextData()))
		let weakContext = WeakContext(context)
		context!.track("goal1", properties: nil)
		let publishTimer = try XCTUnwrap(scheduler.scheduleAfterExecuteReceivedArguments?.execute)
		context = nil
		XCTAssertNotNil(weakContext.value, "a pending publish keeps the context alive")

		handler.publishEventReturnValue = Promise<Void>.value(())
		publishTimer()
		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(["goal1"], handler.publishEventReceivedEvent?.goals.map { $0.name })
	}

	func testCompletionEventsAreDeliveredOnTheMainThread() throws {
		let platformDefault = Context.deliversEventsOnMainThread
		Context.deliversEventsOnMainThread = true
		defer { Context.deliversEventsOnMainThread = platformDefault }

		var deliveredOnMain: [String: Bool] = [:]
		let delivered = XCTestExpectation()
		delivered.expectedFulfillmentCount = 3
		logger.handleEventContextEventClosure = { _, event in
			switch event {
			case .ready: deliveredOnMain["ready"] = Thread.isMainThread
			case .publish: deliveredOnMain["publish"] = Thread.isMainThread
			case .refresh: deliveredOnMain["refresh"] = Thread.isMainThread
			default: return
			}
			delivered.fulfill()
		}

		let (promise, resolver) = Promise<ContextData>.pending()
		let context = try createContext(config: getContextConfig(withUnits: true), data: promise)
		let data = try getContextData()
		DispatchQueue.global().async { resolver.fulfill(data) }
		let ready = XCTestExpectation()
		_ = context.waitUntilReady().done { _ in ready.fulfill() }
		wait(for: [ready], timeout: 1.0)

		context.track("goal1", properties: nil)
		handler.publishEventClosure = { _ in
			Promise { seal in DispatchQueue.global().async { seal.fulfill(()) } }
		}
		provider.getContextDataClosure = {
			Promise { seal in DispatchQueue.global().async { seal.fulfill(data) } }
		}
		_ = context.publish()
		_ = context.refresh()
		wait(for: [delivered], timeout: 1.0)

		XCTAssertEqual(["ready": true, "publish": true, "refresh": true], deliveredOnMain)

		// close() with queued events flushes first, then delivers `.close` on main too.
		var closeDeliveredOnMain: Bool?
		let closeDelivered = XCTestExpectation()
		logger.handleEventContextEventClosure = { _, event in
			if case .close = event {
				closeDeliveredOnMain = Thread.isMainThread
				closeDelivered.fulfill()
			}
		}
		context.track("goal2", properties: nil)
		_ = context.close()
		wait(for: [closeDelivered], timeout: 1.0)

		XCTAssertEqual(true, closeDeliveredOnMain)
	}

	// MARK: - System attributes (application / environment) in audience evaluation

	func testStrictAudienceMatchesConfiguredEnvironment() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"production\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false)],
			loggedExposures())
		XCTAssertEqual("large", context.getVariableValue("banner.size", defaultValue: "default"))
	}

	func testStrictAudienceMatchesConfiguredApplication() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"application\"},{\"value\":\"website\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false)],
			loggedExposures())
	}

	func testStrictAudienceMismatchOnOtherEnvironment() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"staging\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 0, clock.millis(), false, true, false, false, false, true)],
			loggedExposures())
	}

	// 4. A user-set attribute wins over the configured value, even set after creation, and
	// invalidates an assignment cached before it was set.
	func testUserSetEnvironmentOverridesConfiguredValue() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"staging\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))

		// Cached before the attribute is set: production ≠ staging, strict mismatch → 0.
		XCTAssertEqual(0, context.peekTreatment("exp_test_ab"))

		context.setAttribute(name: "environment", value: "staging")

		// The cached assignment is invalidated and re-evaluated: staging now matches → 1.
		XCTAssertEqual(1, context.peekTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 1, clock.millis(), true, true, false, false, false, false)],
			loggedExposures())
	}

	// A user value also loses the match once it overrides a configured value that matched.
	func testUserSetEnvironmentOverridesMatchingConfiguredValue() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"production\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))

		XCTAssertEqual(1, context.peekTreatment("exp_test_ab"))

		context.setAttribute(name: "environment", value: "staging")

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 0, clock.millis(), false, true, false, false, false, true)],
			loggedExposures())
	}

	// An audience condition on the configured environment matches.
	func testAudienceConditionMatchesConfiguredEnvironment() throws {
		let data = try strictAudienceContextData(
			filter: "{\"and\":[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"production\"}]}]}")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
	}

	// With no environment configured, the key is absent from the map: no crash, and a filter on
	// `environment` does not match.
	func testMissingEnvironmentConfigLeavesKeyOut() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"production\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data),
			environment: nil)

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 0, clock.millis(), false, true, false, false, false, true)],
			loggedExposures())
	}

	// A `null` filter on a missing environment matches, confirming the key is absent (not null/"").
	func testMissingEnvironmentConfigMatchesNullFilter() throws {
		let data = try strictAudienceContextData(filter: "[{\"null\":{\"var\":\"environment\"}}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data),
			environment: nil)

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
	}

	// An empty environment name is treated the same as unconfigured: the key is left out.
	func testEmptyEnvironmentConfigLeavesKeyOut() throws {
		let data = try strictAudienceContextData(filter: "[{\"null\":{\"var\":\"environment\"}}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data),
			environment: "")

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
	}

	// An empty application name is treated the same as unconfigured: the key is left out.
	func testEmptyApplicationConfigLeavesKeyOut() throws {
		let data = try strictAudienceContextData(filter: "[{\"null\":{\"var\":\"application\"}}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data),
			application: "")

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
	}

	// Nothing extra is published: the serialized payload carries no `application`/`environment`/
	// `app_version` attribute beyond the user-set ones.
	func testSystemAttributesAreNotPublished() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"production\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))
		context.setAttribute(name: "custom_attr", value: "custom_value")

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))

		let expectation = XCTestExpectation()
		let (promise, resolver) = Promise<Void>.pending()
		handler.publishEventReturnValue = promise

		_ = context.publish().done { [self] in
			let event = handler.publishEventReceivedEvent
			XCTAssertNotNil(event)
			do {
				let payload = try JSONEncoder().encode(event!)
				let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
				let attributes = (object?["attributes"] as? [[String: Any]]) ?? []
				let names = attributes.compactMap { $0["name"] as? String }
				XCTAssertEqual(["custom_attr"], names)
				XCTAssertFalse(names.contains("application"))
				XCTAssertFalse(names.contains("environment"))
				XCTAssertFalse(names.contains("app_version"))
			} catch {
				XCTFail(error.localizedDescription)
			}
			expectation.fulfill()
		}

		resolver.fulfill(())
		wait(for: [expectation], timeout: 1.0)
	}

	// `app_version` is never injected: a filter on it does not match. The SDK path with a configured
	// application version is covered in ABSmartlySDKTest.
	func testAppVersionIsNotInjectedIntoEvaluation() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"app_version\"},{\"value\":\"1.2.3\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))

		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(
			[Exposure(1, "exp_test_ab", "session_id", 0, clock.millis(), false, true, false, false, false, true)],
			loggedExposures())
	}

	func testUserSetAppVersionIsEvaluated() throws {
		let data = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"app_version\"},{\"value\":\"1.2.3\"}]}]")
		let context = try createSystemContext(
			config: getContextConfig(withUnits: true), data: Promise<ContextData>.value(data))
		context.setAttribute(name: "app_version", value: "1.2.3")

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
	}

	func testSystemAttributesAreNotReportedAsUserAttributes() throws {
		let context = try createSystemContext(config: getContextConfig(withUnits: true))
		context.setAttribute(name: "age", value: 25)

		XCTAssertEqual(["age": JSON(25)], context.getAttributes())
		XCTAssertNil(context.getAttribute(name: "environment"))
		XCTAssertNil(context.getAttribute(name: "application"))
	}
}

// Behaviour kept from v1.4.0 for the 1.5.0 release (see CHANGELOG "Compatibility").
final class ContextV140BehaviourTest: XCTestCase {
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

	private func makeContext(_ config: ContextConfig, _ data: Promise<ContextData>) -> Context {
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: DefaultVariableParser(), matcher: AudienceMatcher(), promise: data)
	}

	private func config() -> ContextConfig {
		let config = ContextConfig()
		config.setUnit(unitType: "session_id", uid: "e791e240fcd3df7d238cfc285f475e8152fcc0ec")
		return config
	}

	func testRefreshSettlesExistingWaiterAndSchedulesPreReadyGoals() throws {
		let (initial, _) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		let waiting = context.waitUntilReady()
		context.track("before-ready", properties: nil)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		let completed = expectation(description: "waiter")
		_ = waiting.done { _ in completed.fulfill() }
		_ = context.refresh()
		wait(for: [completed], timeout: 2)
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
	}

	// Completion closures may still be returning on another thread when the promise the test waited
	// on settles, so give the last strong reference up to two seconds to go.
	private func waitUntilReleased(_ weak: WeakContext) -> Bool {
		let deadline = Date().addingTimeInterval(2)
		while weak.value != nil && Date() < deadline {
			usleep(1000)
		}
		return weak.value == nil
	}

	private func loggedLifecycleEvents() -> [String] {
		return logger.handleEventContextEventReceivedInvocations.compactMap { invocation -> String? in
			switch invocation.event {
			case .ready: return "ready"
			case .refresh: return "refresh"
			case .error: return "error"
			default: return nil
			}
		}
	}

	#if DEBUG
	private func settleInitialLoad(_ settle: () -> Void) {
		let settled = XCTestExpectation(description: "initial load handled")
		Context.setTestHook(.initialLoadSettled) { settled.fulfill() }
		defer { Context.setTestHook(.initialLoadSettled, nil) }
		settle()
		wait(for: [settled], timeout: 2)
	}

	func testRefreshThatWinsTheInitialLoadLogsReadyOnce() throws {
		let platformDefault = Context.deliversEventsOnMainThread
		Context.deliversEventsOnMainThread = false
		defer { Context.deliversEventsOnMainThread = platformDefault }

		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		let data = try contextData()
		settleInitialLoad { initialSeal.fulfill(data) }

		XCTAssertEqual(["ready", "refresh"], loggedLifecycleEvents())
		XCTAssertFalse(context.getExperiments().isEmpty)
	}

	// The initial load finishes while a refresh is in flight: `.ready` comes from the initial load
	// and the refresh only logs `.refresh`.
	func testInitialLoadThatWinsARefreshLogsReadyOnce() throws {
		let platformDefault = Context.deliversEventsOnMainThread
		Context.deliversEventsOnMainThread = false
		defer { Context.deliversEventsOnMainThread = platformDefault }

		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		let (refresh, refreshSeal) = Promise<ContextData>.pending()
		provider.getContextDataReturnValue = refresh
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }

		let data = try contextData()
		settleInitialLoad { initialSeal.fulfill(data) }
		refreshSeal.fulfill(data)
		wait(for: [refreshed], timeout: 2)

		XCTAssertEqual(["ready", "refresh"], loggedLifecycleEvents())
	}

	// The initial load has already taken its context reference when a refresh makes the context
	// ready; its state check must then ignore its result.
	private func refreshWhileInitialLoadIsCompleting(_ settle: (Resolver<ContextData>) -> Void) throws -> Context {
		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		var refreshWon = XCTWaiter.Result.timedOut
		Context.setTestHook(.initialLoadTookContext) {
			Context.setTestHook(.initialLoadTookContext, nil)
			let refreshed = XCTestExpectation()
			_ = context.refresh().done { refreshed.fulfill() }
			refreshWon = XCTWaiter().wait(for: [refreshed], timeout: 2)
		}
		defer { Context.setTestHook(.initialLoadTookContext, nil) }
		settleInitialLoad { settle(initialSeal) }
		// Otherwise the scenario ran in the opposite order and the assertions below prove nothing.
		XCTAssertEqual(.completed, refreshWon, "the refresh did not complete inside the initial load's completion")
		return context
	}

	func testInitialSuccessCompletingAfterARefreshWonIsIgnored() throws {
		let context = try refreshWhileInitialLoadIsCompleting { $0.fulfill(ContextData()) }
		XCTAssertFalse(context.getExperiments().isEmpty)
		XCTAssertEqual(["ready", "refresh"], loggedLifecycleEvents())
	}

	func testInitialFailureCompletingAfterARefreshWonIsIgnored() throws {
		let context = try refreshWhileInitialLoadIsCompleting { $0.reject(ABSmartlyError("late failure")) }
		XCTAssertFalse(context.isFailed())
		XCTAssertNil(context.readyError())
		XCTAssertEqual(["ready", "refresh"], loggedLifecycleEvents())
	}

	func testRefreshWinsLateInitialFailure() throws {
		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		settleInitialLoad { initialSeal.reject(ABSmartlyError("late initial failure")) }

		XCTAssertFalse(context.isFailed())
		XCTAssertNil(context.readyError())
		XCTAssertNotNil(context.getContextData())
		XCTAssertFalse(loggedLifecycleEvents().contains("error"))
	}

	func testRefreshWinsLateInitialSuccess() throws {
		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		settleInitialLoad { initialSeal.fulfill(ContextData()) }

		XCTAssertFalse(context.isFailed())
		XCTAssertFalse(context.getExperiments().isEmpty)
	}

	#endif

	// A provider promise that never settles does not keep a closed context alive once a refresh has
	// made it ready and the caller lets go.
	func testContextWhoseInitialLoadNeverSettlesIsReleasedAfterRefreshAndClose() throws {
		let (initial, _) = Promise<ContextData>.pending()
		var context: Context? = Context(
			config: config(), clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: nil,
			parser: DefaultVariableParser(), matcher: AudienceMatcher(), promise: initial)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = XCTestExpectation()
		_ = context!.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)
		let closed = XCTestExpectation()
		_ = context!.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 2)

		// Keep the unsettled provider promise (and its completions) alive through the check, so this
		// tests that the refresh revoked their hold on the context.
		withExtendedLifetime(initial) {
			let released = WeakContext(context)
			context = nil
			XCTAssertTrue(waitUntilReleased(released))
		}
	}

	// A goal tracked while the first load is pending is not discarded when that load fails: no
	// publish is scheduled for the failed context, and a later successful refresh publishes it.
	func testGoalQueuedBeforeAFailedLoadIsPublishedAfterRecovery() throws {
		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		context.track("before-failure", properties: nil)
		let waiting = expectation(description: "ready")
		_ = context.waitUntilReady().done { _ in waiting.fulfill() }
		initialSeal.reject(ABSmartlyError("load failed"))
		wait(for: [waiting], timeout: 2)
		XCTAssertTrue(context.isFailed())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(1, context.getPendingCount())

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)

		handler.publishEventReturnValue = Promise.value(())
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		XCTAssertEqual(["before-failure"], handler.publishEventReceivedEvent?.goals.map { $0.name })
	}

	// A provider that cancels the initial fetch fails the context (settling waiters) and does not keep
	// it alive after close.
	func testCancelledInitialLoadFailsTheContextAndReleasesIt() throws {
		let (initial, initialSeal) = Promise<ContextData>.pending()
		var context: Context? = Context(
			config: config(), clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: nil,
			parser: DefaultVariableParser(), matcher: AudienceMatcher(), promise: initial)
		let waiting = expectation(description: "ready")
		_ = context!.waitUntilReady().done { _ in waiting.fulfill() }
		initialSeal.reject(PMKError.cancelled)
		wait(for: [waiting], timeout: 2)
		XCTAssertTrue(context!.isFailed())

		let closed = expectation(description: "closed")
		_ = context!.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 2)
		withExtendedLifetime(initial) {
			let released = WeakContext(context)
			context = nil
			XCTAssertTrue(waitUntilReleased(released))
		}
	}

	// A publish the handler cancels re-queues its events and lets close() settle (rejected), like any
	// other publish failure, instead of leaving the context closing forever.
	func testCancelledPublishRequeuesEventsAndCloseSettles() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		context.track("goal1", properties: nil)
		handler.publishEventReturnValue = Promise(error: PMKError.cancelled)

		let closeSettled = expectation(description: "close settles")
		context.close().catch(policy: .allErrors) { _ in closeSettled.fulfill() }
		wait(for: [closeSettled], timeout: 2)

		XCTAssertFalse(context.isClosing())
		XCTAssertFalse(context.isClosed())
		XCTAssertEqual(1, context.getPendingCount())
	}

	func testCancelledRefreshSettlesAndAllowsAnotherRefresh() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		provider.getContextDataReturnValue = Promise(error: PMKError.cancelled)
		let cancelled = expectation(description: "cancelled refresh settles")
		context.refresh().catch(policy: .allErrors) { _ in cancelled.fulfill() }
		wait(for: [cancelled], timeout: 2)

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "second refresh")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)
		XCTAssertEqual(2, provider.getContextDataCallsCount)
	}

	// An override set while a failed context recovers is rebuilt from the refreshed experiment
	// (id and variables), not kept from the failed state where the experiment was unknown.
	func testAssignmentsReadWhileFailedAreRebuiltWhenRefreshRecovers() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		context.setOverride(experimentName: "exp_test_ab", variant: 1)
		XCTAssertEqual(1, context.peekTreatment("exp_test_ab"))

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		XCTAssertEqual(JSON("large"), context.getVariableValue("banner.size"))
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		handler.publishEventReturnValue = Promise.value(())
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		XCTAssertEqual([1], handler.publishEventReceivedEvent?.exposures.map { $0.id })
	}

	// An exposure queued while the context was failed has no experiment data. Recovery drops it and
	// the next read exposes the rebuilt assignment once, with the experiment's id and unit.
	func testExposureMadeWhileFailedIsReplacedByOneAttributedExposureAfterRecovery() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		context.setOverride(experimentName: "exp_test_ab", variant: 1)
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(JSON("large"), context.peekVariableValue("banner.size"))
		handler.publishEventReturnValue = Promise.value(())
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		let exposure = try XCTUnwrap(handler.publishEventReceivedEvent?.exposures.first)
		XCTAssertEqual(1, handler.publishEventReceivedEvent?.exposures.count)
		XCTAssertEqual(1, exposure.id)
		XCTAssertEqual("session_id", exposure.unit)
		XCTAssertEqual(1, exposure.variant)
	}

	// An explicit publish of the failed context discarded the exposure before recovery: the rebuilt
	// assignment is still exposed (and published) by the next read.
	func testExposureDiscardedWhileFailedIsExposedAfterRecovery() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		context.setOverride(experimentName: "exp_test_ab", variant: 1)
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		let discarded = expectation(description: "failed flush")
		_ = context.publish().done { discarded.fulfill() }
		wait(for: [discarded], timeout: 2)
		XCTAssertEqual(0, context.getPendingCount())

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	// A read of a non-overridden experiment while failed gives variant 0 without experiment data;
	// after recovery the user's real variant is exposed, not the failed-state one.
	func testRecoveryExposesTheRealVariantNotTheFailedStateOne() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		XCTAssertEqual(0, context.getTreatment("exp_test_ab"))

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		handler.publishEventReturnValue = Promise.value(())
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		let exposures = handler.publishEventReceivedEvent?.exposures ?? []
		XCTAssertEqual(1, exposures.count)
		XCTAssertEqual(1, exposures.first?.id)
		XCTAssertEqual(1, exposures.first?.variant)
		XCTAssertEqual(true, exposures.first?.assigned)
	}

	func testVariableReadDoesNotExposeAnAssignmentWithoutVariables() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		context.setOverride(experimentName: "exp_test_ab", variant: 7)

		XCTAssertNil(context.getVariableValue("banner.size"))
		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(7, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getPendingCount())
	}

	#if DEBUG
	// A publish that started while the first load was pending, then paused before draining while the
	// load failed and an exposure was made without experiment data: it discards that exposure instead
	// of sending it.
	func testFlushThatStartedBeforeTheLoadFailedDoesNotSendFailedStateExposures() throws {
		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		context.setOverride(experimentName: "exp_test_ab", variant: 1)
		context.track("goal", properties: nil)
		handler.publishEventReturnValue = Promise.value(())

		Context.setTestHook(.flushObservedNotFailed) {
			Context.setTestHook(.flushObservedNotFailed, nil)
			let failed = XCTestExpectation()
			_ = context.waitUntilReady().done { _ in failed.fulfill() }
			initialSeal.reject(ABSmartlyError("load failed"))
			XCTAssertEqual(.completed, XCTWaiter().wait(for: [failed], timeout: 2))
			XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		}
		defer { Context.setTestHook(.flushObservedNotFailed, nil) }

		let settled = expectation(description: "publish settles")
		_ = context.publish().ensure { settled.fulfill() }
		wait(for: [settled], timeout: 2)

		XCTAssertTrue(context.isFailed())
		XCTAssertEqual(0, handler.publishEventCallsCount)
		XCTAssertEqual(0, context.getPendingCount())
	}

	// A goal tracked while loading, where the load fails during the goal's logger callback: no
	// publish is scheduled (it would take the failed branch and discard the goal), so a later
	// successful refresh publishes it.
	func testGoalWhoseLoggerCallbackSeesTheLoadFailIsKeptForRecovery() throws {
		let (initial, initialSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), initial)
		logger.handleEventContextEventClosure = { ctx, event in
			guard case .goal = event else { return }
			let failed = XCTestExpectation()
			_ = ctx.waitUntilReady().done { _ in failed.fulfill() }
			initialSeal.reject(ABSmartlyError("load failed"))
			_ = XCTWaiter().wait(for: [failed], timeout: 2)
		}
		context.track("goal", properties: nil)
		XCTAssertTrue(context.isFailed())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(1, context.getPendingCount())

		logger.handleEventContextEventClosure = nil
		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)
		handler.publishEventReturnValue = Promise.value(())
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		XCTAssertEqual(["goal"], handler.publishEventReceivedEvent?.goals.map { $0.name })
	}

	func testFailedCloseSchedulesARetryOfTheRequeuedEvents() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		context.track("goal", properties: nil)
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)

		handler.publishEventReturnValue = Promise(error: ABSmartlyError("publish failed"))
		let failed = expectation(description: "close fails")
		_ = context.close().catch { _ in failed.fulfill() }
		wait(for: [failed], timeout: 2)
		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(2, scheduler.scheduleAfterExecuteCallsCount)

		handler.publishEventReturnValue = Promise.value(())
		let retry = try XCTUnwrap(scheduler.scheduleAfterExecuteReceivedArguments?.execute)
		retry()
		let sent = expectation(description: "retried")
		DispatchQueue.global().async {
			while context.getPendingCount() > 0 { usleep(1000) }
			sent.fulfill()
		}
		wait(for: [sent], timeout: 2)
		XCTAssertEqual(["goal"], handler.publishEventReceivedEvent?.goals.map { $0.name })
	}

	func testCloseCancelsThePendingAutomaticPublish() throws {
		let handle = ScheduledHandleMock()
		scheduler.scheduleAfterExecuteReturnValue = handle
		let context = makeContext(config(), Promise.value(try contextData()))
		context.track("goal", properties: nil)
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(0, handle.cancelCallsCount)

		handler.publishEventReturnValue = Promise.value(())
		let closed = expectation(description: "closed")
		_ = context.close().done { closed.fulfill() }
		XCTAssertGreaterThanOrEqual(handle.cancelCallsCount, 1)
		wait(for: [closed], timeout: 2)
		XCTAssertEqual(1, handler.publishEventCallsCount)
	}

	// An automatic publish that drains the queue while close() is deciding whether the context is
	// idle: close waits for it, and when it is cancelled (its batch re-queued) close reports failure
	// and leaves the context open for a retry, instead of reporting success.
	func testCloseDoesNotSucceedWhileAnAutomaticPublishMayRequeue() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		let (inFlight, inFlightSeal) = Promise<Void>.pending()
		handler.publishEventReturnValue = inFlight
		context.track("goal", properties: nil)
		let autoPublish = try XCTUnwrap(scheduler.scheduleAfterExecuteReceivedArguments?.execute)
		// close() has to see the queue non-empty so it waits; the timer then wins the drain.
		Context.setTestHook(.closeAwaitedInFlight) {
			Context.setTestHook(.closeAwaitedInFlight, nil)
			autoPublish()
		}
		defer { Context.setTestHook(.closeAwaitedInFlight, nil) }

		let closeSettled = expectation(description: "close settles")
		var closeSucceeded = false
		context.close().done { closeSucceeded = true }.ensure { closeSettled.fulfill() }.catch(policy: .allErrors) { _ in }
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { inFlightSeal.reject(PMKError.cancelled) }
		wait(for: [closeSettled], timeout: 3)

		XCTAssertFalse(closeSucceeded)
		XCTAssertFalse(context.isClosed())
		XCTAssertEqual(1, context.getPendingCount())
	}

	// A publish handler that synchronously waits on another thread which reads the context: the
	// handler is called without contextLock held, so this does not deadlock.
	func testPublishHandlerThatReadsTheContextFromAnotherThreadDoesNotDeadlock() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		context.track("goal", properties: nil)
		handler.publishEventClosure = { _ in
			// A separate thread (DispatchQueue.sync could run the block on this thread, where the
			// recursive lock would be re-entered rather than contended).
			let readerDone = DispatchSemaphore(value: 0)
			Thread {
				_ = context.getUnit(unitType: "session_id")
				_ = context.getTreatment("exp_test_ab")
				context.setAttribute(name: "a", value: 1)
				readerDone.signal()
			}.start()
			XCTAssertEqual(.success, readerDone.wait(timeout: .now() + 2), "reader blocked: handler called under contextLock")
			return Promise.value(())
		}
		let published = expectation(description: "published")
		DispatchQueue.global().async {
			_ = context.publish().done { published.fulfill() }
		}
		wait(for: [published], timeout: 3)
		XCTAssertEqual(1, handler.publishEventCallsCount)
		XCTAssertEqual(JSON(1), context.getAttribute(name: "a"))
	}

	func testExposureClaimedHookRunsOnlyForANewClaim() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		var claims = 0
		Context.setTestHook(.exposureClaimed) { claims += 1 }
		defer { Context.setTestHook(.exposureClaimed, nil) }

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual("large", context.getVariableValue("banner.size")?.string)
		XCTAssertEqual(1, claims)
	}

	// A recovery that completes between a read's claim and its enqueue: the stale exposure is
	// dropped and the next read exposes the rebuilt assignment, attributed.
	func testExposureClaimedBeforeARecoveryIsDroppedAndReExposed() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		context.setOverride(experimentName: "exp_test_ab", variant: 1)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		Context.setTestHook(.exposureClaimed) {
			Context.setTestHook(.exposureClaimed, nil)
			let refreshed = XCTestExpectation()
			_ = context.refresh().done { refreshed.fulfill() }
			XCTAssertEqual(.completed, XCTWaiter().wait(for: [refreshed], timeout: 2))
		}
		defer { Context.setTestHook(.exposureClaimed, nil) }

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		handler.publishEventReturnValue = Promise.value(())
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		let exposures = handler.publishEventReceivedEvent?.exposures ?? []
		XCTAssertEqual([1], exposures.map { $0.id })
		XCTAssertEqual(["session_id"], exposures.map { $0.unit })
	}
	#endif

	// Reads and exposures from other threads while a refresh recovers a failed context: under
	// ThreadSanitizer (CI) this checks the recovery's data publication and the exposure claim.
	func testReadsDuringRecoveryAreRaceFree() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		context.setOverride(experimentName: "exp_test_ab", variant: 1)
		provider.getContextDataReturnValue = Promise.value(try contextData())
		handler.publishEventReturnValue = Promise.value(())

		let done = expectation(description: "readers done")
		done.expectedFulfillmentCount = 4
		for _ in 0..<4 {
			DispatchQueue.global().async {
				for _ in 0..<200 {
					_ = context.getTreatment("exp_test_ab")
					_ = context.getVariableValue("banner.size")
					_ = context.peekVariableValue("button.color")
				}
				done.fulfill()
			}
		}
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [done, refreshed], timeout: 10)

		XCTAssertEqual(JSON("large"), context.getVariableValue("banner.size"))
		let published = expectation(description: "published")
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		// An array, not a set: exactly one exposure, attributed to the experiment.
		let ids = handler.publishEventReceivedInvocations.flatMap { $0.exposures.filter { $0.name == "exp_test_ab" }.map { $0.id } }
		XCTAssertEqual([1], ids)
	}

	// Failed close does not itself restart refresh; no refresh is in flight in this scenario.
	func testFailedCloseDoesNotRestartRefreshTimer() throws {
		let cfg = config()
		cfg.refreshInterval = 10
		let context = makeContext(cfg, Promise.value(try contextData()))
		XCTAssertEqual(1, scheduler.scheduleWithFixedDelayAfterRepeatingExecuteCallsCount)
		handler.publishEventReturnValue = Promise(error: ABSmartlyError("publish failed"))
		context.track("goal", properties: nil)
		let failed = expectation(description: "close failed")
		_ = context.close().catch { _ in failed.fulfill() }
		wait(for: [failed], timeout: 2)
		XCTAssertFalse(context.isClosed())
		XCTAssertEqual(1, scheduler.scheduleWithFixedDelayAfterRepeatingExecuteCallsCount)
	}

	// A refresh that completes while close() is publishing does not re-arm the refresh timer,
	// whether the close then fails or succeeds.
	func testRefreshCompletingDuringCloseDoesNotRestartRefreshTimer() throws {
		for closeSucceeds in [false, true] {
			let cfg = config()
			cfg.refreshInterval = 10
			scheduler = SchedulerMock()
			scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
			scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
			handler = ContextEventHandlerMock()
			provider = ContextDataProviderMock()
			let context = makeContext(cfg, Promise.value(try contextData()))
			XCTAssertEqual(1, scheduler.scheduleWithFixedDelayAfterRepeatingExecuteCallsCount)

			let (refresh, refreshSeal) = Promise<ContextData>.pending()
			provider.getContextDataReturnValue = refresh
			let refreshed = expectation(description: "refreshed")
			_ = context.refresh().done { refreshed.fulfill() }

			let (publish, publishSeal) = Promise<Void>.pending()
			let publishing = expectation(description: "final publish started")
			handler.publishEventClosure = { _ in
				publishing.fulfill()
				return publish
			}
			context.track("goal", properties: nil)
			let settled = expectation(description: "close settled")
			_ = context.close().ensure { settled.fulfill() }
			wait(for: [publishing], timeout: 2)
			XCTAssertTrue(context.isClosing())

			refreshSeal.fulfill(try contextData())
			wait(for: [refreshed], timeout: 2)
			if closeSucceeds {
				publishSeal.fulfill(())
			} else {
				publishSeal.reject(ABSmartlyError("publish failed"))
			}
			wait(for: [settled], timeout: 2)
			handler.publishEventClosure = nil

			XCTAssertEqual(closeSucceeds, context.isClosed())
			XCTAssertEqual(1, scheduler.scheduleWithFixedDelayAfterRepeatingExecuteCallsCount)
		}
	}

	// Label-free references compiled against 1.4.0 (one overload of each) still resolve to the
	// 1.4.0 declarations; the overloads added since are disfavoured.
	func testLabelFreeReferencesResolveToThe140Declarations() throws {
		let context = makeContext(ContextConfig(), Promise.value(try contextData()))
		let setUnit = context.setUnit
		setUnit("session_id", "123")
		XCTAssertEqual("123", context.getUnit(unitType: "session_id"))
		let staticSetUnit = Context.setUnit
		staticSetUnit(context)("user_id", "456")
		XCTAssertEqual("456", context.getUnit(unitType: "user_id"))
		let customFieldKeys = context.getCustomFieldKeys
		XCTAssertEqual(context.getCustomFieldKeys(), customFieldKeys())
	}

	// An untyped reference compiled against 1.4.0 (String only) and must still resolve to the
	// String overload; the numeric overloads are disfavoured. A regression fails to compile.
	func testUntypedSetUnitReferenceResolvesToTheStringOverload() throws {
		let context = makeContext(ContextConfig(), Promise.value(try contextData()))
		let setUnit = context.setUnit(unitType:uid:)
		setUnit("session_id", "123")
		XCTAssertEqual("123", context.getUnit(unitType: "session_id"))
	}

	// A goal tracked while loading, drained by close() and re-queued when the final publish fails
	// after the load failed: neither the failed close nor a goal tracked afterwards schedules an
	// automatic publish (it would discard the queue on the failed context); a recovering refresh
	// schedules one and both goals are published.
	func testFailedCloseOfAFailedContextKeepsItsGoalsForRecovery() throws {
		let (load, loadSeal) = Promise<ContextData>.pending()
		let context = makeContext(config(), load)
		context.track("goal", properties: nil)
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)

		let (publish, publishSeal) = Promise<Void>.pending()
		let drained = expectation(description: "final publish started")
		handler.publishEventClosure = { _ in
			drained.fulfill()
			return publish
		}
		let failed = expectation(description: "close fails")
		_ = context.close().catch { _ in failed.fulfill() }
		wait(for: [drained], timeout: 2)
		handler.publishEventClosure = nil

		loadSeal.reject(ABSmartlyError("load failed"))
		let settled = expectation(description: "load failed")
		DispatchQueue.global().async {
			while !context.isFailed() { usleep(1000) }
			settled.fulfill()
		}
		wait(for: [settled], timeout: 2)
		publishSeal.reject(ABSmartlyError("publish failed"))
		wait(for: [failed], timeout: 2)

		XCTAssertEqual(1, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)

		// Tracking on the failed context schedules nothing either.
		context.track("goal2", properties: nil)
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)

		handler.publishEventReturnValue = Promise.value(())
		let retry = try XCTUnwrap(scheduler.scheduleAfterExecuteReceivedArguments?.execute)
		retry()
		let sent = expectation(description: "published")
		DispatchQueue.global().async {
			while context.getPendingCount() > 0 { usleep(1000) }
			sent.fulfill()
		}
		wait(for: [sent], timeout: 2)
		XCTAssertEqual(2, handler.publishEventCallsCount)
		XCTAssertEqual(["goal", "goal2"], handler.publishEventReceivedEvent?.goals.map { $0.name })
	}

	// Goals tracked on a failed context schedule no automatic publish (its flush would discard the
	// queue): they survive until a refresh recovers the context, which schedules their publish.
	func testGoalTrackedOnAFailedContextKeepsTheQueueForRecovery() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		XCTAssertTrue(context.isFailed())

		context.track("goal1", properties: nil)
		context.track("goal2", properties: nil)
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(0, scheduler.scheduleAfterExecuteCallsCount)

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = expectation(description: "refreshed")
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 2)
		XCTAssertEqual(2, context.getPendingCount())
		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)

		handler.publishEventReturnValue = Promise.value(())
		let publish = try XCTUnwrap(scheduler.scheduleAfterExecuteReceivedArguments?.execute)
		publish()
		let sent = expectation(description: "published")
		DispatchQueue.global().async {
			while context.getPendingCount() > 0 { usleep(1000) }
			sent.fulfill()
		}
		wait(for: [sent], timeout: 2)
		XCTAssertEqual(["goal1", "goal2"], handler.publishEventReceivedEvent?.goals.map { $0.name })
	}

	func testRefreshOnFailedContextFetchesAgain() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		XCTAssertTrue(context.isFailed())

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = XCTestExpectation()
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 1.0)

		XCTAssertEqual(1, provider.getContextDataCallsCount)
		XCTAssertNotNil(context.getContextData())
	}

	#if DEBUG
	// A read that claimed an exposure just before close() started does not queue it; the claim is
	// released, so after the final publish fails and the context reopens, the next read exposes it.
	func testExposureDroppedByAClosingContextIsExposedAfterAFailedClose() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		context.track("goal1", properties: nil)
		// The final publish stays pending until the first read has returned, so the context is still
		// closing when that read reaches the queue.
		let (finalPublish, finalPublishSeal) = Promise<Void>.pending()
		handler.publishEventReturnValue = finalPublish

		let closeFailed = XCTestExpectation(description: "close failed")
		Context.setTestHook(.exposureClaimed) {
			Context.setTestHook(.exposureClaimed, nil)
			_ = context.close().catch { _ in closeFailed.fulfill() }
		}
		defer { Context.setTestHook(.exposureClaimed, nil) }

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertTrue(context.isClosing())
		finalPublishSeal.reject(ABSmartlyError("publish failed"))
		wait(for: [closeFailed], timeout: 2)
		XCTAssertFalse(context.isClosed())
		XCTAssertEqual(1, context.getPendingCount())  // the re-queued goal only

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		XCTAssertEqual(2, context.getPendingCount())
		handler.publishEventReturnValue = Promise.value(())
		let published = XCTestExpectation()
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)
		XCTAssertEqual(["exp_test_ab"], handler.publishEventReceivedEvent?.exposures.map { $0.name })
	}

	// A flush that saw the context failed, then lost the race to a successful refresh, publishes the
	// events queued after recovery instead of discarding them.
	func testFlushThatSawFailedStateKeepsEventsQueuedAfterRecovery() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		XCTAssertTrue(context.isFailed())
		provider.getContextDataReturnValue = Promise.value(try contextData())
		handler.publishEventReturnValue = Promise.value(())

		Context.setTestHook(.flushObservedFailed) {
			Context.setTestHook(.flushObservedFailed, nil)
			let refreshed = XCTestExpectation()
			_ = context.refresh().done { refreshed.fulfill() }
			_ = XCTWaiter().wait(for: [refreshed], timeout: 2)
			context.track("after-recovery", properties: nil)
		}
		defer { Context.setTestHook(.flushObservedFailed, nil) }

		let published = XCTestExpectation()
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 2)

		XCTAssertEqual(["after-recovery"], handler.publishEventReceivedEvent?.goals.map { $0.name })
		XCTAssertEqual(0, context.getPendingCount())
	}

	#endif

	func testSuccessfulRefreshRecoversAFailedContext() throws {
		let context = makeContext(config(), Promise(error: ABSmartlyError("load failed")))
		XCTAssertTrue(context.isFailed())

		provider.getContextDataReturnValue = Promise.value(try contextData())
		let refreshed = XCTestExpectation()
		_ = context.refresh().done { refreshed.fulfill() }
		wait(for: [refreshed], timeout: 1.0)
		XCTAssertFalse(context.isFailed())
		XCTAssertNil(context.readyError())

		XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
		handler.publishEventReturnValue = Promise.value(())
		let published = XCTestExpectation()
		_ = context.publish().done { published.fulfill() }
		wait(for: [published], timeout: 1.0)
		XCTAssertEqual(["exp_test_ab"], handler.publishEventReceivedEvent?.exposures.map { $0.name })
	}

	func testNegativePublishDelaySchedulesPublishAsBefore() throws {
		let config = self.config()
		config.publishDelay = -1
		let context = makeContext(config, Promise.value(try contextData()))

		context.track("goal1", properties: nil)

		XCTAssertEqual(1, scheduler.scheduleAfterExecuteCallsCount)
		XCTAssertEqual(-1, scheduler.scheduleAfterExecuteReceivedArguments?.after)
	}

	func testCustomFieldValuesCoercion() throws {
		let json = """
			{"experiments": [{"id": 1, "name": "exp", "customFieldValues": [
				{"name": "upper", "type": "boolean", "value": "TRUE"},
				{"name": "no", "type": "boolean", "value": "false"},
				{"name": "array", "type": "json", "value": "[1, 2]"},
				{"name": "scalar", "type": "json", "value": "5"},
				{"name": "string", "type": "json", "value": "\\"hi\\""},
				{"name": "flag", "type": "json", "value": "true"},
				{"name": "null", "type": "json", "value": "null"},
				{"name": "invalid", "type": "json", "value": "{not json"},
				{"name": "nestedArray", "type": "json", "value": " [{\\"a\\": [1]}] "}
			]}]}
			"""
		let data = try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
		let context = makeContext(config(), Promise.value(data))

		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp", key: "upper"))
		XCTAssertEqual(false, context.getCustomFieldValue(experimentName: "exp", key: "no") as? Bool)
		XCTAssertEqual(JSON([1, 2]), context.getCustomFieldValue(experimentName: "exp", key: "array") as? JSON)
		XCTAssertEqual(JSON(5), context.getCustomFieldValue(experimentName: "exp", key: "scalar") as? JSON)
		XCTAssertEqual(JSON("hi"), context.getCustomFieldValue(experimentName: "exp", key: "string") as? JSON)
		XCTAssertEqual(JSON(true), context.getCustomFieldValue(experimentName: "exp", key: "flag") as? JSON)
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp", key: "null"))
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp", key: "invalid"))
		XCTAssertEqual(JSON([["a": [1]]]), context.getCustomFieldValue(experimentName: "exp", key: "nestedArray") as? JSON)
		XCTAssertEqual("json", context.getCustomFieldValueType(experimentName: "exp", key: "array"))
	}

	func testInvalidJsonCustomFieldIsLoggedByName() throws {
		let json = """
			{"experiments": [{"id": 1, "name": "exp", "customFieldValues": [
				{"name": "broken", "type": "json", "value": "{not json"},
				{"name": "empty", "type": "json", "value": "null"},
				{"name": "valid", "type": "json", "value": "{\\"a\\": 1}"}
			]}]}
			"""
		let data = try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
		var errors: [String] = []
		Logger.errorObserver = { errors.append($0) }
		defer { Logger.errorObserver = nil }

		_ = makeContext(config(), Promise.value(data))

		XCTAssertTrue(errors.contains("Invalid JSON in custom field 'broken' of experiment 'exp'."), "\(errors)")
		XCTAssertFalse(errors.contains { $0.contains("'empty'") || $0.contains("'valid'") })
	}

	func testJsonCustomFieldsCallTheParserOnlyForObjectsAndInvalidJSON() throws {
		final class RecordingParser: VariableParser {
			var configs: [String] = []
			func parse(experimentName: String, config: String) -> [String: JSON]? {
				configs.append(config)
				return DefaultVariableParser().parse(experimentName: experimentName, config: config)
			}
		}
		let json = """
			{"experiments": [{"id": 1, "name": "exp", "customFieldValues": [
				{"name": "object", "type": "json", "value": "{\\"a\\": 1}"},
				{"name": "array", "type": "json", "value": "[1]"},
				{"name": "null", "type": "json", "value": "null"},
				{"name": "invalid", "type": "json", "value": "{not json"}
			]}]}
			"""
		let data = try JSONDecoder().decode(ContextData.self, from: Data(json.utf8))
		let recording = RecordingParser()
		let context = Context(
			config: config(), clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: recording, matcher: AudienceMatcher(), promise: Promise.value(data))

		XCTAssertEqual(["{\"a\": 1}", "{not json"], recording.configs.sorted())
		XCTAssertEqual(["a": JSON(1)], context.getCustomFieldValue(experimentName: "exp", key: "object") as? [String: JSON])
		XCTAssertNil(context.getCustomFieldValue(experimentName: "exp", key: "null"))
	}

	func testCustomFieldReadsAfterCloseLogNoError() throws {
		let context = makeContext(config(), Promise.value(try contextData()))
		let closed = XCTestExpectation()
		_ = context.close().done { closed.fulfill() }
		wait(for: [closed], timeout: 1.0)
		logger.handleEventContextEventReceivedInvocations = []

		XCTAssertEqual("string", context.getCustomFieldValueType(experimentName: "exp_test_ab", key: "country"))
		XCTAssertNotNil(context.getCustomFieldValue(experimentName: "exp_test_ab", key: "country"))
		XCTAssertFalse(context.getCustomFieldKeys(experimentName: "exp_test_ab").isEmpty)
		XCTAssertFalse(context.getCustomFieldKeys().isEmpty)
		let errors = logger.handleEventContextEventReceivedInvocations.filter {
			if case .error = $0.event { return true }
			return false
		}
		XCTAssertEqual(0, errors.count)
	}

	func testV140NamesAreTheRealTypes() throws {
		// v1.4.0 consumers' code names these types; the cross-SDK spellings are aliases of them.
		let client = ClientMock()
		let config = ABSmartlyConfig(
			contextDataProvider: nil, contextEventHandler: DefaultContextEventHandler(client: client),
			contextEventLogger: nil, variableParser: nil, scheduler: nil, client: client)
		XCTAssertTrue(config.contextPublisher is DefaultContextPublisher)
		let sdk: ABsmartlySDK = try ABSmartlySDK(config: config)
		XCTAssertEqual("\(type(of: sdk))", "ABSmartlySDK")
		XCTAssertEqual("\(ABsmartlyConfig.self)", "ABSmartlyConfig")
		XCTAssertEqual("\(DefaultContextPublisher.self)", "DefaultContextEventHandler")
		XCTAssertEqual("0", ClientConfig(apiKey: "k", application: "a", endpoint: "e", environment: "p").applicationVersion)
	}
}

// Holds a context weakly without a `weak var` local, which Swift 6.4 flags as never mutated while
// `weak let` does not compile before Swift 6.
private final class WeakContext {
	weak var value: Context?

	init(_ value: Context?) {
		self.value = value
	}
}
