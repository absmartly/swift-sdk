import Foundation

public struct GoalAchievement: Encodable, Equatable {
	let name: String
	let achievedAt: Int64
	let properties: [String: JSON]?

	public init(_ name: String, achievedAt: Int64, properties: [String: JSON]?) {
		self.name = name
		self.achievedAt = achievedAt
		self.properties = properties
	}

	enum CodingKeys: String, CodingKey {
		case name
		case achievedAt
		case properties
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encode(achievedAt, forKey: .achievedAt)

		switch properties {
		case .some(let value): try container.encode(value, forKey: .properties)
		case .none: try container.encodeNil(forKey: .properties)
		}
	}

	public static func == (lhs: GoalAchievement, rhs: GoalAchievement) -> Bool {
		return lhs.name == rhs.name && lhs.achievedAt == rhs.achievedAt && lhs.properties == rhs.properties
	}
}
