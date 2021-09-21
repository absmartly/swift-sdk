//
//  PublishEvent.swift
//  absmartly
//
//  Created by Roman Odyshew on 19.08.2021.
//

import Foundation

public final class PublishEvent: Encodable {
    var hashed: Bool
    var units: [Unit]
    var publishedAt: Int64
    var exposures: [Exposure]
    var goals: [GoalAchievement]
    var attributes: [Attribute]
    
    init(_ hashed: Bool = false, _ units: [Unit] = [], _ publishedAt: Int64 = 0, _ exposures: [Exposure] = [], _ goals: [GoalAchievement] = [], _ attributes: [Attribute] = []) {
        self.hashed = hashed
        self.units = units
        self.publishedAt = publishedAt
        self.exposures = exposures
        self.goals = goals
        self.attributes = attributes
    }
    
    enum CodingKeys: String, CodingKey {
        case hashed
        case units
        case publishedAt
        case exposures
        case goals
        case attributes
    }
            
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hashed, forKey: .hashed)
        
        if units.count > 0 {
            try container.encode(units, forKey: .units)
        }
        
        try container.encode(publishedAt, forKey: .publishedAt)
        
        if exposures.count > 0 {
            try container.encode(exposures, forKey: .exposures)
        }
        
        if goals.count > 0 {
            try container.encode(goals, forKey: .goals)
        }
        
        if attributes.count > 0 {
            try container.encode(attributes, forKey: .attributes)
        }
    }
}

extension PublishEvent {
    class Unit: Encodable, Equatable {
        public let type: String
        public let uid: String

        init(_ type: String, _ uid: String) {
            self.type = type
            self.uid = uid
        }
        
        public static func == (lhs: PublishEvent.Unit, rhs: PublishEvent.Unit) -> Bool {
            return lhs.type == rhs.type && lhs.uid == rhs.uid
        }
    }
}

extension PublishEvent {
    class Exposure: Encodable {
        let id: Int
        let name: String
        let unit: String?
        let variant: Int
        let exposedAt: Int64
        let assigned: Bool
        let eligible: Bool
        let overridden: Bool
        let fullOn: Bool
        
        init(_ id: Int, _ name: String, _ unit: String?, _ variant: Int, _ exposedAt: Int64, _ assigned: Bool, _ eligible: Bool, _ overridden: Bool, _ fullOn: Bool) {
            self.id = id
            self.name = name
            self.unit = unit
            self.variant = variant
            self.exposedAt = exposedAt
            self.assigned = assigned
            self.eligible = eligible
            self.overridden = overridden
            self.fullOn = fullOn
        }
    }
}

extension PublishEvent {
    class Attribute: Encodable, Equatable {
        let name: String
        
        let value: Any?
        let setAt: Int64
        
        init(_ name: String, _ value: Any?, _ setAt: Int64) {
            self.name = name
            self.value = value
            self.setAt = setAt
        }
        
        enum CodingKeys: String, CodingKey {
            case name
            case value
            case setAt
        }
        
        public static func == (lhs: PublishEvent.Attribute, rhs: PublishEvent.Attribute) -> Bool {
            return lhs.name == rhs.name && rhs.setAt == lhs.setAt && lhs.value.debugDescription == rhs.value.debugDescription
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            
            if value is Int, let value = value as? Int {
                try container.encode(value, forKey: .value)
            } else if value is Int8, let value = value as? Int8 {
                try container.encode(value, forKey: .value)
            } else if value is Int16, let value = value as? Int16 {
                try container.encode(value, forKey: .value)
            } else if value is Int32, let value = value as? Int32 {
                try container.encode(value, forKey: .value)
            } else if value is Int64, let value = value as? Int64 {
                try container.encode(value, forKey: .value)
            } else if value is UInt, let value = value as? UInt {
                try container.encode(value, forKey: .value)
            } else if value is UInt8, let value = value as? UInt8 {
                try container.encode(value, forKey: .value)
            } else if value is UInt16, let value = value as? UInt16 {
                try container.encode(value, forKey: .value)
            } else if value is UInt32, let value = value as? UInt32 {
                try container.encode(value, forKey: .value)
            } else if value is UInt64, let value = value as? UInt64 {
                try container.encode(value, forKey: .value)
            } else if value is Float, let value = value as? Float {
                try container.encode(value, forKey: .value)
            } else if value is Double, let value = value as? Double {
                try container.encode(value, forKey: .value)
            } else if value is String, let value = value as? String {
                try container.encode(value, forKey: .value)
            } else if value is Bool, let value = value as? Bool {
                try container.encode(value, forKey: .value)
            }
            
            try container.encode(setAt, forKey: .setAt)
        }
    }
}
