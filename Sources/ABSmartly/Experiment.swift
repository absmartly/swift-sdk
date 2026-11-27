import Foundation

public struct Experiment: Codable {
	public let id: Int
	public let name: String
	public let unitType: String?
	public let iteration: Int
	public let seedHi: Int
	public let seedLo: Int
	public let split: [Double]
	public let trafficSeedHi: Int
	public let trafficSeedLo: Int
	public let trafficSplit: [Double]
	public let fullOnVariant: Int
	public let applications: [Application]?
	public let variants: [ExperimentVariant]
	public let audienceStrict: Bool
	public let audience: String?
	public let customFieldValues: [CustomFieldValue]?
	/// The experiment's assignment rules, a JSON string of the form `{"rules": [...]}`.
	public let assignmentRules: String?
	/// Ids of the `ContextData.holdouts` entries that cover this experiment.
	public let holdoutIds: [Int]?
	/// The holdout's type (`"full"`, `"all_full_on"`) on a `ContextData.holdouts` entry. Informational:
	/// the SDK derives a holdout's arms from its `split`.
	public let holdoutType: String?
	/// `"switchback"` for a switchback experiment, `"unit"` or nil for a unit experiment.
	public let randomizationType: String?
	/// A switchback's linked unit types and the attribute path holding each one's cluster value, in the
	/// order served: the first unit, in this order, with a value serves the experiment. Nil when the
	/// payload has none, or when it has several and their order is not known (see `ContextData.decode(from:)`).
	public let switchbackClusters: [SwitchbackCluster]?
	/// Allowed cluster values; nil or empty allows every value.
	public let switchbackClusterValues: [String]?
	/// The switchback grid's start, epoch milliseconds.
	public let switchbackStartAt: Int64?
	public let switchbackPeriodMs: Int64?
	/// Analysis-only windows; the SDK does not use them.
	public let switchbackCarryoverDurationMs: Int64?
	public let switchbackBurnInDurationMs: Int64?
	public let switchbackBurnOutDurationMs: Int64?
	public let switchbackDesignType: String?
	public let switchbackEstimand: String?

	// Every field except `name` decodes leniently: a missing or wrong-typed
	// field falls back to its default instead of failing the whole context.
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

		applications = (try? container.decode([Application].self, forKey: .applications)) ?? []
		variants = (try? container.decode([ExperimentVariant].self, forKey: .variants)) ?? []
		customFieldValues = (try? container.decode([CustomFieldValue].self, forKey: .customFieldValues)) ?? []

		// Sent as a JSON string. Anything else (e.g. an inline object) only drops this experiment's rules.
		assignmentRules = try? container.decodeIfPresent(String.self, forKey: .assignmentRules)
		if assignmentRules == nil, container.contains(.assignmentRules),
			(try? container.decodeNil(forKey: .assignmentRules)) == false
		{
			Logger.error("Ignoring assignmentRules for experiment '\(name)': expected a JSON string.")
		}

		holdoutIds = (try? container.decodeIfPresent([LenientElement<Int>].self, forKey: .holdoutIds))?
			.flatMap { $0.compactMap { $0.value } }
		holdoutType = try? container.decodeIfPresent(String.self, forKey: .holdoutType)

		// Only switchback fields use raw last occurrences. In particular, do not re-decode legacy
		// fields: JSONDecoder's behavior and the caller's decoding strategies remain theirs.
		let fields = (decoder.userInfo[SwitchbackClusterOrder.userInfoKey] as? SwitchbackClusterOrder)?
			.fields(at: decoder.codingPath)
		func switchbackValue<T: Decodable>(_ type: T.Type, _ key: CodingKeys) throws -> T? {
			if let raw = fields?.values[key.stringValue] {
				// Wrapped in an array: Foundation before Swift 5.2 (iOS 13.3, macOS 10.15.3 and earlier)
				// rejects a bare top-level scalar.
				var wrapped = Data("[".utf8)
				wrapped.append(raw)
				wrapped.append(contentsOf: Array("]".utf8))
				return try JSONDecoder().decode([T?].self, from: wrapped).first ?? nil
			}
			return try container.decodeIfPresent(type, forKey: key)
		}

		randomizationType = try? switchbackValue(String.self, .randomizationType)
		switchbackStartAt = try? switchbackValue(Int64.self, .switchbackStartAt)
		switchbackPeriodMs = try? switchbackValue(Int64.self, .switchbackPeriodMs)
		switchbackCarryoverDurationMs = try? switchbackValue(Int64.self, .switchbackCarryoverDurationMs)
		switchbackBurnInDurationMs = try? switchbackValue(Int64.self, .switchbackBurnInDurationMs)
		switchbackBurnOutDurationMs = try? switchbackValue(Int64.self, .switchbackBurnOutDurationMs)
		switchbackDesignType = try? switchbackValue(String.self, .switchbackDesignType)
		switchbackEstimand = try? switchbackValue(String.self, .switchbackEstimand)

