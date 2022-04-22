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
		if let container = try? decoder.container(keyedBy: CodingKeys.self) {
			if let experiments = try? container.decode([Experiment].self, forKey: .experiments) {
				self.experiments = experiments
				return
			}
		}

		throw DecodingError.dataCorrupted(
			DecodingError.Context(
				codingPath: [], debugDescription: "Experiments array couldn't be decoded from this data"))
	}
}

extension ContextData: Equatable {
	public static func == (lhs: ContextData, rhs: ContextData) -> Bool {
		lhs.experiments == rhs.experiments
	}
}
