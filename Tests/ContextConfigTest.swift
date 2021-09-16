//
//  ContextConfigTest.swift
//  absmartlyTests
//
//  Created by Roman Odyshew on 01.09.2021.
//

import XCTest
@testable import absmartly

final class ContextConfigTest: XCTestCase {
    
    func testSetUnit() {
        let config = ContextConfig()
        config.setUnit("session_id", "0ab1e23f4eee")
        
        XCTAssertEqual(config.units["session_id"], "0ab1e23f4eee")
    }
    
    func testSetUnits() {
        let units = ["session_id": "0ab1e23f4eee", "user_id": String(0xabcdef)]
        let config = ContextConfig()
        
        config.setUnits(units)
        XCTAssertEqual(config.units, units)
    }
    
    func testSetAttribute() {
        let config = ContextConfig()
        config.setAttribute("user_agent", "Chrome")
        config.setAttribute("age", 9)
        
        XCTAssertEqual(config.attributes["user_agent"] as? String, "Chrome")
        XCTAssertEqual(config.attributes["age"] as? Int, 9)
    }
    
    func testSetAttributes() {
        let attributes:[String: Any] = ["user_agent": "Chrome", "age" : 9]
        let config = ContextConfig()
        
        config.setAttribuets(attributes)
        XCTAssertEqual(config.attributes["user_agent"] as? String, "Chrome")
        XCTAssertEqual(config.attributes["age"] as? Int, 9)
    }
    
    func testSetOverride() {
        let config = ContextConfig()
        config.setOverride("exp_test", 2)
        
        XCTAssertEqual(config.overrides["exp_test"], 2)
    }
    
    func testSetOverrides() {
        let config = ContextConfig()
        let overrides = ["exp_test": 2, "exp_test_new": 1]
        
        config.setOverrides(overrides)
        XCTAssertEqual(config.overrides, overrides)
    }
    
    func testSetPublishDelay() {
        let config = ContextConfig()
        config.publishDelay = 999
        
        XCTAssertEqual(config.publishDelay, 999)
    }
}
