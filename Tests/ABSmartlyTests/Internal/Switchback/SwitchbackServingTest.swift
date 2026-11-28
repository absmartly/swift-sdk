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

	// java-sdk SwitchbackClusterKeys.normalize: a float never keys a cluster, even a whole one; the
	// decision is the NSNumber's storage type, never its value.
	func testClusterKeyRule() throws {
		XCTAssertEqual("porto", SwitchbackServing.clusterKey(JSON("porto")))
		XCTAssertEqual("3", SwitchbackServing.clusterKey(JSON("3")))
		XCTAssertEqual("3", SwitchbackServing.clusterKey(JSON(3)))
		XCTAssertEqual("42", SwitchbackServing.clusterKey(JSON(42)))
		XCTAssertEqual("-7", SwitchbackServing.clusterKey(JSON(Int64(-7))))
		XCTAssertEqual("0", SwitchbackServing.clusterKey(JSON(0)))
		XCTAssertEqual("4000000002", SwitchbackServing.clusterKey(JSON(Int64(4_000_000_002))))
		XCTAssertEqual("9223372036854775807", SwitchbackServing.clusterKey(JSON(Int64.max)))
		XCTAssertEqual("18446744073709551615", SwitchbackServing.clusterKey(JSON(UInt64.max)))
		XCTAssertEqual("3", SwitchbackServing.clusterKey(JSON(Int8(3))))
		XCTAssertEqual("3", SwitchbackServing.clusterKey(JSON(UInt16(3))))
		for value in [
			JSON(3.0), JSON(123_456_789.0), JSON(-0.0), JSON(0.0), JSON(Float(2)), JSON(1.5), JSON(1e20),
			JSON(true), JSON(false), JSON(""), JSON.null, JSON(["a": "b"]), JSON(["x"]),
		] {
			XCTAssertNil(SwitchbackServing.clusterKey(value), "\(value)")
		}
		XCTAssertNil(SwitchbackServing.clusterKey(nil))

		// A Decimal is not an integer type (java-sdk: a BigDecimal gives none), and it cannot tell "42"
		// from "42.0", so none keys.
		for decimal in ["42", "42.000", "-7", "1e20", "4.5"] {
			XCTAssertNil(SwitchbackServing.clusterKey(JSON(NSDecimalNumber(string: decimal))), decimal)
		}
		XCTAssertNil(SwitchbackServing.clusterKey(JSON(Decimal(-7))))
		XCTAssertNil(SwitchbackServing.clusterKey(JSON(NSDecimalNumber.notANumber)))

		// Parsed from JSON text, as attributes from a payload or the wrapper arrive: the token decides.
		let text = "[3, 3.0, 123456789.0, 123456789, -0, -0.0, 3e0, 30e-1, 4000000002, 18446744073709551616, true, 1, 0]"
		let expected: [String?] = ["3", nil, nil, "123456789", "0", nil, nil, nil, "4000000002", nil, nil, "1", "0"]
		XCTAssertEqual(expected, try JSON(data: Data(text.utf8)).arrayValue.map { SwitchbackServing.clusterKey($0) })
		XCTAssertEqual(expected, JSON(parseJSON: text).arrayValue.map { SwitchbackServing.clusterKey($0) })
		let serialized = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [Any]
		XCTAssertEqual(expected, serialized.map { SwitchbackServing.clusterKey(JSON($0)) })
	}
}
