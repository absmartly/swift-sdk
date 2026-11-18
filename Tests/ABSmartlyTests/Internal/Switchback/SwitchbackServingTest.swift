import Foundation
import XCTest

@testable import ABSmartly

final class SwitchbackServingTest: XCTestCase {
	func sources(_ entries: (String, String)...) -> [(unitType: String, path: SwitchbackAttributePath)] {
		return entries.map { ($0.0, SwitchbackAttributePath.parseSupported($0.1)!) }
	}

	// Port of java-sdk SwitchbackServingTest.sourceOrderDecidesWhateverTheUnitOrder.
	func testSourceOrderDecides() {
		let values: [String: JSON] = ["a": JSON("x"), "b": JSON("x")]
		let read: (SwitchbackAttributePath) -> JSON? = { values[$0.rootKey] }
		let forward = SwitchbackServing.resolve(
			sources: sources(("user_id", "a"), ("device_id", "b")), allowedValues: nil, hasUnit: { _ in true }, read: read)
		XCTAssertEqual(.eligible, forward.status)
		XCTAssertEqual("user_id", forward.unitType)
		XCTAssertEqual("x", forward.clusterKey)
		let backward = SwitchbackServing.resolve(
			sources: sources(("device_id", "b"), ("user_id", "a")), allowedValues: nil, hasUnit: { _ in true }, read: read)
		XCTAssertEqual("device_id", backward.unitType)
	}

	func testStatuses() {
		let s = sources(("user_id", "a"), ("device_id", "b"))
		func resolve(_ values: [String: JSON], allowed: [String]? = nil, units: Set<String> = ["user_id", "device_id"])
			-> SwitchbackServing
		{
			return SwitchbackServing.resolve(
				sources: s, allowedValues: allowed, hasUnit: { units.contains($0) }, read: { values[$0.rootKey] })
		}
		XCTAssertEqual(.absent, resolve(["a": JSON("x")], units: []).status)
		let none = resolve([:])
		XCTAssertEqual(.ineligible, none.status)
		XCTAssertEqual("user_id", none.unitType)
		XCTAssertEqual(.ineligible, resolve(["a": JSON("x"), "b": JSON("y")]).status)
		let skipped = resolve(["b": JSON("y")])
		XCTAssertEqual(.eligible, skipped.status)
		XCTAssertEqual("device_id", skipped.unitType)
		XCTAssertEqual(.ineligible, resolve(["a": JSON("x")], allowed: ["y"]).status)
		XCTAssertEqual(.eligible, resolve(["a": JSON("x")], allowed: ["y", "x"]).status)
		XCTAssertEqual(.eligible, resolve(["a": JSON("x")], allowed: []).status)
		// Only linked units present in the context take part.
		XCTAssertEqual(.eligible, resolve(["a": JSON("x"), "b": JSON("y")], units: ["device_id"]).status)
	}

	// Owner rule: a non-empty string as-is, a whole-number integer as base-10 text; every float (3.0
	// included), bool, object, array, empty string and null gives none.
	func testClusterKeyRule() throws {
		XCTAssertEqual("porto", SwitchbackServing.clusterKey(JSON("porto")))
		XCTAssertEqual("42", SwitchbackServing.clusterKey(JSON(42)))
		XCTAssertEqual("-7", SwitchbackServing.clusterKey(JSON(Int64(-7))))
		XCTAssertEqual("4000000002", SwitchbackServing.clusterKey(JSON(Int64(4_000_000_002))))
		XCTAssertEqual("9223372036854775807", SwitchbackServing.clusterKey(JSON(Int64.max)))
		XCTAssertEqual("18446744073709551615", SwitchbackServing.clusterKey(JSON(UInt64.max)))
		XCTAssertEqual("3", SwitchbackServing.clusterKey(JSON(Int8(3))))
		for value in [
			JSON(3.0), JSON(Float(2)), JSON(1.5), JSON(-0.0), JSON(true), JSON(false), JSON(""), JSON.null, JSON(["a": "b"]),
			JSON(["x"]),
		] {
			XCTAssertNil(SwitchbackServing.clusterKey(value), "\(value)")
		}
		XCTAssertNil(SwitchbackServing.clusterKey(nil))

		// Parsed from JSON text, as attributes from a payload or the wrapper arrive.
		let parsed = try JSON(data: Data("[3, 3.0, 3e0, -0, 30e-1, 4000000002, true, 1, 0]".utf8)).arrayValue
		XCTAssertEqual(
			["3", nil, nil, "0", nil, "4000000002", nil, "1", "0"], parsed.map { SwitchbackServing.clusterKey($0) })
	}
}
