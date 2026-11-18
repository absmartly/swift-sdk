import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// Port of java-sdk ContextSwitchbackClusterRuleTest, itself a port of the Collector's
// ContextAPISwitchbackTest ClusterRule section (absmartly/abs 9bd2b5ca35), through the public
// Context API. Switchback "sbc" (id 900, "34/33/33", 1h) is linked to user_id (unit type id 2) at
// "profile/store" and to session_id (unit type id 1) at "session_store", declared in unit type id
// order, so session_id comes first although the user_id link was inserted first.
//
// A context holds one uid per unit type and keeps its units in a map, so the declared source order
// alone decides which unit serves.
//
// Java reads the resolution through a `switchbackResolutionForTest` seam. Swift has none, so the
// resolution is read from what the public API shows: an applying switchback gives variant 0's config
// through getVariableValue (or records an exposure, for a strict audience mismatch), a silent one
// records nothing, and the unit an ineligible resolution is served under is the unit an override
// of the same slot is exposed under (both use the first linked unit in declared order).
final class ContextSwitchbackClusterRuleTest: SwitchbackTestCase {
	static let hour: Int64 = 3_600_000
	// 2026-01-01T00:00:00Z, hour aligned.
	static let anchor: Int64 = 1_767_225_600_000
	static let period: Int64 = 5
	static let nowMs: Int64 = anchor + period * hour + 17 * 60_000
	static let seedHi = 0x1234
	static let seedLo = 0x5678_abcd
	static let seed: Int64 = (Int64(seedHi) << 32) | (Int64(seedLo) & 0xFFFF_FFFF)
	static let trafficSeedHi = 7
	static let trafficSeedLo = 11

	static let session = "session_id"
	static let user = "user_id"

	var experiment: [String: Any] = [:]
	var links: [(String, String)] = []

	override func setUp() {
		super.setUp()
		clock.now = Self.nowMs
		experiment = Self.switchbackExperiment("sbc", 900, Self.user, [34, 33, 33])
		unlinkAll()
		link(Self.user, "profile/store")
		link(Self.session, "session_store")
	}

	static func switchbackExperiment(_ name: String, _ id: Int, _ unitType: String, _ split: [Int]) -> [String: Any] {
		return [
			"id": id, "name": name, "unitType": unitType, "iteration": 1, "seedHi": seedHi, "seedLo": seedLo,
			"split": split.map { Double($0) / 100.0 }, "trafficSeedHi": trafficSeedHi, "trafficSeedLo": trafficSeedLo,
			"trafficSplit": [0.0, 1.0], "fullOnVariant": 0, "applications": [["name": "website"]],
			"variants": split.indices.map { ["name": "\($0)", "config": "{\"sbc.config\":\"test config \($0)\"}"] },
			"audienceStrict": false, "audience": NSNull(), "randomizationType": "switchback",
			"switchbackStartAt": anchor, "switchbackPeriodMs": hour, "switchbackDesignType": "balanced_block",
		]
	}

	static func unitExperiment(_ name: String, _ id: Int, _ unitType: String) -> [String: Any] {
		var experiment = switchbackExperiment(name, id, unitType, [50, 50])
		for key in ["randomizationType", "switchbackStartAt", "switchbackPeriodMs", "switchbackDesignType"] {
			experiment.removeValue(forKey: key)
		}
		experiment["variants"] = [["name": "0", "config": NSNull()], ["name": "1", "config": NSNull()]]
		return experiment
	}

	func unlinkAll() {
		links = []
		refreshLinks()
	}

	func link(_ unitType: String, _ path: String) {
		links.append((unitType, path))
		refreshLinks()
	}

	// switchbackClusters in declared (unit type id ascending) order: session_id (1) before user_id (2).
	func refreshLinks() {
		var clusters: [(String, Any)] = []
		for type in [Self.session, Self.user, "device_id"] {
			for link in links where link.0 == type {
				clusters.append((link.0, link.1))
			}
		}
		if links.isEmpty {
			experiment.removeValue(forKey: "switchbackClusters")
		} else {
			experiment["switchbackClusters"] = SB.OrderedObject(clusters)
		}
	}

	func scheduled(_ clusterKey: String) -> Int {
		return SwitchbackAssigner.assign(clusterKey, periodIndex: Self.period, seed: Self.seed, armCount: 3)
	}

