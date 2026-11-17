import Testing

@testable import ABsmartly

// Ported from 1.x VariantAssignerTest.swift.
@Suite struct VariantAssignerTests {
	@Test func chooseVariant() {
		#expect(VariantAssigner.chooseVariant([0, 1], 0) == 1)
		#expect(VariantAssigner.chooseVariant([0, 1], 0.5) == 1)
		#expect(VariantAssigner.chooseVariant([0, 1], 1) == 1)

		#expect(VariantAssigner.chooseVariant([1, 0], 0) == 0)
		#expect(VariantAssigner.chooseVariant([1, 0], 0.5) == 0)
		#expect(VariantAssigner.chooseVariant([1, 0], 1) == 1)

		#expect(VariantAssigner.chooseVariant([0.5, 0.5], 0) == 0)
		#expect(VariantAssigner.chooseVariant([0.5, 0.5], 0.25) == 0)
		#expect(VariantAssigner.chooseVariant([0.5, 0.5], 0.49999999) == 0)
		#expect(VariantAssigner.chooseVariant([0.5, 0.5], 0.5) == 1)
		#expect(VariantAssigner.chooseVariant([0.5, 0.5], 0.50000001) == 1)
		#expect(VariantAssigner.chooseVariant([0.5, 0.5], 0.75) == 1)
		#expect(VariantAssigner.chooseVariant([0.5, 0.5], 1.0) == 1)

		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0) == 0)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.25) == 0)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.33299999) == 0)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.333) == 1)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.33300001) == 1)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.5) == 1)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.66599999) == 1)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.666) == 2)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.66600001) == 2)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 0.75) == 2)
		#expect(VariantAssigner.chooseVariant([0.333, 0.333, 0.334], 1) == 2)

		#expect(VariantAssigner.chooseVariant([0, 1], 0) == 1)
		#expect(VariantAssigner.chooseVariant([0, 1], 1) == 1)
	}

	private func assertAssignment(
		_ unit: String, _ split: [Double], _ seedHi: Int, _ seedLo: Int, _ expected: Int,
		sourceLocation: SourceLocation = #_sourceLocation
	) {
		let assigner = VariantAssigner(unitHash: Hashing.hashUnit(unit))
		let variant = assigner.assign(split, seedHi: seedHi, seedLo: seedLo)
		#expect(
			variant == expected, "Unit: \(unit), split: \(split), seeds: [\(seedHi), \(seedLo)]",
			sourceLocation: sourceLocation)
	}
	@Test func emailBinarySplit_ZeroSeeds() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x0000_0000, 0x0000_0000, 0)
	}

	@Test func emailBinarySplit_ZeroHiOneLo() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x0000_0000, 0x0000_0001, 1)
	}

	@Test func emailBinarySplit_Seeds1() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x8015_406f, 0x7ef4_9b98, 0)
	}

	@Test func emailBinarySplit_Seeds2() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x3b2e_7d90, 0xca87_df4d, 0)
	}

	@Test func emailBinarySplit_Seeds3() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	@Test func emailBinarySplit_Seeds4() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	@Test func emailBinarySplit_Seeds5() {
		assertAssignment("bleh@absmartly.com", [0.5, 0.5], 0x27d1_dc86, 0x8454_61b9, 1)
	}

	@Test func emailThreeWaySplit_ZeroSeeds() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0000, 0)
	}

	@Test func emailThreeWaySplit_ZeroHiOneLo() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0001, 2)
	}

	@Test func emailThreeWaySplit_Seeds1() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x8015_406f, 0x7ef4_9b98, 0)
	}

	@Test func emailThreeWaySplit_Seeds2() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x3b2e_7d90, 0xca87_df4d, 0)
	}

	@Test func emailThreeWaySplit_Seeds3() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	@Test func emailThreeWaySplit_Seeds4() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x865a_84d0, 0xaa22_d41a, 1)
	}

	@Test func emailThreeWaySplit_Seeds5() {
		assertAssignment("bleh@absmartly.com", [0.33, 0.33, 0.34], 0x27d1_dc86, 0x8454_61b9, 1)
	}

	@Test func numericBinarySplit_ZeroSeeds() {
		assertAssignment("123456789", [0.5, 0.5], 0x0000_0000, 0x0000_0000, 1)
	}

	@Test func numericBinarySplit_ZeroHiOneLo() {
		assertAssignment("123456789", [0.5, 0.5], 0x0000_0000, 0x0000_0001, 0)
	}

	@Test func numericBinarySplit_Seeds1() {
		assertAssignment("123456789", [0.5, 0.5], 0x8015_406f, 0x7ef4_9b98, 1)
	}

	@Test func numericBinarySplit_Seeds2() {
		assertAssignment("123456789", [0.5, 0.5], 0x3b2e_7d90, 0xca87_df4d, 1)
	}

	@Test func numericBinarySplit_Seeds3() {
		assertAssignment("123456789", [0.5, 0.5], 0x52c1_f657, 0xd248_bb2e, 1)
	}

	@Test func numericBinarySplit_Seeds4() {
		assertAssignment("123456789", [0.5, 0.5], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	@Test func numericBinarySplit_Seeds5() {
		assertAssignment("123456789", [0.5, 0.5], 0x27d1_dc86, 0x8454_61b9, 0)
	}

	@Test func numericThreeWaySplit_ZeroSeeds() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0000, 2)
	}

	@Test func numericThreeWaySplit_ZeroHiOneLo() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0001, 1)
	}

	@Test func numericThreeWaySplit_Seeds1() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x8015_406f, 0x7ef4_9b98, 2)
	}

	@Test func numericThreeWaySplit_Seeds2() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x3b2e_7d90, 0xca87_df4d, 2)
	}

	@Test func numericThreeWaySplit_Seeds3() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x52c1_f657, 0xd248_bb2e, 2)
	}

	@Test func numericThreeWaySplit_Seeds4() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	@Test func numericThreeWaySplit_Seeds5() {
		assertAssignment("123456789", [0.33, 0.33, 0.34], 0x27d1_dc86, 0x8454_61b9, 0)
	}

	@Test func hashStringBinarySplit_ZeroSeeds() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x0000_0000, 0x0000_0000, 1)
	}

	@Test func hashStringBinarySplit_ZeroHiOneLo() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x0000_0000, 0x0000_0001, 0)
	}

	@Test func hashStringBinarySplit_Seeds1() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x8015_406f, 0x7ef4_9b98, 1)
	}

	@Test func hashStringBinarySplit_Seeds2() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x3b2e_7d90, 0xca87_df4d, 1)
	}

	@Test func hashStringBinarySplit_Seeds3() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	@Test func hashStringBinarySplit_Seeds4() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	@Test func hashStringBinarySplit_Seeds5() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.5, 0.5], 0x27d1_dc86, 0x8454_61b9, 0)
	}

	@Test func hashStringThreeWaySplit_ZeroSeeds() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0000, 2)
	}

	@Test func hashStringThreeWaySplit_ZeroHiOneLo() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x0000_0000, 0x0000_0001, 0)
	}

	@Test func hashStringThreeWaySplit_Seeds1() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x8015_406f, 0x7ef4_9b98, 2)
	}

	@Test func hashStringThreeWaySplit_Seeds2() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x3b2e_7d90, 0xca87_df4d, 1)
	}

	@Test func hashStringThreeWaySplit_Seeds3() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x52c1_f657, 0xd248_bb2e, 0)
	}

	@Test func hashStringThreeWaySplit_Seeds4() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x865a_84d0, 0xaa22_d41a, 0)
	}

	@Test func hashStringThreeWaySplit_Seeds5() {
		assertAssignment("e791e240fcd3df7d238cfc285f475e8152fcc0ec", [0.33, 0.33, 0.34], 0x27d1_dc86, 0x8454_61b9, 1)
	}
}