		// Scalar allow-list entries compare as text, as in Java and JavaScript. Null entries never
		// match. A non-array or nested value cannot be applied, so the cluster map is dropped with it.
		var clusterValues: [String]? = nil
		var clusterValuesReadable = true
		if fields?.values["switchbackClusterValues"] != nil {
			do {
				clusterValues = try switchbackValue([SwitchbackAllowedValue].self, .switchbackClusterValues)?
					.map { $0.text ?? "" }
			} catch {
				clusterValuesReadable = false
			}
		} else if container.contains(.switchbackClusterValues),
			(try? container.decodeNil(forKey: .switchbackClusterValues)) == false
		{
			clusterValues = (try? container.decode([SwitchbackAllowedValue].self, forKey: .switchbackClusterValues))?
				.map { $0.text ?? "" }
			clusterValuesReadable = clusterValues != nil
		}
		switchbackClusterValues = clusterValues
		if clusterValuesReadable {
			switchbackClusters = Experiment.decodeSwitchbackClusters(
				container, .switchbackClusters, decoder: decoder, name: name)
		} else {
			Logger.error("Ignoring switchbackClusters for experiment '\(name)': switchbackClusterValues is not an array of scalar values.")
			switchbackClusters = nil
		}
	}

	// The wire form is an object read in its JSON key order; `encode(to:)` writes an array of
	// `SwitchbackCluster`s, which keeps the order through any encoder. Nil when the field is absent or
	// null, or not one of those shapes.
	private static func decodeSwitchbackClusters<Key: CodingKey>(
		_ container: KeyedDecodingContainer<Key>, _ key: Key, decoder: Decoder, name: String
	) -> [SwitchbackCluster]? {
		if let field = (decoder.userInfo[SwitchbackClusterOrder.userInfoKey] as? SwitchbackClusterOrder)?
			.clusters(at: decoder.codingPath)
		{
			switch field {
			case .object(let entries):
				return entries.map { SwitchbackCluster(unitType: $0.unitType, attributePath: $0.path) }
			case .notAnObject: return nil
			case .arrayRepresentation: break
			}
		}
		guard container.contains(key), (try? container.decodeNil(forKey: key)) == false else {
			return nil
		}
		if let clusters = try? container.decode([SwitchbackCluster].self, forKey: key) {
			var unique: [SwitchbackCluster] = []
			for cluster in clusters where !unique.contains(where: { $0.unitType == cluster.unitType }) {
				unique.append(cluster)
			}
			return unique
		}
		guard let object = try? container.nestedContainer(keyedBy: DynamicKey.self, forKey: key) else {
			return nil
		}
		let paths = Dictionary(
			object.allKeys.map { ($0.stringValue, try? object.decode(String.self, forKey: $0)) },
			uniquingKeysWith: { first, _ in first })
		if paths.count < 2 {
			return paths.map { SwitchbackCluster(unitType: $0.key, attributePath: $0.value) }
		}
		Logger.error(
			"Ignoring switchbackClusters for experiment '\(name)': the order of its entries is not known. Decode the context data with ContextData.decode(from:).")
		return nil
	}
}

private struct SwitchbackAllowedValue: Decodable {
	let text: String?

	init(from decoder: Decoder) throws {
		let value = try decoder.singleValueContainer()
		if value.decodeNil() { text = nil }
		else if let string = try? value.decode(String.self) { text = string }
		else if let bool = try? value.decode(Bool.self) { text = bool ? "true" : "false" }
		else if let integer = try? value.decode(Int64.self) { text = String(integer) }
		else if let integer = try? value.decode(UInt64.self) { text = String(integer) }
		else { text = String(try value.decode(Double.self)) }
	}
}

private struct DynamicKey: CodingKey {
	let stringValue: String
	let intValue: Int? = nil

	init?(stringValue: String) {
		self.stringValue = stringValue
	}

	init?(intValue: Int) {
		return nil
	}
}

extension Experiment: Equatable {
	public static func == (lhs: Experiment, rhs: Experiment) -> Bool {
		return lhs.id == rhs.id && lhs.name == rhs.name && lhs.unitType == rhs.unitType
			&& lhs.iteration == rhs.iteration && lhs.seedHi == rhs.seedHi && lhs.seedLo == rhs.seedLo
			&& lhs.split == rhs.split && lhs.trafficSeedHi == rhs.trafficSeedHi
			&& lhs.trafficSeedLo == rhs.trafficSeedLo && lhs.trafficSplit == rhs.trafficSplit
			&& lhs.fullOnVariant == rhs.fullOnVariant && lhs.applications == rhs.applications
			&& lhs.variants == rhs.variants && lhs.customFieldValues == rhs.customFieldValues
			&& lhs.assignmentRules == rhs.assignmentRules && lhs.holdoutIds == rhs.holdoutIds
			&& lhs.holdoutType == rhs.holdoutType && lhs.randomizationType == rhs.randomizationType
			&& lhs.switchbackClusters == rhs.switchbackClusters
			&& lhs.switchbackClusterValues == rhs.switchbackClusterValues
			&& lhs.switchbackStartAt == rhs.switchbackStartAt && lhs.switchbackPeriodMs == rhs.switchbackPeriodMs
			&& lhs.switchbackCarryoverDurationMs == rhs.switchbackCarryoverDurationMs
			&& lhs.switchbackBurnInDurationMs == rhs.switchbackBurnInDurationMs
			&& lhs.switchbackBurnOutDurationMs == rhs.switchbackBurnOutDurationMs
			&& lhs.switchbackDesignType == rhs.switchbackDesignType && lhs.switchbackEstimand == rhs.switchbackEstimand
	}
}
