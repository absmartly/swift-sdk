import Foundation

public struct CustomFieldValue: Codable, Equatable {
	public let name: String?
	public let type: String?
	public let value: String?

	init(_ name: String, _ type: String, _ value: String) {
		self.name = name
		self.type = type
		self.value = value
	}

	public static func == (lhs: CustomFieldValue, rhs: CustomFieldValue) -> Bool {
		return lhs.name == rhs.name && lhs.type == rhs.type && lhs.value == rhs.value
	}
}
