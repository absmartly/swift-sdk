import Foundation

/// The experiments served for an application and environment: the body of `GET /context`.
///
/// Decoding is lenient, as in 1.x: unknown fields are ignored at every level, and in an experiment
/// every field except `name` falls back to its default when it is missing or has the wrong type.
public struct ContextData: Sendable, Equatable, Codable {
	public var experiments: [Experiment]
	/// The holdouts that experiments reference through `Experiment.holdoutIds`; nil when the payload
	/// has none.
	public var holdouts: [Experiment]?

	public init(experiments: [Experiment] = []) {
		self.experiments = experiments
	}

	public init(experiments: [Experiment], holdouts: [Experiment]?) {
		self.experiments = experiments
		self.holdouts = holdouts
	}

	private enum CodingKeys: String, CodingKey {
		case experiments, holdouts
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		experiments = try container.decode([Experiment].self, forKey: .experiments)
		// Lenient: a malformed holdout entry (or a malformed `holdouts` field) is dropped on its own, so
		// it only uncovers the experiments that reference it.
		holdouts = (try? container.decodeIfPresent([Lenient<Experiment>].self, forKey: .holdouts))?
			.compactMap(\.value)
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
	/// The ids of the `ContextData.holdouts` entries covering this experiment.
	public var holdoutIds: [Int]?
	/// On a `ContextData.holdouts` entry, the holdout's type (`"full"`, `"all_full_on"`).
	/// Informational: the SDK derives a holdout's arms from its `split`.
	public var holdoutType: String?
	// Holdouts never apply to an experiment whose randomization type is "switchback". Internal until
	// the SDK serves switchbacks.
	var randomizationType: String?

	public init(
		id: Int, name: String, unitType: String?, iteration: Int = 1, seedHi: Int = 0, seedLo: Int = 0,
		split: [Double], trafficSeedHi: Int = 0, trafficSeedLo: Int = 0, trafficSplit: [Double] = [0, 1],
		fullOnVariant: Int = 0, applications: [ExperimentApplication] = [], variants: [ExperimentVariant],
		audienceStrict: Bool = false, audience: String? = nil, customFieldValues: [CustomFieldValue] = [],
		assignmentRules: String? = nil
	) {
		self.init(
			id: id, name: name, unitType: unitType, iteration: iteration, seedHi: seedHi, seedLo: seedLo, split: split,
			trafficSeedHi: trafficSeedHi, trafficSeedLo: trafficSeedLo, trafficSplit: trafficSplit,
			fullOnVariant: fullOnVariant, applications: applications, variants: variants,
			audienceStrict: audienceStrict,
			audience: audience, customFieldValues: customFieldValues, assignmentRules: assignmentRules, holdoutIds: nil,
			holdoutType: nil)
	}

	/// An experiment or a holdout entry with its holdout fields. The 2.0.0 initializer above is kept
	/// unchanged, so code built against 2.0.0 keeps resolving it.
	public init(
		id: Int, name: String, unitType: String?, iteration: Int = 1, seedHi: Int = 0, seedLo: Int = 0,
		split: [Double], trafficSeedHi: Int = 0, trafficSeedLo: Int = 0, trafficSplit: [Double] = [0, 1],
		fullOnVariant: Int = 0, applications: [ExperimentApplication] = [], variants: [ExperimentVariant],
		audienceStrict: Bool = false, audience: String? = nil, customFieldValues: [CustomFieldValue] = [],
		assignmentRules: String? = nil, holdoutIds: [Int]?, holdoutType: String?
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
		self.holdoutIds = holdoutIds
		self.holdoutType = holdoutType
	}

	private enum CodingKeys: String, CodingKey {
		case id, name, unitType, iteration, seedHi, seedLo, split, trafficSeedHi, trafficSeedLo, trafficSplit
		case fullOnVariant, applications, variants, audienceStrict, audience, customFieldValues, assignmentRules
		case holdoutIds, holdoutType, randomizationType
	}

	var isSwitchback: Bool { randomizationType == "switchback" }

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

		// A malformed id is dropped on its own.
		holdoutIds = (try? container.decodeIfPresent([Lenient<Int>].self, forKey: .holdoutIds))?.compactMap(\.value)
		holdoutType = try? container.decodeIfPresent(String.self, forKey: .holdoutType)
		randomizationType = try? container.decodeIfPresent(String.self, forKey: .randomizationType)
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

/// Decodes an array element, or nil when it does not decode, so one bad element does not fail the array.
private struct Lenient<Element: Decodable>: Decodable {
	let value: Element?

	init(from decoder: Decoder) throws {
		value = try? Element(from: decoder)
	}
}
