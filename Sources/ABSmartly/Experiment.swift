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

	public init(from decoder: Decoder) throws {
		guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
			throw DecodingError.dataCorrupted(
				DecodingError.Context(codingPath: [], debugDescription: "Experiment couldn't be decoded from this data")
			)
		}

		self.id = (try? container.decodeIfPresent(Int.self, forKey: .id)) ?? 0

		do {
			self.name = try container.decode(String.self, forKey: .name)
		} catch {
			throw error
		}

		self.unitType = (try? container.decodeIfPresent(String.self, forKey: .unitType)) ?? nil
		self.iteration = (try? container.decodeIfPresent(Int.self, forKey: .iteration)) ?? 0
		self.seedHi = (try? container.decodeIfPresent(Int.self, forKey: .seedHi)) ?? 0
		self.seedLo = (try? container.decodeIfPresent(Int.self, forKey: .seedLo)) ?? 0

		self.split = (try? container.decodeIfPresent([Double].self, forKey: .split)) ?? []
		self.trafficSeedHi = (try? container.decodeIfPresent(Int.self, forKey: .trafficSeedHi)) ?? 0
		self.trafficSeedLo = (try? container.decodeIfPresent(Int.self, forKey: .trafficSeedLo)) ?? 0

		self.trafficSplit = (try? container.decodeIfPresent([Double].self, forKey: .trafficSplit)) ?? []
		self.fullOnVariant = (try? container.decodeIfPresent(Int.self, forKey: .fullOnVariant)) ?? 0

		self.applications = (try? container.decode([Application].self, forKey: .applications)) ?? []
		self.variants = (try? container.decode([ExperimentVariant].self, forKey: .variants)) ?? []
	}
}

extension Experiment: Equatable {
	public static func == (lhs: Experiment, rhs: Experiment) -> Bool {
		return lhs.id == rhs.id && lhs.name == rhs.name && lhs.unitType == rhs.unitType
			&& lhs.iteration == rhs.iteration && lhs.seedHi == rhs.seedHi && lhs.seedLo == rhs.seedLo
			&& lhs.split == rhs.split && lhs.trafficSeedHi == rhs.trafficSeedHi
			&& lhs.trafficSeedLo == rhs.trafficSeedLo && lhs.trafficSplit == rhs.trafficSplit
			&& lhs.fullOnVariant == rhs.fullOnVariant && lhs.applications == rhs.applications
			&& lhs.variants == rhs.variants
	}
}
