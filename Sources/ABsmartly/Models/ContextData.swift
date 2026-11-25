import Foundation

/// The experiments served for an application and environment: the body of `GET /context`.
///
/// Decoding is lenient, as in 1.x: unknown fields are ignored at every level, and in an experiment
/// every field except `name` falls back to its default when it is missing or has the wrong type.
public struct ContextData: Sendable, Equatable, Codable {
	public var experiments: [Experiment]

	public init(experiments: [Experiment] = []) {
		self.experiments = experiments
	}
}

/// One experiment in `ContextData`.
public struct Experiment: Sendable, Equatable, Codable {
	public var id: Int
	public var name: String
	public var unitType: String?
	public var iteration: Int
	public var seedHi: Int
	public var seedLo: Int
	public var split: [Double]
	public var trafficSeedHi: Int
	public var trafficSeedLo: Int
	public var trafficSplit: [Double]
	public var fullOnVariant: Int
	public var applications: [ExperimentApplication]
	public var variants: [ExperimentVariant]
	public var audienceStrict: Bool
	/// The audience filter, a JSON string of the form `{"filter": ...}`.
	public var audience: String?
	public var customFieldValues: [CustomFieldValue]
	/// The assignment rules, a JSON string of the form `{"rules": [...]}`.
	public var assignmentRules: String?

	public init(
		id: Int, name: String, unitType: String?, iteration: Int = 1, seedHi: Int = 0, seedLo: Int = 0,
		split: [Double], trafficSeedHi: Int = 0, trafficSeedLo: Int = 0, trafficSplit: [Double] = [0, 1],
		fullOnVariant: Int = 0, applications: [ExperimentApplication] = [], variants: [ExperimentVariant],
		audienceStrict: Bool = false, audience: String? = nil, customFieldValues: [CustomFieldValue] = [],
		assignmentRules: String? = nil
	) {
		self.id = id
		self.name = name
		self.unitType = unitType
		self.iteration = iteration
		self.seedHi = seedHi
		self.seedLo = seedLo
		self.split = split
		self.trafficSeedHi = trafficSeedHi
		self.trafficSeedLo = trafficSeedLo
		self.trafficSplit = trafficSplit
		self.fullOnVariant = fullOnVariant
		self.applications = applications
		self.variants = variants
		self.audienceStrict = audienceStrict
		self.audience = audience
		self.customFieldValues = customFieldValues
		self.assignmentRules = assignmentRules
	}

	private enum CodingKeys: String, CodingKey {
		case id, name, unitType, iteration, seedHi, seedLo, split, trafficSeedHi, trafficSeedLo, trafficSplit
		case fullOnVariant, applications, variants, audienceStrict, audience, customFieldValues, assignmentRules
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		name = try container.decode(String.self, forKey: .name)

		id = (try? container.decodeIfPresent(Int.self, forKey: .id)) ?? 0
		unitType = try? container.decodeIfPresent(String.self, forKey: .unitType)
		iteration = (try? container.decodeIfPresent(Int.self, forKey: .iteration)) ?? 0
		seedHi = (try? container.decodeIfPresent(Int.self, forKey: .seedHi)) ?? 0
		seedLo = (try? container.decodeIfPresent(Int.self, forKey: .seedLo)) ?? 0
		split = (try? container.decodeIfPresent([Double].self, forKey: .split)) ?? []
		trafficSeedHi = (try? container.decodeIfPresent(Int.self, forKey: .trafficSeedHi)) ?? 0
		trafficSeedLo = (try? container.decodeIfPresent(Int.self, forKey: .trafficSeedLo)) ?? 0
		trafficSplit = (try? container.decodeIfPresent([Double].self, forKey: .trafficSplit)) ?? []
		fullOnVariant = (try? container.decodeIfPresent(Int.self, forKey: .fullOnVariant)) ?? 0
		audienceStrict = (try? container.decodeIfPresent(Bool.self, forKey: .audienceStrict)) ?? false
		audience = try? container.decodeIfPresent(String.self, forKey: .audience)
		applications = (try? container.decode([ExperimentApplication].self, forKey: .applications)) ?? []
		variants = (try? container.decode([ExperimentVariant].self, forKey: .variants)) ?? []
		customFieldValues = (try? container.decode([CustomFieldValue].self, forKey: .customFieldValues)) ?? []

		// Sent as a JSON string. Anything else (e.g. an inline object) only drops this experiment's rules.
		assignmentRules = try? container.decodeIfPresent(String.self, forKey: .assignmentRules)
		if assignmentRules == nil, container.contains(.assignmentRules),
			(try? container.decodeNil(forKey: .assignmentRules)) == false
		{
			Log.error("Ignoring assignmentRules: expected a JSON string.", detail: "Experiment '\(name)'.")
		}
	}
}

/// An application an experiment runs in.
public struct ExperimentApplication: Sendable, Equatable, Codable {
	public var name: String?

	public init(name: String?) {
		self.name = name
	}
}

/// A variant of an experiment. `config` is a JSON object string holding the variant's variables.
public struct ExperimentVariant: Sendable, Equatable, Codable {
	public var name: String?
	public var config: String?

	public init(name: String?, config: String?) {
		self.name = name
		self.config = config
	}
}

/// A custom field of an experiment, as served: `value` is text interpreted according to `type`
/// (`"json"`, `"number"`, `"boolean"`, else text). `Context.customFieldValue(_:in:)` returns it typed.
public struct CustomFieldValue: Sendable, Equatable, Codable {
	public var name: String?
	public var type: String?
	public var value: String?

	public init(name: String?, type: String?, value: String?) {
		self.name = name
		self.type = type
		self.value = value
	}
}
