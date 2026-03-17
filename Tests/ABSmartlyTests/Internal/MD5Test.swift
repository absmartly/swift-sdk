import Foundation
import XCTest

@testable import ABSmartly

final class MD5Test: XCTestCase {

	let testCases: [(input: String, expected: String)] = [
		("", "1B2M2Y8AsgTpgAmY7PhCfg"),
		(" ", "chXunH2dwinSkhpA6JnsXw"),
		("t", "41jvpIn1gGLxDdcxa2Vkng"),
		("te", "Vp73JkK-D63XEdakaNaO4Q"),
		("tes", "KLZi2IO212_Zbk3cXpungA"),
		("test", "CY9rzUYh03PK3k6DJie09g"),
		("testy", "K5I_V6RgP8c6sYKz-TVn8g"),
		("testy1", "8fT8xGipOhPkZ2DncKU-1A"),
		("testy12", "YqRAtOz000gIu61ErEH18A"),
		("testy123", "pfV2H07L6WvdqlY0zHuYIw"),
		("special characters açb↓c", "4PIrO7lKtTxOcj2eMYlG7A"),
		("The quick brown fox jumps over the lazy dog", "nhB9nTcrtoJr2B01QqQZ1g"),
		("The quick brown fox jumps over the lazy dog and eats a pie", "iM-8ECRrLUQzixl436y96A"),
		("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.", "24m7XOq4f5wPzCqzbBicLA"),
	]

	func testHashEmptyString() {
		let hash: String = Hashing.hash("")
		XCTAssertEqual(hash, "1B2M2Y8AsgTpgAmY7PhCfg")
	}

	func testHashSpace() {
		let hash: String = Hashing.hash(" ")
		XCTAssertEqual(hash, "chXunH2dwinSkhpA6JnsXw")
	}

	func testHashSingleChar() {
		let hash: String = Hashing.hash("t")
		XCTAssertEqual(hash, "41jvpIn1gGLxDdcxa2Vkng")
	}

	func testHashTwoChars() {
		let hash: String = Hashing.hash("te")
		XCTAssertEqual(hash, "Vp73JkK-D63XEdakaNaO4Q")
	}

	func testHashThreeChars() {
		let hash: String = Hashing.hash("tes")
		XCTAssertEqual(hash, "KLZi2IO212_Zbk3cXpungA")
	}

	func testHashFourChars() {
		let hash: String = Hashing.hash("test")
		XCTAssertEqual(hash, "CY9rzUYh03PK3k6DJie09g")
	}

	func testHashFiveChars() {
		let hash: String = Hashing.hash("testy")
		XCTAssertEqual(hash, "K5I_V6RgP8c6sYKz-TVn8g")
	}

	func testHashSixChars() {
		let hash: String = Hashing.hash("testy1")
		XCTAssertEqual(hash, "8fT8xGipOhPkZ2DncKU-1A")
	}

	func testHashSevenChars() {
		let hash: String = Hashing.hash("testy12")
		XCTAssertEqual(hash, "YqRAtOz000gIu61ErEH18A")
	}

	func testHashEightChars() {
		let hash: String = Hashing.hash("testy123")
		XCTAssertEqual(hash, "pfV2H07L6WvdqlY0zHuYIw")
	}

	func testHashSpecialCharacters() {
		let hash: String = Hashing.hash("special characters açb↓c")
		XCTAssertEqual(hash, "4PIrO7lKtTxOcj2eMYlG7A")
	}

	func testHashQuickBrownFox() {
		let hash: String = Hashing.hash("The quick brown fox jumps over the lazy dog")
		XCTAssertEqual(hash, "nhB9nTcrtoJr2B01QqQZ1g")
	}

	func testHashQuickBrownFoxExtended() {
		let hash: String = Hashing.hash("The quick brown fox jumps over the lazy dog and eats a pie")
		XCTAssertEqual(hash, "iM-8ECRrLUQzixl436y96A")
	}

	func testHashLoremIpsum() {
		let hash: String = Hashing.hash("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.")
		XCTAssertEqual(hash, "24m7XOq4f5wPzCqzbBicLA")
	}

	func testHashBytesReturnsUTF8OfStringHash() {
		let stringHash: String = Hashing.hash("test")
		let bytesHash: [UInt8] = Hashing.hashBytes("test")
		XCTAssertEqual(Array(stringHash.utf8), bytesHash)
	}

	func testHashBytesConsistentWithHash() {
		for testCase in testCases {
			let stringHash: String = Hashing.hash(testCase.input)
			let bytesHash: [UInt8] = Hashing.hashBytes(testCase.input)
			XCTAssertEqual(Array(stringHash.utf8), bytesHash, "hashBytes mismatch for input: \(testCase.input)")
		}
	}
}
