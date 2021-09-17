//
//  Experiment.swift
//  absmartly
//
//  Created by Roman Odyshew on 20.08.2021.
//

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
    public let variants: [Variant]
    
    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Experiment couldn't be decoded from this data"))
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
        
        self.applications = (try? container.decode([OptionalDecodableObject<Application>].self, forKey: .applications))?.compactMap { $0.value } ?? []
        self.variants = (try? container.decode([OptionalDecodableObject<Variant>].self, forKey: .variants))?.compactMap { $0.value } ?? []
    }
}

extension Experiment {
    public class Application: Codable, Equatable {
        public let name: String?
        
        init(_ name: String) {
            self.name = name
        }
        
        public static func == (lhs: Experiment.Application, rhs: Experiment.Application) -> Bool {
            return lhs.name == rhs.name
        }
    }
    
    public class Variant: Codable, Equatable {
        public let name: String?
        public let config: String?
        
        init(_ name: String, _ config: String) {
            self.name = name
            self.config = config
        }
        
        public static func == (lhs: Experiment.Variant, rhs: Experiment.Variant) -> Bool {
            return lhs.name == rhs.name && lhs.config == rhs.config
        }
        
        public func decodeConfig<T>() -> T? {
            guard let configData = config?.data(using: .utf8) else { return nil }
            
            do {
                guard let decodedData = try JSONSerialization.jsonObject(with: configData, options: []) as? T else {
                    return nil
                }
                
                return decodedData
            } catch {
                return nil
            }
        }
    }
}

extension Experiment: Equatable {
    public static func == (lhs: Experiment, rhs: Experiment) -> Bool {
        return lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.unitType == rhs.unitType &&
            lhs.iteration == rhs.iteration &&
            lhs.seedHi == rhs.seedHi &&
            lhs.seedLo == rhs.seedLo &&
            lhs.split == rhs.split &&
            lhs.trafficSeedHi == rhs.trafficSeedHi &&
            lhs.trafficSeedLo == rhs.trafficSeedLo &&
            lhs.trafficSplit == rhs.trafficSplit &&
            lhs.fullOnVariant == rhs.fullOnVariant &&
            lhs.applications == rhs.applications &&
            lhs.variants == rhs.variants
    }
}
