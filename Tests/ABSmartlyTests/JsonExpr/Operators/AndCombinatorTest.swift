import Foundation
import XCTest

@testable import ABSmartly

final class AndCombinatorTest: OperatorTest {
	let combinator = AndCombinator()

	func testCombineTrue() {
		XCTAssertTrue(combinator.combine(evaluator, [true]).boolValue)
		XCTAssertEqual(1, evaluator.booleanConvertCallsCount)
		XCTAssertEqual(true, evaluator.booleanConvertReceivedX)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(true, evaluator.evaluateReceivedExpr)
	}

	func testCombineFalse() {
		XCTAssertFalse(combinator.combine(evaluator, [false]).boolValue)
		XCTAssertEqual(1, evaluator.booleanConvertCallsCount)
		XCTAssertEqual(false, evaluator.booleanConvertReceivedX)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(false, evaluator.evaluateReceivedExpr)
	}

	func testCombineNull() {
		XCTAssertFalse(combinator.combine(evaluator, [JSON.null]).boolValue)
		XCTAssertEqual(1, evaluator.booleanConvertCallsCount)
		XCTAssertEqual(JSON.null, evaluator.booleanConvertReceivedX)
		XCTAssertEqual(1, evaluator.evaluateCallsCount)
		XCTAssertEqual(JSON.null, evaluator.evaluateReceivedExpr)
	}

	func testCombineShortCircuit() {
		XCTAssertFalse(combinator.combine(evaluator, [true, false, true]).boolValue)
		XCTAssertEqual(2, evaluator.booleanConvertCallsCount)
		XCTAssertEqual([JSON(true), JSON(false)], evaluator.booleanConvertReceivedInvocations)
		XCTAssertEqual(2, evaluator.evaluateCallsCount)
		XCTAssertEqual([JSON(true), JSON(false)], evaluator.evaluateReceivedInvocations)
	}

	func testCombine() {
		XCTAssertTrue(combinator.combine(evaluator, [true, true]).boolValue)
		XCTAssertTrue(combinator.combine(evaluator, [true, true, true]).boolValue)

		XCTAssertFalse(combinator.combine(evaluator, [true, false]).boolValue)
		XCTAssertFalse(combinator.combine(evaluator, [false, true]).boolValue)
		XCTAssertFalse(combinator.combine(evaluator, [false, false]).boolValue)
		XCTAssertFalse(combinator.combine(evaluator, [false, false, false]).boolValue)
	}
}
