import Foundation

public final class PublishEvent: Encodable, Equatable {
	public var hashed: Bool
	public var units: [Unit]
	public var publishedAt: Int64
	public var exposures: [Exposure]
	public var goals: [GoalAchievement]
	public var attributes: [Attribute]

	init(
		_ hashed: Bool = false, _ units: [Unit] = [], _ publishedAt: Int64 = 0, _ exposures: [Exposure] = [],
		_ goals: [GoalAchievement] = [], _ attributes: [Attribute] = []
	) {
		self.hashed = hashed
		self.units = units
		self.publishedAt = publishedAt
		self.exposures = exposures
		self.goals = goals
		self.attributes = attributes
	}

	enum CodingKeys: String, CodingKey {
		case hashed
		case units
		case publishedAt
		case exposures
		case goals
		case attributes
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(hashed, forKey: .hashed)

		if units.count > 0 {
			try container.encode(units, forKey: .units)
		}

		try container.encode(publishedAt, forKey: .publishedAt)

		if exposures.count > 0 {
			try container.encode(exposures, forKey: .exposures)
		}

		if goals.count > 0 {
			try container.encode(goals, forKey: .goals)
		}

		if attributes.count > 0 {
			try container.encode(attributes, forKey: .attributes)
		}
	}

	public static func == (lhs: PublishEvent, rhs: PublishEvent) -> Bool {
		return lhs.hashed == rhs.hashed && lhs.units == rhs.units && lhs.publishedAt == rhs.publishedAt
			&& lhs.exposures == rhs.exposures && lhs.goals == rhs.goals && lhs.attributes == rhs.attributes
	}
}
