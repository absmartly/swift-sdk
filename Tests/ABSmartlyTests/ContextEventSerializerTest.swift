import Foundation
import XCTest

@testable import ABSmartly

final class ContextEventSerializerTest: XCTestCase {
	func testSerialize() throws {
		let units = [
			Unit(type: "session_id", uid: "pAE3a1i5Drs5mKRNq56adA"),
			Unit(type: "user_id", uid: "JfnnlDI7RTiF9RgfG2JNCw"),
		]

		let attributes = [
			Attribute("attr1", value: "value1", setAt: 123_456_000),
			Attribute("attr2", value: "value2", setAt: 123_456_789),
			Attribute("attr2", value: JSON.null, setAt: 123_450_000),
			Attribute("attr3", value: ["nested": ["value": 5]], setAt: 123_470_000),
			Attribute("attr4", value: ["nested": [1, 2, "test"]], setAt: 123_480_000),
		]

		let exposures = [
			Exposure(1, "exp_test_ab", "session_id", 1, 123470000, true, true, false, false, false, true)
		]

		let propertiesMap: [String: JSON] = ["amount": 6, "value": 5.25, "tries": 1]

		let goals = [
			GoalAchievement("goal1", achievedAt: 123_456_000, properties: propertiesMap),
			GoalAchievement("goal2", achievedAt: 123_456_789, properties: nil),
		]

		let event = PublishEvent(true, units, 123_456_789, exposures, goals, attributes)

		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let jsonData = try encoder.encode(event)

		guard let stringData = String(data: jsonData, encoding: .utf8) else {
			XCTFail("Encode data to string error")
			return
		}

		XCTAssertEqual(
			stringData,
			"{\"attributes\":[{\"name\":\"attr1\",\"setAt\":123456000,\"value\":\"value1\"},{\"name\":\"attr2\",\"setAt\":123456789,\"value\":\"value2\"},{\"name\":\"attr2\",\"setAt\":123450000,\"value\":null},{\"name\":\"attr3\",\"setAt\":123470000,\"value\":{\"nested\":{\"value\":5}}},{\"name\":\"attr4\",\"setAt\":123480000,\"value\":{\"nested\":[1,2,\"test\"]}}],\"exposures\":[{\"assigned\":true,\"audienceMismatch\":true,\"custom\":false,\"eligible\":true,\"exposedAt\":123470000,\"fullOn\":false,\"id\":1,\"name\":\"exp_test_ab\",\"overridden\":false,\"unit\":\"session_id\",\"variant\":1}],\"goals\":[{\"achievedAt\":123456000,\"name\":\"goal1\",\"properties\":{\"amount\":6,\"tries\":1,\"value\":5.25}},{\"achievedAt\":123456789,\"name\":\"goal2\",\"properties\":null}],\"hashed\":true,\"publishedAt\":123456789,\"units\":[{\"type\":\"session_id\",\"uid\":\"pAE3a1i5Drs5mKRNq56adA\"},{\"type\":\"user_id\",\"uid\":\"JfnnlDI7RTiF9RgfG2JNCw\"}]}"
		)
	}
}
