import Foundation
import XCTest

@testable import ABSmartly

// Resources/switchback/golden-vectors.json is copied byte-for-byte from absmartly/abs 9bd2b5ca35
// lib/utils/src/test/resources/switchback/golden-vectors.json (git blob b314abeb9e97), via java-sdk
// 07807b51 core-api/src/test/resources/switchback/golden-vectors.json. Port of java-sdk
// SwitchbackAssignerGoldenVectorsTest.
final class SwitchbackAssignerGoldenVectorsTest: XCTestCase {
	static func loadVectors() throws -> [String: Any] {
		let path = TestResources.path(forResource: "golden-vectors", ofType: "json", subdirectory: "switchback")
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		return try JSONSerialization.jsonObject(with: data) as! [String: Any]
	}

	// The platform hashes a numeric cluster unit as its decimal text; strings pass through.
	static func clusterUnit(_ value: Any) -> String {
		if let string = value as? String {
			return string
		}
		let number = value as! NSNumber
		// `CFNumberIsFloatType` is not available on Linux; the Objective-C type encoding is.
		let type = String(cString: number.objCType)
		XCTAssertFalse(type == "d" || type == "f", "clusterUnit must be a string or integer: \(number)")
		return number.stringValue
	}

	// 64-bit fields are decimal strings; a number would mean the fixture regressed to a lossy encoding.
	static func exactInt64(_ value: Any?) -> Int64 {
		guard let string = value as? String, let parsed = Int64(string) else {
			XCTFail("64-bit field must be a decimal string: \(String(describing: value))")
			return 0
		}
		return parsed
	}

	func testAssignSwitchbackMatchesEveryGoldenVector() throws {
		let cases = try Self.loadVectors()["assignSwitchback"] as! [[String: Any]]
		XCTAssertEqual(882, cases.count)

		var armCounts = Set<Int>()
		var boundaryCases = 0
		var integerUnits = 0
		for c in cases {
			let unit = Self.clusterUnit(c["clusterUnit"]!)
			if c["clusterUnit"] is NSNumber {
				integerUnits += 1
			}
			let periodIndex = Self.exactInt64(c["periodIndex"])
			let seed = Self.exactInt64(c["seed"])
			let armCount = c["armCount"] as! Int
			armCounts.insert(armCount)
			if [Int64.min, Int64.max].contains(periodIndex) || [Int64.min, Int64.max].contains(seed) {
				boundaryCases += 1
			}

			XCTAssertEqual(
				c["expectedVariant"] as? Int,
				SwitchbackAssigner.assign(unit, periodIndex: periodIndex, seed: seed, armCount: armCount), "\(c)")
		}

		XCTAssertEqual([2, 3, 10], armCounts)
		XCTAssertGreaterThan(boundaryCases, 0)
		XCTAssertGreaterThan(integerUnits, 0)
	}

	func testFisherYatesPermutationMatchesEveryGoldenVector() throws {
		let cases = try Self.loadVectors()["fisherYatesPermutation"] as! [[String: Any]]
		XCTAssertEqual(504, cases.count)

		for c in cases {
			let unit = Self.clusterUnit(c["clusterUnit"]!)
			let cycleIndex = Self.exactInt64(c["cycleIndex"])
			let seed = Self.exactInt64(c["seed"])
			let armCount = c["armCount"] as! Int

			XCTAssertEqual(
				c["expectedPermutation"] as? [Int],
				SwitchbackAssigner.fisherYatesPermutation(
					armCount, baseHash: SwitchbackAssigner.baseHash(unit, cycleIndex: cycleIndex, seed: seed)),
				"\(c)")
		}
	}

