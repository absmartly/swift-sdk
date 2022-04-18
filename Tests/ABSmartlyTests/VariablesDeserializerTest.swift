import Foundation
import XCTest

@testable import ABSmartly

final class VariablesDeserializerTest: XCTestCase {

	func testSerialize() {
		var variables: [String: AnyObject]?
		let path = Bundle.module.path(forResource: "variables", ofType: "json", inDirectory: "Resources")!
		do {
			let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
			variables =
				try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: AnyObject]
		} catch {
			XCTFail("Deserialization error: \(error.localizedDescription)")
		}

		XCTAssertEqual(variables?.count, 6)

		XCTAssertEqual(variables?["a"] as? Int, 1)
		XCTAssertEqual(variables?["b"] as? String, "test")
		XCTAssertEqual((variables?["c"] as? [String: AnyObject])?.count, 4)
		XCTAssertEqual((variables?["c"] as? [String: AnyObject])?["test"] as? Int, 2)
		XCTAssertEqual((variables?["c"] as? [String: AnyObject])?["double"] as? Double, 19.123)
		XCTAssertEqual((variables?["c"] as? [String: AnyObject])?["list"] as? [String], ["x", "y", "z"])
		XCTAssertEqual(
			(variables?["c"] as? [String: AnyObject])?["point"] as? [String: Double], ["x": -1.0, "y": 0.0, "z": 1.0])
		XCTAssertEqual(variables?["d"] as? Bool, true)
		XCTAssertEqual((variables?["f"] as? [Any])?.count, 4)
		XCTAssertEqual((variables?["f"] as? [Any])?[0] as? Int, 9_234_567_890)
		XCTAssertEqual((variables?["f"] as? [Any])?[1] as? String, "a")
		XCTAssertEqual((variables?["f"] as? [Any])?[2] as? Bool, true)
		XCTAssertEqual((variables?["f"] as? [Any])?[3] as? Bool, false)
		XCTAssertEqual(variables?["g"] as? Double, 9.123)
	}
}
