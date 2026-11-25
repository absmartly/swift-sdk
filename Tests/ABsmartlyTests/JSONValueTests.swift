import Foundation
import Testing

@testable import ABsmartly

/// Types a literal as a `JSONValue` (collection literals cannot be passed to `JSONValue(_:)`).
private func json(_ value: JSONValue) -> JSONValue { value }

@Suite struct JSONValueTests {
	// NaN and infinity are null on the SDK's own encoders (the collector PUT, `description`); an
	// app's encoder keeps its nonConformingFloatEncodingStrategy.
	@Test func nonFiniteNumbersFollowTheAppEncodersStrategy() throws {
		let value: JSONValue = ["nan": .double(.nan), "inf": .double(.infinity)]
		let strict = JSONEncoder()
		#expect(throws: EncodingError.self) { try strict.encode(value) }

		let lenient = JSONEncoder()
		lenient.outputFormatting = .sortedKeys
		lenient.nonConformingFloatEncodingStrategy = .convertToString(
			positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
		#expect(String(decoding: try lenient.encode(value), as: UTF8.self) == #"{"inf":"+inf","nan":"nan"}"#)

		#expect(value.description == #"{"inf":null,"nan":null}"#)
	}

	static func decode(_ text: String) throws -> JSONValue {
		try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
	}

	static func encode(_ value: JSONValue) throws -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		return String(decoding: try encoder.encode(value), as: UTF8.self)
	}

	static func hash(_ value: JSONValue) -> Int {
		var hasher = Hasher()
		value.hash(into: &hasher)
		return hasher.finalize()
	}

	// MARK: - Equality

	@Test func numberEquality() {
		#expect(json(1) == json(1))
		#expect(JSONValue.int(2) == JSONValue.double(2.0))
		#expect(json(9_234_567_890) == json(9_234_567_890))
		#expect(json(-1.5) == json(-1.5))
		#expect(!(json(1) == json(2)))
		#expect(!(JSONValue.int(1) == JSONValue.double(1.5)))
		#expect(json(1) != json(2))
		#expect(!(JSONValue.int(1) != JSONValue.double(1.0)))
	}

