import Foundation
import XCTest

@testable import ABSmartly

// Cluster key selection inside Context. Port of java-sdk ContextSwitchbackClusterTest: variants are
// derived from the raw key and SwitchbackAssigner, both pinned by the platform golden vectors.
final class ContextSwitchbackClusterTest: SwitchbackTestCase {
	// 3 arms over 12 periods: two keys in different buckets are told apart by their schedules.
	static let arms = 3

	static func attributeSwitchback(_ path: Any, _ change: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
		var experiment = SB.switchback(arms: arms, periodMs: SB.hour, clusters: [(SB.unitType, path)])
		change(&experiment)
		return experiment
	}

	static func dataOf(_ experiment: [String: Any]) -> ContextData {
		return SB.data([experiment])
	}

	static func dataOf(_ path: String) -> ContextData {
		return dataOf(attributeSwitchback(path))
	}

	static func expected(_ key: String, _ periodIndex: Int64) -> Int {
		return SB.draw(key, periodIndex, arms: arms)
	}

	static func expectedSchedule(_ key: String) -> [Int] {
		return (0..<12).map { expected(key, Int64($0)) }
	}

	func clusterExposure(_ variant: Int, _ exposedAt: Int64, eligible: Bool = true, audienceMismatch: Bool = false)
		-> Exposure
	{
		return exposure(variant, exposedAt, eligible: eligible, audienceMismatch: audienceMismatch)
	}

	// A context without the default cluster attribute, so only the attributes a test sets are read.
	func create(_ data: ContextData, units: [String: String]? = [SB.unitType: SB.uid]) -> Context {
		return createContext(data, units: units, clusterAttribute: false)
	}

	func exposeAndPublish(_ context: Context) -> PublishEvent? {
		clock.now = SB.anchor
		_ = context.getTreatment("exp_sb")
		return publish(context)
	}

	// The unit uid is never the cluster key: with no cluster value the unit is ineligible.
	func testUnitUidIsNeverTheClusterKey() {
		let context = create(Self.dataOf("city"))
		for i in 0..<3 {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(0, context.getTreatment("exp_sb"))
		}
		XCTAssertEqual(0, context.getPendingCount())
	}

	// A numeric UID serves and publishes under its canonical string (JavaScript toFixed(0)), exactly as
	// the same string UID does; the cluster key is the attribute.
	func testNumericUnitUidClustersLikeItsCanonicalString() {
		let cases: [(JSON, String)] = [
			(JSON(123_456_789), "123456789"), (JSON(123_456_789.0), "123456789"),
			(JSON(Int64(9_007_199_254_740_993)), "9007199254740992"), (JSON(125.75), "126"),
		]
		for (numericUid, text) in cases {
			let numeric = createContext(Self.dataOf("city"), units: nil, clusterAttribute: false) {
				$0.setUnit(unitType: SB.unitType, value: numericUid)
			}
			clock.now = SB.anchor
			numeric.setAttribute(name: "city", value: JSON("Lisboa"))
			let numericEvent = exposeAndPublish(numeric)
			let numericSchedule = peekSchedule(numeric)
			let textContext = create(Self.dataOf("city"), units: [SB.unitType: text])
			clock.now = SB.anchor
			textContext.setAttribute(name: "city", value: JSON("Lisboa"))
			let textEvent = exposeAndPublish(textContext)

			XCTAssertEqual(Self.expectedSchedule("Lisboa"), numericSchedule, text)
			XCTAssertEqual(peekSchedule(textContext), numericSchedule, text)
			XCTAssertEqual(textEvent?.units, numericEvent?.units, text)
			XCTAssertEqual(textEvent?.exposures, numericEvent?.exposures, text)
			XCTAssertEqual(Hashing.hash(text), numericEvent?.units.first?.uid, text)
		}
	}

