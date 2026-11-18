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
	/// cannot see that order, so a switchback with more than one cluster source decoded that way
	/// serves only an ineligible control.
	public static func decode(from json: Data, decoder: JSONDecoder = JSONDecoder()) throws -> ContextData {
		decoder.userInfo[SwitchbackClusterOrder.userInfoKey] = SwitchbackClusterOrder(json: json)
		return try decoder.decode(ContextData.self, from: json)
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
