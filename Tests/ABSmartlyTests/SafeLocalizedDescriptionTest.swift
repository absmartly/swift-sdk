import Foundation
import XCTest

@testable import ABSmartly

/// An app's own class-based error, the kind that crashed `localizedDescription` on Linux with
/// Swift 6.0 and 6.1.
private final class AppClassError: LocalizedError {
	var errorDescription: String? { return "app error" }
}

private struct AppStructError: Error, CustomStringConvertible {
	var description: String { return "struct error" }
}

final class SafeLocalizedDescriptionTest: XCTestCase {
	func testClassBasedAppErrorIsDescribed() {
		let error: Error = AppClassError()
		XCTAssertEqual("app error", error.safeLocalizedDescription)
	}

	func testNSErrorAndStructErrorsUseLocalizedDescription() {
		let nsError: Error = NSError(domain: "d", code: 1, userInfo: [NSLocalizedDescriptionKey: "ns error"])
		XCTAssertEqual("ns error", nsError.safeLocalizedDescription)
		XCTAssertEqual(AppStructError().localizedDescription, AppStructError().safeLocalizedDescription)
	}
}
