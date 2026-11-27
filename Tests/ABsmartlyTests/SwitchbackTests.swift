import Foundation
import Testing

@testable import ABsmartly

/// The switchback building blocks: the schedule draw against the platform golden vectors, cluster
/// attribute paths against the Collector's cases, serving resolution and cluster keys.
///
/// `Resources/switchback/golden-vectors.json` is a byte-identical copy of the platform's resource
/// (git blob b314abeb9e97) and `attribute-path-cases.json` of the Collector's (blob 7b1d3fed5985),
/// both via java-sdk 07807b51.
@Suite struct SwitchbackAssignerTests {
	private static func fixture(_ name: String) -> JSONValue {
		try! JSONDecoder().decode(JSONValue.self, from: Fixtures.data("switchback/" + name))
	}

	// An integer cluster unit is keyed by its decimal text, as `SwitchbackServing.clusterKey` keys it.
	private static func clusterUnit(_ v: JSONValue) -> String {
		v["clusterUnit"].flatMap { $0.stringValue ?? SwitchbackServing.clusterKey($0) }!
	}

	@Test func assignMatchesEveryGoldenVector() {
		let vectors = Self.fixture("golden-vectors")["assignSwitchback"]?.arrayValue ?? []
		#expect(vectors.count == 882)
		#expect(vectors.filter { $0["clusterUnit"]?.stringValue == nil }.count == 294)
		for v in vectors {
			let variant = SwitchbackAssigner.assign(
				Self.clusterUnit(v), periodIndex: Int64(v["periodIndex"]!.stringValue!)!,
				seed: Int64(v["seed"]!.stringValue!)!, armCount: v["armCount"]!.intValue!)
			#expect(variant == v["expectedVariant"]?.intValue, "\(v)")
		}
	}

	@Test func permutationMatchesEveryGoldenVector() {
		let vectors = Self.fixture("golden-vectors")["fisherYatesPermutation"]?.arrayValue ?? []
		#expect(vectors.count == 504)
		for v in vectors {
			let permutation = SwitchbackAssigner.permutation(
				Self.clusterUnit(v), cycleIndex: Int64(v["cycleIndex"]!.stringValue!)!,
				seed: Int64(v["seed"]!.stringValue!)!, armCount: v["armCount"]!.intValue!)
			#expect(.array(permutation.map { .int(Int64($0)) }) == v["expectedPermutation"], "\(v)")
		}
	}

	// A step hash of 0xffffffff gives a probability of exactly 1.0, which would index past `i`: this
	// base hash (found by search) gives it at i = 1, and the clamp keeps j = 1.
	@Test func aStepProbabilityOfOneIsClamped() {
		var buffer = [UInt8](repeating: 0, count: 8)
		for (offset, value) in [(0, UInt32(1_739_289_435)), (4, UInt32(1))] {
			for byte in 0..<4 {
				buffer[offset + byte] = UInt8((value >> (8 * UInt32(byte))) & 0xff)
			}
		}
		#expect(MurmurHash.hash(buffer) == 0xFFFF_FFFF)
		#expect(SwitchbackAssigner.fisherYates(2, baseHash: 1_739_289_435) == [0, 1])
	}

	// Every cycle serves each arm exactly once (the balanced block).
	@Test func everyCycleServesEachArmOnce() {
		for arms in [2, 3, 7, 10] {
			for cycle in [Int64.min, -1, 0, 1, 12345, Int64.max] {
				let variants = (0..<Int64(arms)).map { slot in
					SwitchbackAssigner.assign(
						"k", periodIndex: cycle &* Int64(arms) &+ slot, seed: SB.seed, armCount: arms)
				}
				if cycle > Int64.min / Int64(arms) && cycle < Int64.max / Int64(arms) {
					#expect(Set(variants) == Set(0..<arms), "arms \(arms) cycle \(cycle)")
				}
			}
		}
	}

	@Test func floorDivRoundsTowardNegativeInfinity() {
		#expect(SwitchbackAssigner.floorDiv(7, 2) == 3)
		#expect(SwitchbackAssigner.floorDiv(-7, 2) == -4)
		#expect(SwitchbackAssigner.floorDiv(-8, 2) == -4)
		#expect(SwitchbackAssigner.floorDiv(-1, 3_600_000) == -1)
		#expect(SwitchbackAssigner.floorDiv(0, 5) == 0)
		#expect(SwitchbackAssigner.floorDiv(Int64.min, 3) == -3_074_457_345_618_258_603)
		#expect(SwitchbackAssigner.floorDiv(Int64.max, 3) == 3_074_457_345_618_258_602)
	}