	func makeContext(
		_ attributes: [String: JSON]?, _ experiments: [[String: Any]], _ units: [(String, String)],
		override: Int? = nil
	) -> Context {
		logger.clearInvocations()
		return createContext(
			SB.data(experiments), units: Dictionary(units, uniquingKeysWith: { first, _ in first }),
			clusterAttribute: false
		) { config in
			for (name, value) in attributes ?? [:] {
				config.setAttribute(name: name, value: value)
			}
			if let override = override {
				config.setOverride(experimentName: "sbc", variant: override)
			}
		}
	}

	// The Collector's ExperimentAssignment for "sbc", or nil when it lists none (not applicable).
	struct Assigned {
		var unit: String?
		var eligible: Bool
		var variant: Int
		var fullOn: Bool
		var ruleOverride: Bool
		var silent: Bool
		var config: String?
		var exposures: [Exposure]
	}

	func sbcExposures() -> [Exposure] {
		return loggedExposures().filter { $0.name == "sbc" }
	}

	func sbc(_ attributes: [String: JSON]?, _ units: (String, String)...) -> Assigned? {
		return sbcWith(attributes, [experiment], units)
	}

	// Every other experiment is resolved (and exposed) before "sbc". Only "sbc" exposures are returned.
	func sbcWith(
		_ attributes: [String: JSON]?, _ experiments: [[String: Any]], _ units: [(String, String)],
		file: StaticString = #filePath, line: UInt = #line
	) -> Assigned? {
		let context = makeContext(attributes, experiments, units)
		for other in experiments where (other["name"] as! String) != "sbc" {
			_ = context.getTreatment(other["name"] as! String)
		}
		let variant = context.getTreatment("sbc")
		let config = context.getVariableValue("sbc.config", defaultValue: nil)?.string
		let exposures = sbcExposures()
		// A strict audience mismatch is not assigned (so it gives no variable value), yet it is listed
		// and recorded.
		guard config != nil || !exposures.isEmpty else {
			XCTAssertEqual(0, variant, file: file, line: line)
			return nil
		}
		XCTAssertLessThanOrEqual(exposures.count, 1, file: file, line: line)
		var unit = exposures.first?.unit
		if exposures.isEmpty {
			// Silent: the unit it is served under is the one an override of the slot is exposed under.
			let overridden = makeContext(attributes, experiments, units, override: 0)
			_ = overridden.getTreatment("sbc")
			unit = sbcExposures().first?.unit
		}
		return Assigned(
			unit: unit, eligible: exposures.first?.eligible ?? false, variant: variant,
			fullOn: exposures.first?.fullOn ?? false, ruleOverride: exposures.first?.ruleOverride ?? false,
			silent: exposures.isEmpty, config: config, exposures: exposures)
	}

	// R33-5: an ineligible cluster resolution is still an assignment, as control, under the first
	// linked-type unit in declared order, and no exposure is recorded for it.
	func assertIneligible(
		_ attributes: [String: JSON], _ expectedUnit: String, _ units: (String, String)...,
		file: StaticString = #filePath, line: UInt = #line
	) {
		guard let assignment = sbcWith(attributes, [experiment], units, file: file, line: line) else {
			XCTFail("not applicable: \(attributes)", file: file, line: line)
			return
		}
		XCTAssertEqual(expectedUnit, assignment.unit, "\(attributes)", file: file, line: line)
		XCTAssertFalse(assignment.eligible, file: file, line: line)
		XCTAssertTrue(assignment.silent, file: file, line: line)
		XCTAssertEqual(0, assignment.variant, file: file, line: line)
		XCTAssertFalse(assignment.fullOn, file: file, line: line)
		XCTAssertFalse(assignment.ruleOverride, file: file, line: line)
		XCTAssertEqual("test config 0", assignment.config, file: file, line: line)
		XCTAssertTrue(assignment.exposures.isEmpty, "\(attributes)", file: file, line: line)
	}

	func store(_ value: Any) -> JSON {
		return JSON(["store": value])
	}

