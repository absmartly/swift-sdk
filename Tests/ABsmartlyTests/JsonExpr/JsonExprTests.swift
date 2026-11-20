import Testing

@testable import ABsmartly

@Suite struct JsonExprTests {
	static let John: [String: JSONValue] = ["age": 20, "language": "en-US", "returning": false]
	static let Terry: [String: JSONValue] = ["age": 20, "language": "en-GB", "returning": true]
	static let Kate: [String: JSONValue] = ["age": 50, "language": "es-ES", "returning": false]
	static let Maria: [String: JSONValue] = ["age": 52, "language": "pt-PT", "returning": true]

	static func unaryOp(_ op: String, _ arg: ExprValue) -> ExprValue {
		[op: arg]
	}

	static func binaryOp(_ op: String, _ lhs: ExprValue, _ rhs: ExprValue) -> ExprValue {
		[op: [lhs, rhs]]
	}

	static func varFor(_ path: String) -> ExprValue {
		["var": ["path": .string(path)]]
	}

	static func valueFor(_ value: ExprValue) -> ExprValue {
		["value": value]
	}

	static let AgeTwentyAndUS: ExprValue = [
		binaryOp("eq", varFor("age"), valueFor(20)),
		binaryOp("eq", varFor("language"), valueFor("en-US")),
	]
	static let AgeOverFifty: ExprValue = [binaryOp("gte", varFor("age"), valueFor(50))]
	static let AgeTwentyAndUS_Or_AgeOverFifty: ExprValue = [["or": [AgeTwentyAndUS, AgeOverFifty]]]
	static let Returning: ExprValue = [varFor("returning")]
	static let Returning_And_AgeTwentyAndUS_Or_AgeOverFifty: ExprValue = [Returning, AgeTwentyAndUS_Or_AgeOverFifty]
	static let NotReturning_And_Spanish: ExprValue = [
		unaryOp("not", Returning), binaryOp("eq", varFor("language"), valueFor("es-ES")),
	]

	private func eval(_ expr: ExprValue, _ vars: [String: JSONValue]) -> Bool {
		JsonExpr.evaluateBoolean(expr, vars: vars)
	}

	@Test func ageTwentyAsUSEnglish() {
		#expect(eval(Self.AgeTwentyAndUS, Self.John))
		#expect(!eval(Self.AgeTwentyAndUS, Self.Terry))
		#expect(!eval(Self.AgeTwentyAndUS, Self.Kate))
		#expect(!eval(Self.AgeTwentyAndUS, Self.Maria))
	}

	@Test func ageOverFifty() {
		#expect(!eval(Self.AgeOverFifty, Self.John))
		#expect(!eval(Self.AgeOverFifty, Self.Terry))
		#expect(eval(Self.AgeOverFifty, Self.Kate))
		#expect(eval(Self.AgeOverFifty, Self.Maria))
	}

	@Test func ageTwentyAndUS_Or_AgeOverFifty() {
		#expect(eval(Self.AgeTwentyAndUS_Or_AgeOverFifty, Self.John))
		#expect(!eval(Self.AgeTwentyAndUS_Or_AgeOverFifty, Self.Terry))
		#expect(eval(Self.AgeTwentyAndUS_Or_AgeOverFifty, Self.Kate))
		#expect(eval(Self.AgeTwentyAndUS_Or_AgeOverFifty, Self.Maria))
	}

	@Test func returning() {
		#expect(!eval(Self.Returning, Self.John))
		#expect(eval(Self.Returning, Self.Terry))
		#expect(!eval(Self.Returning, Self.Kate))
		#expect(eval(Self.Returning, Self.Maria))
	}

	@Test func returning_And_AgeTwentyAndUS_Or_AgeOverFifty() {
		#expect(!eval(Self.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, Self.John))
		#expect(!eval(Self.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, Self.Terry))
		#expect(!eval(Self.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, Self.Kate))
		#expect(eval(Self.Returning_And_AgeTwentyAndUS_Or_AgeOverFifty, Self.Maria))
	}

	@Test func notReturning_And_Spanish() {
		#expect(!eval(Self.NotReturning_And_Spanish, Self.John))
		#expect(!eval(Self.NotReturning_And_Spanish, Self.Terry))
		#expect(eval(Self.NotReturning_And_Spanish, Self.Kate))
		#expect(!eval(Self.NotReturning_And_Spanish, Self.Maria))
	}
}
