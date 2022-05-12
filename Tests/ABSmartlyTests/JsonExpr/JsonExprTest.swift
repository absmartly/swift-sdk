import Foundation
import XCTest

@testable import ABSmartly

final class JsonExprTest: XCTestCase {
	let John = ["age": JSON(20), "language": JSON("en-US"), "returning": JSON(false)]
	let Terry = ["age": JSON(20), "language": JSON("en-GB"), "returning": JSON(true)]
	let Kate = ["age": JSON(50), "language": JSON("es-ES"), "returning": JSON(false)]
	let Maria = ["age": JSON(52), "language": JSON("pt-PT"), "returning": JSON(true)]
	let jsonExpr = JsonExpr()

	static func unaryOp(_ op: String, _ arg: JSON) -> JSON {
		return JSON([op: arg])
	}
	static func binaryOp(_ op: String, _ lhs: JSON, _ rhs: JSON) -> JSON {
		return JSON([op: JSON([lhs, rhs])])
	}

	static func varFor(_ path: String) -> JSON {
		return JSON(["var": JSON(["path": JSON(path)])])
	}

	static func valueFor(_ value: Any) -> JSON {
		return JSON(["value": JSON(value)])
	}

	static let AgeTwentyAndUS = JSON([
		binaryOp("eq", varFor("age"), valueFor(20)),
		binaryOp("eq", varFor("language"), valueFor("en-US")),
	])

	static let AgeOverFifty = JSON([binaryOp("gte", varFor("age"), valueFor(50))])
	static let AgeTwentyAndUS_Or_AgeOverFifty = JSON([JSON(["or": JSON([AgeTwentyAndUS, AgeOverFifty])])])
	static let Returning = JSON([varFor("returning")])
	static let Returning_And_AgeTwentyAndUS_Or_AgeOverFifty = JSON([Returning, AgeTwentyAndUS_Or_AgeOverFifty])
	static let NotReturning_And_Spanish = JSON([
		unaryOp("not", Returning), binaryOp("eq", varFor("language"), valueFor("es-ES")),
	])

	func testAgeTwentyAsUSEnglish() {
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS, vars: John))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS, vars: Terry))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS, vars: Kate))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS, vars: Maria))
	}

	func testAgeOverFifty() {
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeOverFifty, vars: John))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeOverFifty, vars: Terry))
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeOverFifty, vars: Kate))
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeOverFifty, vars: Maria))
	}

	func testAgeTwentyAndUS_Or_AgeOverFifty() {
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS_Or_AgeOverFifty, vars: John))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS_Or_AgeOverFifty, vars: Terry))
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS_Or_AgeOverFifty, vars: Kate))
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.AgeTwentyAndUS_Or_AgeOverFifty, vars: Maria))
	}

	func testReturning() {
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning, vars: John))
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning, vars: Terry))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning, vars: Kate))
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning, vars: Maria))
	}

	func testReturning_And_AgeTwentyAndUS_Or_AgeOverFifty() {
		XCTAssertFalse(
			jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, vars: John))
		XCTAssertFalse(
			jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, vars: Terry))
		XCTAssertFalse(
			jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, vars: Kate))
		XCTAssertTrue(
			jsonExpr.evaluateBooleanExpr(JsonExprTest.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, vars: Maria))
	}

	func testNotReturning_And_Spanish() {
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.NotReturning_And_Spanish, vars: John))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.NotReturning_And_Spanish, vars: Terry))
		XCTAssertTrue(jsonExpr.evaluateBooleanExpr(JsonExprTest.NotReturning_And_Spanish, vars: Kate))
		XCTAssertFalse(jsonExpr.evaluateBooleanExpr(JsonExprTest.NotReturning_And_Spanish, vars: Maria))
	}
}
