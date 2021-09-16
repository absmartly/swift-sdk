//
//  ContextEventSerializerTest.swift
//  absmartlyTests
//
//  Created by Roman Odyshew on 01.09.2021.
//

import Foundation
import XCTest
@testable import absmartly

final class ContextEventSerializerTest: XCTestCase {
    
    func testSerialize() {
        let event = PublishEvent()
        
        event.hashed = true
        event.publishedAt = 123456789
        event.units = [PublishEvent.Unit("session_id", "pAE3a1i5Drs5mKRNq56adA"), PublishEvent.Unit("user_id", "JfnnlDI7RTiF9RgfG2JNCw")]
        
        let propertiesMap: [String: Any] = ["amount": 6, "value": 5.0, "tries": 1]
        
        event.goals = [GoalAchievement("goal1", achievedAt: 123456000, properties: propertiesMap),
                       GoalAchievement("goal2", achievedAt: 123456789, properties: nil)]
        
        event.attributes = [
            PublishEvent.Attribute("attr1", "value1", 123456000),
            PublishEvent.Attribute("attr2", "value2", 123456789),
            PublishEvent.Attribute("attr2", nil, 123450000)]
        
        XCTAssertEqual(event.serializeValue, "{\"hashed\":true,\"units\":[{\"type\":\"session_id\",\"uid\":\"pAE3a1i5Drs5mKRNq56adA\"},{\"type\":\"user_id\",\"uid\":\"JfnnlDI7RTiF9RgfG2JNCw\"}],\"publishedAt\":123456789,\"goals\":[{\"name\":\"goal1\",\"achievedAt\":123456000,\"properties\":{\"amount\":6,\"tries\":1,\"value\":5.0}},{\"name\":\"goal2\",\"achievedAt\":123456789,\"properties\":null}],\"attributes\":[{\"name\":\"attr1\",\"value\":\"value1\",\"setAt\":123456000},{\"name\":\"attr2\",\"value\":\"value2\",\"setAt\":123456789},{\"name\":\"attr2\",\"setAt\":123450000}]}")
    }
}