	func testMissingOrUnreadableClusterConfigurationReturnsOnlyLegacyIneligibleControl() {
		for broken in ["null-cluster", "missing-links", "unreadable-path", "geo.city", "'geo.city'", "\"geo.city\"",
			"unknown-unit"]
		{
			unlinkAll()
			if broken == "unreadable-path" {
				link(Self.session, "'geo")
			} else if broken == "unknown-unit" {
				// A readable map whose only linked type (device_id) is absent from the context.
				link("device_id", "session_store")
				XCTAssertNil(
					sbc(["session_store": JSON("s-1")], (Self.session, "x1"), (Self.user, "u1")), broken)
				continue
			} else if broken == "missing-links" {
				experiment["switchbackClusters"] = SB.OrderedObject([])
			} else if broken != "null-cluster" {
				link(Self.session, broken)
			}
			let attributes: [String: JSON] = [
				"geo": JSON(["city": "Porto"]), "geo.city": JSON("Faro"), "session_store": JSON("s-1"),
			]
			// The declared unit (user_id) only identifies an ineligible control response.
			assertIneligible(attributes, Self.user, (Self.session, "x1"), (Self.user, "u1"))
			// Without a unit of the declared type, there is no response at all.
			XCTAssertNil(sbc(attributes, (Self.session, "x1")), broken)
		}
	}

	// The Collector's name is kept; a context has no request order, so one order is exercised.
	func testTrafficUsesServingUidNotExperimentUidInBothRequestOrders() {
		// percentageOfTraffic = 40.
		experiment["trafficSplit"] = [0.6, 0.4]
		let ordinary = Self.unitExperiment("ordinary", 901, Self.user)
		let split = [0.6, 0.4]
		var witnesses: [String?] = [nil, nil]
		var i = 0
		while i < 1000 && (witnesses[0] == nil || witnesses[1] == nil) {
			let uid = "traffic-\(i)"
			let arm = VariantAssigner(Hashing.hashBytes(uid)).assign(split, Self.trafficSeedHi, Self.trafficSeedLo)
			witnesses[arm == 0 ? 0 : 1] = uid
			i += 1
		}
		guard let out = witnesses[0], let inTraffic = witnesses[1] else {
			XCTFail("no traffic witnesses")
			return
		}
		let key = "s-18"
		// The eligible draw must be distinguishable from control.
		XCTAssertNotEqual(0, scheduled(key))
		for servingEligible in [false, true] {
			let assignment = sbcWith(
				["session_store": JSON(key), "profile": store(key)], [experiment, ordinary],
				[(Self.session, servingEligible ? inTraffic : out), (Self.user, servingEligible ? out : inTraffic)])
			XCTAssertEqual(Self.session, assignment?.unit)
			XCTAssertEqual(servingEligible, assignment?.eligible)
			XCTAssertEqual(servingEligible ? scheduled(key) : 0, assignment?.variant)
			// A traffic miss on an eligible cluster is still recorded, under the serving unit.
			XCTAssertEqual(1, assignment?.exposures.count)
			XCTAssertEqual(Self.session, assignment?.exposures.first?.unit)
			XCTAssertEqual(servingEligible, assignment?.exposures.first?.eligible)
		}
	}

	func testOneMatchingUnitServesItsValue() {
		let assignment = sbc(["profile": store("s-17")], (Self.user, "u1"))

		XCTAssertEqual(true, assignment?.eligible)
		XCTAssertEqual(Self.user, assignment?.unit)
		XCTAssertEqual(scheduled("s-17"), assignment?.variant)
	}

	// A strict audience mismatch on an eligible cluster is not assigned, yet the Collector still lists
	// it, as control under the serving unit, and publishes its exposure.
	func testStrictAudienceMismatchOnAnEligibleClusterIsListedAsControlAndRecorded() {
		experiment["audience"] = "{\"filter\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"gold\"}]}]}"
		experiment["audienceStrict"] = true
		let assignment = sbc(["session_store": JSON("s-17")], (Self.session, "x1"))

		XCTAssertNotNil(assignment)
		XCTAssertEqual(Self.session, assignment?.unit)
		XCTAssertEqual(true, assignment?.eligible)
		XCTAssertEqual(false, assignment?.silent)
		XCTAssertEqual(0, assignment?.variant)
		XCTAssertEqual(1, assignment?.exposures.count)
		XCTAssertEqual(true, assignment?.exposures.first?.audienceMismatch)
		XCTAssertEqual(false, assignment?.exposures.first?.assigned)
	}

