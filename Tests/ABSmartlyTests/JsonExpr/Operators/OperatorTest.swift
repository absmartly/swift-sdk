import Foundation
import XCTest

@testable import ABSmartly

class OperatorTest: XCTestCase {
	let evaluator = EvaluatorMock()

	override func setUp() {
		evaluator.evaluateClosure = { arg in arg }
		evaluator.booleanConvertClosure = { arg in arg == .null ? false : arg }
		evaluator.numberConvertClosure = { arg in arg }
		evaluator.stringConvertClosure = { arg in JSON(arg.stringValue) }
		evaluator.extractVarClosure = { arg in
			if arg == "a/b/c" {
				return "abc"
			}
			return JSON.null
		}
		evaluator.compareClosure = { lhs, rhs in
			switch lhs.type {
			case .bool:
				return (lhs.boolValue == rhs.boolValue) ? 0 : (lhs.boolValue ? 1 : -1)
			case .number:
				return (lhs.doubleValue == rhs.doubleValue) ? 0 : (lhs.doubleValue > rhs.doubleValue ? 1 : -1)
			case .string:
				return lhs.stringValue.compare(rhs.stringValue).rawValue
			default:
				if lhs == rhs {
					return 0
				}
			}

			return nil
		}
	}
}
