import XCTest

@testable import ABSmartly

final class ContextConfigTest: XCTestCase {

	func testSetUnit() {
		let config = ContextConfig()
		config.setUnit(unitType: "session_id", uid: "0ab1e23f4eee")

		XCTAssertEqual(config.units["session_id"], "0ab1e23f4eee")
	}

	func testSetUnits() {
		let units = ["session_id": "0ab1e23f4eee", "user_id": String(0xabcdef)]
		let config = ContextConfig()

		config.setUnits(units: units)
		XCTAssertEqual(config.units, units)
	}

	func testSetAttribute() {
		let config = ContextConfig()
		config.setAttribute(name: "user_agent", value: "Chrome")
		config.setAttribute(name: "age", value: 9)

		XCTAssertEqual(config.attributes["user_agent"]?.stringValue, "Chrome")
		XCTAssertEqual(config.attributes["age"]?.intValue, 9)
	}

	func testSetAttributes() {
		let attributes: [String: JSON] = ["user_agent": "Chrome", "age": 9]
		let config = ContextConfig()

		config.setAttributes(attributes: attributes)
		XCTAssertEqual(config.attributes["user_agent"]?.stringValue, "Chrome")
		XCTAssertEqual(config.attributes["age"]?.intValue, 9)
	}

	func testSetOverride() {
		let config = ContextConfig()
		config.setOverride(experimentName: "exp_test", variant: 2)

		XCTAssertEqual(config.overrides["exp_test"], 2)
	}

	func testSetOverrides() {
		let config = ContextConfig()
		let overrides = ["exp_test": 2, "exp_test_new": 1]

		config.setOverrides(overrides: overrides)
		XCTAssertEqual(config.overrides, overrides)
	}

	func testSetCustomAssignment() {
		let config = ContextConfig()
		config.setCustomAssignment(experimentName: "exp_test", variant: 2)

		XCTAssertEqual(config.cassignments["exp_test"], 2)
	}

	func testSetCustomAssignments() {
		let config = ContextConfig()
		let cassignments = ["exp_test": 2, "exp_test_new": 1]

		config.setCustomAssignments(assignments: cassignments)
		XCTAssertEqual(config.cassignments, cassignments)
	}

	func testSetPublishDelay() {
		let config = ContextConfig()
		config.publishDelay = 999

		XCTAssertEqual(config.publishDelay, 999)
	}

	// An untyped reference compiled against 1.4.0 (String only) and must still resolve to the
	// String overload; the numeric overloads are disfavoured. A regression fails to compile.
	func testUntypedSetUnitReferenceResolvesToTheStringOverload() {
		let config = ContextConfig()
		let setUnit = config.setUnit(unitType:uid:)
		setUnit("session_id", "123")
		XCTAssertEqual("123", config.unitValues["session_id"]?.string)
		config.setUnit(unitType: "n", uid: 5)
		XCTAssertEqual(JSON(5), config.unitValues["n"])
	}
}
