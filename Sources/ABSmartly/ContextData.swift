import Foundation

public final class ContextData: Codable {
	public let experiments: [Experiment]

	enum CodingKeys: String, CodingKey {
		case experiments
	}

	public init() {
		experiments = []
	}

	public init(experiments: [Experiment]) {
		self.experiments = experiments
	}

	public init(from decoder: Decoder) throws {
		do {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.experiments = try container.decode([Experiment].self, forKey: .experiments)
		} catch let error as DecodingError {
			throw error
		} catch {
			throw DecodingError.dataCorrupted(
				DecodingError.Context(
					codingPath: decoder.codingPath,
					debugDescription: "Failed to decode ContextData: \(error.localizedDescription)",
					underlyingError: error))
		}
	}
}

extension ContextData: Equatable {
	public static func == (lhs: ContextData, rhs: ContextData) -> Bool {
		lhs.experiments == rhs.experiments
	}
}
