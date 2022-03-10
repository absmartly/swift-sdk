import Foundation
import XCTest
@testable import ABSmartly

final class VariantAssignerTest: XCTestCase {
    
    func testSetUnit() {
        
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0,1], 0))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0,1], 0.5))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0,1], 1))
        
        XCTAssertEqual(0, VariantAssigner.chooseVariant([1,0], 0))
        XCTAssertEqual(0, VariantAssigner.chooseVariant([1,0], 0.5))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([1,0], 1))
        
        XCTAssertEqual(0, VariantAssigner.chooseVariant([0.5,0.5], 0))
        XCTAssertEqual(0, VariantAssigner.chooseVariant([0.5,0.5], 0.25))
        XCTAssertEqual(0, VariantAssigner.chooseVariant([0.5,0.5], 0.49999999))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5,0.5], 0.5))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5,0.5], 0.50000001))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5,0.5], 0.75))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5,0.5], 1.0))
        
        XCTAssertEqual(0, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0))
        XCTAssertEqual(0, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.25))
        XCTAssertEqual(0, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.33299999))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.333))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.33300001))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.5))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.66599999))
        XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.666))
        XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.66600001))
        XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333,0.333,0.334], 0.75))
        XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333,0.333,0.334], 1))
        
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0,1], 0))
        XCTAssertEqual(1, VariantAssigner.chooseVariant([0,1], 1))
    }
    
    func testAssignmentsMatch() {
        let splits: [[Double]] = [[0.5, 0.5],
                                  [0.5, 0.5],
                                  [0.5, 0.5],
                                  [0.5, 0.5],
                                  [0.5, 0.5],
                                  [0.5, 0.5],
                                  [0.5, 0.5],
                                  [0.33, 0.33, 0.34],
                                  [0.33, 0.33, 0.34],
                                  [0.33, 0.33, 0.34],
                                  [0.33, 0.33, 0.34],
                                  [0.33, 0.33, 0.34],
                                  [0.33, 0.33, 0.34],
                                  [0.33, 0.33, 0.34]]
        
        let seeds: [[Int]] = [[0x00000000, 0x00000000],
                              [0x00000000, 0x00000001],
                              [0x8015406f, 0x7ef49b98],
                              [0x3b2e7d90, 0xca87df4d],
                              [0x52c1f657, 0xd248bb2e],
                              [0x865a84d0, 0xaa22d41a],
                              [0x27d1dc86, 0x845461b9],
                              [0x00000000, 0x00000000],
                              [0x00000000, 0x00000001],
                              [0x8015406f, 0x7ef49b98],
                              [0x3b2e7d90, 0xca87df4d],
                              [0x52c1f657, 0xd248bb2e],
                              [0x865a84d0, 0xaa22d41a],
                              [0x27d1dc86, 0x845461b9]]

        
        let source: [String:[Int]] = ["123456789": [1, 0, 1, 1, 1, 0, 0, 2, 1, 2, 2, 2, 0, 0],
                                    "bleh@absmartly.com": [0, 1, 0, 0, 0, 0, 1, 0, 2, 0, 0, 0, 1, 1],
                                    "e791e240fcd3df7d238cfc285f475e8152fcc0ec":[1, 0, 1, 1, 0, 0, 0, 2, 0, 2, 1, 0, 0, 1]]
        
        for item in source {
            let unitHash: [UInt8] = Hashing.hash(item.key)
            let assigner = VariantAssigner(unitHash)
            
            
            for i in 0...seeds.count - 1 {
                let flags: [Int] = seeds[i]
                let split: [Double] = splits[i]
                let variant: Int = assigner.assign(split, flags[0], flags[1])
                XCTAssertEqual(variant, item.value[i])
            }
        }
    }
}
