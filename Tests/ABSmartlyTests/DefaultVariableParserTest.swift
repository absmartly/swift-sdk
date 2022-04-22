import Foundation
import XCTest

@testable import ABSmartly

final class DefaultVariableParserTest: XCTestCase {
	func testParse() throws {
		let path = Bundle.module.path(forResource: "variables", ofType: "json", inDirectory: "Resources")!
		let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
		let config = String(data: data, encoding: .utf8)

		let parser = DefaultVariableParser()
		let actual = parser.parse(experimentName: "test", config: config!)

		let expected: [String: JSON] = [
			"a": 1,
			"b": "test",
			"c": [
				"test": 2,
				"double": 19.123,
				"list": ["x", "y", "z"],
				"point": [
					"x": -1.0,
					"y": 0.0,
					"z": 1.0,
				],
			],
			"d": true,
			"f": [9_234_567_890, "a", true, false],
			"g": 9.123,
		]

		XCTAssertEqual(expected, actual)
	}

	func testReturnsNilOnError() throws {
		let path = Bundle.module.path(forResource: "variables", ofType: "json", inDirectory: "Resources")!
		let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
		let config = String(data: data.subdata(in: 0..<6), encoding: .utf8)

		let parser = DefaultVariableParser()
		let actual = parser.parse(experimentName: "test", config: config!)

		XCTAssertNil(actual)
	}
}
