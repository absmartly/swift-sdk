//
//  GoalAchievement.swift
//  absmartly
//
//  Created by Roman Odyshew on 19.08.2021.
//

import Foundation

public class GoalAchievement: StringSerializable {
    let name: String
    let achievedAt: Int64
    let properties: [String:Any]?
    
    public init(_ name: String, achievedAt: Int64, properties: [String:Any]?) {
        self.name = name
        self.achievedAt = achievedAt
        self.properties = properties
    }
    
    var serializeValue: String {
        var propertiesString: String = ""
        
        if let properties = properties, properties.count > 0 {

            properties.sorted(by: { $0.key < $1.key }).forEach {
                if $0.value is Int || $0.value is Int8 || $0.value is Int16 || $0.value is Int32 || $0.value is Int64 ||
                    $0.value is UInt || $0.value is UInt8 || $0.value is UInt16 || $0.value is UInt32 || $0.value is UInt64 ||
                    $0.value is Float || $0.value is Float32 || $0.value is Double {

                    if !propertiesString.isEmpty {
                        propertiesString += ","
                    }
                    
                    propertiesString += "\"\($0.key)\":\(String(describing: $0.value))"
                }
                
                if $0.value is String || $0.value is Character {

                    if !propertiesString.isEmpty {
                        propertiesString += ","
                    }
                    
                    propertiesString += "\"\($0.key)\":\"\(String(describing: $0.value))\""
                }
                
                if let bool = $0.value as? Bool {
                    propertiesString += "\"\($0.key)\":\(bool ? "true" : "false")"
                }
            }
            
            if !propertiesString.isEmpty {
                propertiesString = ",\"properties\":{" + propertiesString + "}"
            }
        } else {
            propertiesString = ",\"properties\":null"
        }
        
        return "{\"name\":\"" + name + "\",\"achievedAt\":\(achievedAt)\(propertiesString)}";
    }
}
