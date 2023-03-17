import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

final class SqlliteCacheTest: XCTestCase {
	var localCache: SqlliteCache?

	override func setUp() {
		localCache = SqlliteCache()
	}

	func testWriteEventsToCache() {
		let expectation = XCTestExpectation()
		let expectation2 = XCTestExpectation()

		guard let localCache = localCache else { return }

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
			Exposure(1, "exp_test_ab", "session_id", 1, 123_470_000, true, true, false, false, false, true)
		]

		let propertiesMap: [String: JSON] = ["amount": 6, "value": 5.25, "tries": 1]

		let goals = [
			GoalAchievement("goal1", achievedAt: 123_456_000, properties: propertiesMap),
			GoalAchievement("goal2", achievedAt: 123_456_789, properties: nil),
		]

		let event = PublishEvent(true, units, 123_456_789, exposures, goals, attributes)

		do {
			let result = localCache.writeEvent(event: event)
			expectation.fulfill()
		} catch {
			XCTFail(error.localizedDescription)
		}

		do {
			let events = localCache.retrieveEvents()
			XCTAssertTrue(events.count == 1)
			expectation2.fulfill()
		} catch {
			XCTFail(error.localizedDescription)
		}

		wait(for: [expectation, expectation2], timeout: 5.0)

	}

	func testWriteContextDataToCache() throws {
		let expectation = XCTestExpectation()
		let expectation2 = XCTestExpectation()

		guard let localCache = localCache else { return }

		let contextData = ContextData(experiments: [Experiment]())

		do {
			let writeResult = localCache.writeContextData(contextData: contextData)
			expectation.fulfill()
		} catch {
			XCTFail(error.localizedDescription)
		}

		do {
			let contextDateSaved = localCache.getContextData()
			XCTAssertEqual(contextData, contextDateSaved)
			expectation2.fulfill()
		} catch {
			XCTFail(error.localizedDescription)
		}

		wait(for: [expectation, expectation2], timeout: 5.0)
	}

}
