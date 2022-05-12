import Foundation
import XCTest

@testable import ABSmartly

final class VarOperatorTest: OperatorTest {
	let varOperator = VarOperator()

	func testEvaluate() {
		XCTAssertEqual("abc", varOperator.evaluate(evaluator, "a/b/c"))

		XCTAssertEqual(1, evaluator.extractVarCallsCount)
		XCTAssertEqual("a/b/c", evaluator.extractVarReceivedPath)
		XCTAssertFalse(evaluator.evaluateCalled)
	}
}
