//
//  PublishEvent.swift
//  absmartly
//
//  Created by Roman Odyshew on 19.08.2021.
//

import Foundation

protocol StringSerializable {
    var serializeValue: String { get }
}

public final class PublishEvent: StringSerializable {
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
    
    var serializeValue: String {
        var serializedData: String = "{\"hashed\":" + (hashed ? "true" : "false")
        
        if let unitsString = serializeArray(units) {
            serializedData += ",\"units\":" + unitsString
        }
        
        serializedData += ",\"publishedAt\":\(publishedAt)"
        
        if let exposuresString = serializeArray(exposures) {
            serializedData += ",\"exposures\":" + exposuresString
        }
        
        if let goalsString = serializeArray(goals) {
            serializedData += ",\"goals\":" + goalsString
        }
        
        if let attributesString = serializeArray(attributes) {
            serializedData += ",\"attributes\":" + attributesString
        }
        
        serializedData += "}"
        
        return serializedData
    }
    
    private func serializeArray(_ array: [StringSerializable]) -> String? {
        let arrayStr: String = array.map { $0.serializeValue }.joined(separator: ",")
        if arrayStr.isEmpty { return nil }
        return "[" + arrayStr + "]"
    }
}

extension PublishEvent {
    class Unit: Equatable, StringSerializable {
        public let type: String
        public let uid: String

        init(_ type: String, _ uid: String) {
            self.type = type
            self.uid = uid
        }
        
        var serializeValue: String {
            return "{" +
                "\"type\":\"" + type + "\"" +
                ",\"uid\":\"" + uid +
                "\"}"
        }
        
        public static func == (lhs: PublishEvent.Unit, rhs: PublishEvent.Unit) -> Bool {
            return lhs.type == rhs.type && lhs.uid == rhs.uid
        }
    }
}

extension PublishEvent {
    class Exposure: StringSerializable {
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
        
        var serializeValue: String {
            let serializeValuePart: String = "{\"id\":\(id),\"name\":\"" + name + "\",\"unit\":\"" + (unit ?? "") + "\""
            
            return serializeValuePart +
                    ",\"variant\":\(variant)" +
                    ",\"exposedAt\":\(exposedAt)" +
                    ",\"assigned\":" + (assigned ? "true" : "false") +
                    ",\"eligible\":" + (eligible ? "true" : "false") +
                    ",\"overridden\":" + (overridden ? "true" : "false") +
                    ",\"fullOn\":" + (fullOn ? "true" : "false") +
                    "}";
        }
    }
}

extension PublishEvent {
    class Attribute: Equatable, StringSerializable {
        let name: String
        
        let value: Any?
        let setAt: Int64
        
        init(_ name: String, _ value: Any?, _ setAt: Int64) {
            self.name = name
            self.value = value
            self.setAt = setAt
        }
        
        var serializeValue: String {
            var valueString: String = ""
            
            if let value = value {
                if value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64 ||
                    value is UInt || value is UInt8 || value is UInt16 || value is UInt32 || value is UInt64 ||
                    value is Float || value is Float32 || value is Double {
                    
                    valueString += ",\"value\":\(String(describing: value))"
                }
                
                if value is String || value is Character {
                    valueString += ",\"value\":\"\(String(describing: value))\""
                }
                
                if let bool = value as? Bool {
                    valueString += ",\"value\":\(bool ? "true" : "false")"
                }
            }
            
            return "{" +
                    "\"name\":\"" + name + "\"" +
                    valueString +
                    ",\"setAt\":\(setAt)" +
                    "}";
            
        }
        
        public static func == (lhs: PublishEvent.Attribute, rhs: PublishEvent.Attribute) -> Bool {
            return lhs.name == rhs.name && rhs.setAt == lhs.setAt && lhs.value.debugDescription == rhs.value.debugDescription
        }
    }
}
