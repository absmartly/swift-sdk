import Foundation
import XCTest

@testable import ABSmartly

/// Pins the comparison semantics of the vendored SwiftyJSON `JSON`, whose NSNumber
/// operators were rewritten as file-private functions so the file compiles on Linux.
final class JSONComparisonTest: XCTestCase {
	func testNumberEquality() {
		XCTAssertTrue(JSON(1) == JSON(1))
		XCTAssertTrue(JSON(2) == JSON(2.0))
		XCTAssertTrue(JSON(9_234_567_890) == JSON(9_234_567_890))
		XCTAssertTrue(JSON(-1.5) == JSON(-1.5))
		XCTAssertFalse(JSON(1) == JSON(2))
		XCTAssertFalse(JSON(1) == JSON(1.5))
		XCTAssertTrue(JSON(1) != JSON(2))
		XCTAssertFalse(JSON(1) != JSON(1.0))
	}

	func testNumberOrdering() {
		XCTAssertTrue(JSON(1) < JSON(2))
		XCTAssertTrue(JSON(1.5) < JSON(2))
		XCTAssertFalse(JSON(2) < JSON(2.0))
		XCTAssertFalse(JSON(3) < JSON(2))
		XCTAssertTrue(JSON(-1) < JSON(0))

		XCTAssertTrue(JSON(3) > JSON(2.5))
		XCTAssertFalse(JSON(2) > JSON(2))
		XCTAssertFalse(JSON(1) > JSON(2))

		XCTAssertTrue(JSON(2) <= JSON(2.0))
		XCTAssertTrue(JSON(1) <= JSON(2))
		XCTAssertFalse(JSON(3) <= JSON(2))

		XCTAssertTrue(JSON(2) >= JSON(2.0))
		XCTAssertTrue(JSON(3) >= JSON(2))
		XCTAssertFalse(JSON(1) >= JSON(2))
	}

	func testParsedValuesCompareLikeLiterals() {
		// Wrapped in an array: whether JSONSerialization accepts a bare top-level scalar
		// differs between platforms.
		let parsed = JSON(parseJSON: "[1, 2.5, true, false, \"a\"]")
		XCTAssertEqual(parsed[0].type, .number)
		XCTAssertEqual(parsed[1].type, .number)
		XCTAssertEqual(parsed[2].type, .bool)
		XCTAssertEqual(parsed[3].type, .bool)
		XCTAssertTrue(parsed[0] == JSON(1))
		XCTAssertTrue(parsed[0] < parsed[1])
		XCTAssertTrue(parsed[1] > JSON(2))
		XCTAssertTrue(parsed[2] == JSON(true))
		XCTAssertFalse(parsed[2] == parsed[0])
		XCTAssertFalse(parsed[3] == JSON(0))
		XCTAssertTrue(parsed[4] == JSON("a"))
	}

	func testBoolIsNotANumber() {
		XCTAssertEqual(JSON(true).type, .bool)
		XCTAssertEqual(JSON(false).type, .bool)
		XCTAssertEqual(JSON(1).type, .number)
		XCTAssertEqual(JSON(0).type, .number)

		XCTAssertFalse(JSON(true) == JSON(1))
		XCTAssertFalse(JSON(1) == JSON(true))
		XCTAssertFalse(JSON(false) == JSON(0))
		XCTAssertTrue(JSON(true) != JSON(1))

		XCTAssertFalse(JSON(true) < JSON(2))
		XCTAssertFalse(JSON(0) < JSON(true))
		XCTAssertFalse(JSON(true) > JSON(0))
		XCTAssertFalse(JSON(1) <= JSON(true))
		XCTAssertFalse(JSON(true) >= JSON(1))
	}

	func testBoolComparisons() {
		XCTAssertTrue(JSON(true) == JSON(true))
		XCTAssertFalse(JSON(true) == JSON(false))

		// Bools are unordered: only <= and >= hold, and only for equal values.
		XCTAssertFalse(JSON(false) < JSON(true))
		XCTAssertFalse(JSON(true) > JSON(false))
		XCTAssertTrue(JSON(true) <= JSON(true))
		XCTAssertTrue(JSON(false) >= JSON(false))
		XCTAssertFalse(JSON(false) <= JSON(true))
		XCTAssertFalse(JSON(true) >= JSON(false))
	}

	func testStringComparisons() {
		XCTAssertTrue(JSON("abc") == JSON("abc"))
		XCTAssertFalse(JSON("abc") == JSON("abd"))
		XCTAssertTrue(JSON("abc") < JSON("abd"))
		XCTAssertTrue(JSON("b") > JSON("a"))
		XCTAssertTrue(JSON("a") <= JSON("a"))
		XCTAssertTrue(JSON("a") >= JSON("a"))
		XCTAssertFalse(JSON("b") <= JSON("a"))

		XCTAssertFalse(JSON("1") == JSON(1))
		XCTAssertFalse(JSON("1") < JSON(2))
		XCTAssertFalse(JSON("true") == JSON(true))
	}

	func testNullAndContainers() {
		XCTAssertTrue(JSON.null == JSON(NSNull()))
		XCTAssertFalse(JSON.null == JSON(0))
		XCTAssertTrue(JSON([1, "a", true]) == JSON([1, "a", true]))
		XCTAssertFalse(JSON([1, 2]) == JSON([2, 1]))
		XCTAssertTrue(JSON(["a": 1, "b": [true]]) == JSON(["b": [true], "a": 1]))
		XCTAssertFalse(JSON(["a": 1]) == JSON(["a": 2]))
	}
}
