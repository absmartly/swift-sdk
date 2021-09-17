//
//  ContextConfig.swift
//  absmartly
//
//  Created by Roman Odyshew on 19.08.2021.
//

import Foundation

public final class ContextConfig {
    private(set) var units: [String: String] = [:]
    private(set) var attributes: [String: Any] = [:]
    private(set) var overrides: [String: Int] = [:]
    
    public var publishDelay: Int = 100
    
    public init() {
        
    }
    
    public func setUnit(_ unitType: String, _ uid: String) {
        units[unitType] = uid
    }
    
    public func setUnits(_ units: [String: String]) {
        units.forEach { setUnit($0.key, $0.value) }
    }
    
    public func setAttribute(_ name: String, _ value: Any) {
        attributes[name] = value
    }
    
    public func setAttribuets(_ attributes: [String: Any]) {
        attributes.forEach { setAttribute($0.key, $0.value) }
    }
    
    public func setOverride(_ experimentName: String, _ variant: Int) {
        overrides[experimentName] = variant
    }
    
    public func setOverrides(_ overrides: [String: Int]) {
        overrides.forEach { setOverride($0.key, $0.value) }
    }
}
