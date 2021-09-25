//
//  ContextTest.swift
//  absmartlyTests
//
//  Created by Roman Odyshew on 09.09.2021.
//

import XCTest
@testable import absmartly

final class ContextTest: XCTestCase {
    private let expectedVariants: [String: Int] = [
        "exp_test_ab": 1,
        "exp_test_abc": 2,
        "exp_test_not_eligible": 0,
        "exp_test_fullon": 2,
        "exp_test_new": 1]
    
    private let variableExperiments: [String: String] = [
        "banner.border": "exp_test_ab",
        "banner.size": "exp_test_ab",
        "button.color": "exp_test_abc",
        "card.width": "exp_test_not_eligible",
        "submit.color": "exp_test_fullon",
        "submit.shape": "exp_test_fullon",
        "show-modal": "exp_test_new"
    ]
    
    private let expectedVariables: [String:Any] = [
        "banner.border": 1,
        "banner.size": "large",
        "button.color": "red",
        "submit.color": "blue",
        "submit.shape": "rect",
        "show-modal": true]

    
    private func getContextData(_ source: String = "context") throws -> ContextData {
        var contextData: ContextData
 
        if let path = Bundle(for: type(of: self)).path(forResource: source, ofType: "json") {
            do {
                let data = try Foundation.Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                contextData = try JSONDecoder().decode(ContextData.self, from: data)
                return contextData
            } catch {
                XCTFail("Deserialization error: \(error.localizedDescription)")
                throw ABSmartlyError("Deserialization error: \(error.localizedDescription)")
            }
        } else {
            XCTFail("context.json file not found")
            throw ABSmartlyError("context.json file not found")
        }
    }
    
    private func getContextConfig(_ withUnits: Bool = false) -> ContextConfig {
        let contextConfig: ContextConfig = ContextConfig()
        
        if withUnits {
            contextConfig.setUnit(unitType: "session_id", uid: "e791e240fcd3df7d238cfc285f475e8152fcc0ec")
            contextConfig.setUnit(unitType: "user_id", uid: "123456789")
            contextConfig.setUnit(unitType: "email", uid: "bleh@absmartly.com")
        }
        
        return contextConfig
    }
    
    private func getContextDataProvider() -> ContextDataProvider {
        let clientOptions = ClientOptions(apiKey: "test", application: "https://absmartly.com/", endpoint: "", environment: "", version: "")
        let requestFactory = RequestFactory(clientOptions)
        return ContextDataProvider(requestFactory, clientOptions)
    }
    
    private func getEventPublisher() -> EventPublisher {
        let clientOptions = ClientOptions(apiKey: "test", application: "https://absmartly.com/", endpoint: "", environment: "", version: "")
        let requestFactory = RequestFactory(clientOptions)
        return EventPublisher(requestFactory)
    }
    
