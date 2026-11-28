import Foundation

public final class ContextData: Codable {
	public let experiments: [Experiment]
	/// Holdouts that experiments reference through `Experiment.holdoutIds`; nil when the payload has none.
	public let holdouts: [Experiment]?

	enum CodingKeys: String, CodingKey {
		case experiments
		case holdouts
	}

	public init() {
		experiments = []
		holdouts = nil
	}

	public init(experiments: [Experiment]) {
		self.experiments = experiments
		self.holdouts = nil
	}

	public init(experiments: [Experiment], holdouts: [Experiment]? = nil) {
		self.experiments = experiments
		self.holdouts = holdouts
	}

	/// Decodes context data from its JSON, keeping the order of each experiment's `switchbackClusters`,
	/// which decides which unit serves a switchback. `JSONDecoder().decode(ContextData.self, from:)`
	/// cannot verify exact source keys or order, so a switchback with multiple sources or a non-ASCII source key decoded that way
	/// serves only an ineligible control.
	public static func decode(from json: Data, decoder: JSONDecoder = JSONDecoder()) throws -> ContextData {
		guard SwitchbackClusterOrder.mayHaveSwitchbackFields(json) else {
			return try decoder.decode(ContextData.self, from: json)
		}
		// Never mutate the caller's decoder: it may be shared across threads. A private decoder keeps
		// the caller's decoding configuration and adds only this payload's raw switchback metadata.
		let ordered = JSONDecoder()
		ordered.dateDecodingStrategy = decoder.dateDecodingStrategy
		ordered.dataDecodingStrategy = decoder.dataDecodingStrategy
		ordered.nonConformingFloatDecodingStrategy = decoder.nonConformingFloatDecodingStrategy
		ordered.keyDecodingStrategy = decoder.keyDecodingStrategy
		ordered.userInfo = decoder.userInfo
		#if canImport(Darwin)
		if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
			ordered.allowsJSON5 = decoder.allowsJSON5
			ordered.assumesTopLevelDictionary = decoder.assumesTopLevelDictionary
		}
		#endif
		ordered.userInfo[SwitchbackClusterOrder.userInfoKey] = SwitchbackClusterOrder(json: json)
		return try ordered.decode(ContextData.self, from: json)
	}

	public init(from decoder: Decoder) throws {
		do {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.experiments = try container.decode([Experiment].self, forKey: .experiments)
			// Lenient: a malformed holdout entry (or a malformed `holdouts` field) is dropped on its own, so
			// it only uncovers the experiments that reference it.
			self.holdouts = (try? container.decodeIfPresent([LenientElement<Experiment>].self, forKey: .holdouts))?
				.flatMap { $0.compactMap { $0.value } }
		} catch let error as DecodingError {
			throw error
		} catch {
			throw DecodingError.dataCorrupted(
				DecodingError.Context(
					codingPath: decoder.codingPath,
					debugDescription: "Failed to decode ContextData: \(error.safeLocalizedDescription)",
					underlyingError: error))
		}
	}
}

extension ContextData: Equatable {
	public static func == (lhs: ContextData, rhs: ContextData) -> Bool {
		lhs.experiments == rhs.experiments && lhs.holdouts == rhs.holdouts
	}
}
