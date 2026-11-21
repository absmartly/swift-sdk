import Foundation

/// An exposure: the first time a treatment or a variable of an experiment was read for this context.
public struct Exposure: Sendable, Equatable, Encodable {
	public var id: Int
	public var name: String
	public var unit: String?
	public var variant: Int
	public var exposedAt: Int64
	public var assigned: Bool
	public var eligible: Bool
	public var overridden: Bool
	public var fullOn: Bool
	public var custom: Bool
	public var audienceMismatch: Bool
	/// The variant came from an assignment rule; the collector keeps it out of analysis.
	public var ruleOverride: Bool

	public init(
		id: Int, name: String, unit: String?, variant: Int, exposedAt: Int64, assigned: Bool, eligible: Bool,
		overridden: Bool, fullOn: Bool, custom: Bool, audienceMismatch: Bool, ruleOverride: Bool
	) {
		self.id = id
		self.name = name
		self.unit = unit
		self.variant = variant
		self.exposedAt = exposedAt
		self.assigned = assigned
		self.eligible = eligible
		self.overridden = overridden
		self.fullOn = fullOn
		self.custom = custom
		self.audienceMismatch = audienceMismatch
		self.ruleOverride = ruleOverride
	}
}

/// A goal achievement recorded by `Context.track(_:properties:)`.
public struct Goal: Sendable, Equatable, Encodable {
	public var name: String
	public var achievedAt: Int64
	public var properties: [String: JSONValue]?

	public init(name: String, achievedAt: Int64, properties: [String: JSONValue]?) {
		self.name = name
		self.achievedAt = achievedAt
		self.properties = properties
	}

	private enum CodingKeys: String, CodingKey {
		case name, achievedAt, properties
	}

	// `properties` is always present: `null` when there are none.
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encode(achievedAt, forKey: .achievedAt)
		if let properties {
			try container.encode(properties, forKey: .properties)
		} else {
			try container.encodeNil(forKey: .properties)
		}
	}
}

/// The body of a publish (`PUT /context`): the context's hashed units, its attribute history, and
/// the exposures and goals queued since the last publish.
public struct PublishEvent: Sendable, Equatable, Encodable {
	/// A unit type with the hash of its UID.
	public struct Unit: Sendable, Equatable, Codable {
		public var type: String
		public var uid: String

		public init(type: String, uid: String) {
			self.type = type
			self.uid = uid
		}
	}

	/// An attribute as it was set, with the time it was set.
	public struct Attribute: Sendable, Equatable, Encodable {
		public var name: String
		public var value: JSONValue
		public var setAt: Int64

		public init(name: String, value: JSONValue, setAt: Int64) {
			self.name = name
			self.value = value
			self.setAt = setAt
		}
	}

	public var hashed: Bool
	public var units: [Unit]
	public var publishedAt: Int64
	public var exposures: [Exposure]
	public var goals: [Goal]
	public var attributes: [Attribute]

	public init(
		hashed: Bool = true, units: [Unit], publishedAt: Int64, exposures: [Exposure], goals: [Goal],
		attributes: [Attribute]
	) {
		self.hashed = hashed
		self.units = units
		self.publishedAt = publishedAt
		self.exposures = exposures
		self.goals = goals
		self.attributes = attributes
	}

	private enum CodingKeys: String, CodingKey {
		case hashed, units, publishedAt, exposures, goals, attributes
	}

	// Empty lists are left out, as in 1.x.
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(hashed, forKey: .hashed)
		if !units.isEmpty {
			try container.encode(units, forKey: .units)
		}
		try container.encode(publishedAt, forKey: .publishedAt)
		if !exposures.isEmpty {
			try container.encode(exposures, forKey: .exposures)
		}
		if !goals.isEmpty {
			try container.encode(goals, forKey: .goals)
		}
		if !attributes.isEmpty {
			try container.encode(attributes, forKey: .attributes)
		}
	}
}
