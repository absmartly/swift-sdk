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

	/// Decodes the body of `GET /context`, keeping each experiment's `switchbackClusters` in its JSON
	/// key order, which decides which unit serves a switchback. Use it for context data you fetch
	/// yourself: `JSONDecoder` cannot see that order, so a switchback with more than one linked unit
	/// type decoded that way has no cluster map and cannot draw: it serves control, though an
	/// override still applies (and logs an error).
	public init(json: Data) throws(ABsmartlyError) {
		let decoder = JSONDecoder()
		decoder.userInfo[SwitchbackClusterOrder.userInfoKey] = SwitchbackClusterOrder(json: json)
		do {
			self = try decoder.decode(ContextData.self, from: json)
		} catch {
			throw .decoding(error.safeDescription)
		}
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
	/// `"switchback"` for a switchback experiment; `"unit"` or nil for a unit experiment. Holdouts never
	/// apply to a switchback.
	public var randomizationType: String?
	/// A switchback's linked unit types and the attribute path holding each one's cluster value, in
	/// serving order: the first unit, in this order, whose path gives a value serves the experiment.
	/// Nil when the payload has none, or has several whose order is not known (see
	/// `ContextData(json:)`).
	public var switchbackClusters: [SwitchbackCluster]?
	/// The cluster values a switchback serves; nil or empty serves every value.
	public var switchbackClusterValues: [String]?
	/// The start of a switchback's period grid, epoch milliseconds (hour aligned).
	public var switchbackStartAt: Int64?
	/// The length of a switchback period, milliseconds.
	public var switchbackPeriodMs: Int64?
	/// Analysis-only switchback windows and design fields; the SDK serves without them, except
	/// `switchbackDesignType`, a change of which starts a new switchback schedule.
	public var switchbackCarryoverDurationMs: Int64?
	public var switchbackBurnInDurationMs: Int64?
	public var switchbackBurnOutDurationMs: Int64?
	public var switchbackDesignType: String?
	public var switchbackEstimand: String?

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
		case switchbackClusters, switchbackClusterValues, switchbackStartAt, switchbackPeriodMs
		case switchbackCarryoverDurationMs, switchbackBurnInDurationMs, switchbackBurnOutDurationMs
		case switchbackDesignType, switchbackEstimand
	}

	#if DEBUG
		@TaskLocal static var classificationWorkCount: Locked<Int>?
	#endif

	var isSwitchback: Bool {
		#if DEBUG
			Self.classificationWorkCount?.withLock { $0 += 1 }
		#endif
		return randomizationType == "switchback"
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

		// A malformed id is dropped on its own.
		holdoutIds = (try? container.decodeIfPresent([Lenient<Int>].self, forKey: .holdoutIds))?.compactMap(\.value)
		holdoutType = try? container.decodeIfPresent(String.self, forKey: .holdoutType)
		randomizationType = try? container.decodeIfPresent(String.self, forKey: .randomizationType)

		// A switchback field of the wrong shape is nil on its own, as 2.1.0 ignored these fields.
		switchbackStartAt = try? container.decodeIfPresent(Int64.self, forKey: .switchbackStartAt)
		switchbackPeriodMs = try? container.decodeIfPresent(Int64.self, forKey: .switchbackPeriodMs)
		switchbackCarryoverDurationMs = try? container.decodeIfPresent(
			Int64.self, forKey: .switchbackCarryoverDurationMs)
		switchbackBurnInDurationMs = try? container.decodeIfPresent(Int64.self, forKey: .switchbackBurnInDurationMs)
		switchbackBurnOutDurationMs = try? container.decodeIfPresent(Int64.self, forKey: .switchbackBurnOutDurationMs)
		switchbackDesignType = try? container.decodeIfPresent(String.self, forKey: .switchbackDesignType)
		switchbackEstimand = try? container.decodeIfPresent(String.self, forKey: .switchbackEstimand)

		// An allow-list that is not an array of strings cannot be applied, so the cluster map is dropped
		// with it: the switchback then serves only control, never every value.
		if container.contains(.switchbackClusterValues),
			(try? container.decodeNil(forKey: .switchbackClusterValues)) == false
		{
			switchbackClusterValues = try? container.decode([String].self, forKey: .switchbackClusterValues)
			if switchbackClusterValues == nil {
				Log.error(
					"Ignoring switchbackClusters: switchbackClusterValues is not an array of strings.",
					detail: "Experiment '\(name)'.")
				return
			}
		}
		switchbackClusters = Self.decodeSwitchbackClusters(container, decoder: decoder, name: name)
	}

	// The wire form is an object read in its JSON key order; `encode(to:)` writes an array of
	// `SwitchbackCluster`s, which keeps the order through any encoder. Nil when the field is absent,
	// null or neither shape, or when the order of a map with several entries is not known.
	private static func decodeSwitchbackClusters(
		_ container: KeyedDecodingContainer<CodingKeys>, decoder: Decoder, name: String
	) -> [SwitchbackCluster]? {
		let key = CodingKeys.switchbackClusters
		guard container.contains(key), (try? container.decodeNil(forKey: key)) == false else {
			return nil
		}
		if let clusters = try? container.decode([SwitchbackCluster].self, forKey: key) {
			// Unit types are compared by their bytes, as the SDK serves them.
			var unique: [SwitchbackCluster] = []
			for cluster in clusters
			where !unique.contains(where: { SwitchbackStrings.equal($0.unitType, cluster.unitType) }) {
				unique.append(cluster)
			}
			return unique
		}
		guard let object = try? container.nestedContainer(keyedBy: AnyKey.self, forKey: key) else {
			return nil
		}
		// Keys and paths come from the ordered reader, with their exact bytes: Foundation's keyed
		// container merges canonically equivalent keys and has no defined key order.
		if let entries = (decoder.userInfo[SwitchbackClusterOrder.userInfoKey] as? SwitchbackClusterOrder)?
			.entries(at: decoder.codingPath)
		{
			return entries.map { SwitchbackCluster(unitType: $0.unitType, attributePath: $0.attributePath) }
		}
		var paths: [String: String?] = [:]
		for entry in object.allKeys where paths[entry.stringValue] == nil {
			paths[entry.stringValue] = .some(try? object.decode(String.self, forKey: entry))
		}
		if paths.count < 2 {
			return paths.map { SwitchbackCluster(unitType: $0.key, attributePath: $0.value) }
		}
		Log.error(
			"Ignoring switchbackClusters: the order of its entries is not known. Decode the context data with ContextData(json:).",
			detail: "Experiment '\(name)'.")
		return nil
	}
}

/// One `Experiment.switchbackClusters` entry: a linked unit type and the attribute path holding its
/// cluster value.
public struct SwitchbackCluster: Sendable, Equatable, Codable {
	public var unitType: String
	/// The attribute path, `/`-separated; nil when the payload's value is not a string, which makes
	/// the experiment's cluster map unreadable.
	public var attributePath: String?

	public init(unitType: String, attributePath: String?) {
		self.unitType = unitType
		self.attributePath = attributePath
	}
}

private struct AnyKey: CodingKey {
	let stringValue: String
	var intValue: Int? { nil }

	init?(stringValue: String) {
		self.stringValue = stringValue
	}

	init?(intValue: Int) {
		return nil
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