	func testTwoAgreeingUnitsServeTheValue() {
		let assignment = sbc(
			["profile": store("s-17"), "session_store": JSON("s-17")], (Self.user, "u1"), (Self.session, "x1"))

		XCTAssertEqual(true, assignment?.eligible)
		XCTAssertEqual(scheduled("s-17"), assignment?.variant)
	}

	func testTwoDisagreeingUnitsAreIneligible() {
		// session_id (type id 1) is first in declared order whatever the unit order.
		assertIneligible(
			["profile": store("s-17"), "session_store": JSON("s-18")], Self.session, (Self.user, "u1"),
			(Self.session, "x1"))
	}

	// The Collector serves two session_id units agreeing on one value. A context holds one uid per unit
	// type: a second uid is rejected (Swift reports an `.error` event and keeps the first, where Java
	// throws), so only the single-unit path is reproducible.
	func testTwoUnitsOfOneTypeWithOnePathAgreeOnTheSameValue() {
		let key = "s-17"
		XCTAssertNotEqual(0, scheduled(key))
		let context = makeContext(["session_store": JSON(key)], [experiment], [(Self.session, "x1")])
		context.setUnit(unitType: Self.session, uid: "x2")
		XCTAssertEqual("x1", context.getUnit(unitType: Self.session))
		XCTAssertTrue(
			logger.handleEventContextEventReceivedInvocations.contains {
				if case .error = $0.event { return true }
				return false
			})

		let assignment = sbc(["session_store": JSON(key)], (Self.session, "x1"))
		XCTAssertEqual(true, assignment?.eligible)
		XCTAssertEqual(scheduled(key), assignment?.variant)
	}

	func testNoMatchingUnitIsIneligible() {
		// A value at the path, but no unit of a linked type: not applicable to this context.
		XCTAssertNil(sbc(["session_store": JSON("s-1")], ("device_id", "d1")))
		XCTAssertNil(sbc(["session_store": JSON("s-1")]))
	}

	func testMatchingUnitWithoutAValueIsIneligible() {
		assertIneligible(["other": JSON("s-1")], Self.user, (Self.user, "u1"))
		assertIneligible(["other": JSON("s-1")], Self.session, (Self.user, "u1"), (Self.session, "x1"))
	}

	func testNonStringNonIntegerValuesAreIneligible() {
		for value in [JSON(1.5), JSON(3.0), JSON(true), JSON(["a": 1]), JSON(["a"]), JSON("")] {
			assertIneligible(["session_store": value], Self.session, (Self.session, "x1"))
		}
	}

	func testWholeNumbersAreKeyedByTheirDecimalText() {
		XCTAssertNotEqual(0, scheduled("17"))
		let assignment = sbc(["session_store": JSON(17)], (Self.session, "x1"))

		XCTAssertEqual(true, assignment?.eligible)
		XCTAssertEqual(scheduled("17"), assignment?.variant)
		// Equal to the string "17" from another unit type, so the two agree.
		XCTAssertEqual(
			true,
			sbc(["session_store": JSON(17), "profile": store("17")], (Self.session, "x1"), (Self.user, "u1"))?
				.eligible)
	}

	func testNestedAndArrayPathsAreRead() {
		unlinkAll()
		link(Self.session, "items/1/store")

		let assignment = sbc(["items": JSON([["store": "a"], ["store": "b"]])], (Self.session, "x1"))
		XCTAssertEqual(scheduled("b"), assignment?.variant)
		XCTAssertNotEqual(scheduled("a"), scheduled("b"))
	}

	func testExposureUnitIsTheFirstMatchingUnitInDeclaredOrderWhateverTheRequestOrder() {
		let key = "s-18"
		XCTAssertNotEqual(0, scheduled(key))
		// Declared order is unit type id ascending: session_id (1) before user_id (2), although the
		// user_id link was inserted first.
		let assignment = sbc(["profile": store(key), "session_store": JSON(key)], (Self.user, "u1"), (Self.session, "x1"))

		XCTAssertEqual(Self.session, assignment?.unit)
		XCTAssertEqual(Self.session, assignment?.exposures.first?.unit)
		XCTAssertEqual(scheduled(key), assignment?.variant)
	}

