import Foundation

public class GoalAchievement: Encodable {
    let name: String
    let achievedAt: Int64
    let properties: [String:Any]?
    
    public init(_ name: String, achievedAt: Int64, properties: [String:Any]?) {
        self.name = name
        self.achievedAt = achievedAt
        self.properties = properties
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case achievedAt
        case properties
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(achievedAt, forKey: .achievedAt)
        
        let dictionaryOptional: CodableAnyDictionary?
        
        if let dictionary = properties {
            dictionaryOptional = CodableAnyDictionary(dictionary)
        } else {
            dictionaryOptional = nil
        }
        
        try container.encode(dictionaryOptional, forKey: .properties)
    }
    
    private class CodableAnyDictionary: Encodable {
        let values: [String:Any]
        
        init(_ values: [String:Any]) {
            self.values = values
        }
        
        private struct CustomCodingKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) {
                self.stringValue = stringValue
            }
            var intValue: Int?
            init?(intValue: Int) {
                return nil
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CustomCodingKeys.self)
            
            for key in values.keys.sorted() {
                guard let codingKey = CustomCodingKeys(stringValue: key) else {
                    continue
                }
                
                if values[key] is Int, let value = values[key] as? Int {
                    try container.encode(value, forKey: codingKey)
                } else  if values[key] is Int8, let value = values[key] as? Int8 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is Int16, let value = values[key] as? Int16 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is Int32, let value = values[key] as? Int32 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is Int64, let value = values[key] as? Int64 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is UInt, let value = values[key] as? UInt {
                    try container.encode(value, forKey: codingKey)
                } else  if values[key] is UInt8, let value = values[key] as? UInt8 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is UInt16, let value = values[key] as? UInt16 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is UInt32, let value = values[key] as? UInt32 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is UInt64, let value = values[key] as? UInt64 {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is Decimal, let value = values[key] as? Decimal {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is Float, let value = values[key] as? Float {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is Double, let value = values[key] as? Double {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is String, let value = values[key] as? String {
                    try container.encode(value, forKey: codingKey)
                } else if values[key] is Bool, let value = values[key] as? Bool {
                    try container.encode(value, forKey: codingKey)
                }
            }
        }
    }
}