	// The seed is (seedHi << 32) | (seedLo & 0xffffffff), with negative halves.
	@Test func seedCombinesTheHalves() {
		var experiment = Experiment(
			id: 1, name: "x", unitType: nil, seedHi: -5, seedLo: -7, split: [0.5, 0.5], variants: [])
		#expect(SwitchbackSchedule.seed(experiment) == SB.seed)
		#expect(SwitchbackSchedule.seed(experiment) == -17_179_869_191)
		experiment.seedHi = 1
		experiment.seedLo = 2
		#expect(SwitchbackSchedule.seed(experiment) == 4_294_967_298)
		experiment.seedHi = 0
		experiment.seedLo = -1
		#expect(SwitchbackSchedule.seed(experiment) == 0xFFFF_FFFF)
	}
}

@Suite struct SwitchbackAttributePathTests {
	private func parse(_ path: String?) -> SwitchbackAttributePath? {
		SwitchbackAttributePath.parseSupported(path)
	}

	private func resolve(_ path: String, _ attributes: [String: JSONValue]) -> JSONValue? {
		guard let parsed = parse(path), let root = attributes[parsed.rootKey] else { return nil }
		return parsed.resolve(in: root)
	}

	@Test func matchesEveryCollectorPathCase() throws {
		let fixture = try JSONDecoder().decode(
			JSONValue.self, from: Fixtures.data("switchback/attribute-path-cases"))
		let attributes = fixture["attributes"]?.objectValue ?? [:]
		let cases = fixture["cases"]?.arrayValue ?? []
		#expect(cases.count == 7)
		for c in cases {
			let path = c["path"]!.stringValue!
			if c["supported"]?.boolValue == false {
				#expect(parse(path) == nil, "\(c)")
				continue
			}
			#expect(parse(path) != nil, "\(c)")
			let value = resolve(path, attributes)
			if c["value"]?.isNull == true {
				#expect(value == nil, "\(c)")
			} else {
				#expect(value == c["value"], "\(c)")
			}
		}
	}

	@Test func quotedSegmentsAreLiteralKeys() {
		let attributes: [String: JSONValue] = ["geo": ["0": "zero", "a/b": "slash"]]
		#expect(resolve("geo/'0'", attributes) == "zero")
		#expect(resolve("geo/\"a/b\"", attributes) == "slash")
	}

	@Test(arguments: [
		"geo/'0", "'geo", "\"geo/city", "geo/\"", "geo.city", "geo/a.b", "a./b", ".", "items/0.5/city", "'geo.city'",
		"\"geo.city\"", "geo/'a.b'",
	])
	func rejectsMalformedPaths(_ path: String) {
		#expect(parse(path) == nil)
	}

	@Test func separatorsAreCollapsed() {
		let attributes: [String: JSONValue] = ["geo": ["city": "Porto"]]
		#expect(resolve("/geo//city/", attributes) == "Porto")
		#expect(resolve("geo", attributes) == attributes["geo"])
	}

	@Test func rejectsUnsupportedPaths() {
		for path in [nil, "", "/", "//", "0/city", "items/0", "items/0/1/city", "items/-1/city", "'"] as [String?] {
			#expect(parse(path) == nil, "\(String(describing: path))")
		}
	}

	@Test func indexSegmentsReadOnlyArraysAndKeySegmentsReadOnlyObjects() {
		let attributes: [String: JSONValue] = [
			"items": [["city": "Lisbon"]], "geo": ["0": ["city": "zero"]], "name": "scalar",
		]
		#expect(resolve("geo/0/city", attributes) == nil)
		#expect(resolve("items/1/city", attributes) == nil)
		#expect(resolve("name/x", attributes) == nil)
		#expect(resolve("missing/x", attributes) == nil)
		#expect(resolve("items/-0/city", attributes) == "Lisbon")
	}

	@Test func tryParseIntFollowsGuava() {
		#expect(SwitchbackAttributePath.tryParseInt("0") == 0)
		#expect(SwitchbackAttributePath.tryParseInt("-0") == 0)
		#expect(SwitchbackAttributePath.tryParseInt("007") == 7)
		#expect(SwitchbackAttributePath.tryParseInt("2147483647") == 2_147_483_647)
		#expect(SwitchbackAttributePath.tryParseInt("-2147483648") == -2_147_483_648)
		// A long digit run is not an int, so it reads as an object key, and parsing never overflows.
		let long = String(repeating: "9", count: 10_000)
		#expect(SwitchbackAttributePath.tryParseInt(long) == nil)
		#expect(SwitchbackAttributePath.tryParseInt("-" + long) == nil)
		#expect(resolve("items/\(long)/city", ["items": .object([long: ["city": "deep"]])]) == "deep")
		for s in ["", "-", "+1", "1a", " 1", "2147483648", "-2147483649", "99999999999999999999", "\u{0660}", "1.0"] {
			#expect(SwitchbackAttributePath.tryParseInt(s) == nil, "\(s)")
		}
	}

	@Test func unicodeSegments() {
		let attributes: [String: JSONValue] = ["géo": ["cidade": "Évora", "'\u{301}x": "accent"]]
		#expect(resolve("géo/cidade", attributes) == "Évora")
		#expect(resolve("géo/\"'\u{301}x\"", attributes) == "accent")
	}

