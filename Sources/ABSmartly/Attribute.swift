import Foundation

public struct Attribute: Encodable, Equatable {
	public let name: String

	public let value: JSON
	public let setAt: Int64

	init(_ name: String, value: JSON, setAt: Int64) {
		self.name = name
		self.value = value
		self.setAt = setAt
	}

	enum CodingKeys: String, CodingKey {
		case name
		case value
		case setAt
	}

	public static func == (lhs: Attribute, rhs: Attribute) -> Bool {
		return lhs.name == rhs.name && lhs.setAt == rhs.setAt && lhs.value == rhs.value
	}
}
