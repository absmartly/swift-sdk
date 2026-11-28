import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// Port of java-sdk SwitchbackServerParityTest: replays the Collector's R33 serving rules
// (ContextAPI.switchbackServing and switchbackVariant) through the public Context API. Each case
// states the serving unit type and raw cluster key the Collector picks, or that it records nothing;
// the expected variant is SwitchbackAssigner over that raw key, pinned by the golden vectors.
//
// The Collector's "two units of the same type" case has no SDK counterpart: a context holds one uid
// per unit type, which testSameTypeSecondUidIsRejected asserts.
final class SwitchbackServerParityTest: XCTestCase {
	static let hour: Int64 = 3_600_000
	static let anchor: Int64 = 1_767_225_600_000
	static let periods = 4
	static let arms = 3
	static let seed: Int64 = 1_234_567_890_123

	static let store = "store_id"
	static let device = "device_id"
	static let user = "user_id"

	static let twoSources: [(String, Any)] = [(store, "store_city"), (device, "geo/city")]

	static func experiment(
		seed: Int64 = seed, armCount: Int = arms, _ clusters: [(String, Any)], values: Any? = nil
	) -> [String: Any] {
		var experiment: [String: Any] = [
			// R33 payloads may still carry unitType; it is never used for switchback assignment.
			"id": 1, "name": "exp_sb", "unitType": user, "iteration": 1,
			"seedHi": Int(Int32(truncatingIfNeeded: seed >> 32)), "seedLo": Int(Int32(truncatingIfNeeded: seed)),
			"split": [Double](repeating: 1.0 / Double(armCount), count: armCount),
			"variants": (0..<armCount).map { ["name": "\($0)", "config": NSNull()] }, "trafficSplit": [0.0, 1.0],
			"trafficSeedHi": 0, "trafficSeedLo": 0, "fullOnVariant": 0, "applications": [["name": "website"]],
			"audienceStrict": false, "randomizationType": "switchback", "switchbackClusters": SB.OrderedObject(clusters),
			"switchbackStartAt": anchor, "switchbackPeriodMs": hour, "switchbackDesignType": "balanced_block",
		]
		if let values = values {
			experiment["switchbackClusterValues"] = values
		}
		return experiment
	}

	struct Served {
		var variants: [Int] = []
		var exposures: [Exposure] = []
	}

