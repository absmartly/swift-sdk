import Foundation
import XCTest

import ABSmartly

/// Formats SDK errors the way an app does, through the public API only (no `@testable`). On
/// Linux with Swift 6.0 and 6.1, `localizedDescription` used to crash for class-based errors.
final class PublicErrorFormattingTest: XCTestCase {
	func testLocalizedDescriptionOfThrownSDKError() {
		XCTAssertThrowsError(
			try ABsmartlySDK(
				endpoint: "https://test.absmartly.io/v1",
				apiKey: "",
				application: "test-app",
				environment: "test"
			)
		) { error in
			XCTAssertEqual(error.localizedDescription, "Missing APIKey configuration")
			XCTAssertEqual((error as? ABSmartlyError)?.errorMessage, "Missing APIKey configuration")
		}
	}

	func testLocalizedDescriptionOfABSmartlyError() {
		let error: Error = ABSmartlyError("Something failed")
		XCTAssertEqual(error.localizedDescription, "Something failed")
		XCTAssertEqual((error as? LocalizedError)?.errorDescription, "Something failed")
		XCTAssertEqual(ABSmartlyError("Direct").localizedDescription, "Direct")
	}
}
