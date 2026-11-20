import Foundation

/// A JSON value: variable values, attributes, goal properties and custom fields.
///
/// Integers and floating-point numbers are separate cases so integers beyond 2^53 stay exact.
/// Everywhere the SDK compares numbers (audiences, assignment rules) both cases are numbers, and
/// `.int(1) == .double(1)` is `true`.
public enum JSONValue: Sendable {
	case null
	case bool(Bool)
	case int(Int64)
	case double(Double)
	case string(String)
	case array([JSONValue])
	case object([String: JSONValue])
}

// MARK: - Accessors

extension JSONValue {
	public var isNull: Bool {
		if case .null = self { return true }
		return false
	}

	public var boolValue: Bool? {
		if case .bool(let value) = self { return value }
		return nil
	}

	/// The string, or `nil` for any other case.
	public var stringValue: String? {
		if case .string(let value) = self { return value }
		return nil
	}

	/// The number as a `Double`, for both numeric cases.
	public var doubleValue: Double? {
		switch self {
		case .int(let value): return Double(value)
		case .double(let value): return value
		default: return nil
		}
	}

	/// The number as an `Int` when it is integral and in range.
	public var intValue: Int? {
		switch self {
		case .int(let value): return Int(exactly: value)
		case .double(let value): return Int(exactly: value)
		default: return nil
		}
	}

	public var arrayValue: [JSONValue]? {
		if case .array(let value) = self { return value }
		return nil
	}

	public var objectValue: [String: JSONValue]? {
		if case .object(let value) = self { return value }
		return nil
	}

	var isNumber: Bool {
		switch self {
		case .int, .double: return true
		default: return false
		}
	}

	/// The member named `key` of an object, else `nil`.
	public subscript(key: String) -> JSONValue? {
		if case .object(let object) = self { return object[key] }
		return nil
	}

	/// The element at `index` of an array, else `nil` (also when out of bounds).
	public subscript(index: Int) -> JSONValue? {
		if case .array(let array) = self, array.indices.contains(index) { return array[index] }
		return nil
	}
}

// MARK: - Equality

extension JSONValue: Hashable {
	public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
		switch (lhs, rhs) {
		case (.null, .null): return true
		case (.bool(let l), .bool(let r)): return l == r
		case (.int(let l), .int(let r)): return l == r
		case (.int(let l), .double(let r)): return Double(exactly: l) == r
		case (.double(let l), .int(let r)): return Double(exactly: r) == l
		case (.double(let l), .double(let r)): return l == r
		case (.string(let l), .string(let r)): return l == r
		case (.array(let l), .array(let r)): return l == r
		case (.object(let l), .object(let r)): return l == r
		default: return false
		}
	}

	public func hash(into hasher: inout Hasher) {
		switch self {
		case .null:
			hasher.combine(0)
		case .bool(let value):
			hasher.combine(1)
			hasher.combine(value)
		case .int(let value):
			// Numbers that compare equal must hash equal across the two cases.
			hasher.combine(2)
			if let double = Double(exactly: value) {
				hasher.combine(double)
			} else {
				hasher.combine(value)
			}
		case .double(let value):
			hasher.combine(2)
			hasher.combine(value)
		case .string(let value):
			hasher.combine(3)
			hasher.combine(value)
		case .array(let value):
			hasher.combine(4)
			hasher.combine(value)
		case .object(let value):
			hasher.combine(5)
			hasher.combine(value)
		}
	}
}

// MARK: - Codable

extension JSONValue: Codable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode(Int64.self) {
			self = .int(value)
		} else if let value = try? container.decode(Double.self) {
			self = .double(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode([JSONValue].self) {
			self = .array(value)
		} else if let value = try? container.decode([String: JSONValue].self) {
			self = .object(value)
		} else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .null: try container.encodeNil()
		case .bool(let value): try container.encode(value)
		case .int(let value): try container.encode(value)
		case .double(let value): try container.encode(value)
		case .string(let value): try container.encode(value)
		case .array(let value): try container.encode(value)
		case .object(let value): try container.encode(value)
		}
	}
}

extension JSONValue {
	/// Parses JSON text (any value, not only objects and arrays).
	///
	/// Uses `JSONSerialization`, the parser 1.5.0 used (through SwiftyJSON) for audiences,
	/// assignment rules, variant configs and JSON custom fields, so numbers come out as they did
	/// there: a literal with a fraction or exponent is a double (`-0.0` keeps its sign, while `-0` is
	/// the integer 0), and an integer outside Int64 or one Foundation reads as a decimal is a double.
	public init(parsing text: String) throws(ABsmartlyError) {
		let object: Any
		do {
			object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
		} catch {
			throw .decoding(error.safeDescription)
		}
		self = JSONValue(foundationObject: object)
	}