	static func makeContext(
		_ experiments: [[String: Any]], _ units: [String: String], _ attributes: [(String, JSON)]?,
		clock: MutableClock, logger: ContextEventLoggerMock
	) -> Context {
		let config = ContextConfig()
		for (unitType, uid) in units {
			config.setUnit(unitType: unitType, uid: uid)
		}
		let handler = ContextEventHandlerMock()
		handler.publishEventReturnValue = Promise<Void>.value(())
		let scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		let context = Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: ContextDataProviderMock(),
			logger: logger, parser: DefaultVariableParser(), matcher: AudienceMatcher(),
			promise: Promise<ContextData>.value(SB.data(experiments)), application: "website", environment: "production")
		for (name, value) in attributes ?? [] {
			context.setAttribute(name: name, value: value)
		}
		return context
	}

	static func exposures(_ logger: ContextEventLoggerMock) -> [Exposure] {
		return logger.handleEventContextEventReceivedInvocations.compactMap {
			if case let .exposure(exposure) = $0.event { return exposure }
			return nil
		}
	}

	// Serves `periods` periods with getTreatment, one call per period.
	func serve(_ experiment: [String: Any], _ units: [String: String], _ attributes: [(String, JSON)]?) -> Served {
		let clock = MutableClock(Self.anchor)
		let logger = ContextEventLoggerMock()
		let context = Self.makeContext([experiment], units, attributes, clock: clock, logger: logger)
		var served = Served()
		for p in 0..<Self.periods {
			clock.now = Self.anchor + Int64(p) * Self.hour + 1
			served.variants.append(context.getTreatment("exp_sb"))
		}
		served.exposures = Self.exposures(logger)
		return served
	}

	static func collectorVariant(_ rawKey: String, _ periodIndex: Int) -> Int {
		return SwitchbackAssigner.assign(rawKey, periodIndex: Int64(periodIndex), seed: seed, armCount: arms)
	}

	// The Collector served `key` under a unit of `servingType`: one eligible exposure per period.
	func assertEligible(
		_ served: Served, _ servingType: String, _ key: String, _ message: String, file: StaticString = #filePath,
		line: UInt = #line
	) {
		XCTAssertEqual(Self.periods, served.exposures.count, message, file: file, line: line)
		guard served.exposures.count == Self.periods else { return }
		for p in 0..<Self.periods {
			let expected = Self.collectorVariant(key, p)
			XCTAssertEqual(expected, served.variants[p], "\(message) period \(p)", file: file, line: line)
			let exposure = served.exposures[p]
			XCTAssertEqual(servingType, exposure.unit, message, file: file, line: line)
			XCTAssertEqual(expected, exposure.variant, message, file: file, line: line)
			XCTAssertTrue(exposure.assigned, message, file: file, line: line)
			XCTAssertTrue(exposure.eligible, message, file: file, line: line)
			XCTAssertEqual(Self.anchor + Int64(p) * Self.hour + 1, exposure.exposedAt, message, file: file, line: line)
		}
	}

	// The Collector records nothing: control in every period, no exposure.
	func assertSilentControl(_ served: Served, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
		XCTAssertEqual([Int](repeating: 0, count: Self.periods), served.variants, message, file: file, line: line)
		XCTAssertTrue(served.exposures.isEmpty, "\(message): \(served.exposures)", file: file, line: line)
	}

	static let twoUnits = [store: "s1", device: "d1"]

	// Independent murmur3 reference: periods 0..3 of the raw keys under `seed` with 3 arms.
	func testRawKeySchedulesMatchTheIndependentReference() {
		assertEligible(
			serve(Self.experiment([(Self.store, "city")]), [Self.store: "s1"], [("city", JSON("Lisboa"))]), Self.store,
			"Lisboa", "Lisboa")
		for p in 0..<Self.periods {
			XCTAssertEqual([0, 1, 2, 2][p], Self.collectorVariant("Lisboa", p))
			XCTAssertEqual([2, 1, 0, 1][p], Self.collectorVariant("Porto", p))
			XCTAssertEqual([0, 2, 1, 2][p], Self.collectorVariant("42", p))
		}
	}

	func testAgreementServesTheFirstSourceUnit() {
		assertEligible(
			serve(
				Self.experiment(Self.twoSources), Self.twoUnits,
				[("store_city", JSON("Lisboa")), ("geo", JSON(["city": "Lisboa"]))]), Self.store, "Lisboa", "agreement")
	}

	func testDisagreementIsIneligibleAndRecordsNothing() {
		assertSilentControl(
			serve(
				Self.experiment(Self.twoSources), Self.twoUnits,
				[("store_city", JSON("Lisboa")), ("geo", JSON(["city": "Porto"]))]), "disagreement")
	}

	// A unit yielding no value is skipped; the next unit with a value serves.
	func testMissingValueIsSkippedAndTheNextValueServes() {
		assertEligible(
			serve(Self.experiment(Self.twoSources), Self.twoUnits, [("geo", JSON(["city": "Porto"]))]), Self.device,
			"Porto", "first source missing")
		assertEligible(
			serve(Self.experiment(Self.twoSources), Self.twoUnits, [("store_city", JSON("Porto"))]), Self.store,
			"Porto", "second source missing")
		assertSilentControl(
			serve(Self.experiment(Self.twoSources), Self.twoUnits, [("other", JSON("x"))]), "no value at all")
		assertSilentControl(serve(Self.experiment(Self.twoSources), Self.twoUnits, nil), "no attributes")
	}

	// A unit linked by a source but absent from the context does not take part.
	func testOnlyLinkedUnitsPresentInTheContextTakePart() {
		assertEligible(
			serve(
				Self.experiment(Self.twoSources), [Self.device: "d1"],
				[("store_city", JSON("Lisboa")), ("geo", JSON(["city": "Porto"]))]), Self.device, "Porto",
			"store unit absent")
	}

	func testFilteredValueIsIneligibleAndAllowedValueServes() {
		let lisboa: [(String, JSON)] = [("store_city", JSON("Lisboa"))]
		assertSilentControl(
			serve(Self.experiment(Self.twoSources, values: ["Porto", "Faro"]), Self.twoUnits, lisboa), "filtered")
		assertEligible(
			serve(Self.experiment(Self.twoSources, values: ["Porto", "Lisboa"]), Self.twoUnits, lisboa), Self.store,
			"Lisboa", "allowed")
		// A null or empty allow-list admits every value.
		assertEligible(
			serve(Self.experiment(Self.twoSources, values: NSNull()), Self.twoUnits, lisboa), Self.store, "Lisboa",
			"null filter")
		assertEligible(
			serve(Self.experiment(Self.twoSources, values: [] as [Any]), Self.twoUnits, lisboa), Self.store, "Lisboa",
			"empty filter")
		// The filter compares the normalised text of numeric values.
		assertEligible(
			serve(Self.experiment(Self.twoSources, values: ["42"]), Self.twoUnits, [("store_city", JSON(42))]),
			Self.store, "42", "numeric filter")
		// A filtered first value is not replaced by a later allowed one: they disagree.
		assertSilentControl(
			serve(
				Self.experiment(Self.twoSources, values: ["Porto"]), Self.twoUnits,
				[("store_city", JSON("Lisboa")), ("geo", JSON(["city": "Porto"]))]), "filtered first value")
	}

	// Java throws on a second uid; Swift reports an `.error` event and keeps the first uid.
	func testSameTypeSecondUidIsRejected() {
		let logger = ContextEventLoggerMock()
		let context = Self.makeContext([], [:], nil, clock: MutableClock(Self.anchor), logger: logger)
		context.setUnit(unitType: Self.store, uid: "s1")
		context.setUnit(unitType: Self.store, uid: "s2")
		XCTAssertEqual("s1", context.getUnit(unitType: Self.store))
		XCTAssertTrue(
			logger.handleEventContextEventReceivedInvocations.contains {
				if case .error = $0.event { return true }
				return false
			})
		assertEligible(
			serve(Self.experiment([(Self.store, "city")]), [Self.store: "s1"], [("city", JSON("Faro"))]), Self.store,
			"Faro", "single unit of the type")
	}

	// The declared order (unit_type_id ascending) decides, not the order units were set or named.
	func testLowerUnitTypeIdSourceServesFirst() {
		let deviceFirst: [(String, Any)] = [(Self.device, "geo/city"), (Self.store, "store_city")]
		let agreeing: [(String, JSON)] = [("store_city", JSON("Lisboa")), ("geo", JSON(["city": "Lisboa"]))]
		assertEligible(
			serve(Self.experiment(deviceFirst), Self.twoUnits, agreeing), Self.device, "Lisboa", "device declared first")
		assertEligible(
			serve(Self.experiment(Self.twoSources), Self.twoUnits, agreeing), Self.store, "Lisboa",
			"store declared first")
	}

	// Booleans, fractions, exponent-form numbers, objects, arrays, null and "" yield no value:
	// skipped, never a disagreement.
	func testNonKeyValuesAreIgnored() {
		let ignored: [JSON] = [
			JSON(true), JSON(false), JSON(1.5), JSON(1e20), JSON(["a": "b"]), JSON(["x"]),
			JSON([] as [Any]), JSON.null, JSON(""),
		]
		for value in ignored {
			let message = "ignored \(value)"
			assertEligible(
				serve(
					Self.experiment(Self.twoSources), Self.twoUnits,
					[("store_city", value), ("geo", JSON(["city": "Porto"]))]), Self.device, "Porto", message)
			assertSilentControl(
				serve(Self.experiment([(Self.store, "store_city")]), [Self.store: "s1"], [("store_city", value)]),
				message + " alone")
		}
	}

	// Integers are keyed by their base-10 text, so they agree with that text; floats and decimals
	// give no value (java-sdk SwitchbackClusterKeys.normalize).
	func testNumericValuesAreKeyedAsText() {
		let fortyTwo: [JSON] = [JSON(42), JSON(Int64(42)), JSON(Int16(42)), JSON(Int8(42)), JSON("42")]
		for storeValue in fortyTwo {
			for deviceValue in fortyTwo {
				assertEligible(
					serve(
						Self.experiment(Self.twoSources), Self.twoUnits,
						[("store_city", storeValue), ("geo", JSON(["city": deviceValue.object]))]), Self.store, "42",
					"\(storeValue)/\(deviceValue)")
			}
		}
		for value in [
			JSON(42.0), JSON(Float(42)), JSON(NSDecimalNumber(string: "42")),
			JSON(NSDecimalNumber(string: "123456789012345678901234567890")),
		] {
			assertSilentControl(
				serve(Self.experiment([(Self.store, "n")]), [Self.store: "s1"], [("n", value)]), "no key for \(value)")
		}
		assertEligible(
			serve(Self.experiment([(Self.store, "n")]), [Self.store: "s1"], [("n", JSON(Int64(-7)))]), Self.store, "-7",
			"negative")
		assertSilentControl(
			serve(
				Self.experiment(Self.twoSources), Self.twoUnits,
				[("store_city", JSON(42)), ("geo", JSON(["city": "042"]))]),
			"42 vs 042 disagree")
	}

	// A malformed path makes the whole experiment unservable: ineligible control for any linked unit,
	// even when another source is valid.
	func testMalformedPathsAreUnservable() {
		let attributes: [(String, JSON)] = [
			("store_city", JSON("Lisboa")), ("geo", JSON(["city": "Porto"])), ("geo.city", JSON("Faro")),
		]
		for path in ["'geo/city", "\"geo", "geo/'city", "geo.city", "geo/a.b", "'geo.city'", "\"geo.city\""] {
			assertSilentControl(
				serve(Self.experiment([(Self.store, "store_city"), (Self.device, path)]), Self.twoUnits, attributes), path)
			assertSilentControl(serve(Self.experiment([(Self.device, path)]), Self.twoUnits, attributes), path + " alone")
		}
	}

	// No context unit of any linked type: the experiment does not apply; unitType is never used.
	func testNoLinkedUnitIsAbsent() {
		assertSilentControl(
			serve(Self.experiment(Self.twoSources), [Self.user: "u1"], [("store_city", JSON("Lisboa"))]),
			"no linked unit")
	}

	// Traffic eligibility is sticky on the serving unit's hash: it equals that of a unit experiment on
	// the serving unit's type with the same traffic seed and split, in every period.
	func testTrafficFollowsTheServingUnitHash() {
		var eligible = 0
		var ineligible = 0
		for u in 0..<24 {
			var switchback = Self.experiment(Self.twoSources)
			switchback["trafficSplit"] = [0.5, 0.5]
			switchback["trafficSeedHi"] = 3
			switchback["trafficSeedLo"] = 4
			var twin = switchback
			twin["name"] = "exp_unit"
			twin["id"] = 2
			twin.removeValue(forKey: "randomizationType")
			twin["unitType"] = Self.device

			let clock = MutableClock(Self.anchor)
			let logger = ContextEventLoggerMock()
			// Only the device unit has a value, so it serves.
			let context = Self.makeContext(
				[switchback, twin], [Self.store: "s1", Self.device: "device-\(u)"], [("geo", JSON(["city": "Porto"]))],
				clock: clock, logger: logger)
			_ = context.getTreatment("exp_unit")
			let twinEligible = Self.exposures(logger)[0].eligible
			for p in 0..<Self.periods {
				clock.now = Self.anchor + Int64(p) * Self.hour
				let variant = context.getTreatment("exp_sb")
				let exposure = Self.exposures(logger)[p + 1]
				XCTAssertEqual(Self.device, exposure.unit)
				XCTAssertEqual(twinEligible, exposure.eligible)
				XCTAssertEqual(twinEligible ? Self.collectorVariant("Porto", p) : 0, variant)
			}
			if twinEligible {
				eligible += 1
			} else {
				ineligible += 1
			}
		}
		XCTAssertGreaterThan(eligible, 0)
		XCTAssertGreaterThan(ineligible, 0)
	}

	static func resource(_ name: String) throws -> Data {
		return try Data(
			contentsOf: URL(fileURLWithPath: TestResources.path(forResource: name, ofType: "json", subdirectory: "switchback")))
	}

	// Each attribute-path-cases.json case, served as a cluster path over the fixture's attributes.
	func testAttributePathCasesMatchTheCollector() throws {
		let fixture = try JSON(data: Self.resource("attribute-path-cases"))
		let attributes = fixture["attributes"].dictionaryValue.map { ($0.key, $0.value) }
		var eligibleCases = 0
		for c in fixture["cases"].arrayValue {
			let served = serve(Self.experiment([(Self.store, c["path"].stringValue)]), [Self.store: "s1"], attributes)
			if !c["supported"].boolValue || c["value"].type == .null {
				assertSilentControl(served, "\(c)")
				continue
			}
			assertEligible(served, Self.store, c["value"].stringValue, "\(c)")
			eligibleCases += 1
		}
		XCTAssertEqual(3, eligibleCases)
	}

	// The latest value of a repeated attribute name wins; names are matched trimmed.
	func testRepeatedAttributeNamesResolveToTheLatest() {
		assertEligible(
			serve(Self.experiment([(Self.store, "cluster")]), [Self.store: "s1"], [(" cluster ", JSON("Porto"))]),
			Self.store, "Porto", "trimmed name")

		let clock = MutableClock(Self.anchor)
		let logger = ContextEventLoggerMock()
		let context = Self.makeContext(
			[Self.experiment([(Self.store, "cluster")])], [Self.store: "s1"],
			[("cluster", JSON("Lisboa")), ("cluster", JSON("Porto"))], clock: clock, logger: logger)
		clock.now = Self.anchor + 1
		XCTAssertEqual(Self.collectorVariant("Porto", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(true, Self.exposures(logger).first?.eligible)
	}

	// The vendored fixtures are the Collector's blobs at absmartly/abs 9bd2b5ca35:
	// lib/utils/src/test/resources/switchback/golden-vectors.json (git blob b314abeb9e97) and
	// collector/src/test/resources/switchback/attribute-path-cases.json (git blob 7b1d3fed5985). Java
	// pins SHA-256s of the bytes; this pins the git blob ids themselves, plus the same SHA-256s.
	func testSharedFixturesMatchCollectorBlobs() throws {
		let vectors = try Self.resource("golden-vectors")
		let paths = try Self.resource("attribute-path-cases")
		XCTAssertEqual("b314abeb9e97b35f911c7caacec90b8ff73b9d77", Self.gitBlobId(vectors))
		XCTAssertEqual("7b1d3fed59856fcbc296ed68a820b43359ae1932", Self.gitBlobId(paths))
		XCTAssertEqual("66dda4bafddaa119b030beafff8dc56f5750a8387919ffbe0842c93525ef32b6", Self.hex(SHA256.digest(Array(vectors))))
		XCTAssertEqual("2ee7eb0053997b48b8992980ffe11fe3accb2db01471aa9a617420e1609c6518", Self.hex(SHA256.digest(Array(paths))))
		// The abandoned Phase 1E bucket fixture is not vendored.
		let bucket = (TestResources.path(forResource: "golden-vectors", ofType: "json", subdirectory: "switchback") as NSString)
			.deletingLastPathComponent + "/bucket-golden-vectors.json"
		XCTAssertFalse(FileManager.default.fileExists(atPath: bucket))
	}

	static func gitBlobId(_ data: Data) -> String {
		return hex(SHA1.digest(Array("blob \(data.count)\0".utf8) + Array(data)))
	}

	static func hex(_ bytes: [UInt8]) -> String {
		return bytes.map { String(format: "%02x", $0) }.joined()
	}

	func testDeclaredOrderInvariant() {
		XCTAssertEqual([Self.store, Self.device], Self.twoSources.map { $0.0 })
	}
}

// Minimal SHA-1 and SHA-256 (FIPS 180-4), only for pinning the vendored fixtures.
private enum SHA1 {
	static func digest(_ message: [UInt8]) -> [UInt8] {
		var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
		for chunk in padded(message) {
			var w = [UInt32](repeating: 0, count: 80)
			for i in 0..<16 {
				w[i] = chunk[i]
			}
			for i in 16..<80 {
				w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
			}
			var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
			for i in 0..<80 {
				let (f, k): (UInt32, UInt32)
				switch i {
				case 0..<20: (f, k) = ((b & c) | (~b & d), 0x5A82_7999)
				case 20..<40: (f, k) = (b ^ c ^ d, 0x6ED9_EBA1)
				case 40..<60: (f, k) = ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
				default: (f, k) = (b ^ c ^ d, 0xCA62_C1D6)
				}
				let t = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
				(e, d, c, b, a) = (d, c, rotl(b, 30), a, t)
			}
			h[0] = h[0] &+ a
			h[1] = h[1] &+ b
			h[2] = h[2] &+ c
			h[3] = h[3] &+ d
			h[4] = h[4] &+ e
		}
		return h.flatMap { bigEndian($0) }
	}
}

private enum SHA256 {
	static let k: [UInt32] = [
		0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
		0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
		0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
		0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
		0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
		0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
		0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
		0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
	]

	static func digest(_ message: [UInt8]) -> [UInt8] {
		var h: [UInt32] = [
			0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
		]
		for chunk in padded(message) {
			var w = [UInt32](repeating: 0, count: 64)
			for i in 0..<16 {
				w[i] = chunk[i]
			}
			for i in 16..<64 {
				let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
				let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
				w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
			}
			var v = h
			for i in 0..<64 {
				let s1 = rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25)
				let ch = (v[4] & v[5]) ^ (~v[4] & v[6])
				let t1 = v[7] &+ s1 &+ ch &+ k[i] &+ w[i]
				let s0 = rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22)
				let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
				let t2 = s0 &+ maj
				v = [t1 &+ t2, v[0], v[1], v[2], v[3] &+ t1, v[4], v[5], v[6]]
			}
			for i in 0..<8 {
				h[i] = h[i] &+ v[i]
			}
		}
		return h.flatMap { bigEndian($0) }
	}
}

// The message padded to 512-bit blocks, each as 16 big-endian words.
private func padded(_ message: [UInt8]) -> [[UInt32]] {
	var bytes = message
	bytes.append(0x80)
	while bytes.count % 64 != 56 {
		bytes.append(0)
	}
	let bits = UInt64(message.count) * 8
	for shift in stride(from: 56, through: 0, by: -8) {
		bytes.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
	}
	return stride(from: 0, to: bytes.count, by: 64).map { start in
		(0..<16).map { i in
			let o = start + i * 4
			return UInt32(bytes[o]) << 24 | UInt32(bytes[o + 1]) << 16 | UInt32(bytes[o + 2]) << 8 | UInt32(bytes[o + 3])
		}
	}
}

private func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
	return (x << n) | (x >> (32 - n))
}

private func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
	return (x >> n) | (x << (32 - n))
}

private func bigEndian(_ x: UInt32) -> [UInt8] {
	return [UInt8(x >> 24), UInt8(truncatingIfNeeded: x >> 16), UInt8(truncatingIfNeeded: x >> 8), UInt8(truncatingIfNeeded: x)]
}