	// Independent reference (Python MD5/base64url) for the published hash of numeric UIDs, and the
	// raw-key schedule of "123456789" as a numeric attribute value (murmur3 reference).
	func testNumericUnitUidMatchesTheIndependentReference() {
		let cases: [(JSON, String)] = [
			(JSON(123_456_789), "JfnnlDI7RTiF9RgfG2JNCw"),
			(JSON(Int64(9_007_199_254_740_993)), "OngwCmjeKhIQyeNybDy4eg"),
		]
		let schedule = [0, 2, 1, 0, 1, 2, 0, 1, 2, 2, 1, 0]
		for (uid, hash) in cases {
			let context = createContext(Self.dataOf("region"), units: nil, clusterAttribute: false) {
				$0.setUnit(unitType: SB.unitType, value: uid)
			}
			clock.now = SB.anchor
			context.setAttribute(name: "region", value: JSON(123_456_789))
			let event = exposeAndPublish(context)

			XCTAssertEqual(hash, event?.units.first?.uid)
			XCTAssertEqual([clusterExposure(schedule[0], SB.anchor)], event?.exposures)
			XCTAssertEqual(schedule, peekSchedule(context))
		}
	}

	// Periods 0..11 of the raw key "Lisboa", from the independent murmur3 reference.
	func testAttributeSourceServesTheRawAttributeValue() {
		clock.now = SB.anchor
		let context = create(Self.dataOf("city"))
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		XCTAssertEqual([0, 2, 1, 2, 1, 0, 1, 0, 2, 0, 1, 2], peekSchedule(context))
		XCTAssertEqual(Self.expectedSchedule("Lisboa"), peekSchedule(context))
	}

	func testUnitsSharingAnAttributeValueShareTheSchedule() {
		let lisboa = create(Self.dataOf("city"))
		lisboa.setAttribute(name: "city", value: JSON("Lisboa"))
		let porto = create(Self.dataOf("city"))
		porto.setAttribute(name: "city", value: JSON("Porto"))
		let otherLisboa = create(Self.dataOf("city"), units: [SB.unitType: "another-store"])
		otherLisboa.setAttribute(name: "city", value: JSON("Lisboa"))

		XCTAssertEqual(Self.expectedSchedule("Lisboa"), peekSchedule(lisboa))
		XCTAssertEqual(Self.expectedSchedule("Lisboa"), peekSchedule(otherLisboa))
		XCTAssertEqual(Self.expectedSchedule("Porto"), peekSchedule(porto))
		XCTAssertNotEqual(Self.expectedSchedule("Lisboa"), Self.expectedSchedule("Porto"))
	}

	func testNestedAndArrayPathsAndIntegerValuesResolve() {
		clock.now = SB.anchor
		let nested = create(Self.dataOf("geo/city"))
		nested.setAttribute(name: "geo", value: JSON(["city": "Porto"]))
		XCTAssertEqual(Self.expectedSchedule("Porto"), peekSchedule(nested))

		clock.now = SB.anchor
		let array = create(Self.dataOf("items/1/city"))
		array.setAttribute(name: "items", value: JSON([["city": "Lisbon"], ["city": "Faro"]]))
		XCTAssertEqual(Self.expectedSchedule("Faro"), peekSchedule(array))

		clock.now = SB.anchor
		let integer = create(Self.dataOf("region"))
		integer.setAttribute(name: "region", value: JSON(Int64(42)))
		XCTAssertEqual(Self.expectedSchedule("42"), peekSchedule(integer))

		// Nested numeric leaves follow the same rule: an integer keys, a decimal or float does not.
		clock.now = SB.anchor
		let nestedInteger = create(Self.dataOf("geo/city"))
		nestedInteger.setAttribute(name: "geo", value: JSON(["city": 42]))
		XCTAssertEqual(Self.expectedSchedule("42"), peekSchedule(nestedInteger))
		let decimal = create(Self.dataOf("geo/city"))
		decimal.setAttribute(name: "geo", value: JSON(["city": NSDecimalNumber(string: "42")]))
		XCTAssertEqual([Int](repeating: 0, count: 12), peekSchedule(decimal))

		clock.now = SB.anchor
		let character = create(Self.dataOf("city"))
		character.setAttribute(name: "city", value: JSON(String(Character("c"))))
		XCTAssertEqual(Self.expectedSchedule("c"), peekSchedule(character))

		clock.now = SB.anchor + 10
		let floating = create(Self.dataOf("city"))
		floating.setAttribute(name: "city", value: JSON(Float(2)))
		XCTAssertEqual(0, floating.getTreatment("exp_sb"))
		XCTAssertEqual(0, floating.getPendingCount())
	}