	func testEveryCycleCoversEveryArmExactlyOnce() {
		for armCount in [2, 3, 10] {
			for cycle in Int64(-3)..<20 {
				var seen = [Bool](repeating: false, count: armCount)
				for slot in 0..<armCount {
					let variant = SwitchbackAssigner.assign(
						"store_42", periodIndex: cycle * Int64(armCount) + Int64(slot), seed: 0x1234_5678_9abc,
						armCount: armCount)
					XCTAssertFalse(seen[variant], "arm repeated within a cycle")
					seen[variant] = true
				}
			}
		}
	}

	func testFloorDiv() {
		XCTAssertEqual(0, SwitchbackAssigner.floorDiv(0, 3))
		XCTAssertEqual(0, SwitchbackAssigner.floorDiv(2, 3))
		XCTAssertEqual(1, SwitchbackAssigner.floorDiv(3, 3))
		XCTAssertEqual(-1, SwitchbackAssigner.floorDiv(-1, 3))
		XCTAssertEqual(-1, SwitchbackAssigner.floorDiv(-3, 3))
		XCTAssertEqual(-2, SwitchbackAssigner.floorDiv(-4, 3))
		// Math.floorDiv(Long.MIN_VALUE, 3L) and Math.floorDiv(Long.MAX_VALUE, 10L).
		XCTAssertEqual(-3_074_457_345_618_258_603, SwitchbackAssigner.floorDiv(Int64.min, 3))
		XCTAssertEqual(922_337_203_685_477_580, SwitchbackAssigner.floorDiv(Int64.max, 10))
		XCTAssertEqual(Int64.min, SwitchbackAssigner.floorDiv(Int64.min, 1))
	}

	// The cluster key is the raw value: neither hashing it nor rendering an integer as a double gives
	// the same draw. Pinned values come from the golden vectors' formula (java-sdk's assigner).
	func testClusterKeyIsHashedRawNotPreHashed() {
		let seed: Int64 = (Int64(-5) << 32) | (Int64(-7) & 0xFFFF_FFFF)
		let schedule = (0..<12).map { SwitchbackAssigner.assign("store-42", periodIndex: Int64($0), seed: seed, armCount: 3) }
		XCTAssertEqual([0, 2, 1, 2, 1, 0, 1, 2, 0, 1, 0, 2], schedule)
		let hashed = (0..<12).map {
			SwitchbackAssigner.assign(Hashing.hash("store-42"), periodIndex: Int64($0), seed: seed, armCount: 3)
		}
		XCTAssertNotEqual(schedule, hashed)
	}
}

extension SwitchbackAssignerGoldenVectorsTest {
	func testPublicEntryPointsMatchAndRejectFewerThanTwoArms() throws {
		let vectors = try Self.loadVectors()
		for c in (vectors["assignSwitchback"] as! [[String: Any]]).prefix(50) {
			XCTAssertEqual(
				c["expectedVariant"] as? Int,
				SwitchbackAssigner.variant(
					clusterUnit: Self.clusterUnit(c["clusterUnit"]!), periodIndex: Self.exactInt64(c["periodIndex"]),
					seed: Self.exactInt64(c["seed"]), armCount: c["armCount"] as! Int))
		}
		for c in (vectors["fisherYatesPermutation"] as! [[String: Any]]).prefix(50) {
			XCTAssertEqual(
				c["expectedPermutation"] as? [Int],
				SwitchbackAssigner.permutation(
					clusterUnit: Self.clusterUnit(c["clusterUnit"]!), cycleIndex: Self.exactInt64(c["cycleIndex"]),
					seed: Self.exactInt64(c["seed"]), armCount: c["armCount"] as! Int))
		}
		XCTAssertNil(SwitchbackAssigner.variant(clusterUnit: "u", periodIndex: 0, seed: 0, armCount: 1))
		XCTAssertNil(SwitchbackAssigner.variant(clusterUnit: "u", periodIndex: 0, seed: 0, armCount: -3))
		XCTAssertNil(SwitchbackAssigner.permutation(clusterUnit: "u", cycleIndex: 0, seed: 0, armCount: 0))
	}
}