    func testConfigSetOverrides() {
        var contextData: ContextData
        
        do {
            contextData = try getContextData()
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let overrides: [String: Int] = ["exp_test": 2, "exp_test_1": 1]
        
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        overrides.forEach { contextConfig.setOverride(experimentName: $0.key, variant: $0.value) }
        
        let promise = Promise<ContextData> { success, error in
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        
        overrides.forEach {
            XCTAssertEqual($0.value, context.getOverride(experimentName: $0.key))
        }
    }
    
    func testContextReady() {
        var contextData: ContextData
        
        do {
            contextData = try getContextData()
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertTrue(context.isReady)
        
        do {
            if let data = try context.getContextData() {
                XCTAssertEqual(contextData, data)
            } else {
                XCTFail("No context data from context")
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testIsFailed() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            error(ABSmartlyError("Context Error"))
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertTrue(context.isReady)
        XCTAssertTrue(context.isFailed)
    }
    
    func testIsFailedFutureAsync() {
        let expectation = XCTestExpectation()
        
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
                error(ABSmartlyError("Context Error"))
                expectation.fulfill()
            })
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertFalse(context.isReady)
        XCTAssertFalse(context.isFailed)
        
        context.waitUntilReadyAsync { contextData in
            XCTAssertTrue(contextData == nil)
            XCTAssertTrue(context.isReady)
            XCTAssertTrue(context.isFailed)
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testNonFailedFuture() {
        let expectation = XCTestExpectation()
        
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
                var contextData: ContextData
                
                do {
                    contextData = try self.getContextData()
                } catch {
                    XCTFail(error.localizedDescription)
                    return
                }
                
                success(contextData)
                expectation.fulfill()
            })
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertFalse(context.isReady)
        XCTAssertFalse(context.isFailed)
        
        context.waitUntilReadyAsync { _ in
            XCTAssertTrue(context.isReady)
            XCTAssertFalse(context.isFailed)
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testErrorOnNotReady() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            return
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        
        XCTAssertFalse(context.isReady)
        XCTAssertFalse(context.isFailed)
        
        let noReadyMessage = "ABSmartly Context is not yet ready."
        
        do {
            let _ = try context.peekTreatment("exp_test_ab")
            XCTFail("Expect error on peekTreatment")
        } catch {
            XCTAssertEqual(error.localizedDescription, noReadyMessage)
        }
        
        do {
            let _ = try context.getTreatment("exp_test_ab")
            XCTFail("Expect error on getTreatment")
        } catch {
            XCTAssertEqual(error.localizedDescription, noReadyMessage)
        }
        
        do {
            let _ = try context.getContextData()
            XCTFail("Expect error on getContextData")
        } catch {
            XCTAssertEqual(error.localizedDescription, noReadyMessage)
        }
        
        do {
            let _ = try context.getExperiments()
            XCTFail("Expect error on getExperiments")
        } catch {
            XCTAssertEqual(error.localizedDescription, noReadyMessage)
        }
        
        do {
            let _ = try context.getVariableValue(key: "banner.border", defaultValue: 17)
            XCTFail("Expect error on getVariableValue")
        } catch {
            XCTAssertEqual(error.localizedDescription, noReadyMessage)
        }
        
        do {
            let _ = try context.peekVariableValue(key: "banner.border", defaultValue: 17)
            XCTFail("Expect error on peekVariableValue")
        } catch {
            XCTAssertEqual(error.localizedDescription, noReadyMessage)
        }
        
        do {
            let _ = try context.getVariableKeys()
            XCTFail("Expect error on getVariableKeys")
        } catch {
            XCTAssertEqual(error.localizedDescription, noReadyMessage)
        }
    }
    
    func testErrorOnClosing() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            var contextData: ContextData
            
            do {
                contextData = try self.getContextData()
            } catch {
                XCTFail(error.localizedDescription)
                return
            }
            
            success(contextData)
        }
        
        let closingMessage = "ABSmartly Context is closing."
        
        var contextTestClosures: [(_:Context)->()] = []
        contextTestClosures.append { context in
            do {
                try context.setAttribute(name: "attr1", value: "value1")
                XCTFail("Expect error on setAttribute")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                try context.setAttributes(["attr1": "value1"])
                XCTFail("Expect error on setAttributes")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                try context.setOverride(experimentName: "exp1", variant: 1)
                XCTFail("Expect error on setOverride")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                try context.setOverrides(["exp1": 1])
                XCTFail("Expect error on setOverrides")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.peekTreatment("exp_test_ab")
                XCTFail("Expect error on peekTreatment")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.getTreatment("exp_test_ab")
                XCTFail("Expect error on getTreatment")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.track("goal1", properties: [:])
                XCTFail("Expect error on track")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.publish(nil)
                XCTFail("Expect error on publish")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.getContextData()
                XCTFail("Expect error on getContextData")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.getExperiments()
                XCTFail("Expect error on getExperiments")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.getVariableValue(key: "banner.border", defaultValue: 17)
                XCTFail("Expect error on getVariableValue")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        contextTestClosures.append { context in
            do {
                let _ = try context.peekVariableValue(key: "banner.border", defaultValue: 17)
                XCTFail("Expect error on peekVariableValue")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.append { context in
            do {
                let _ = try context.getVariableKeys()
                XCTFail("Expect error on getVariableKeys")
            } catch {
                XCTAssertEqual(error.localizedDescription, closingMessage)
            }
        }
        
        contextTestClosures.forEach { testClosure in
            let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
            
            XCTAssertTrue(context.isReady)
            XCTAssertFalse(context.isFailed)
            
            do {
                let _ = try context.track("goal1", properties: ["amount": 125, "hours": 245])
            } catch {
                XCTFail("Track throw error: \(error.localizedDescription)")
            }
            
            context.close(nil)
            
            XCTAssertTrue(context.isClosing)
            XCTAssertFalse(context.isClosed)
            testClosure(context)
        }
    }
    
    func testErrorOnClosed() {
        let expectation = XCTestExpectation()
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            var contextData: ContextData
            
            do {
                contextData = try self.getContextData()
            } catch {
                XCTFail(error.localizedDescription)
                return
            }
            
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        
        XCTAssertTrue(context.isReady)
        XCTAssertFalse(context.isFailed)
        
        do {
            let _ = try context.track("goal1", properties: ["amount": 125, "hours": 245])
        } catch {
            XCTFail("Track throw error: \(error.localizedDescription)")
        }
        
        context.close { _ in
            XCTAssertFalse(context.isClosing)
            XCTAssertTrue(context.isClosed)
            
            let cloedMessage = "ABSmartly Context is closed."
            
            do {
                try context.setAttribute(name: "attr1", value: "value1")
                XCTFail("Expect error on setAttribute")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                try context.setAttributes(["attr1": "value1"])
                XCTFail("Expect error on setAttributes")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                try context.setOverride(experimentName: "exp1", variant: 1)
                XCTFail("Expect error on setOverride")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                try context.setOverrides(["exp1": 1])
                XCTFail("Expect error on setOverrides")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.peekTreatment("exp_test_ab")
                XCTFail("Expect error on peekTreatment")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.getTreatment("exp_test_ab")
                XCTFail("Expect error on getTreatment")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.track("goal1", properties: [:])
                XCTFail("Expect error on track")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.publish(nil)
                XCTFail("Expect error on publish")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.getContextData()
                XCTFail("Expect error on getContextData")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.getExperiments()
                XCTFail("Expect error on getExperiments")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.getVariableValue(key: "banner.border", defaultValue: 17)
                XCTFail("Expect error on getVariableValue")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.peekVariableValue(key: "banner.border", defaultValue: 17)
                XCTFail("Expect error on peekVariableValue")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            do {
                let _ = try context.getVariableKeys()
                XCTFail("Expect error on getVariableKeys")
            } catch {
                XCTAssertEqual(error.localizedDescription, cloedMessage)
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetExperiments() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        var contextData: ContextData
        
        do {
            contextData = try self.getContextData()
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let promise = Promise<ContextData> { success, error in
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertTrue(context.isReady)
        XCTAssertEqual(contextData.experiments.map { $0.name }, try context.getExperiments())
    }
    
    func testsetAttributesBeforeReady() {
        let expectation = XCTestExpectation()
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        var contextData: ContextData
        
        do {
            contextData = try self.getContextData()
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let promise = Promise<ContextData> { success, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
                success(contextData)
                expectation.fulfill()
            })
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertFalse(context.isReady)
        
        do {
            try context.setAttribute(name: "attr1", value: "value1")
            try context.setAttributes(["attr1": "value2"])
        } catch {
            print("Error: " + error.localizedDescription)
        }
        
        wait(for: [expectation], timeout: 4.0)
    }
    
    func setOverride() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        var contextData: ContextData
        
        do {
            contextData = try self.getContextData()
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let promise = Promise<ContextData> { success, error in
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertTrue(context.isReady)
        
        do {
            try context.setOverride(experimentName: "exp_test", variant: 2)
        } catch {
            XCTFail(error.localizedDescription)
        }
        XCTAssertEqual(2, context.getOverride(experimentName: "exp_test"))
        
        
        do {
            try context.setOverride(experimentName: "exp_test", variant: 3)
        } catch {
            XCTFail(error.localizedDescription)
        }
        XCTAssertEqual(3, context.getOverride(experimentName: "exp_test"))
        
        
        do {
            try context.setOverride(experimentName: "exp_test_2", variant: 1)
        } catch {
            XCTFail(error.localizedDescription)
        }
        XCTAssertEqual(1, context.getOverride(experimentName: "exp_test_2"))
        
        
        let overrides = ["exp_test_new": 3, "exp_test_new_2": 5]
        do {
            try context.setAttributes(overrides)
        } catch {
            XCTFail(error.localizedDescription)
        }
        
        XCTAssertEqual(3, context.getOverride(experimentName: "exp_test"))
        XCTAssertEqual(1, context.getOverride(experimentName: "exp_test_2"))
        
        overrides.forEach {
            XCTAssertEqual($0.value, context.getOverride(experimentName: $0.key))
        }
        
        XCTAssertEqual(nil, context.getOverride(experimentName: "exp_test_not_found"))
    }
    
    func testOverrideClearsAssignmentCache() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        let promise = Promise<ContextData> { success, error in
            var contextData: ContextData
            
            do {
                contextData = try self.getContextData()
            } catch {
                XCTFail(error.localizedDescription)
                return
            }
            
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        
        let overrides: [String: Int] = ["exp_test_new": 3, "exp_test_new_2": 5]
        do {
            try context.setOverrides(overrides)
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        do {
            try overrides.forEach { XCTAssertEqual($0.value, try context.getTreatment($0.key)) }
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        XCTAssertEqual(overrides.count, context.getPendingCount)
        
        do {
            try overrides.forEach {
                try context.setOverride(experimentName: $0.key, variant: $0.value)
                XCTAssertEqual($0.value, try context.getTreatment($0.key))
            }
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        XCTAssertEqual(overrides.count, context.getPendingCount)
        
        do {
            try overrides.forEach {
                try context.setOverride(experimentName: $0.key, variant: $0.value + 11)
                XCTAssertEqual($0.value + 11, try context.getTreatment($0.key))
            }
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        XCTAssertEqual(overrides.count * 2, context.getPendingCount)
        
        do {
            try XCTAssertEqual(1, context.getTreatment("exp_test_ab"))
            XCTAssertEqual(overrides.count * 2 + 1, context.getPendingCount)
            
            try context.setOverride(experimentName: "exp_test_ab", variant: 9)
            try XCTAssertEqual(9, context.getTreatment("exp_test_ab"))
            XCTAssertEqual(overrides.count * 2 + 2, context.getPendingCount)
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
    }
    
    func testSetOverridesBeforeReady() {
        let expectation = XCTestExpectation()
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        
        
        let promise = Promise<ContextData> { success, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                var contextData: ContextData
                
                do {
                    contextData = try self.getContextData()
                } catch {
                    XCTFail(error.localizedDescription)
                    return
                }
                
                success(contextData)
                expectation.fulfill()
            })
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        XCTAssertFalse(context.isReady)
        
        do {
            try context.setOverride(experimentName: "exp_test", variant: 2)
            try context.setOverrides(["exp_test_new": 3,
                                      "exp_test_new_2": 5])
        } catch {
            print("Error: " + error.localizedDescription)
        }
        
        context.waitUntilReadyAsync { context in
            XCTAssertEqual(2, context?.getOverride(experimentName: "exp_test"))
            XCTAssertEqual(3, context?.getOverride(experimentName: "exp_test_new"))
            XCTAssertEqual(5, context?.getOverride(experimentName: "exp_test_new_2"))
        }
        
        wait(for: [expectation], timeout: 2.5)
    }
    
    func testPeekTreatment() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        var contextData: ContextData
        
        do {
            contextData = try self.getContextData()
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let promise = Promise<ContextData> { success, error in
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        
        do {
            try contextData.experiments.forEach {
                XCTAssertEqual(expectedVariants[$0.name], try context.peekTreatment($0.name))
            }
            
            XCTAssertEqual(0, try context.peekTreatment("no_found"))
            
            try contextData.experiments.forEach {
                XCTAssertEqual(expectedVariants[$0.name], try context.peekTreatment($0.name))
            }
            
            XCTAssertEqual(0, try context.peekTreatment("no_found"))
            XCTAssertEqual(0, context.getPendingCount)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testGetVariableValue() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        var contextData: ContextData
        
        do {
            contextData = try self.getContextData("refreshed")
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let promise = Promise<ContextData> { success, error in
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        
        do {
            XCTAssertEqual(variableExperiments, try context.getVariableKeys())
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
    }
    
    func testPeekTreatmentReturnsOverrideVariant() {
        let eventPublisher = getEventPublisher()
        let contextDataProvider = getContextDataProvider()
        let contextConfig: ContextConfig = getContextConfig(true)
        
        var contextData: ContextData
        
        do {
            contextData = try self.getContextData()
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        
        let promise = Promise<ContextData> { success, error in
            success(contextData)
        }
        
        let context = Context(eventPublisher, contextDataProvider, promise, contextConfig)
        
        do {
            try contextData.experiments.forEach {
                if let variant = expectedVariants[$0.name] {
                    try context.setOverride(experimentName: $0.name, variant: 11 + variant)
                }
            }
            
            try context.setOverride(experimentName: "not_found", variant: 3)
            
            try contextData.experiments.forEach {
                if let variant = expectedVariants[$0.name] {
                    XCTAssertEqual(variant + 11, try context.peekTreatment($0.name))
                }
            }
            XCTAssertEqual(3, try context.peekTreatment("not_found"))
            
            try contextData.experiments.forEach {
                if let variant = expectedVariants[$0.name] {
                    XCTAssertEqual(variant + 11, try context.peekTreatment($0.name))
                }
            }
            XCTAssertEqual(3, try context.peekTreatment("not_found"))
            XCTAssertEqual(0, context.getPendingCount)
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
    }
}