	// Owner decision 2026-11-28 (match java-sdk/rust-sdk): a float never keys a cluster, even when it
	// is whole and is published as an integer. Only an integer storage type keys. Pinned at direct and
	// nested paths, for values built in Swift and parsed from JSON text.
	func testOnlyIntegerNumbersKeyAClusterAtDirectAndNestedPaths() throws {
		let cases: [(String, JSON, String?)] = [
			("integer", JSON(3), "3"), ("string", JSON("3"), "3"), ("parsed integer", try JSON(data: Data("[3]".utf8))[0], "3"),
			("large integer", try JSON(data: Data("[123456789]".utf8))[0], "123456789"),
			("integer zero", try JSON(data: Data("[-0]".utf8))[0], "0"),
			("Int64.min", JSON(Int64.min), "-9223372036854775808"), ("UInt64.max", JSON(UInt64.max), "18446744073709551615"),
			("double", JSON(3.0), nil), ("parsed whole float", try JSON(data: Data("[3.0]".utf8))[0], nil),
			("parsed large whole float", try JSON(data: Data("[123456789.0]".utf8))[0], nil),
			("parsed negative zero", try JSON(data: Data("[-0.0]".utf8))[0], nil),
			("parseJSON whole float", JSON(parseJSON: "[3.0]")[0], nil),
			("negative zero", JSON(-0.0), nil), ("float", JSON(Float(2)), nil), ("fraction", JSON(3.5), nil),
			("parsed exponent", try JSON(data: Data("[3e0]".utf8))[0], nil), ("whole decimal", JSON(NSDecimalNumber(string: "42")), nil),
			("true", JSON(true), nil),
		]
		for (label, value, key) in cases {
			for nested in [false, true] {
				let context = create(Self.dataOf(nested ? "items/0/cluster" : "number"))
				clock.now = SB.anchor
				context.setAttribute(name: nested ? "items" : "number", value: nested ? JSON([["cluster": value.object]]) : value)
				let expected = key.map { Self.expectedSchedule($0) } ?? [Int](repeating: 0, count: 12)
				XCTAssertEqual(expected, peekSchedule(context), "\(label), nested=\(nested)")
				clock.now = SB.anchor
				let event = try XCTUnwrap(exposeAndPublish(context) ?? PublishEvent(), label)
				XCTAssertEqual(key.map { [clusterExposure(Self.expected($0, 0), SB.anchor)] } ?? [], event.exposures,
					"\(label), nested=\(nested)")
			}
		}
	}

	// The released 1.5.0 attribute encoding is unchanged: a whole float is still published as written
	// by JSONEncoder, with or without a switchback; only the cluster rule changed.
	func testPublishedAttributeBytesAreUnchanged() throws {
		for (value, token) in [(JSON(3.0), "3"), (JSON(3), "3"), (JSON(-0.0), "0"), (JSON(3.5), "3.5")] {
			let event = PublishEvent(false, [], 0, [], [], [Attribute("number", value: value, setAt: 0)])
			let body = String(data: try JSONEncoder().encode(event), encoding: .utf8)!
			XCTAssertTrue(body.contains("\"value\":\(token)"), body)
		}
	}

	func testNonfiniteNumbersYieldNoCluster() {
		for value in [JSON(Double.nan), JSON(Double.infinity), JSON(-Double.infinity), JSON(NSDecimalNumber.notANumber)] {
			XCTAssertNil(SwitchbackServing.clusterKey(value))
		}
	}

