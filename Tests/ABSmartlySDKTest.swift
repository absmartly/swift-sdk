//
//  ABSmartlySDKTest.swift
//  absmartlyTests
//
//  Created by Roman Odyshew on 01.09.2021.
//

import Foundation
import XCTest
@testable import absmartly

final class ABSmartlySDKTest: XCTestCase {
    
    func testContextReady() {
        
        let config = ContextConfig()
        config.setUnit(unitType: "session_id", uid: "0ab1e23f4eee")
        
        XCTAssertEqual(config.units["session_id"], "0ab1e23f4eee")
        
        let sdk = ABSmartlySDK(ClientOptions(apiKey: "", application: "", endpoint: "", environment: "", version: ""))
        
        var contextData: ContextData?
        
        if let path = Bundle(for: type(of: self)).path(forResource: "context", ofType: "json") {
            do {
                let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                contextData = try JSONDecoder().decode(ContextData.self, from: data)
            } catch {
                XCTFail("Deserialization error: \(error.localizedDescription)")
            }
        } else {
            XCTFail("context.json file not found")
        }
        
        if let contextData = contextData {
            let context = sdk.createContextWithData(config: ContextConfig(), contextData: contextData)
            context.waitUntilReadyAsync {
                XCTAssertEqual($0?.isReady, true)
            }
            
        } else {
            XCTFail("No context Data")
        }
    }
}
