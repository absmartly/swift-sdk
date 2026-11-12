// On Apple platforms `ABSmartly.JSON` must stay SwiftyJSON's `JSON` (as in v1.4.0 and earlier),
// so apps that import both modules can pass `SwiftyJSON.JSON` values to the SDK and keep its
// results in `SwiftyJSON.JSON` variables. Linux uses a vendored copy and has no SwiftyJSON.
#if canImport(SwiftyJSON)
	import ABSmartly
	import SwiftyJSON
	import XCTest

	final class SwiftyJSONCompatibilityTest: XCTestCase {
		func testJSONIsSwiftyJSONType() {
			XCTAssertTrue(ABSmartly.JSON.self == SwiftyJSON.JSON.self)
		}

		func testSwiftyJSONValuesConvertFreely() {
			let swifty: SwiftyJSON.JSON = ["a": 1, "b": "x"]
			let sdk: ABSmartly.JSON = swifty
			let back: SwiftyJSON.JSON = sdk
			XCTAssertEqual(back["a"].intValue, 1)
			XCTAssertEqual(back["b"].stringValue, "x")
		}

		// Never called: compiling it is the test. Uses only the public API (no @testable import).
		private func compilesAgainstPublicAPI(_ context: Context) {
			let value: SwiftyJSON.JSON = "premium"
			context.setAttribute(name: "plan", value: value)
			context.setAttributes(["plan": value] as [String: SwiftyJSON.JSON])
			context.setUnit(unitType: "user_id", value: SwiftyJSON.JSON("123"))
			context.track("purchase", properties: ["amount": SwiftyJSON.JSON(10)])
			let result: SwiftyJSON.JSON? = context.getVariableValue("color", defaultValue: SwiftyJSON.JSON("red"))
			let peeked: SwiftyJSON.JSON? = context.peekVariableValue("color", defaultValue: value)
			_ = (result, peeked)
		}
	}
#endif