	// Attribute values that yield no cluster key serve variant 0, not eligible, record no exposure.
	func testValuesWithoutAClusterKeyAreIneligible() {
		let values: [JSON] = [JSON.null, JSON(""), JSON(true), JSON(1.5), JSON(2.0), JSON(["a": "b"]), JSON(["x"])]
		for value in values {
			let context = create(Self.dataOf("city"))
			context.setAttribute(name: "city", value: value)
			clock.now = SB.anchor + 10
			XCTAssertEqual(0, context.getTreatment("exp_sb"), "\(value)")
			// Variant 0's own config, like any ineligible assignment.
			XCTAssertEqual(0, context.getVariableValue("sb.arm", defaultValue: JSON(-1))?.intValue, "\(value)")
			XCTAssertEqual(0, context.getPendingCount(), "\(value)")
		}

		let missing = create(Self.dataOf("geo/city"))
		missing.setAttribute(name: "geo", value: JSON(["country": "PT"]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(0, missing.getTreatment("exp_sb"))
		XCTAssertEqual(0, missing.getPendingCount())
	}

	// Cluster keys compare by UTF-16 code units, as Java's String.equals and JavaScript's === do: a
	// composed "é" and a decomposed "e" + U+0301 are different keys, though Swift's == calls them equal.
	func testCanonicallyEquivalentClusterKeysAreDistinct() {
		let composed = "Caf\u{E9}"
		let decomposed = "Cafe\u{301}"
		XCTAssertEqual(composed, decomposed)

		let allowList = Self.attributeSwitchback("city") { $0["switchbackClusterValues"] = [composed] }
		let filtered = create(Self.dataOf(allowList))
		filtered.setAttribute(name: "city", value: JSON(decomposed))
		clock.now = SB.anchor
		XCTAssertEqual(0, filtered.getTreatment("exp_sb"))
		XCTAssertEqual(0, filtered.getPendingCount())

		let allowed = create(Self.dataOf(allowList))
		allowed.setAttribute(name: "city", value: JSON(composed))
		XCTAssertEqual(Self.expected(composed, 0), allowed.getTreatment("exp_sb"))
		XCTAssertEqual(1, allowed.getPendingCount())

		let twoSources = SB.switchback(
			arms: Self.arms, periodMs: SB.hour, clusters: [(SB.unitType, "city"), ("device_id", "town")])
		let disagreeing = create(SB.data([twoSources]), units: [SB.unitType: SB.uid, "device_id": "device-1"])
		disagreeing.setAttribute(name: "city", value: JSON(composed))
		disagreeing.setAttribute(name: "town", value: JSON(decomposed))
		XCTAssertEqual(0, disagreeing.getTreatment("exp_sb"))
		XCTAssertEqual(0, disagreeing.getPendingCount())
	}

	func testUnicodeRootAndNestedAttributeNamesMatchExactly() {
		for nested in [false, true] {
			let context = create(Self.dataOf(nested ? "geo/cafe\u{301}" : "cafe\u{301}"))
			clock.now = SB.anchor
			context.setAttribute(name: nested ? "geo" : "caf\u{E9}",
				value: nested ? JSON(["caf\u{E9}": "market_1"]) : JSON("market_1"))
			XCTAssertEqual(0, context.getTreatment("exp_sb"))
			XCTAssertEqual(0, context.getPendingCount())
		}
	}

	func testUnicodeEquivalentUnitTypeDoesNotInventLinkedMembership() {
		let experiment = SB.switchback(arms: 2, periodMs: SB.hour, clusters: [("cafe\u{301}", "city")])
		let context = create(SB.data([experiment]), units: ["caf\u{E9}": "store-1"])
		clock.now = SB.anchor
		context.setAttribute(name: "city", value: JSON("market_1"))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	// Java's unencodableAttributeValuesAreIneligible (a cyclic Map, a plain Object) has no Swift
	// counterpart: an attribute is a `JSON` value, which cannot be cyclic. The closest Swift value, a
	// JSON of an unsupported type, is `.unknown` and yields no key.
	func testUnencodableAttributeValuesAreIneligible() {
		let context = create(Self.dataOf("geo/city"))
		context.setAttribute(name: "geo", value: JSON(NSObject()))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())
	}

	// Unservable configurations serve an ineligible control to linked units, never a unit-assignment
	// draw, and record nothing.
	func testUnservableConfigurationsAreIneligible() {
		var experiments: [[String: Any]] = ["items/0", "items/-1/city", "", "geo.city", "'city", "\"city"].map {
			Self.attributeSwitchback($0)
		}
		experiments.append(Self.attributeSwitchback("city") { $0["switchbackPeriodMs"] = NSNull() })
		experiments.append(Self.attributeSwitchback("city") { $0["switchbackPeriodMs"] = 0 })
		experiments.append(Self.attributeSwitchback("city") { $0["switchbackPeriodMs"] = -SB.hour })
		experiments.append(Self.attributeSwitchback("city") { $0["split"] = [1.0] })
		experiments.append(Self.attributeSwitchback(NSNull()))
		for experiment in experiments {
			let context = create(Self.dataOf(experiment))
			context.setAttribute(name: "city", value: JSON("Lisboa"))
			context.setAttribute(name: "items", value: JSON([["city": "Lisbon"]]))
			for i in 0..<3 {
				clock.now = SB.anchor + Int64(i) * SB.hour
				XCTAssertEqual(0, context.getTreatment("exp_sb"), "\(experiment)")
			}
			XCTAssertEqual(0, context.getPendingCount(), "\(experiment)")
		}
	}

	// A missing or empty cluster map takes the Collector's legacy path: a unit of the declared unitType
	// only identifies an ineligible control (variant 0's config, no exposure); without one the
	// experiment does not apply.
	func testMissingOrEmptyClusterMapIsOnlyALegacyIneligibleControl() {
		let none = SB.switchback(arms: Self.arms, periodMs: SB.hour, clusters: nil)
		let empty = SB.switchback(arms: Self.arms, periodMs: SB.hour, clusters: [])
		for experiment in [none, empty] {
			let context = create(Self.dataOf(experiment))
			context.setAttribute(name: "city", value: JSON("Lisboa"))
			XCTAssertEqual(0, context.getTreatment("exp_sb"))
			XCTAssertEqual(0, context.getVariableValue("sb.arm", defaultValue: JSON(-1))?.intValue)
			XCTAssertEqual(0, context.getPendingCount())

			let other = create(Self.dataOf(experiment), units: ["user_id": "u1"])
			other.setAttribute(name: "city", value: JSON("Lisboa"))
			XCTAssertEqual(0, other.getTreatment("exp_sb"))
			XCTAssertEqual(-1, other.getVariableValue("sb.arm", defaultValue: JSON(-1))?.intValue)
			XCTAssertEqual(0, other.getPendingCount())
		}
	}

	// The Collector reads the attribute set at or before the exposure instant, latest setAt first.
	func testLatestAttributeSetAtOrBeforeTheResolutionInstantIsUsed() {
		let context = create(Self.dataOf("city"))
		clock.now = SB.anchor + 2 * SB.hour
		context.setAttribute(name: "city", value: JSON("Porto"))
		clock.now = SB.anchor + 4 * SB.hour
		context.setAttribute(name: "city", value: JSON("Lisboa"))

		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(0, context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + 3 * SB.hour
		XCTAssertEqual(Self.expected("Porto", 3), context.peekTreatment("exp_sb"))
		clock.now = SB.anchor + 4 * SB.hour
		XCTAssertEqual(Self.expected("Lisboa", 4), context.peekTreatment("exp_sb"))
	}

	// Within a period the cluster key is fixed at first resolution; the next period reads the
	// attribute again.
	func testSetAttributeMidPeriodDoesNotReassignWithinThePeriod() {
		let context = create(Self.dataOf("city"))
		clock.now = SB.anchor + 10
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))

		clock.now = SB.anchor + 20
		context.setAttribute(name: "city", value: JSON("Porto"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.peekTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		let periods = 12
		var differing = 0
		for i in 1..<periods {
			clock.now = SB.anchor + Int64(i) * SB.hour
			XCTAssertEqual(Self.expected("Porto", Int64(i)), context.getTreatment("exp_sb"))
			if Self.expected("Porto", Int64(i)) != Self.expected("Lisboa", Int64(i)) {
				differing += 1
			}
		}
		XCTAssertNotEqual(0, differing)
		XCTAssertEqual(UInt(periods), context.getPendingCount())
	}

	// A unit first resolved without a key stays ineligible (and unrecorded) for the rest of that period.
	func testAttributeSetAfterAnIneligibleResolutionWaitsForTheNextPeriod() {
		let context = create(Self.dataOf("city"))
		clock.now = SB.anchor + 10
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		clock.now = SB.anchor + 20
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())

		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(Self.expected("Lisboa", 1), context.getTreatment("exp_sb"))
		XCTAssertEqual([clusterExposure(Self.expected("Lisboa", 1), SB.anchor + SB.hour)], publishExposures(context))
	}

	// A slot replaced through an ineligible resolution still keeps the period's first key.
	func testTrafficChangesWithinThePeriodKeepThePeriodsBucket() {
		let context = create(Self.dataOf("city"))
		clock.now = SB.anchor + 10
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))

		clock.now = SB.anchor + 20
		context.setAttribute(name: "city", value: JSON("Porto"))
		refresh(context, Self.dataOf(Self.attributeSwitchback("city") { $0["trafficSplit"] = [1.0, 0.0] }))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))

		refresh(context, Self.dataOf("city"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(3, context.getPendingCount())

		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(Self.expected("Porto", 1), context.getTreatment("exp_sb"))
	}

	// The cluster is resolved before traffic: a traffic miss of an eligible cluster is a recorded
	// ineligible exposure under the serving unit, and traffic restored later in the period serves the
	// key read at first resolution.
	func testTrafficRestoredWithinThePeriodKeepsTheKey() {
		let context = create(Self.dataOf(Self.attributeSwitchback("city") { $0["trafficSplit"] = [1.0, 0.0] }))
		clock.now = SB.anchor + 10
		context.setAttribute(name: "city", value: JSON("Faro"))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))

		clock.now = SB.anchor + 20
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		refresh(context, Self.dataOf("city"))
		XCTAssertEqual(1, Self.expected("Faro", 0))
		XCTAssertEqual(Self.expected("Faro", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(
			[clusterExposure(0, SB.anchor + 10, eligible: false), clusterExposure(Self.expected("Faro", 0), SB.anchor + 20)],
			publishExposures(context))
	}

	static let goldAudience = "{\"filter\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"gold\"}]}]}"

	// An audience change re-resolves the period slot (new exposure state) but keeps its key.
	func testAudienceRevalidationAfterSetAttributeKeepsThePeriodsBucket() {
		let context = create(Self.dataOf(Self.attributeSwitchback("city") { $0["audience"] = Self.goldAudience }))
		clock.now = SB.anchor + 10
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		context.setAttribute(name: "tier", value: JSON("gold"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))

		clock.now = SB.anchor + 20
		context.setAttribute(name: "city", value: JSON("Porto"))
		context.setAttribute(name: "tier", value: JSON("silver"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))

		XCTAssertEqual(
			[
				clusterExposure(Self.expected("Lisboa", 0), SB.anchor + 10),
				clusterExposure(Self.expected("Lisboa", 0), SB.anchor + 20, audienceMismatch: true),
			], publishExposures(context))
	}

	// A slot first resolved without a key carries that missing key into its replacement.
	func testAudienceRevalidationAfterAnIneligibleResolutionKeepsTheMissingKey() {
		let context = create(Self.dataOf(Self.attributeSwitchback("city") { $0["audience"] = Self.goldAudience }))
		clock.now = SB.anchor + 10
		context.setAttribute(name: "tier", value: JSON("gold"))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))

		clock.now = SB.anchor + 20
		context.setAttribute(name: "city", value: JSON("Faro"))
		context.setAttribute(name: "tier", value: JSON("silver"))
		XCTAssertEqual(1, Self.expected("Faro", 0))
		XCTAssertEqual(0, context.getTreatment("exp_sb"))
		XCTAssertEqual(0, context.getPendingCount())

		clock.now = SB.anchor + SB.hour
		XCTAssertEqual(Self.expected("Faro", 1), context.peekTreatment("exp_sb"))
		// Period 1 of Faro is variant 0; period 2 is not, so the key is visibly read again.
		clock.now = SB.anchor + 2 * SB.hour
		XCTAssertEqual(2, Self.expected("Faro", 2))
		XCTAssertEqual(Self.expected("Faro", 2), context.peekTreatment("exp_sb"))
	}

	func testClusterPathChangesInvalidateThePeriod() {
		let context = create(Self.dataOf("city"))
		clock.now = SB.anchor + 10
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		context.setAttribute(name: "geo", value: JSON(["city": "Porto"]))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		refresh(context, Self.dataOf("city"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		refresh(context, Self.dataOf("geo/city"))
		XCTAssertEqual(Self.expected("Porto", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())

		refresh(
			context, Self.dataOf(Self.attributeSwitchback("geo/city") { $0["switchbackClusterValues"] = ["Porto", "Faro"] }))
		XCTAssertEqual(Self.expected("Porto", 0), context.getTreatment("exp_sb"))
		XCTAssertEqual(3, context.getPendingCount())
	}

	// Re-linking the experiment to another unit type re-keys the period and moves the exposure unit.
	func testLinkedUnitTypeChangeRekeysThePeriod() {
		let context = create(Self.dataOf("city"), units: [SB.unitType: SB.uid, "user_id": "user-0002"])
		clock.now = SB.anchor + 1
		context.setAttribute(name: "city", value: JSON("Lisboa"))
		context.setAttribute(name: "ucity", value: JSON("Faro"))
		XCTAssertEqual(Self.expected("Lisboa", 0), context.getTreatment("exp_sb"))

		refresh(
			context,
			Self.dataOf(SB.switchback(arms: Self.arms, periodMs: SB.hour, clusters: [("user_id", "ucity")])))
		XCTAssertEqual(Self.expected("Faro", 0), context.getTreatment("exp_sb"))
		let exposures = publishExposures(context)
		XCTAssertEqual(2, exposures.count)
		XCTAssertEqual(SB.unitType, exposures.first?.unit)
		XCTAssertEqual("user_id", exposures.last?.unit)
	}

	func testCustomAssignmentAppliesOnlyToUnitsWithAClusterKey() {
		let keyed = create(Self.dataOf("city"))
		keyed.setAttribute(name: "city", value: JSON("Lisboa"))
		keyed.setCustomAssignment(experimentName: "exp_sb", variant: 2)
		XCTAssertEqual(2, keyed.getTreatment("exp_sb"))

		let unkeyed = create(Self.dataOf("city"))
		unkeyed.setCustomAssignment(experimentName: "exp_sb", variant: 2)
		XCTAssertEqual(0, unkeyed.getTreatment("exp_sb"))
	}

	// Inertness: a unit experiment ("unit" or absent) carrying every switchback field serves and
	// publishes exactly what the same experiment without them does.
	func testUnitExperimentsIgnoreClusterFields() {
		let splitRule = "{\"rules\":[{\"type\":\"split\",\"environments\":[],\"percentages\":\"34/33/33\"}]}"
		for type in ["unit", nil] as [String?] {
			var unit = SB.switchback(
				arms: Self.arms, periodMs: 0, clusters: [("user_id", "city"), (SB.unitType, "'x")])
			unit["randomizationType"] = type.map { $0 as Any } ?? NSNull()
			unit["switchbackClusterValues"] = ["nothing"]
			// A split rule randomizes over unitType for a unit experiment, never a cluster unit.
			unit["assignmentRules"] = splitRule
			var reference = unit
			for key in reference.keys where key.hasPrefix("switchback") {
				reference.removeValue(forKey: key)
			}

			var published: [[Exposure]] = []
			for experiment in [unit, reference] {
				let context = create(Self.dataOf(experiment), units: [SB.unitType: SB.uid, "user_id": "u"])
				context.setAttribute(name: "city", value: JSON("Lisboa"))
				clock.now = SB.anchor - SB.hour
				let first = context.getTreatment("exp_sb")
				for i in 1..<6 {
					clock.now = SB.anchor - SB.hour + Int64(i) * SB.hour
					XCTAssertEqual(first, context.getTreatment("exp_sb"))
				}
				published.append(publishExposures(context))
			}
			XCTAssertEqual(1, published[0].count)
			XCTAssertEqual(true, published[0].first?.eligible)
			XCTAssertEqual(true, published[0].first?.ruleOverride)
			XCTAssertEqual(SB.anchor - SB.hour, published[0].first?.exposedAt)
			XCTAssertEqual(published[1], published[0])
		}
	}
}
