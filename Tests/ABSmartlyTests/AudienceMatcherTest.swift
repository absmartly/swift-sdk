import XCTest

@testable import ABSmartly

final class AudienceMatcherTest: XCTestCase {
	let matcher = AudienceMatcher()

	func testEvaluateReturnsNullOnEmptyAudience() {
		XCTAssertNil(matcher.evaluate("", [:]))
		XCTAssertNil(matcher.evaluate("{}", [:]))
		XCTAssertNil(matcher.evaluate("null", [:]))
	}

	func testEvaluateReturnsNullIfFilterNotMapOrList() {
		XCTAssertNil(matcher.evaluate("{\"filter\":null}", [:]))
		XCTAssertNil(matcher.evaluate("{\"filter\":false}", [:]))
		XCTAssertNil(matcher.evaluate("{\"filter\":5}", [:]))
		XCTAssertNil(matcher.evaluate("{\"filter\":\"a\"}", [:]))
	}

	func testEvaluateReturnsBoolean() {
		XCTAssertTrue(matcher.evaluate("{\"filter\":[{\"value\":5}]}", [:])!)
		XCTAssertTrue(matcher.evaluate("{\"filter\":[{\"value\":true}]}", [:])!)
		XCTAssertTrue(matcher.evaluate("{\"filter\":[{\"value\":1}]}", [:])!)
		XCTAssertFalse(matcher.evaluate("{\"filter\":[{\"value\":null}]}", [:])!)
		XCTAssertFalse(matcher.evaluate("{\"filter\":[{\"value\":0}]}", [:])!)

		XCTAssertFalse(matcher.evaluate("{\"filter\":[{\"not\":{\"var\":\"returning\"}}]}", ["returning": true])!)
		XCTAssertTrue(matcher.evaluate("{\"filter\":[{\"not\":{\"var\":\"returning\"}}]}", ["returning": false])!)
	}
}
