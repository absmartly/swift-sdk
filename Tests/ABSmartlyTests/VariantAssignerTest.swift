import Foundation
import XCTest

@testable import ABSmartly

final class VariantAssignerTest: XCTestCase {

	func testChooseVariant() {
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0, 1], 0))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0, 1], 0.5))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0, 1], 1))

		XCTAssertEqual(0, VariantAssigner.chooseVariant([1, 0], 0))
		XCTAssertEqual(0, VariantAssigner.chooseVariant([1, 0], 0.5))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([1, 0], 1))

		XCTAssertEqual(0, VariantAssigner.chooseVariant([0.5, 0.5], 0))
		XCTAssertEqual(0, VariantAssigner.chooseVariant([0.5, 0.5], 0.25))
		XCTAssertEqual(0, VariantAssigner.chooseVariant([0.5, 0.5], 0.49999999))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5, 0.5], 0.5))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5, 0.5], 0.50000001))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5, 0.5], 0.75))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.5, 0.5], 1.0))

		XCTAssertEqual(0, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0))
		XCTAssertEqual(0, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.25))
		XCTAssertEqual(0, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.33299999))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.333))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.33300001))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.5))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.66599999))
		XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.666))
		XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.66600001))
		XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.75))
		XCTAssertEqual(2, VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 1))

		XCTAssertEqual(1, VariantAssigner.chooseVariant([0, 1], 0))
		XCTAssertEqual(1, VariantAssigner.chooseVariant([0, 1], 1))
	}

	private func assertAssignment(_ unit: String, _ split: [Double], _ seedHi: Int, _ seedLo: Int, _ expected: Int, file: StaticString = #file, line: UInt = #line) {
		let unitHash: [UInt8] = Hashing.hash(unit)
		let assigner = VariantAssigner(unitHash)
		let variant = assigner.assign(split, seedHi, seedLo)
		XCTAssertEqual(variant, expected, "Unit: \(unit), split: \(split), seeds: [\(seedHi), \(seedLo)]", file: file, line: line)
	}

	func testEmailBinarySplit_ZeroSeeds() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x0000_0000, 0x0000_0000, 0)
	}

	func testEmailBinarySplit_ZeroHiOneLo() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x0000_0000, 0x0000_0001, 1)
	}

	func testEmailBinarySplit_Seeds1() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x8015_406f, 0x7ef4_9b98, 0)
	}

	func testEmailBinarySplit_Seeds2() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x3b2e_7d90, 0xca87_df4d, 0)
	}

	func testEmailBinarySplit_Seeds3() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	func testEmailBinarySplit_Seeds4() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	func testEmailBinarySplit_Seeds5() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x27d1_dc86, 0x8454_61b9, 1)
	}

	func testEmailThreeWaySplit_ZeroSeeds() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0000, 0)
	}

	func testEmailThreeWaySplit_ZeroHiOneLo() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0001, 2)
	}

	func testEmailThreeWaySplit_Seeds1() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x8015_406f, 0x7ef4_9b98, 0)
	}

	func testEmailThreeWaySplit_Seeds2() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x3b2e_7d90, 0xca87_df4d, 0)
	}

	func testEmailThreeWaySplit_Seeds3() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	func testEmailThreeWaySplit_Seeds4() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x865a_84d0, 0xaa22_d41a, 1)
	}

	func testEmailThreeWaySplit_Seeds5() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x27d1_dc86, 0x8454_61b9, 1)
	}

	func testNumericBinarySplit_ZeroSeeds() {
		assertAssignment("123456789", [0.5, 0.5], 0x0000_0000, 0x0000_0000, 1)
	}

	func testNumericBinarySplit_ZeroHiOneLo() {
		assertAssignment("123456789", [0.5, 0.5], 0x0000_0000, 0x0000_0001, 0)
	}

	func testNumericBinarySplit_Seeds1() {
		assertAssignment("123456789", [0.5, 0.5], 0x8015_406f, 0x7ef4_9b98, 1)
	}

	func testNumericBinarySplit_Seeds2() {
		assertAssignment("123456789", [0.5, 0.5], 0x3b2e_7d90, 0xca87_df4d, 1)
	}

	func testNumericBinarySplit_Seeds3() {
		assertAssignment("123456789", [0.5, 0.5], 0x52c1_f657, 0xd248_bb2e, 1)
	}

	func testNumericBinarySplit_Seeds4() {
		assertAssignment("123456789", [0.5, 0.5], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	func testNumericBinarySplit_Seeds5() {
		assertAssignment("123456789", [0.5, 0.5], 0x27d1_dc86, 0x8454_61b9, 0)
	}

	func testNumericThreeWaySplit_ZeroSeeds() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0000, 2)
	}

	func testNumericThreeWaySplit_ZeroHiOneLo() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0001, 1)
	}

	func testNumericThreeWaySplit_Seeds1() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x8015_406f, 0x7ef4_9b98, 2)
	}

	func testNumericThreeWaySplit_Seeds2() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x3b2e_7d90, 0xca87_df4d, 2)
	}

	func testNumericThreeWaySplit_Seeds3() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x52c1_f657, 0xd248_bb2e, 2)
	}

	func testNumericThreeWaySplit_Seeds4() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	func testNumericThreeWaySplit_Seeds5() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x27d1_dc86, 0x8454_61b9, 0)
	}

	func testHashStringBinarySplit_ZeroSeeds() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x0000_0000, 0x0000_0000, 1)
	}

	func testHashStringBinarySplit_ZeroHiOneLo() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x0000_0000, 0x0000_0001, 0)
	}

	func testHashStringBinarySplit_Seeds1() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x8015_406f, 0x7ef4_9b98, 1)
	}

	func testHashStringBinarySplit_Seeds2() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x3b2e_7d90, 0xca87_df4d, 1)
	}

	func testHashStringBinarySplit_Seeds3() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	func testHashStringBinarySplit_Seeds4() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	func testHashStringBinarySplit_Seeds5() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x27d1_dc86, 0x8454_61b9, 0)
	}

	func testHashStringThreeWaySplit_ZeroSeeds() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0000, 2)
	}

	func testHashStringThreeWaySplit_ZeroHiOneLo() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0001, 0)
	}

	func testHashStringThreeWaySplit_Seeds1() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x8015_406f, 0x7ef4_9b98, 2)
	}

	func testHashStringThreeWaySplit_Seeds2() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x3b2e_7d90, 0xca87_df4d, 1)
	}

	func testHashStringThreeWaySplit_Seeds3() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	func testHashStringThreeWaySplit_Seeds4() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	func testHashStringThreeWaySplit_Seeds5() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x27d1_dc86, 0x8454_61b9, 1)
	}
}
