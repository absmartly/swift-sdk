import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class ABSmartlySDKTest: XCTestCase {
	var sdk: ABSmartlySDK?
	var client: ClientMock?
	var contextConfig = ContextConfig()

	func setUpSDK(block: ((ABSmartlyConfig) -> Void)? = nil) {
		contextConfig = ContextConfig()
		contextConfig.setUnit(unitType: "session_id", uid: "123456789")

		client = ClientMock()
		do {
			let sdkConfig = ABSmartlyConfig(client: client!)
			if let block = block {
				block(sdkConfig)
			}
			sdk = try ABSmartlySDK(config: sdkConfig)
		} catch {
			XCTFail(error.localizedDescription)
		}
	}

	func testThrowsWithInvalidConfig() {
		let config = ABSmartlyConfig()

		XCTAssertThrowsError(try ABSmartlySDK(config: config)) { error in
			XCTAssertEqual(error.localizedDescription, "Missing Client instance")
		}
	}

	func testCreateContext() {
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

	func testCreateContextWithData() {
		setUpSDK()

		guard let sdk = sdk, let client = client else { return }

		let context = sdk.createContextWithData(config: contextConfig, contextData: ContextData())
		XCTAssertNotNil(context)
		XCTAssertTrue(context.isReady())
		XCTAssertEqual(0, client.getContextDataCallsCount)
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
}
