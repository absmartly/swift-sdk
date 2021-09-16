//
//  ContextDataDeserializerTests.swift
//  absmartlyTests
//
//  Created by Roman Odyshew on 01.09.2021.
//

import XCTest
@testable import absmartly

final class ContextDataDeserializerTests: XCTestCase {
    func testContextDataDeserialization() {
        
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
        
        guard contextData?.experiments.count == 4 else {
            XCTFail("Unexpect experiments count, expect 4 but given \(String(describing: contextData?.experiments.count))")
            return
        }
        
        XCTAssertTrue(contextData?.experiments[0].id == 1)
        XCTAssertTrue(contextData?.experiments[0].name == "exp_test_ab")
        XCTAssertTrue(contextData?.experiments[0].unitType == "session_id")
        XCTAssertTrue(contextData?.experiments[0].iteration == 1)
        XCTAssertTrue(contextData?.experiments[0].seedHi == 3603515)
        XCTAssertTrue(contextData?.experiments[0].seedLo == 233373850)
        XCTAssertTrue(contextData?.experiments[0].split == [0.5, 0.5])
        XCTAssertTrue(contextData?.experiments[0].trafficSeedHi == 449867249)
        XCTAssertTrue(contextData?.experiments[0].trafficSeedLo == 455443629)
        XCTAssertTrue(contextData?.experiments[0].trafficSplit == [0.0, 1.0])
        XCTAssertTrue(contextData?.experiments[0].fullOnVariant == 0)
        XCTAssertTrue(contextData?.experiments[0].applications?.count == 1)
        XCTAssertTrue(contextData?.experiments[0].applications?[0].name == "website")
        
        if contextData?.experiments[0].variants.count == 2 {
            XCTAssertTrue(contextData?.experiments[0].variants[0].name == "A")
            XCTAssertTrue(contextData?.experiments[0].variants[0].config == nil)
            XCTAssertTrue(contextData?.experiments[0].variants[1].name == "B")
            XCTAssertTrue(contextData?.experiments[0].variants[1].config == "{\"banner.border\":1,\"banner.size\":\"large\"}")
        } else {
            XCTFail("Unexpect Variants count, expect 2 but given \(String(describing: contextData?.experiments[0].variants.count))")
        }
        
        // *************************************** //
        
        XCTAssertTrue(contextData?.experiments[1].id == 2)
        XCTAssertTrue(contextData?.experiments[1].name == "exp_test_abc")
        XCTAssertTrue(contextData?.experiments[1].unitType == "session_id")
        XCTAssertTrue(contextData?.experiments[1].iteration == 1)
        XCTAssertTrue(contextData?.experiments[1].seedHi == 55006150)
        XCTAssertTrue(contextData?.experiments[1].seedLo == 47189152)
        XCTAssertTrue(contextData?.experiments[1].split == [0.34, 0.33, 0.33])
        XCTAssertTrue(contextData?.experiments[1].trafficSeedHi == 705671872)
        XCTAssertTrue(contextData?.experiments[1].trafficSeedLo == 212903484)
        XCTAssertTrue(contextData?.experiments[1].trafficSplit == [0.0, 1.0])
        XCTAssertTrue(contextData?.experiments[1].fullOnVariant == 0)
        XCTAssertTrue(contextData?.experiments[1].applications?.count == 1)
        XCTAssertTrue(contextData?.experiments[1].applications?[0].name == "website")
        
        
        if contextData?.experiments[1].variants.count == 3 {
            XCTAssertTrue(contextData?.experiments[1].variants[0].name == "A")
            XCTAssertTrue(contextData?.experiments[1].variants[0].config == nil)
            XCTAssertTrue(contextData?.experiments[1].variants[1].name == "B")
            XCTAssertTrue(contextData?.experiments[1].variants[1].config == "{\"button.color\":\"blue\"}")
            XCTAssertTrue(contextData?.experiments[1].variants[2].name == "C")
            XCTAssertTrue(contextData?.experiments[1].variants[2].config == "{\"button.color\":\"red\"}")
        } else {
            XCTFail("Unexpect Variants count, expect 3 but given \(String(describing: contextData?.experiments[1].variants.count))")
        }
        
        // *************************************** //
        
        XCTAssertTrue(contextData?.experiments[2].id == 3)
        XCTAssertTrue(contextData?.experiments[2].name == "exp_test_not_eligible")
        XCTAssertTrue(contextData?.experiments[2].unitType == "user_id")
        XCTAssertTrue(contextData?.experiments[2].iteration == 1)
        XCTAssertTrue(contextData?.experiments[2].seedHi == 503266407)
        XCTAssertTrue(contextData?.experiments[2].seedLo == 144942754)
        XCTAssertTrue(contextData?.experiments[2].split == [0.34, 0.33, 0.33])
        XCTAssertTrue(contextData?.experiments[2].trafficSeedHi == 87768905)
        XCTAssertTrue(contextData?.experiments[2].trafficSeedLo == 511357582)
        XCTAssertTrue(contextData?.experiments[2].trafficSplit == [0.99, 0.01])
        XCTAssertTrue(contextData?.experiments[2].fullOnVariant == 0)
        XCTAssertTrue(contextData?.experiments[2].applications?.count == 1)
        XCTAssertTrue(contextData?.experiments[2].applications?[0].name == "website")
        
        if contextData?.experiments[2].variants.count == 3 {
            XCTAssertTrue(contextData?.experiments[2].variants[0].name == "A")
            XCTAssertTrue(contextData?.experiments[2].variants[0].config == nil)
            XCTAssertTrue(contextData?.experiments[2].variants[1].name == "B")
            XCTAssertTrue(contextData?.experiments[2].variants[1].config == "{\"card.width\":\"80%\"}")
            XCTAssertTrue(contextData?.experiments[2].variants[2].name == "C")
            XCTAssertTrue(contextData?.experiments[2].variants[2].config == "{\"card.width\":\"75%\"}")
        } else {
            XCTFail("Unexpect Variants count, expect 3 but given \(String(describing: contextData?.experiments[2].variants.count))")
        }
        
        // *************************************** //
        
        XCTAssertTrue(contextData?.experiments[3].id == 4)
        XCTAssertTrue(contextData?.experiments[3].name == "exp_test_fullon")
        XCTAssertTrue(contextData?.experiments[3].unitType == "session_id")
        XCTAssertTrue(contextData?.experiments[3].iteration == 1)
        XCTAssertTrue(contextData?.experiments[3].seedHi == 856061641)
        XCTAssertTrue(contextData?.experiments[3].seedLo == 990838475)
        XCTAssertTrue(contextData?.experiments[3].split == [0.25, 0.25, 0.25, 0.25])
        XCTAssertTrue(contextData?.experiments[3].trafficSeedHi == 360868579)
        XCTAssertTrue(contextData?.experiments[3].trafficSeedLo == 330937933)
        XCTAssertTrue(contextData?.experiments[3].trafficSplit == [0.0, 1.0])
        XCTAssertTrue(contextData?.experiments[3].fullOnVariant == 2)
        XCTAssertTrue(contextData?.experiments[3].applications?.count == 1)
        XCTAssertTrue(contextData?.experiments[3].applications?[0].name == "website")
        
        if contextData?.experiments[3].variants.count == 4 {
            XCTAssertTrue(contextData?.experiments[3].variants[0].name == "A")
            XCTAssertTrue(contextData?.experiments[3].variants[0].config == nil)
            XCTAssertTrue(contextData?.experiments[3].variants[1].name == "B")
            XCTAssertTrue(contextData?.experiments[3].variants[1].config == "{\"submit.color\":\"red\",\"submit.shape\":\"circle\"}")
            XCTAssertTrue(contextData?.experiments[3].variants[2].name == "C")
            XCTAssertTrue(contextData?.experiments[3].variants[2].config == "{\"submit.color\":\"blue\",\"submit.shape\":\"rect\"}")
            XCTAssertTrue(contextData?.experiments[3].variants[3].name == "D")
            XCTAssertTrue(contextData?.experiments[3].variants[3].config == "{\"submit.color\":\"green\",\"submit.shape\":\"square\"}")
        } else {
            XCTFail("Unexpect Variants count, expect 4 but given \(String(describing: contextData?.experiments[3].variants.count))")
        }
        
    }
}