	@Test func parsedValuesCompareLikeLiterals() throws {
		let parsed = try JSONValue(parsing: "[1, 2.5, true, false, \"a\"]")
		guard case .int = try #require(parsed[0]) else {
			Issue.record("1 is an int")
			return
		}
		guard case .double = try #require(parsed[1]) else {
			Issue.record("2.5 is a double")
			return
		}
		guard case .bool = try #require(parsed[2]) else {
			Issue.record("true is a bool")
			return
		}
		guard case .bool = try #require(parsed[3]) else {
			Issue.record("false is a bool")
			return
		}
		#expect(parsed[0] == json(1))
		#expect(parsed[2] == json(true))
		#expect(!(parsed[2] == parsed[0]))
		#expect(!(parsed[3] == json(0)))
		#expect(parsed[4] == json("a"))
	}

	@Test func boolIsNotANumber() {
		#expect(json(true) == .bool(true))
		#expect(json(false) == .bool(false))
		#expect(json(1) == .int(1))
		#expect(json(0) == .int(0))
		#expect(!json(true).isNumber)
		#expect(json(1).isNumber)

		#expect(!(json(true) == json(1)))
		#expect(!(json(1) == json(true)))
		#expect(!(json(false) == json(0)))
		#expect(json(true) != json(1))
		#expect(JSONValue.double(1) != .bool(true))
		#expect(json(true).intValue == nil)
		#expect(json(1).boolValue == nil)
	}

	@Test func boolComparisons() {
		#expect(json(true) == json(true))
		#expect(!(json(true) == json(false)))
	}

	@Test func stringComparisons() {
		#expect(json("abc") == json("abc"))
		#expect(!(json("abc") == json("abd")))
		#expect(!(json("1") == json(1)))
		#expect(!(json("true") == json(true)))
	}

	@Test func nullAndContainers() {
		#expect(JSONValue.null == nil)
		#expect(!(JSONValue.null == json(0)))
		#expect(!(JSONValue.null == ""))
		#expect(!(JSONValue.null == false))
		#expect(json([1, "a", true]) == json([1, "a", true]))
		#expect(!(json([1, 2]) == json([2, 1])))
		#expect(json(["a": 1, "b": [true]]) == json(["b": [true], "a": 1]))
		#expect(!(json(["a": 1]) == json(["a": 2])))
		#expect(json([JSONValue.int(1)]) == json([JSONValue.double(1)]))
	}

	// MARK: - Codable

	@Test(arguments: [
		"null", "true", "false", "0", "-1", "42", "9223372036854775807", "-9223372036854775808", "1.5", "-0.25",
		"1e+300", "\"\"", "\"text\"", "\"üñí \\\"q\\\" \\n\"", "[]", "{}", "[1,\"a\",null,[true],{\"k\":2.5}]",
		"{\"a\":{\"b\":[1,{\"c\":null}]},\"d\":false}",
	])
	func codableRoundTrip(text: String) throws {
		let value = try Self.decode(text)
		let reencoded = try Self.decode(try Self.encode(value))
		#expect(reencoded == value, "\(text)")
		#expect(try Self.encode(value) == Self.encode(reencoded))
	}

	@Test func decodesEachCase() throws {
		#expect(try Self.decode("null") == .null)
		#expect(try Self.decode("true") == .bool(true))
		#expect(try Self.decode("false") == .bool(false))
		#expect(try Self.decode("7") == .int(7))
		#expect(try Self.decode("7.25") == .double(7.25))
		#expect(try Self.decode("\"x\"") == .string("x"))
		#expect(try Self.decode("[1]") == .array([.int(1)]))
		#expect(try Self.decode("{\"a\":1}") == .object(["a": .int(1)]))
	}

	@Test func boolAndNumberStayDistinctWhenDecoded() throws {
		let decoded = try Self.decode("[true, 1, false, 0, 1.0]")
		let array = try #require(decoded.arrayValue)
		guard case .bool(true) = array[0] else {
			Issue.record("true: \(array[0])")
			return
		}
		guard case .int(1) = array[1] else {
			Issue.record("1: \(array[1])")
			return
		}
		guard case .bool(false) = array[2] else {
			Issue.record("false: \(array[2])")
			return
		}
		guard case .int(0) = array[3] else {
			Issue.record("0: \(array[3])")
			return
		}
		// A whole floating-point literal is read as an integer by JSONDecoder; it still equals 1.
		#expect(array[4] == 1)
		#expect(try Self.encode(.bool(true)) == "true")
		#expect(try Self.encode(.int(1)) == "1")
		#expect(try Self.encode(.bool(false)) == "false")
	}

	@Test func encodesEachCase() throws {
		#expect(try Self.encode(.null) == "null")
		#expect(try Self.encode(.int(-3)) == "-3")
		#expect(try Self.encode(.double(5.25)) == "5.25")
		#expect(try Self.encode(.string("a\"b")) == #""a\"b""#)
		#expect(try Self.encode([1, "a", nil, [true]]) == #"[1,"a",null,[true]]"#)
		#expect(try Self.encode(["b": 1, "a": ["c": nil]]) == #"{"a":{"c":null},"b":1}"#)
	}

	@Test func decodesInsideOtherTypes() throws {
		struct Wrapper: Codable, Equatable {
			var value: JSONValue
			var optional: JSONValue?
		}
		let wrapper = try JSONDecoder().decode(Wrapper.self, from: Data(#"{"value":{"x":[1,2]},"optional":null}"#.utf8))
		#expect(wrapper.value == ["x": [1, 2]])
		#expect(wrapper.optional == nil)
		let round = try JSONDecoder().decode(Wrapper.self, from: try JSONEncoder().encode(wrapper))
		#expect(round.value == wrapper.value)
	}

	@Test func parsingAnyValue() throws {
		#expect(try JSONValue(parsing: "5") == 5)
		#expect(try JSONValue(parsing: "\"s\"") == "s")
		#expect(try JSONValue(parsing: " null ") == .null)
		#expect(try JSONValue(parsing: "{\"a\":[1]}") == ["a": [1]])
		for bad in ["", "{", "[1,", "nope", "{\"a\":}", "'x'"] {
			#expect(throws: ABsmartlyError.self, "\(bad)") { try JSONValue(parsing: bad) }
		}
		do {
			_ = try JSONValue(parsing: "{")
		} catch {
			guard case .decoding = error else {
				Issue.record("expected .decoding, got \(error)")
				return
			}
		}
	}

	// MARK: - Int64 exactness

	@Test func int64IsExactAboveTwoToThe53() throws {
		let big: Int64 = 9_007_199_254_740_993  // 2^53 + 1, not representable as a Double
		let decoded = try Self.decode("9007199254740993")
		#expect(decoded == .int(big))
		#expect(try Self.encode(decoded) == "9007199254740993")
		#expect(decoded != .int(big - 1))
		#expect(decoded != .double(9_007_199_254_740_992))
		#expect(decoded.doubleValue == 9_007_199_254_740_992)
		#expect(decoded.intValue == Int(big))

		#expect(try Self.decode(String(Int64.max)) == .int(.max))
		#expect(try Self.decode(String(Int64.min)) == .int(.min))
		#expect(try Self.encode(.int(.max)) == String(Int64.max))
	}

	@Test func integersBeyondInt64AreDoubles() throws {
		let decoded = try Self.decode("9223372036854775808")
		guard case .double(let value) = decoded else {
			Issue.record("expected a double, got \(decoded)")
			return
		}
		#expect(value == 9_223_372_036_854_775_808)
	}

	@Test func intDoubleEqualityIsExact() {
		#expect(JSONValue.int(3) == .double(3))
		#expect(JSONValue.double(3) == .int(3))
		#expect(JSONValue.int(-0) == .double(-0.0))
		#expect(JSONValue.int(3) != .double(3.000_000_1))
		// 2^53 + 1 has no exact Double, so it equals no double.
		#expect(JSONValue.int(9_007_199_254_740_993) != .double(9_007_199_254_740_992))
		#expect(JSONValue.int(9_007_199_254_740_992) == .double(9_007_199_254_740_992))
		#expect(JSONValue.int(.max) != .double(9_223_372_036_854_775_808))
		#expect(JSONValue.double(.nan) != .double(.nan))
	}

	// MARK: - Hashing

	@Test func equalValuesHashEqually() {
		let pairs: [(JSONValue, JSONValue)] = [
			(.int(3), .double(3)),
			(.int(0), .double(-0.0)),
			(.int(-7), .double(-7)),
			(.int(9_007_199_254_740_992), .double(9_007_199_254_740_992)),
			([1, 2], [.double(1), .double(2)]),
			(["a": 1], ["a": .double(1)]),
			("x", "x"),
			(nil, .null),
		]
		for (lhs, rhs) in pairs {
			#expect(lhs == rhs)
			#expect(Self.hash(lhs) == Self.hash(rhs), "\(lhs) / \(rhs)")
		}
	}

	@Test func setsAndDictionariesUseNumericEquality() {
		let set: Set<JSONValue> = [.int(1), .double(1), .double(1.5), .bool(true), "1", .null]
		#expect(set.count == 5)
		#expect(set.contains(.double(1)))
		#expect(set.contains(.int(1)))
		#expect(set.contains(true))
		var dictionary: [JSONValue: String] = [.int(2): "int"]
		dictionary[.double(2)] = "double"
		#expect(dictionary.count == 1)
		#expect(dictionary[.int(2)] == "double")
	}

	@Test func boolAndNumberHashDifferently() {
		// Not required by Hashable, but they are unequal and live in different hash domains.
		#expect(JSONValue.bool(true) != .int(1))
		#expect(Self.hash(.bool(true)) != Self.hash(.int(1)))
		#expect(Self.hash(.bool(false)) != Self.hash(.int(0)))
	}

	// MARK: - Literals

	@Test func literals() {
		let null: JSONValue = nil
		let bool: JSONValue = true
		let int: JSONValue = 42
		let double: JSONValue = 4.5
		let string: JSONValue = "s"
		let array: JSONValue = [1, "a", nil]
		let object: JSONValue = ["k": [true]]
		#expect(null == .null)
		#expect(bool == .bool(true))
		#expect(int == .int(42))
		#expect(double == .double(4.5))
		#expect(string == .string("s"))
		#expect(array == .array([.int(1), .string("a"), .null]))
		#expect(object == .object(["k": .array([.bool(true)])]))
		guard case .int = int else {
			Issue.record("an integer literal is .int")
			return
		}
		guard case .double = double else {
			Issue.record("a float literal is .double")
			return
		}
	}

	@Test func duplicateDictionaryLiteralKeysKeepTheLast() {
		let object: JSONValue = ["a": 1, "a": 2]
		#expect(object == ["a": 2])
	}

	// MARK: - Accessors

	@Test func accessors() {
		let value: JSONValue = ["s": "x", "i": 3, "d": 2.5, "b": false, "a": [1, 2], "o": ["k": nil], "n": nil]

		#expect(value["s"]?.stringValue == "x")
		#expect(value["i"]?.intValue == 3)
		#expect(value["i"]?.doubleValue == 3)
		#expect(value["d"]?.doubleValue == 2.5)
		#expect(value["d"]?.intValue == nil)
		#expect(value["b"]?.boolValue == false)
		#expect(value["a"]?.arrayValue == [1, 2])
		#expect(value["o"]?.objectValue == ["k": .null])
		#expect(value["n"]?.isNull == true)
		#expect(value["missing"] == nil)
		#expect(value.objectValue?.count == 7)
		#expect(value.arrayValue == nil)

		// Typed accessors are nil for other cases.
		#expect(JSONValue.int(1).stringValue == nil)
		#expect(JSONValue.string("1").intValue == nil)
		#expect(JSONValue.string("1").doubleValue == nil)
		#expect(JSONValue.string("true").boolValue == nil)
		#expect(JSONValue.null.objectValue == nil)
		#expect(!JSONValue.int(0).isNull)
	}

	@Test func intValueOnlyForIntegralInRangeNumbers() {
		#expect(JSONValue.double(4.0).intValue == 4)
		#expect(JSONValue.double(-4.0).intValue == -4)
		#expect(JSONValue.double(4.5).intValue == nil)
		#expect(JSONValue.double(1e300).intValue == nil)
		#expect(JSONValue.double(.nan).intValue == nil)
		#expect(JSONValue.double(.infinity).intValue == nil)
		#expect(JSONValue.int(.max).intValue == Int(exactly: Int64.max))
	}

	@Test func subscripts() {
		let array: JSONValue = [10, [20, 30]]
		#expect(array[0] == 10)
		#expect(array[1]?[1] == 30)
		#expect(array[2] == nil)
		#expect(array[-1] == nil)
		#expect(array["key"] == nil)
		let object: JSONValue = ["a": ["b": [1, 2]]]
		#expect(object["a"]?["b"]?[1] == 2)
		#expect(object[0] == nil)
		#expect(JSONValue.string("abc")[0] == nil)
		#expect(JSONValue.null["a"] == nil)
	}

	// MARK: - JSONValueConvertible

	@Test func scalarConversions() {
		#expect("s".jsonValue == .string("s"))
		#expect("abc".dropFirst().jsonValue == .string("bc"))
		#expect(true.jsonValue == .bool(true))
		#expect(Int(-5).jsonValue == .int(-5))
		#expect(Int8(-8).jsonValue == .int(-8))
		#expect(Int16(16).jsonValue == .int(16))
		#expect(Int32(32).jsonValue == .int(32))
		#expect(Int64.max.jsonValue == .int(.max))
		#expect(UInt(7).jsonValue == .int(7))
		#expect(UInt8(8).jsonValue == .int(8))
		#expect(UInt16(16).jsonValue == .int(16))
		#expect(UInt32.max.jsonValue == .int(Int64(UInt32.max)))
		#expect(UInt64(9_007_199_254_740_993).jsonValue == .int(9_007_199_254_740_993))
		#expect(2.5.jsonValue == .double(2.5))
		#expect(Float(0.5).jsonValue == .double(0.5))
		#expect(JSONValue.null.jsonValue == .null)
	}

	@Test func unsignedBeyondInt64BecomeDoubles() {
		guard case .double(let value) = UInt64.max.jsonValue else {
			Issue.record("UInt64.max is a double")
			return
		}
		#expect(value == Double(UInt64.max))
		guard case .double = UInt.max.jsonValue else {
			Issue.record("UInt.max is a double")
			return
		}
	}

	@Test func containerConversions() {
		let optionalSome: Int? = 3
		let optionalNone: String? = nil
		#expect(optionalSome.jsonValue == .int(3))
		#expect(optionalNone.jsonValue == .null)
		#expect([1, 2, 3].jsonValue == .array([1, 2, 3]))
		#expect(["a", "b"].jsonValue == .array(["a", "b"]))
		#expect(["x": 1.5].jsonValue == .object(["x": 1.5]))
		#expect(["x": [true, false]].jsonValue == .object(["x": [true, false]]))
		let nested: [String: [Int?]] = ["n": [1, nil]]
		#expect(nested.jsonValue == ["n": [1, nil]])
	}

	@Test func conversionsAreAcceptedBySetAttribute() {
		let context = Harness().context(data: ContextData())
		context.setAttribute("string", to: "s")
		context.setAttribute("int", to: 42)
		context.setAttribute("double", to: 1.5)
		context.setAttribute("bool", to: true)
		context.setAttribute("array", to: [1, 2])
		context.setAttribute("object", to: ["k": "v"])
		context.setAttribute("json", to: JSONValue.null)
		context.setAttribute("uint8", to: UInt8(3))
		#expect(
			context.attributes == [
				"string": "s", "int": 42, "double": 1.5, "bool": true, "array": [1, 2], "object": ["k": "v"],
				"json": nil, "uint8": 3,
			])
	}

	// MARK: - Description

	@Test func description() {
		#expect(JSONValue.null.description == "null")
		#expect(JSONValue.bool(true).description == "true")
		#expect(JSONValue.int(-12).description == "-12")
		#expect(JSONValue.double(2.5).description == "2.5")
		#expect(JSONValue.string("a/b").description == #""a/b""#)
		#expect(JSONValue.string("q\"").description == #""q\"""#)
		#expect(json(["b": 1, "a": [true, nil]]).description == #"{"a":[true,null],"b":1}"#)
		#expect("\(json([1, "x"]))" == #"[1,"x"]"#)
		#expect(JSONValue.int(9_007_199_254_740_993).description == "9007199254740993")
	}

	@Test func descriptionParsesBack() throws {
		let value: JSONValue = ["k": [1, 2.5, "s", nil, true, ["n": -1]]]
		#expect(try JSONValue(parsing: value.description) == value)
	}
}