	func testIneligibleClusterNeverPublishesAnExposure() {
		let context = makeContext(
			["session_store": JSON("a"), "profile": store("b")], [experiment], [(Self.user, "u1"), (Self.session, "x1")])
		XCTAssertEqual(0, context.getTreatment("sbc"))
		XCTAssertEqual(0, context.getPendingCount())
		XCTAssertNil(publish(context))
		XCTAssertEqual(0, handler.publishEventCallsCount)
		XCTAssertTrue(loggedExposures().isEmpty)
	}

	func testAUnitWithoutAValueDoesNotServeEvenIfFirstInDeclaredOrder() {
		let key = "s-17"
		XCTAssertNotEqual(0, scheduled(key))
		let assignment = sbc(["profile": store(key)], (Self.session, "x1"), (Self.user, "u1"))

		XCTAssertEqual(Self.user, assignment?.unit)
		XCTAssertEqual(Self.user, assignment?.exposures.first?.unit)
		XCTAssertEqual(scheduled(key), assignment?.variant)
	}

	func testValueNotInTheFilterIsIneligible() {
		experiment["switchbackClusterValues"] = ["s-1", "s-2"]

		assertIneligible(["session_store": JSON("s-3")], Self.session, (Self.session, "x1"))
		let allowed = sbc(["session_store": JSON("s-2")], (Self.session, "x1"))
		XCTAssertEqual(true, allowed?.eligible)
		XCTAssertEqual(scheduled("s-2"), allowed?.variant)
	}

	func testNullFilterAssignsEveryValue() {
		experiment["switchbackClusterValues"] = NSNull()

		for i in 0..<20 {
			let assignment = sbc(["session_store": JSON("s-\(i)")], (Self.session, "x1"))
			XCTAssertEqual(true, assignment?.eligible)
			XCTAssertEqual(scheduled("s-\(i)"), assignment?.variant)
		}
	}

	// A valid cluster map whose linked types are all absent from the context does not fall back to the
	// experiment's declared unitType: no assignment, no exposure.
	func testValidClusterWithoutLinkedRequestUnitDoesNotFallBackToExperimentUnit() {
		unlinkAll()
		link(Self.session, "session_store")
		let key = "s-17"
		XCTAssertNotEqual(0, scheduled(key))

		XCTAssertNil(sbc(["session_store": JSON(key), "profile": store(key)], (Self.user, "u1")))
		let linked = sbc(["session_store": JSON(key)], (Self.user, "u1"), (Self.session, "x1"))
		XCTAssertEqual(Self.session, linked?.unit)
		XCTAssertEqual(scheduled(key), linked?.variant)
	}

	// The Collector's wire-rule oracle SdkSwitchbackRule, transcribed: period index from the anchor
	// re-ceiled to the hour, traffic on the serving uid's hash, then the schedule draw over the cluster
	// key. A nil cluster key (no value, disagreement, filtered value) has no draw. It shares
	// SwitchbackAssigner, VariantAssigner and Hashing with the SDK, so it is a wire-rule parity check.
	enum SdkSwitchbackRule {
		static func periodIndex(_ experiment: [String: Any], _ nowMs: Int64) -> Int64? {
			guard let startAt = experiment["switchbackStartAt"] as? Int64,
				let periodMs = experiment["switchbackPeriodMs"] as? Int64, periodMs > 0,
				(experiment["split"] as? [Double])?.count ?? 0 >= 2
			else {
				return nil
			}
			let anchor = -SwitchbackAssigner.floorDiv(-startAt, hour) * hour
			guard nowMs >= anchor else { return nil }
			return SwitchbackAssigner.floorDiv(nowMs - anchor, periodMs)
		}

		static func evaluate(_ experiment: [String: Any], _ uid: String, _ clusterKey: String?, _ nowMs: Int64)
			-> (variant: Int, eligible: Bool)
		{
			guard let clusterKey = clusterKey, let periodIndex = periodIndex(experiment, nowMs) else { return (0, false) }
			let eligible =
				VariantAssigner(Hashing.hashBytes(uid)).assign(
					experiment["trafficSplit"] as! [Double], experiment["trafficSeedHi"] as! Int,
					experiment["trafficSeedLo"] as! Int) == 1
			guard eligible else { return (0, false) }
			let seed =
				(Int64(experiment["seedHi"] as! Int) << 32) | (Int64(experiment["seedLo"] as! Int) & 0xFFFF_FFFF)
			return (
				SwitchbackAssigner.assign(
					clusterKey, periodIndex: periodIndex, seed: seed,
					armCount: (experiment["split"] as! [Double]).count), true
			)
		}
	}

