import Testing

@testable import ABsmartly

@Suite struct MD5Tests {
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

	private func hash(_ input: String) -> String {
		String(decoding: Hashing.hashUnit(input), as: UTF8.self)
	}

	@Test func hashEmptyString() {
		#expect(hash("") == "1B2M2Y8AsgTpgAmY7PhCfg")
	}

	@Test func hashSpace() {
		#expect(hash(" ") == "chXunH2dwinSkhpA6JnsXw")
	}

	@Test func hashSingleChar() {
		#expect(hash("t") == "41jvpIn1gGLxDdcxa2Vkng")
	}

	@Test func hashTwoChars() {
		#expect(hash("te") == "Vp73JkK-D63XEdakaNaO4Q")
	}

	@Test func hashThreeChars() {
		#expect(hash("tes") == "KLZi2IO212_Zbk3cXpungA")
	}

	@Test func hashFourChars() {
		#expect(hash("test") == "CY9rzUYh03PK3k6DJie09g")
	}

	@Test func hashFiveChars() {
		#expect(hash("testy") == "K5I_V6RgP8c6sYKz-TVn8g")
	}

	@Test func hashSixChars() {
		#expect(hash("testy1") == "8fT8xGipOhPkZ2DncKU-1A")
	}

	@Test func hashSevenChars() {
		#expect(hash("testy12") == "YqRAtOz000gIu61ErEH18A")
	}

	@Test func hashEightChars() {
		#expect(hash("testy123") == "pfV2H07L6WvdqlY0zHuYIw")
	}

	@Test func hashSpecialCharacters() {
		#expect(hash("special characters açb↓c") == "4PIrO7lKtTxOcj2eMYlG7A")
	}

	// Characters outside the BMP are stored as UTF-16 surrogate pairs and must encode to 4-byte UTF-8; these canonical hashes are shared across all SDKs.
	@Test func hashAstralAndMultibyteCharacters() {
		#expect(hash("😀") == "KgLqw51xanDs83V5GFkntg")
		#expect(hash("😀😁") == "ZJuDalvUWRJnVtkspj-2bQ")
		#expect(hash("世界你好") == "v2CJG7YcjjWncKOSCzF2GA")
		#expect(hash("user_世界_123") == "SCgk4OzXlFMvo1UMsP88fA")
	}

	@Test func hashQuickBrownFox() {
		#expect(hash("The quick brown fox jumps over the lazy dog") == "nhB9nTcrtoJr2B01QqQZ1g")
	}

	@Test func hashQuickBrownFoxExtended() {
		#expect(hash("The quick brown fox jumps over the lazy dog and eats a pie") == "iM-8ECRrLUQzixl436y96A")
	}

	@Test func hashLoremIpsum() {
		#expect(hash("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.") == "24m7XOq4f5wPzCqzbBicLA")
	}

	@Test func hashBytesReturnsUTF8OfStringHash() {
		let stringHash = hash("test")
		let bytesHash: [UInt8] = Hashing.hashUnit("test")
		#expect(Array(stringHash.utf8) == bytesHash)
	}

	@Test func hashBytesConsistentWithHash() {
		for testCase in testCases {
			#expect(Hashing.hashUnit(testCase.input) == Array(testCase.expected.utf8), "hashBytes mismatch for input: \(testCase.input)")
		}
	}
}
