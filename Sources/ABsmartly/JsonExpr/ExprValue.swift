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
	// Retain attribute storage; operators convert only the children they visit.
	case attributeArray([JSONValue])
	case attributeObject([String: JSONValue])
}

extension ExprValue {
	/// Test hook (debug builds): counts attribute nodes converted by the current task.
	@TaskLocal static var attributeConversionCount: Locked<Int>?

	init(_ json: JSONValue) {
		switch json {
		case .null: self = .null
		case .bool(let value): self = .bool(value)
		case .int(let value): self = .int(value)
		case .double(let value): self = .double(value)
		case .string(let value): self = .string(value)
		case .array(let value): self = .array(value.map { ExprValue($0) })
		case .object(let value): self = .object(value.mapValues { ExprValue($0) })
		}
	}

	init(attribute json: JSONValue) {
		// Debug only: a task-local lookup on every attribute read costs ~12% of an evaluation.
		#if DEBUG
			Self.attributeConversionCount?.withLock { $0 += 1 }
		#endif
		switch json {
		case .array(let value):
			self = .attributeArray(value)
		case .object(let value):
			self = .attributeObject(value)
		default:
			self.init(json)
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
		case let number as NSNumber:
			// Narrowed here rather than matched first: a failing `as NSDecimalNumber` is slow on Linux.
			if let decimal = number as? NSDecimalNumber {
				self = .decimal(decimal.decimalValue)
			} else {
				self = ExprValue(JSONValue(foundationNumber: number))
			}
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
		case .attributeArray(let value): return .array(value)
		case .attributeObject(let value): return .object(value)
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
		switch self {
		case .array(let value): return value
		case .attributeArray(let value): return value.map(ExprValue.init(attribute:))
		default: return nil
		}
	}

	var objectValue: [String: ExprValue]? {
		switch self {
		case .object(let value): return value
		case .attributeObject(let value): return value.mapValues(ExprValue.init(attribute:))
		default: return nil
		}
	}

	func allObjectValuesSatisfy(_ predicate: (String, ExprValue) -> Bool) -> Bool {
		switch self {
		case .object(let object): return object.allSatisfy { predicate($0.key, $0.value) }
		case .attributeObject(let object):
			return object.allSatisfy { predicate($0.key, ExprValue(attribute: $0.value)) }
		default: return false
		}
	}

	var arrayCount: Int? {
		switch self {
		case .array(let value): return value.count
		case .attributeArray(let value): return value.count
		default: return nil
		}
	}

	var objectCount: Int? {
		switch self {
		case .object(let value): return value.count
		case .attributeObject(let value): return value.count
		default: return nil
		}
	}

	subscript(key: String) -> ExprValue? {
		switch self {
		case .object(let object): return object[key]
		case .attributeObject(let object): return object[key].map(ExprValue.init(attribute:))
		default: return nil
		}
	}

	subscript(index: Int) -> ExprValue? {
		switch self {
		case .array(let array): return array.indices.contains(index) ? array[index] : nil
		case .attributeArray(let array): return array.indices.contains(index) ? ExprValue(attribute: array[index]) : nil
		default: return nil
		}
	}

	// SwiftyJSON's type names, used in 1.x's log messages.
	var typeName: String {
		switch self {
		case .null: return "null"
		case .bool: return "bool"
		case .int, .double, .decimal: return "number"
		case .string: return "string"
		case .array, .attributeArray: return "array"
		case .object, .attributeObject: return "dictionary"
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
		case (.attributeArray, _), (_, .attributeArray):
			guard let count = lhs.arrayCount, count == rhs.arrayCount else { return false }
			return (0..<count).allSatisfy { lhs[$0] == rhs[$0] }
		case (.attributeObject, _), (_, .attributeObject):
			guard let count = lhs.objectCount, count == rhs.objectCount else { return false }
			return lhs.allObjectValuesSatisfy { key, value in rhs[key].map { value == $0 } ?? false }
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
