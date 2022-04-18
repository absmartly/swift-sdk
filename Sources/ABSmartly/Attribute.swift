import Foundation

class Attribute: Encodable, Equatable {
	let name: String

	let value: Any?
	let setAt: Int64

	init(_ name: String, value: Any?, setAt: Int64) {
		self.name = name
		self.value = value
		self.setAt = setAt
	}

	enum CodingKeys: String, CodingKey {
		case name
		case value
		case setAt
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)

		switch value {
		case let value as Int: try container.encode(value, forKey: .value)
		case let value as Int8: try container.encode(value, forKey: .value)
		case let value as Int16: try container.encode(value, forKey: .value)
		case let value as Int32: try container.encode(value, forKey: .value)
		case let value as Int64: try container.encode(value, forKey: .value)
		case let value as UInt: try container.encode(value, forKey: .value)
		case let value as UInt8: try container.encode(value, forKey: .value)
		case let value as UInt16: try container.encode(value, forKey: .value)
		case let value as UInt32: try container.encode(value, forKey: .value)
		case let value as UInt64: try container.encode(value, forKey: .value)
		case let value as Float: try container.encode(value, forKey: .value)
		case let value as Double: try container.encode(value, forKey: .value)
		case let value as Bool: try container.encode(value, forKey: .value)
		case let value as String: try container.encode(value, forKey: .value)
		case nil: break
		default:
			Logger.error("Unencodable attribute value: \(String(describing: value ?? nil))")
		}
		try container.encode(setAt, forKey: .setAt)
	}

	public static func == (lhs: Attribute, rhs: Attribute) -> Bool {
		if lhs.name != rhs.name || lhs.setAt != rhs.setAt {
			return false
		}

		do {
			let l = try lhs.toJSON()
			let r = try rhs.toJSON()
			return l == r
		} catch {
			return false
		}
	}

	public func toJSON() throws -> String {
		let encoder = JSONEncoder()
		let data = try encoder.encode(self)
		return String(data: data, encoding: .utf8) ?? ""
	}
}