	enum ClusterCase: CaseIterable {
		case single, disagreeingSecondSource, missingValue, filteredValue
	}

	func gridContext(_ cluster: ClusterCase, _ uid: String, _ key: String) -> Context {
		unlinkAll()
		link(Self.session, "session_store")
		experiment.removeValue(forKey: "switchbackClusterValues")
		switch cluster {
		case .disagreeingSecondSource:
			link(Self.user, "profile/store")
			return makeContext(
				["session_store": JSON(key), "profile": store(key + "-other")], [experiment],
				[(Self.session, uid), (Self.user, "u-" + uid)])
		case .missingValue:
			return makeContext(["other": JSON(key)], [experiment], [(Self.session, uid)])
		case .filteredValue:
			experiment["switchbackClusterValues"] = [key + "-allowed"]
			return makeContext(["session_store": JSON(key)], [experiment], [(Self.session, uid)])
		case .single:
			return makeContext(["session_store": JSON(key)], [experiment], [(Self.session, uid)])
		}
	}

	func testContextMatchesTheSdkSwitchbackWireRuleParityGrid() {
		var eligible = 0
		var ineligible = 0
		var trafficMisses = 0
		let hour = Self.hour
		for cluster in ClusterCase.allCases {
			for anchor in [Self.anchor, Self.anchor + 7 * hour] {
				for periodMs in [hour, 2 * hour, 24 * hour] {
					experiment["trafficSplit"] = [0.3, 0.7]
					experiment["switchbackStartAt"] = anchor
					experiment["switchbackPeriodMs"] = periodMs
					for u in 0..<6 {
						let uid = "uid-\(u)"
						for key in ["s-1", "s-2", "42", "Lisboa"] {
							for now in [
								anchor - hour, anchor - 1, anchor, anchor + periodMs - 1, anchor + periodMs,
								anchor + 3 * periodMs + 5, anchor + 11 * periodMs,
							] {
								clock.now = now
								let oracleKey = cluster == .single ? key : nil
								let oracle = SdkSwitchbackRule.evaluate(experiment, uid, oracleKey, now)
								let context = gridContext(cluster, uid, key)
								let message = "\(cluster)/\(anchor)/\(periodMs)/\(uid)/\(key)/\(now)"
								XCTAssertEqual(oracle.variant, context.getTreatment("sbc"), message)
								let exposures = loggedExposures()
								// Before the anchor nothing is recorded; from it, a keyed cluster records one
								// exposure whose eligibility is the oracle's (a traffic miss included).
								let expectedExposures = oracleKey != nil && now >= anchor ? 1 : 0
								XCTAssertEqual(expectedExposures, exposures.count, message)
								// A silent resolution is ineligible.
								XCTAssertEqual(oracle.eligible, exposures.first?.eligible ?? false, message)
								if cluster == .single {
									if oracle.eligible {
										eligible += 1
									} else {
										ineligible += 1
										if now >= anchor {
											trafficMisses += 1
										}
									}
								}
							}
						}
					}
				}
			}
		}
		XCTAssertGreaterThan(eligible, 100)
		XCTAssertGreaterThan(ineligible, 100)
		XCTAssertGreaterThan(trafficMisses, 0)

		// The deliberate divergence: an anchor off the hour is unservable in the SDK (as in the
		// Collector's Registry), while the transcribed oracle would re-ceil it and draw.
		let unaligned = Self.anchor + 7 * hour + 1
		experiment["trafficSplit"] = [0.0, 1.0]
		experiment["switchbackStartAt"] = unaligned
		experiment["switchbackPeriodMs"] = hour
		clock.now = Self.anchor + 8 * hour + 5
		XCTAssertNotNil(SdkSwitchbackRule.periodIndex(experiment, clock.now))
		XCTAssertTrue(SdkSwitchbackRule.evaluate(experiment, "uid-0", "s-1", clock.now).eligible)
		let context = gridContext(.single, "uid-0", "s-1")
		XCTAssertEqual(0, context.getTreatment("sbc"))
		XCTAssertTrue(loggedExposures().isEmpty)
	}
}