	private init(foundationObject object: Any) {
		switch object {
		case let number as NSNumber:
			self = JSONValue(foundationNumber: number)
		case let string as String:
			self = .string(string)
		case let array as [Any]:
			self = .array(array.map(JSONValue.init(foundationObject:)))
		case let dictionary as [String: Any]:
			self = .object(dictionary.mapValues(JSONValue.init(foundationObject:)))
		default:
			self = .null
		}
	}

	private static let trueNumber = NSNumber(value: true)
	private static let falseNumber = NSNumber(value: false)

	// Booleans are told apart as SwiftyJSON does: equal to true or false and of the same ObjC type.
	// Signed integer types are integers; unsigned 64-bit only within Int64. Everything else
	// (doubles, NSDecimalNumber) is a double, as SwiftyJSON's number is read through `doubleValue`.
	init(foundationNumber number: NSNumber) {
		let type = String(cString: number.objCType)
		if (number.compare(Self.trueNumber) == .orderedSame && type == String(cString: Self.trueNumber.objCType))
			|| (number.compare(Self.falseNumber) == .orderedSame && type == String(cString: Self.falseNumber.objCType))
		{
			self = .bool(number.boolValue)
			return
		}
		if !(number is NSDecimalNumber) {
			switch type {
			case "c", "s", "i", "l", "q", "C", "S", "I":
				self = .int(number.int64Value)
				return
			case "L", "Q":
				if let value = Int64(exactly: number.uint64Value) {
					self = .int(value)
					return
				}
			default:
				break
			}
		}
		self = .double(number.doubleValue)
	}
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral {
	public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
	public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
	public init(integerLiteral value: Int64) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
	public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
	public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
	public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
	public init(dictionaryLiteral elements: (String, JSONValue)...) {
		self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
	}
}

extension JSONValue: CustomStringConvertible {
	/// Compact JSON text, keys sorted.
	public var description: String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		guard let data = try? encoder.encode(self) else { return "null" }
		return String(decoding: data, as: UTF8.self)
	}
}

// MARK: - Conversions

/// A type that converts to a `JSONValue`, so it can be passed where the SDK takes one
/// (`setAttribute(_:to:)`, `variable(_:default:)`).
public protocol JSONValueConvertible: Sendable {
	var jsonValue: JSONValue { get }
}

extension JSONValue: JSONValueConvertible {
	public var jsonValue: JSONValue { self }
}

extension String: JSONValueConvertible {
	public var jsonValue: JSONValue { .string(self) }
}

extension Substring: JSONValueConvertible {
	public var jsonValue: JSONValue { .string(String(self)) }
}

extension Bool: JSONValueConvertible {
	public var jsonValue: JSONValue { .bool(self) }
}

extension Int: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(Int64(self)) }
}

extension Int8: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(Int64(self)) }
}

extension Int16: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(Int64(self)) }
}

extension Int32: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(Int64(self)) }
}

extension Int64: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(self) }
}

extension UInt: JSONValueConvertible {
	public var jsonValue: JSONValue { Int64(exactly: self).map(JSONValue.int) ?? .double(Double(self)) }
}

extension UInt8: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(Int64(self)) }
}

extension UInt16: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(Int64(self)) }
}

extension UInt32: JSONValueConvertible {
	public var jsonValue: JSONValue { .int(Int64(self)) }
}

extension UInt64: JSONValueConvertible {
	public var jsonValue: JSONValue { Int64(exactly: self).map(JSONValue.int) ?? .double(Double(self)) }
}

extension Double: JSONValueConvertible {
	public var jsonValue: JSONValue { .double(self) }
}

extension Float: JSONValueConvertible {
	public var jsonValue: JSONValue { .double(Double(self)) }
}

extension Optional: JSONValueConvertible where Wrapped: JSONValueConvertible {
	public var jsonValue: JSONValue { self?.jsonValue ?? .null }
}

extension Array: JSONValueConvertible where Element: JSONValueConvertible {
	public var jsonValue: JSONValue { .array(map(\.jsonValue)) }
}

extension Dictionary: JSONValueConvertible where Key == String, Value: JSONValueConvertible {
	public var jsonValue: JSONValue { .object(mapValues(\.jsonValue)) }
}