	@Test func javaTrimStripsControlCharactersAndSpacesOnly() {
		#expect(javaTrim(" \t\u{0}store\n ") == "store")
		#expect(javaTrim("\u{A0}store") == "\u{A0}store")
		#expect(javaTrim(" \u{1F} ") == "")
	}
}

@Suite struct SwitchbackServingTests {
	private func sources(_ entries: (String, String)...) -> [SwitchbackSource] {
		entries.map { SwitchbackSource(unitType: $0.0, path: SwitchbackAttributePath.parseSupported($0.1)!) }
	}

	@Test func sourceOrderDecides() {
		let values: [String: JSONValue] = ["a": "x", "b": "x"]
		let read: (SwitchbackAttributePath) -> JSONValue? = { values[$0.rootKey] }
		let forward = SwitchbackServing.resolve(
			sources(("user_id", "a"), ("device_id", "b")), allowedValues: nil, hasUnit: { _ in true }, read: read)
		#expect(forward == SwitchbackServing(status: .eligible, unitType: "user_id", clusterKey: "x"))
		let backward = SwitchbackServing.resolve(
			sources(("device_id", "b"), ("user_id", "a")), allowedValues: nil, hasUnit: { _ in true }, read: read)
		#expect(backward.unitType == "device_id")
	}

	@Test func statuses() {
		let s = sources(("user_id", "a"), ("device_id", "b"))
		func resolve(
			_ values: [String: JSONValue], allowed: [String]? = nil, units: Set<String> = ["user_id", "device_id"]
		)
			-> SwitchbackServing
		{
			SwitchbackServing.resolve(
				s, allowedValues: allowed, hasUnit: { units.contains($0) }, read: { values[$0.rootKey] })
		}
		#expect(resolve(["a": "x"], units: []) == .absent)
		#expect(resolve([:]) == SwitchbackServing(status: .ineligible, unitType: "user_id", clusterKey: nil))
		#expect(resolve(["a": "x", "b": "y"]).status == .ineligible)
		#expect(resolve(["a": "x", "b": "x"]).status == .eligible)
		#expect(resolve(["b": "y"]) == SwitchbackServing(status: .eligible, unitType: "device_id", clusterKey: "y"))
		#expect(resolve(["a": "x"], allowed: ["y"]).status == .ineligible)
		#expect(resolve(["a": "x"], allowed: ["y", "x"]).status == .eligible)
		#expect(resolve(["a": "x"], allowed: []).status == .eligible)
		// Only linked units present in the context take part.
		#expect(resolve(["a": "x", "b": "y"], units: ["device_id"]).status == .eligible)
		#expect(resolve(["a": "x", "b": "y"], units: ["device_id"]).unitType == "device_id")
	}

	@Test func legacyServesAnIneligibleControlUnderTheDeclaredUnit() {
		#expect(SwitchbackServing.legacy(unitType: "u", hasUnit: { $0 == "u" }).status == .ineligible)
		#expect(SwitchbackServing.legacy(unitType: "u", hasUnit: { $0 == "u" }).unitType == "u")
		#expect(SwitchbackServing.legacy(unitType: "u", hasUnit: { _ in false }) == .absent)
		#expect(SwitchbackServing.legacy(unitType: nil, hasUnit: { _ in true }) == .absent)
	}

	// A non-empty string as-is, an integer as base-10 text; every float (3.0 included), bool, object,
	// array, empty string and null gives none.
	@Test func clusterKeyRule() throws {
		#expect(SwitchbackServing.clusterKey("porto") == "porto")
		#expect(SwitchbackServing.clusterKey(42) == "42")
		#expect(SwitchbackServing.clusterKey(-7) == "-7")
		#expect(SwitchbackServing.clusterKey(.int(4_000_000_002)) == "4000000002")
		#expect(SwitchbackServing.clusterKey(.int(.max)) == "9223372036854775807")
		#expect(SwitchbackServing.clusterKey(UInt8(3).jsonValue) == "3")
		for value: JSONValue in [3.0, .double(2), 1.5, -0.0, true, false, "", nil, ["a": "b"], ["x"]] {
			#expect(SwitchbackServing.clusterKey(value) == nil, "\(value)")
		}
		#expect(SwitchbackServing.clusterKey(nil as JSONValue?) == nil)
		// Beyond Int64 a UInt64 is a double, so it keys nothing.
		#expect(SwitchbackServing.clusterKey(UInt64.max.jsonValue) == nil)

		// Parsed from JSON text with `JSONValue(parsing:)`, which keeps a literal with a fraction or
		// exponent a double. (`JSONDecoder` reads a whole `3.0` as the integer 3, which keys "3".)
		let parsed = try JSONValue(parsing: "[3, 3.0, 3e0, -0, 30e-1, 4000000002, true]").arrayValue ?? []
		#expect(parsed.map { SwitchbackServing.clusterKey($0) } == ["3", nil, nil, "0", nil, "4000000002", nil])
	}
}
