import Foundation
import XCTest

@testable import ABSmartly

final class ContextEventSerializerTest: XCTestCase {

	func testSerialize() {
		let event = PublishEvent()

		event.hashed = true
		event.publishedAt = 123_456_789
		event.units = [
			PublishEvent.Unit("session_id", "pAE3a1i5Drs5mKRNq56adA"),
			PublishEvent.Unit("user_id", "JfnnlDI7RTiF9RgfG2JNCw"),
		]

		let propertiesMap: [String: Any] = ["amount": 6, "value": 5.25, "tries": 1]

		event.goals = [
			GoalAchievement("goal1", achievedAt: 123_456_000, properties: propertiesMap),
			GoalAchievement("goal2", achievedAt: 123_456_789, properties: nil),
		]

		event.attributes = [
			PublishEvent.Attribute("attr1", "value1", 123_456_000),
			PublishEvent.Attribute("attr2", "value2", 123_456_789),
			PublishEvent.Attribute("attr2", nil, 123_450_000),
		]

		do {
			let encoder = JSONEncoder()
			let jsonData = try encoder.encode(event)

			guard let stringData = String(data: jsonData, encoding: .ascii) else {
				XCTFail("Encode data to string error")
				return
			}

			XCTAssertEqual(
				stringData,
				"{\"attributes\":[{\"name\":\"attr1\",\"value\":\"value1\",\"setAt\":123456000},{\"name\":\"attr2\",\"value\":\"value2\",\"setAt\":123456789},{\"name\":\"attr2\",\"setAt\":123450000}],\"goals\":[{\"name\":\"goal1\",\"properties\":{\"amount\":6,\"tries\":1,\"value\":5.25},\"achievedAt\":123456000},{\"name\":\"goal2\",\"properties\":null,\"achievedAt\":123456789}],\"units\":[{\"type\":\"session_id\",\"uid\":\"pAE3a1i5Drs5mKRNq56adA\"},{\"type\":\"user_id\",\"uid\":\"JfnnlDI7RTiF9RgfG2JNCw\"}],\"hashed\":true,\"publishedAt\":123456789}"
			)
		} catch {
			XCTFail("Encode error: \(error.localizedDescription)")
		}
	}
}
