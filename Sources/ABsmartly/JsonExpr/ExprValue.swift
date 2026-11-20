import Foundation

/// A value inside an audience or assignment-rule expression: a `JSONValue` that also keeps a number
/// `JSONSerialization` parsed as a decimal (more digits than a double holds, or an integer outside
/// the 64-bit ranges), as 1.5.0's SwiftyJSON did. Rebuilding such a number from a double would make
/// `0.1234567890123456789` equal `0.1234567890123456788` inside arrays and objects, and change its
/// truthiness when it overflows Int64. Attributes stay `JSONValue` and convert when read.
enum ExprValue: Sendable {
	case null
	case bool(Bool)
	case int(Int64)
	case double(Double)
	// Boxed, so the enum stays as small as `JSONValue`.
	indirect case decimal(Decimal)
	case string(String)
	case array([ExprValue])
	case object([String: ExprValue])
}

extension ExprValue {
	init(_ json: JSONValue) {
		switch json {
		case .null: self = .null
		case .bool(let value): self = .bool(value)
		case .int(let value): self = .int(value)
		case .double(let value): self = .double(value)
		case .string(let value): self = .string(value)
		case .array(let value): self = .array(value.map(ExprValue.init))
		case .object(let value): self = .object(value.mapValues(ExprValue.init))
		}
	}

	/// Parses JSON text as `JSONValue(parsing:)` does, keeping decimals.
	init(parsing text: String) throws(ABsmartlyError) {
		let object: Any
		do {
			object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
		} catch {
			throw .decoding(error.safeDescription)
		}
		self = ExprValue(foundationObject: object)
	}

	private init(foundationObject object: Any) {
		switch object {
		case let number as NSDecimalNumber:
			self = .decimal(number.decimalValue)
		case let number as NSNumber:
			self = ExprValue(JSONValue(foundationNumber: number))
		case let string as String:
			self = .string(string)
		case let array as [Any]:
			self = .array(array.map(ExprValue.init(foundationObject:)))
		case let dictionary as [String: Any]:
			self = .object(dictionary.mapValues(ExprValue.init(foundationObject:)))
		default:
			self = .null
		}
	}

	/// The `JSONValue`, a decimal as its double.
	var jsonValue: JSONValue {
		switch self {
		case .null: return .null
		case .bool(let value): return .bool(value)
		case .int(let value): return .int(value)
		case .double(let value): return .double(value)
		case .decimal(let value): return .double(NSDecimalNumber(decimal: value).doubleValue)
		case .string(let value): return .string(value)
		case .array(let value): return .array(value.map(\.jsonValue))
		case .object(let value): return .object(value.mapValues(\.jsonValue))
		}
	}

	var isNull: Bool {
		if case .null = self { return true }
		return false
	}

	var stringValue: String? {
		if case .string(let value) = self { return value }
		return nil
	}

	/// The number as a `Double`, as 1.5.0 read every number (`NSNumber.doubleValue`).
	var doubleValue: Double? {
		switch self {
		case .int(let value): return Double(value)
		case .double(let value): return value
		case .decimal(let value): return NSDecimalNumber(decimal: value).doubleValue
		default: return nil
		}
	}

	var arrayValue: [ExprValue]? {
		if case .array(let value) = self { return value }
		return nil
	}

	var objectValue: [String: ExprValue]? {
		if case .object(let value) = self { return value }
		return nil
	}

	subscript(key: String) -> ExprValue? {
		if case .object(let object) = self { return object[key] }
		return nil
	}

	subscript(index: Int) -> ExprValue? {
		if case .array(let array) = self, array.indices.contains(index) { return array[index] }
		return nil
	}

	// SwiftyJSON's type names, used in 1.x's log messages.
	var typeName: String {
		switch self {
		case .null: return "null"
		case .bool: return "bool"
		case .int, .double, .decimal: return "number"
		case .string: return "string"
		case .array: return "array"
		case .object: return "dictionary"
		}
	}
}

extension ExprValue: Equatable {
	static func == (lhs: ExprValue, rhs: ExprValue) -> Bool {
		switch (lhs, rhs) {
		case (.decimal(let l), .decimal(let r)): return l == r
		case (.decimal, _), (_, .decimal): return false
		case (.array(let l), .array(let r)): return l == r
		case (.object(let l), .object(let r)): return l == r
		default: return lhs.jsonValue == rhs.jsonValue
		}
	}
}

extension ExprValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
	ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
	ExpressibleByDictionaryLiteral
{
	init(nilLiteral: ()) { self = .null }
	init(booleanLiteral value: Bool) { self = .bool(value) }
	init(integerLiteral value: Int64) { self = .int(value) }
	init(floatLiteral value: Double) { self = .double(value) }
	init(stringLiteral value: String) { self = .string(value) }
	init(arrayLiteral elements: ExprValue...) { self = .array(elements) }
	init(dictionaryLiteral elements: (String, ExprValue)...) {
		self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
	}
}

extension ExprValue: CustomStringConvertible {
	var description: String {
		if case .decimal(let value) = self { return NSDecimalNumber(decimal: value).description }
		return jsonValue.description
	}
}
