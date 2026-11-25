import Testing

@testable import ABsmartly

@Suite struct JsonExprTests {
	static let john: [String: JSONValue] = ["age": 20, "language": "en-US", "returning": false]
	static let terry: [String: JSONValue] = ["age": 20, "language": "en-GB", "returning": true]
	static let kate: [String: JSONValue] = ["age": 50, "language": "es-ES", "returning": false]
	static let maria: [String: JSONValue] = ["age": 52, "language": "pt-PT", "returning": true]

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

	static let ageTwentyAndUS: ExprValue = [
		binaryOp("eq", varFor("age"), valueFor(20)),
		binaryOp("eq", varFor("language"), valueFor("en-US")),
	]
	static let ageOverFifty: ExprValue = [binaryOp("gte", varFor("age"), valueFor(50))]
	static let ageTwentyAndUSOrAgeOverFifty: ExprValue = [["or": [ageTwentyAndUS, ageOverFifty]]]
	static let returningExpr: ExprValue = [varFor("returning")]
	static let returningAndAgeTwentyAndUSOrAgeOverFifty: ExprValue = [returningExpr, ageTwentyAndUSOrAgeOverFifty]
	static let notReturningAndSpanish: ExprValue = [
		unaryOp("not", returningExpr), binaryOp("eq", varFor("language"), valueFor("es-ES")),
	]

	private func eval(_ expr: ExprValue, _ vars: [String: JSONValue]) -> Bool {
		JsonExpr.evaluateBoolean(expr, vars: vars)
	}

	@Test func ageTwentyAsUSEnglish() {
		#expect(eval(Self.ageTwentyAndUS, Self.john))
		#expect(!eval(Self.ageTwentyAndUS, Self.terry))
		#expect(!eval(Self.ageTwentyAndUS, Self.kate))
		#expect(!eval(Self.ageTwentyAndUS, Self.maria))
	}

	@Test func ageOverFifty() {
		#expect(!eval(Self.ageOverFifty, Self.john))
		#expect(!eval(Self.ageOverFifty, Self.terry))
		#expect(eval(Self.ageOverFifty, Self.kate))
		#expect(eval(Self.ageOverFifty, Self.maria))
	}

	@Test func ageTwentyAndUS_Or_AgeOverFifty() {
		#expect(eval(Self.ageTwentyAndUSOrAgeOverFifty, Self.john))
		#expect(!eval(Self.ageTwentyAndUSOrAgeOverFifty, Self.terry))
		#expect(eval(Self.ageTwentyAndUSOrAgeOverFifty, Self.kate))
		#expect(eval(Self.ageTwentyAndUSOrAgeOverFifty, Self.maria))
	}

	@Test func returning() {
		#expect(!eval(Self.returningExpr, Self.john))
		#expect(eval(Self.returningExpr, Self.terry))
		#expect(!eval(Self.returningExpr, Self.kate))
		#expect(eval(Self.returningExpr, Self.maria))
	}

	@Test func returning_And_AgeTwentyAndUS_Or_AgeOverFifty() {
		#expect(!eval(Self.returningAndAgeTwentyAndUSOrAgeOverFifty, Self.john))
		#expect(!eval(Self.returningAndAgeTwentyAndUSOrAgeOverFifty, Self.terry))
		#expect(!eval(Self.returningAndAgeTwentyAndUSOrAgeOverFifty, Self.kate))
		#expect(eval(Self.returningAndAgeTwentyAndUSOrAgeOverFifty, Self.maria))
	}

	@Test func notReturning_And_Spanish() {
		#expect(!eval(Self.notReturningAndSpanish, Self.john))
		#expect(!eval(Self.notReturningAndSpanish, Self.terry))
		#expect(eval(Self.notReturningAndSpanish, Self.kate))
		#expect(!eval(Self.notReturningAndSpanish, Self.maria))
	}
}
