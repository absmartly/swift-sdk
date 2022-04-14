import Foundation
import XCTest

@testable import ABSmartly

final class MurmurHashTest: XCTestCase {

	func testSerialize() {
		let testData: [Any] = [
			["", 0x0000_0000, 0x0000_0000],
			[" ", 0x0000_0000, 0x7ef4_9b98],
			["t", 0x0000_0000, 0xca87_df4d],
			["te", 0x0000_0000, 0xedb8_ee1b],
			["tes", 0x0000_0000, 0x0bb9_0e5a],
			["test", 0x0000_0000, 0xba6b_d213],
			["testy", 0x0000_0000, 0x44af_8342],
			["testy1", 0x0000_0000, 0x8a1a_243a],
			["testy12", 0x0000_0000, 0x8454_61b9],
			["testy123", 0x0000_0000, 0x4762_8ac4],
			["special characters açb↓c", 0x0000_0000, 0xbe83_b140],
			["The quick brown fox jumps over the lazy dog", 0x0000_0000, 0x2e4f_f723],
			["", 0xdead_beef, 0x0de5_c6a9],
			[" ", 0xdead_beef, 0x25ac_ce43],
			["t", 0xdead_beef, 0x3b15_dcf8],
			["te", 0xdead_beef, 0xac98_1332],
			["tes", 0xdead_beef, 0xc1c7_8dda],
			["test", 0xdead_beef, 0xaa22_d41a],
			["testy", 0xdead_beef, 0x84f5_f623],
			["testy1", 0xdead_beef, 0x09ed_28e9],
			["testy12", 0xdead_beef, 0x2246_7835],
			["testy123", 0xdead_beef, 0xd633_060d],
			["special characters açb↓c", 0xdead_beef, 0xf7fd_d8a2],
			["The quick brown fox jumps over the lazy dog", 0xdead_beef, 0x3a7b_3f4d],
			["", 0x0000_0001, 0x514e_28b7],
			[" ", 0x0000_0001, 0x4f0f_7132],
			["t", 0x0000_0001, 0x5db1_831e],
			["te", 0x0000_0001, 0xd248_bb2e],
			["tes", 0x0000_0001, 0xd432_eb74],
			["test", 0x0000_0001, 0x99c0_2ae2],
			["testy", 0x0000_0001, 0xc5b2_dc1e],
			["testy1", 0x0000_0001, 0x3392_5ceb],
			["testy12", 0x0000_0001, 0xd92c_9f23],
			["testy123", 0x0000_0001, 0x3bc1_712d],
			["special characters açb↓c", 0x0000_0001, 0x2933_27b5],
			["The quick brown fox jumps over the lazy dog", 0x0000_0001, 0x78e6_9e27],
		]

		for data in testData {

			guard let array = data as? [Any] else { continue }

			guard let testString = array[0] as? String else { continue }
			guard let seed = array[1] as? UInt32 else { continue }
			guard let expect = array[2] as? UInt32 else { continue }

			let key: [UInt8] = Array(testString.utf8)
			let actual: UInt32 = MurmurHash.murmurHash(key, seed)

			XCTAssertEqual(actual, expect)
		}
	}
}
