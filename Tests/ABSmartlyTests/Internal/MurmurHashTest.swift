import Foundation
import XCTest

@testable import ABSmartly

final class MurmurHashTest: XCTestCase {

	private func murmur(_ input: String, _ seed: UInt32) -> UInt32 {
		let key: [UInt8] = Array(input.utf8)
		return MurmurHash.murmurHash(key, seed)
	}

	func testSeed0EmptyString() {
		XCTAssertEqual(murmur("", 0x0000_0000), 0x0000_0000)
	}

	func testSeed0Space() {
		XCTAssertEqual(murmur(" ", 0x0000_0000), 0x7ef4_9b98)
	}

	func testSeed0T() {
		XCTAssertEqual(murmur("t", 0x0000_0000), 0xca87_df4d)
	}

	func testSeed0Te() {
		XCTAssertEqual(murmur("te", 0x0000_0000), 0xedb8_ee1b)
	}

	func testSeed0Tes() {
		XCTAssertEqual(murmur("tes", 0x0000_0000), 0x0bb9_0e5a)
	}

	func testSeed0Test() {
		XCTAssertEqual(murmur("test", 0x0000_0000), 0xba6b_d213)
	}

	func testSeed0Testy() {
		XCTAssertEqual(murmur("testy", 0x0000_0000), 0x44af_8342)
	}

	func testSeed0Testy1() {
		XCTAssertEqual(murmur("testy1", 0x0000_0000), 0x8a1a_243a)
	}

	func testSeed0Testy12() {
		XCTAssertEqual(murmur("testy12", 0x0000_0000), 0x8454_61b9)
	}

	func testSeed0Testy123() {
		XCTAssertEqual(murmur("testy123", 0x0000_0000), 0x4762_8ac4)
	}

	func testSeed0SpecialCharacters() {
		XCTAssertEqual(murmur("special characters açb↓c", 0x0000_0000), 0xbe83_b140)
	}

	func testSeed0QuickBrownFox() {
		XCTAssertEqual(murmur("The quick brown fox jumps over the lazy dog", 0x0000_0000), 0x2e4f_f723)
	}

	func testSeedDeadbeefEmptyString() {
		XCTAssertEqual(murmur("", 0xdead_beef), 0x0de5_c6a9)
	}

	func testSeedDeadbeefSpace() {
		XCTAssertEqual(murmur(" ", 0xdead_beef), 0x25ac_ce43)
	}

	func testSeedDeadbeefT() {
		XCTAssertEqual(murmur("t", 0xdead_beef), 0x3b15_dcf8)
	}

	func testSeedDeadbeefTe() {
		XCTAssertEqual(murmur("te", 0xdead_beef), 0xac98_1332)
	}

	func testSeedDeadbeefTes() {
		XCTAssertEqual(murmur("tes", 0xdead_beef), 0xc1c7_8dda)
	}

	func testSeedDeadbeefTest() {
		XCTAssertEqual(murmur("test", 0xdead_beef), 0xaa22_d41a)
	}

	func testSeedDeadbeefTesty() {
		XCTAssertEqual(murmur("testy", 0xdead_beef), 0x84f5_f623)
	}

	func testSeedDeadbeefTesty1() {
		XCTAssertEqual(murmur("testy1", 0xdead_beef), 0x09ed_28e9)
	}

	func testSeedDeadbeefTesty12() {
		XCTAssertEqual(murmur("testy12", 0xdead_beef), 0x2246_7835)
	}

	func testSeedDeadbeefTesty123() {
		XCTAssertEqual(murmur("testy123", 0xdead_beef), 0xd633_060d)
	}

	func testSeedDeadbeefSpecialCharacters() {
		XCTAssertEqual(murmur("special characters açb↓c", 0xdead_beef), 0xf7fd_d8a2)
	}

	func testSeedDeadbeefQuickBrownFox() {
		XCTAssertEqual(murmur("The quick brown fox jumps over the lazy dog", 0xdead_beef), 0x3a7b_3f4d)
	}

	func testSeed1EmptyString() {
		XCTAssertEqual(murmur("", 0x0000_0001), 0x514e_28b7)
	}

	func testSeed1Space() {
		XCTAssertEqual(murmur(" ", 0x0000_0001), 0x4f0f_7132)
	}

	func testSeed1T() {
		XCTAssertEqual(murmur("t", 0x0000_0001), 0x5db1_831e)
	}

	func testSeed1Te() {
		XCTAssertEqual(murmur("te", 0x0000_0001), 0xd248_bb2e)
	}

	func testSeed1Tes() {
		XCTAssertEqual(murmur("tes", 0x0000_0001), 0xd432_eb74)
	}

	func testSeed1Test() {
		XCTAssertEqual(murmur("test", 0x0000_0001), 0x99c0_2ae2)
	}

	func testSeed1Testy() {
		XCTAssertEqual(murmur("testy", 0x0000_0001), 0xc5b2_dc1e)
	}

	func testSeed1Testy1() {
		XCTAssertEqual(murmur("testy1", 0x0000_0001), 0x3392_5ceb)
	}

	func testSeed1Testy12() {
		XCTAssertEqual(murmur("testy12", 0x0000_0001), 0xd92c_9f23)
	}

	func testSeed1Testy123() {
		XCTAssertEqual(murmur("testy123", 0x0000_0001), 0x3bc1_712d)
	}

	func testSeed1SpecialCharacters() {
		XCTAssertEqual(murmur("special characters açb↓c", 0x0000_0001), 0x2933_27b5)
	}

	func testSeed1QuickBrownFox() {
		XCTAssertEqual(murmur("The quick brown fox jumps over the lazy dog", 0x0000_0001), 0x78e6_9e27)
	}
}
