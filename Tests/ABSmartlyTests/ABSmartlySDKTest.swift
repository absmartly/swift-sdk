import Foundation
import XCTest
@testable import ABSmartly

final class ABSmartlySDKTest: XCTestCase {
    
    func testContextReady() {
        let config = ContextConfig()
        config.setUnit(unitType: "session_id", uid: "0ab1e23f4eee")
        
        XCTAssertEqual(config.units["session_id"], "0ab1e23f4eee")
        
        let sdk = ABSmartlySDK(ClientOptions(apiKey: "", application: "", endpoint: "", environment: "", version: ""))
        
        var contextData: ContextData?
        
        let path = Bundle.module.path(forResource: "context", ofType: "json", inDirectory: "Resources")!
        do {
            let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
            contextData = try JSONDecoder().decode(ContextData.self, from: data)
        } catch {
            XCTFail("Deserialization error: \(error.localizedDescription)")
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
