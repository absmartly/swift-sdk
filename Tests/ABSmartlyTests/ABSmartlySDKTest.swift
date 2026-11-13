import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class ABsmartlySDKTest: XCTestCase {
	var sdk: ABsmartlySDK?
	var client: ClientMock?
	var contextConfig = ContextConfig()

	func setUpSDK(block: ((ABsmartlyConfig) -> Void)? = nil) {
		contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "123456789")

		client = ClientMock()
		do {
			let sdkConfig = ABsmartlyConfig(client: client!)
			if let block = block {
				block(sdkConfig)
			}
			sdk = try ABsmartlySDK(config: sdkConfig)
		} catch {
			XCTFail(error.safeLocalizedDescription)
		}
	}

	func testThrowsWithInvalidConfig() {
		let config = ABsmartlyConfig()

		XCTAssertThrowsError(try ABsmartlySDK(config: config)) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing Client instance")
		}
	}

	func testCreateContext() throws {
		setUpSDK()

		guard let sdk = sdk, let client = client else { return }

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<ContextData>.pending()
		client.getContextDataReturnValue = promise

		_ = promise.done { data in
			expectation.fulfill()
		}

		let context = sdk.createContext(config: contextConfig)
		XCTAssertNotNil(context)
		XCTAssertFalse(context.isReady())
		XCTAssertEqual(1, client.getContextDataCallsCount)

		resolver.fulfill(ContextData())

		wait(for: [expectation], timeout: 1.0)
	}

	func testCreateContextWithData() throws {
		setUpSDK()

		guard let sdk = sdk, let client = client else { return }

		let context = sdk.createContextWithData(config: contextConfig, contextData: ContextData())
		XCTAssertNotNil(context)
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(0, client.getContextDataCallsCount)
	}

	// exp_test_ab with a strict audience and a 0/100 split, so a match gives variant 1 and a mismatch 0.
	func strictAudienceContextData(filter: String) throws -> ContextData {
		let audience = "{\"filter\":\(filter)}"
		let experiment: [String: Any] = [
			"id": 1, "name": "exp_test_ab", "iteration": 1, "unitType": "session_id", "seedHi": 3_603_515,
			"seedLo": 233_373_850, "split": [0.0, 1.0], "trafficSeedHi": 449_867_249, "trafficSeedLo": 455_443_629,
			"trafficSplit": [0.0, 1.0], "fullOnVariant": 0,
			"variants": [["name": "A", "config": NSNull()], ["name": "B", "config": "{}"]],
			"audienceStrict": true, "audience": audience,
		]
		let data = try JSONSerialization.data(withJSONObject: ["experiments": [experiment]])
		return try JSONDecoder().decode(ContextData.self, from: data)
	}

	// createContextWithData forwards the client's application/environment into the Context, so a
	// strict audience targeting the configured environment matches without the caller setting it.
	// Uses peek so no exposure is queued and the real DefaultScheduler never auto-publishes.
	func testCreateContextForwardsClientApplicationAndEnvironment() throws {
		setUpSDK()

		guard let sdk = sdk, let client = client else { return }

		client.getApplicationReturnValue = "website"
		client.getEnvironmentReturnValue = "production"

		let filter = "[{\"eq\":[{\"var\":\"environment\"},{\"value\":\"production\"}]}]"
		let contextData = try strictAudienceContextData(filter: filter)

		let context = sdk.createContextWithData(config: contextConfig, contextData: contextData)
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(1, context.peekTreatment("exp_test_ab"))

		// A staging target does not match the configured production environment.
		let stagingData = try strictAudienceContextData(
			filter: filter.replacingOccurrences(of: "production", with: "staging"))
		let stagingContext = sdk.createContextWithData(config: contextConfig, contextData: stagingData)
		XCTAssertEqual(0, stagingContext.peekTreatment("exp_test_ab"))
	}

	// A client configured with an application version does not inject it as `app_version`.
	func testCreateContextDoesNotEvaluateApplicationVersion() throws {
		let sdk = try ABsmartlySDK(
			endpoint: "https://test.absmartly.io/v1", apiKey: "test-api-key", application: "website",
			environment: "production", applicationVersion: "1.2.3")

		let contextData = try strictAudienceContextData(
			filter: "[{\"eq\":[{\"var\":\"app_version\"},{\"value\":\"1.2.3\"}]}]")

		let config = ContextConfig()
		config.setUnit(unitType: "session_id", uid: "123456789")
		let context = sdk.createContextWithData(config: config, contextData: contextData)
		XCTAssertEqual(0, context.peekTreatment("exp_test_ab"))

		// The same audience matches once the attribute is set explicitly.
		context.setAttribute(name: "app_version", value: "1.2.3")
		XCTAssertEqual(1, context.peekTreatment("exp_test_ab"))
	}

	func testGetContextData() {
		setUpSDK()

		guard let sdk = sdk, let client = client else { return }

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<ContextData>.pending()
		client.getContextDataReturnValue = promise

		_ = promise.done { data in
			expectation.fulfill()
		}

		let result = sdk.getContextData()
		XCTAssertNotNil(result)
		XCTAssertEqual(1, client.getContextDataCallsCount)
		resolver.fulfill(ContextData())

		wait(for: [expectation], timeout: 1.0)
	}

	func testCustomContextDataProvider() throws {
		let contextDataProvider = ContextDataProviderMock()
		setUpSDK { config in
			config.contextDataProvider = contextDataProvider
		}

		guard let sdk = sdk, let client = client else { return }

		do {
			let expectation = XCTestExpectation()

			let (promise, resolver) = Promise<ContextData>.pending()
			contextDataProvider.getContextDataReturnValue = promise

			_ = promise.done { data in
				expectation.fulfill()
			}

			let result = sdk.getContextData()
			XCTAssertNotNil(result)
			XCTAssertEqual(1, contextDataProvider.getContextDataCallsCount)
			XCTAssertEqual(0, client.getContextDataCallsCount)
			resolver.fulfill(ContextData())

			wait(for: [expectation], timeout: 1.0)
		}

		do {
			let expectation = XCTestExpectation()

			let (promise, resolver) = Promise<ContextData>.pending()
			contextDataProvider.getContextDataReturnValue = promise

			_ = promise.done { data in
				expectation.fulfill()
			}

			let result = sdk.createContext(config: contextConfig)
			XCTAssertNotNil(result)
			XCTAssertEqual(2, contextDataProvider.getContextDataCallsCount)
			XCTAssertEqual(0, client.getContextDataCallsCount)
			resolver.fulfill(ContextData())

			wait(for: [expectation], timeout: 1.0)
		}
	}

	func testClose() {
		setUpSDK()

		guard let sdk = sdk, let client = client else { return }

		let expectation = XCTestExpectation()

		let (promise, resolver) = Promise<Void>.pending()
		client.closeReturnValue = promise

		_ = promise.done {
			expectation.fulfill()
		}

		let result = sdk.close()

		XCTAssertNotNil(result)
		XCTAssertEqual(1, client.closeCallsCount)
		resolver.fulfill(())

		wait(for: [expectation], timeout: 1.0)
	}

	func testNamedParameterInitialization() throws {
		let sdk = try ABsmartlySDK(
			endpoint: "https://test.absmartly.io/v1",
			apiKey: "test-api-key",
			application: "test-app",
			environment: "test"
		)

		XCTAssertNotNil(sdk)

		let contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "test123")
		let context = sdk.createContext(config: contextConfig)
		XCTAssertNotNil(context)
	}

	func testNamedParameterInitializationWithOptionalParameters() throws {
		let sdk = try ABsmartlySDK(
			endpoint: "https://test.absmartly.io/v1",
			apiKey: "test-api-key",
			application: "test-app",
			environment: "production",
			applicationVersion: "1.2.3",
			timeout: 5.0,
			retries: 3
		)

		XCTAssertNotNil(sdk)

		let contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "user_id", uid: "user456")
		let context = sdk.createContext(config: contextConfig)
		XCTAssertNotNil(context)
	}

	func testNamedParameterInitializationThrowsWithEmptyEndpoint() {
		XCTAssertThrowsError(
			try ABsmartlySDK(
				endpoint: "",
				apiKey: "test-api-key",
				application: "test-app",
				environment: "test"
			)
		) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing Endpoint configuration")
		}
	}

	func testNamedParameterInitializationThrowsWithEmptyApiKey() {
		XCTAssertThrowsError(
			try ABsmartlySDK(
				endpoint: "https://test.absmartly.io/v1",
				apiKey: "",
				application: "test-app",
				environment: "test"
			)
		) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing APIKey configuration")
		}
	}

	func testNamedParameterInitializationThrowsWithEmptyApplication() {
		XCTAssertThrowsError(
			try ABsmartlySDK(
				endpoint: "https://test.absmartly.io/v1",
				apiKey: "test-api-key",
				application: "",
				environment: "test"
			)
		) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing Application configuration")
		}
	}

	func testNamedParameterInitializationThrowsWithEmptyEnvironment() {
		XCTAssertThrowsError(
			try ABsmartlySDK(
				endpoint: "https://test.absmartly.io/v1",
				apiKey: "test-api-key",
				application: "test-app",
				environment: ""
			)
		) { error in
			XCTAssertEqual(error.safeLocalizedDescription, "Missing Environment configuration")
		}
	}

	func testNamedParameterInitializationWithCustomEventLogger() throws {
		let customLogger = ContextEventLoggerMock()

		let sdk = try ABsmartlySDK(
			endpoint: "https://test.absmartly.io/v1",
			apiKey: "test-api-key",
			application: "test-app",
			environment: "test",
			contextEventLogger: customLogger
		)

		XCTAssertNotNil(sdk)
	}

	func testNamedParameterInitializationPassesEventLoggerToContexts() throws {
		let customLogger = ContextEventLoggerMock()
		let contextDataProvider = ContextDataProviderMock()
		contextDataProvider.getContextDataReturnValue = Promise<ContextData>.value(ContextData())

		let sdk = try ABsmartlySDK(
			endpoint: "https://test.absmartly.io/v1",
			apiKey: "test-api-key",
			application: "test-app",
			environment: "test",
			contextEventLogger: customLogger,
			contextDataProvider: contextDataProvider
		)

		let ready = XCTestExpectation(description: "ready")
		customLogger.handleEventContextEventClosure = { _, event in
			if case .ready = event {
				ready.fulfill()
			}
		}

		let contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "test123")
		_ = sdk.createContext(config: contextConfig)

		wait(for: [ready], timeout: 1.0)
	}

	func testNamedParameterInitializationPassesEventLoggerToContextsWithData() throws {
		let customLogger = ContextEventLoggerMock()

		let sdk = try ABsmartlySDK(
			endpoint: "https://test.absmartly.io/v1",
			apiKey: "test-api-key",
			application: "test-app",
			environment: "test",
			contextEventLogger: customLogger
		)

		let ready = XCTestExpectation(description: "ready")
		customLogger.handleEventContextEventClosure = { _, event in
			if case .ready = event {
				ready.fulfill()
			}
		}

		let contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "test123")
		_ = sdk.createContextWithData(config: contextConfig, contextData: ContextData())

		wait(for: [ready], timeout: 1.0)
	}

	func testContextConfigEventLoggerOverridesSDKEventLogger() throws {
		let sdkLogger = ContextEventLoggerMock()
		let contextLogger = ContextEventLoggerMock()

		let sdk = try ABsmartlySDK(
			endpoint: "https://test.absmartly.io/v1",
			apiKey: "test-api-key",
			application: "test-app",
			environment: "test",
			contextEventLogger: sdkLogger
		)

		let ready = XCTestExpectation(description: "ready")
		contextLogger.handleEventContextEventClosure = { _, event in
			if case .ready = event {
				ready.fulfill()
			}
		}

		let contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "test123")
		contextConfig.eventLogger = contextLogger
		_ = sdk.createContextWithData(config: contextConfig, contextData: ContextData())

		wait(for: [ready], timeout: 1.0)
		XCTAssertEqual(0, sdkLogger.handleEventContextEventCallsCount)
	}

	func testBackwardsCompatibility() throws {
		let clientConfig = ClientConfig(
			apiKey: "test-key",
			application: "test-app",
			endpoint: "https://test.absmartly.io/v1",
			environment: "test"
		)

		let client = try DefaultClient(config: clientConfig)
		let sdkConfig = ABsmartlyConfig(client: client)
		let sdk = try ABsmartlySDK(config: sdkConfig)

		XCTAssertNotNil(sdk)

		let contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "test123")
		let context = sdk.createContext(config: contextConfig)
		XCTAssertNotNil(context)
	}
}
