import Testing

@testable import ABsmartly

@Suite struct MurmurHashTests {
	private func murmur(_ input: String, _ seed: UInt32) -> UInt32 {
		MurmurHash.hash(Array(input.utf8), seed: seed)
	}
	@Test func seed0EmptyString() {
		#expect(murmur("", 0x0000_0000) == 0x0000_0000)
	}

	@Test func seed0Space() {
		#expect(murmur(" ", 0x0000_0000) == 0x7ef4_9b98)
	}

	@Test func seed0T() {
		#expect(murmur("t", 0x0000_0000) == 0xca87_df4d)
	}

	@Test func seed0Te() {
		#expect(murmur("te", 0x0000_0000) == 0xedb8_ee1b)
	}

	@Test func seed0Tes() {
		#expect(murmur("tes", 0x0000_0000) == 0x0bb9_0e5a)
	}

	@Test func seed0Test() {
		#expect(murmur("test", 0x0000_0000) == 0xba6b_d213)
	}

	@Test func seed0Testy() {
		#expect(murmur("testy", 0x0000_0000) == 0x44af_8342)
	}

	@Test func seed0Testy1() {
		#expect(murmur("testy1", 0x0000_0000) == 0x8a1a_243a)
	}

	@Test func seed0Testy12() {
		#expect(murmur("testy12", 0x0000_0000) == 0x8454_61b9)
	}

	@Test func seed0Testy123() {
		#expect(murmur("testy123", 0x0000_0000) == 0x4762_8ac4)
	}

	@Test func seed0SpecialCharacters() {
		#expect(murmur("special characters açb↓c", 0x0000_0000) == 0xbe83_b140)
	}

	@Test func seed0QuickBrownFox() {
		#expect(murmur("The quick brown fox jumps over the lazy dog", 0x0000_0000) == 0x2e4f_f723)
	}

	@Test func seedDeadbeefEmptyString() {
		#expect(murmur("", 0xdead_beef) == 0x0de5_c6a9)
	}

	@Test func seedDeadbeefSpace() {
		#expect(murmur(" ", 0xdead_beef) == 0x25ac_ce43)
	}

	@Test func seedDeadbeefT() {
		#expect(murmur("t", 0xdead_beef) == 0x3b15_dcf8)
	}

	@Test func seedDeadbeefTe() {
		#expect(murmur("te", 0xdead_beef) == 0xac98_1332)
	}

	@Test func seedDeadbeefTes() {
		#expect(murmur("tes", 0xdead_beef) == 0xc1c7_8dda)
	}

	@Test func seedDeadbeefTest() {
		#expect(murmur("test", 0xdead_beef) == 0xaa22_d41a)
	}

	@Test func seedDeadbeefTesty() {
		#expect(murmur("testy", 0xdead_beef) == 0x84f5_f623)
	}

	@Test func seedDeadbeefTesty1() {
		#expect(murmur("testy1", 0xdead_beef) == 0x09ed_28e9)
	}

	@Test func seedDeadbeefTesty12() {
		#expect(murmur("testy12", 0xdead_beef) == 0x2246_7835)
	}

	@Test func seedDeadbeefTesty123() {
		#expect(murmur("testy123", 0xdead_beef) == 0xd633_060d)
	}

	@Test func seedDeadbeefSpecialCharacters() {
		#expect(murmur("special characters açb↓c", 0xdead_beef) == 0xf7fd_d8a2)
	}

	@Test func seedDeadbeefQuickBrownFox() {
		#expect(murmur("The quick brown fox jumps over the lazy dog", 0xdead_beef) == 0x3a7b_3f4d)
	}

	@Test func seed1EmptyString() {
		#expect(murmur("", 0x0000_0001) == 0x514e_28b7)
	}

	@Test func seed1Space() {
		#expect(murmur(" ", 0x0000_0001) == 0x4f0f_7132)
	}

	@Test func seed1T() {
		#expect(murmur("t", 0x0000_0001) == 0x5db1_831e)
	}

	@Test func seed1Te() {
		#expect(murmur("te", 0x0000_0001) == 0xd248_bb2e)
	}

	@Test func seed1Tes() {
		#expect(murmur("tes", 0x0000_0001) == 0xd432_eb74)
	}

	@Test func seed1Test() {
		#expect(murmur("test", 0x0000_0001) == 0x99c0_2ae2)
	}

	@Test func seed1Testy() {
		#expect(murmur("testy", 0x0000_0001) == 0xc5b2_dc1e)
	}

	@Test func seed1Testy1() {
		#expect(murmur("testy1", 0x0000_0001) == 0x3392_5ceb)
	}

	@Test func seed1Testy12() {
		#expect(murmur("testy12", 0x0000_0001) == 0xd92c_9f23)
	}

	@Test func seed1Testy123() {
		#expect(murmur("testy123", 0x0000_0001) == 0x3bc1_712d)
	}

	@Test func seed1SpecialCharacters() {
		#expect(murmur("special characters açb↓c", 0x0000_0001) == 0x2933_27b5)
	}

	@Test func seed1QuickBrownFox() {
		#expect(murmur("The quick brown fox jumps over the lazy dog", 0x0000_0001) == 0x78e6_9e27)
	}
}
