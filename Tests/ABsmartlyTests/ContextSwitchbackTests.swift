import Foundation
import Testing

@testable import ABsmartly

/// Switchback serving through a `Context`, with the period grid driven by a `ManualClock`: the
/// behaviour of java-sdk's ContextSwitchbackTest and javascript-sdk's switchback suite, in the 2.x API.
@Suite struct ContextSwitchbackTests {
	static let assignVariant1 = "{\"rules\":[{\"type\":\"assign\",\"environments\":[],\"variant\":1}]}"
	static let splitAllVariant1 =
		"{\"rules\":[{\"type\":\"split\",\"environments\":[],\"conditions\":null,\"percentages\":\"0/100\"}]}"
	static let split50 =
		"{\"rules\":[{\"type\":\"split\",\"environments\":[],\"conditions\":null,\"percentages\":\"50/50\"}]}"
	// An audience the default context never matches (no "tier" attribute).
	static let goldAudience = "{\"filter\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"gold\"}]}]}"

	// MARK: The draw and the grid

	// The cluster identity is the raw attribute value, neither hashed nor the unit uid.
	@Test func clusterIdentityIsTheRawClusterValue() {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback(arms: 3)]))
		let served = sb.peekSchedule(context)

		#expect(served == SB.expected3Arms)
		#expect(served != SB.uidHash3Arms)
		#expect(served != SB.uid3Arms)
		#expect(served == (0..<12).map { SB.draw(SB.clusterKey, Int64($0), arms: 3) })
		let hashed = String(decoding: Hashing.hashUnit(SB.clusterKey), as: UTF8.self)
		#expect(served != (0..<12).map { SB.draw(hashed, Int64($0), arms: 3) })
	}

	@Test func servesTwoThreeAndTenArmSchedules() {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([
				SB.switchback(1, "exp_2", arms: 2), SB.switchback(2, "exp_3", arms: 3),
				SB.switchback(3, "exp_10", arms: 10),
			]))
		#expect(sb.peekSchedule(context, "exp_2") == SB.expected2Arms)
		#expect(sb.peekSchedule(context, "exp_3") == SB.expected3Arms)
		#expect(sb.peekSchedule(context, "exp_10") == SB.expected10Arms)
		#expect(sb.exposures.isEmpty)
	}

	@Test func periodBoundariesAtTheExactMillisecond() {
		for periodMs in [SB.hour, SB.day] {
			let sb = SwitchbackEnv()
			let context = sb.context(SB.data([SB.switchback(periodMs: periodMs)]))
			let expectations: [(Int64, Int)] = [
				(SB.anchor - 1, 0), (SB.anchor, SB.expected2Arms[0]), (SB.anchor + periodMs - 1, SB.expected2Arms[0]),
				(SB.anchor + periodMs, SB.expected2Arms[1]), (SB.anchor + 4 * periodMs - 1, SB.expected2Arms[3]),
				(SB.anchor + 4 * periodMs, SB.expected2Arms[4]),
			]
			for (now, variant) in expectations {
				sb.clock.now = now
				#expect(context.treatment(for: "exp_sb", exposing: false) == variant, "period \(periodMs) at \(now)")
			}
		}
	}

	// The anchor is used as served, never rounded; before it the experiment is a silent control.
	@Test func preAnchorAndUnalignedStartServeASilentControl() async throws {
		var aligned = SB.switchback(1, "exp_aligned")
		aligned["switchbackStartAt"] = SB.anchor + SB.hour
		var unaligned = SB.switchback(2, "exp_unaligned")
		let start = SB.anchor + 1_234_567
		unaligned["switchbackStartAt"] = start
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([aligned, unaligned]))

		for now in [SB.anchor, start - 1, start, SB.anchor + SB.hour - 1] {
			sb.clock.now = now
			#expect(context.treatment(for: "exp_aligned") == 0)
			#expect(context.treatment(for: "exp_unaligned") == 0)
			#expect(context.variableValue("sb.arm") == 0)
		}
		#expect(context.pendingEventCount == 0)
		for i in 1..<4 {
			sb.clock.now = SB.anchor + Int64(i) * SB.hour
			#expect(context.treatment(for: "exp_aligned") == SB.expected2Arms[i - 1])
			#expect(context.treatment(for: "exp_unaligned") == 0)
		}
		#expect(
			try await sb.publish(context) == [
				SB.exposure(SB.expected2Arms[0], SB.anchor + SB.hour, name: "exp_aligned"),
				SB.exposure(SB.expected2Arms[1], SB.anchor + 2 * SB.hour, name: "exp_aligned"),
				SB.exposure(SB.expected2Arms[2], SB.anchor + 3 * SB.hour, name: "exp_aligned"),
			])
	}

	// The Collector's anchor bounds: hour aligned and in [0, 10000-01-01T00:00:00Z); a period above 0;
	// at least two arms. Anything else serves a silent control in every period.
	@Test func unservableSchedulesNeverDrawAndNeverFallBackToUnitAssignment() async throws {
		let maxAnchor = SwitchbackSchedule.maxAnchorMs
		var cases: [[String: Any]] = []
		for startAt: Any in [
			SB.anchor + 1, SB.anchor - 1, SB.anchor + 30 * 60_000, -SB.hour, Int64(-1), maxAnchor, maxAnchor + SB.hour,
			NSNull(), "2026-01-01",
		] {
			cases.append(SB.switchback(extra: ["switchbackStartAt": startAt]))
		}
		for periodMs: Any in [0, -SB.hour, NSNull(), "3600000", 1.5] {
			cases.append(SB.switchback(extra: ["switchbackPeriodMs": periodMs]))
		}
		cases.append(SB.switchback(arms: 1))
		for experiment in cases {
			let sb = SwitchbackEnv(now: 0)
			let context = sb.context(SB.data([experiment]))
			for now in [0, SB.anchor, SB.anchor + 2 * SB.hour + 1, maxAnchor + SB.day] {
				sb.clock.now = now
				#expect(context.treatment(for: "exp_sb") == 0, "\(experiment) at \(now)")
			}
			#expect(context.pendingEventCount == 0, "\(experiment)")
			#expect(try await sb.publish(context) == nil)
		}

		// In-range hour-aligned anchors, including 0 and the last hour before the bound, serve.
		for startAt in [0, SB.anchor, maxAnchor - SB.hour] {
			let sb = SwitchbackEnv(now: startAt + SB.hour)
			let context = sb.context(SB.data([SB.switchback(extra: ["switchbackStartAt": startAt])]))
			#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[1], "startAt \(startAt)")
			#expect(context.pendingEventCount == 1)
		}
	}

	// MARK: Exposures

	@Test func oneExposurePerPeriodStampedWithThePeriodsClockReading() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback()]))

		sb.clock.now = SB.anchor + 10
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[0])
		sb.clock.now = SB.anchor + SB.hour - 1
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[0])
		#expect(context.variableValue("sb.arm") == .int(Int64(SB.expected2Arms[0])))
		#expect(context.pendingEventCount == 1)

		sb.clock.now = SB.anchor + SB.hour
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[1])
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[1])
		sb.clock.now = SB.anchor + 2 * SB.hour + 5
		#expect(context.variableValue("sb.arm") == .int(Int64(SB.expected2Arms[2])))
		#expect(
			try await sb.publish(context) == [
				SB.exposure(SB.expected2Arms[0], SB.anchor + 10), SB.exposure(SB.expected2Arms[1], SB.anchor + SB.hour),
				SB.exposure(SB.expected2Arms[2], SB.anchor + 2 * SB.hour + 5),
			])
	}

	// One read takes one clock reading: the period that chose the variant is the one in `exposedAt`.
	@Test func aReadTakesOneClockReading() {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback()]))
		let before = sb.clock.reads
		_ = context.treatment(for: "exp_sb")
		#expect(sb.clock.reads == before + 1)
		_ = context.variableValue("sb.arm")
		#expect(sb.clock.reads == before + 2)
	}

	// A variable read visiting several switchback candidates takes one reading for all of them.
	@Test func aVariableReadOverSeveralSwitchbacksTakesOneClockReading() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([
				SB.switchback(1, "exp_other_unit", clusters: [("user_id", SB.clusterPath)]),
				SB.switchback(2, "exp_store"),
			]))
		let before = sb.clock.reads
		#expect(context.variableValue("sb.arm") == .int(Int64(SB.expected2Arms[0])))
		#expect(sb.clock.reads == before + 1)
		#expect(
			try await sb.publish(context) == [SB.exposure(SB.expected2Arms[0], SB.anchor, id: 2, name: "exp_store")])
	}

	// Unit experiments read the clock only to stamp an exposure, as in 2.1.0.
	@Test func unitExperimentsNeverReadTheClockToResolve() {
		let sb = SwitchbackEnv()
		let context = sb.context(Fixtures.contextData(), units: Fixtures.units)
		let before = sb.clock.reads
		_ = context.treatment(for: "exp_test_ab", exposing: false)
		_ = context.variableValue("banner.size", exposing: false)
		#expect(sb.clock.reads == before)
		_ = context.treatment(for: "exp_test_ab")
		#expect(sb.clock.reads == before + 1)
	}

	// A peek never queues and never marks the period exposed.
	@Test func peekingQueuesNothing() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback()]))
		#expect(context.treatment(for: "exp_sb", exposing: false) == SB.expected2Arms[0])
		#expect(context.variableValue("sb.arm", exposing: false) == .int(Int64(SB.expected2Arms[0])))
		#expect(context.pendingEventCount == 0)
		sb.clock.now = SB.anchor + 7
		_ = context.treatment(for: "exp_sb")
		#expect(try await sb.publish(context) == [SB.exposure(SB.expected2Arms[0], SB.anchor + 7)])
	}

	// Re-entering an older period evicts the lowest other period, never the one just resolved.
	@Test func rewindKeepsThePeriodJustResolved() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback()]))
		for i: Int64 in [5, 6, 4, 4] {
			sb.clock.now = SB.anchor + i * SB.hour
			_ = context.treatment(for: "exp_sb")
		}
		#expect(try await sb.publish(context)?.count == 3)
	}

	// Only the two most recent periods stay cached, so a clock rewind past them exposes again.
	@Test func onlyTwoPeriodsAreRetained() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback()]))
		for i: Int64 in [0, 1, 0, 2, 1, 0] {
			sb.clock.now = SB.anchor + i * SB.hour
			_ = context.treatment(for: "exp_sb")
		}
		// 0, 1 (0 retained), 2 evicts 0, back in 1 (retained), 0 again (evicted: exposes again).
		#expect(
			try await sb.publish(context)?.map(\.exposedAt) == [
				SB.anchor, SB.anchor + SB.hour, SB.anchor + 2 * SB.hour, SB.anchor,
			])
	}

	// MARK: Serving

	// The first linked unit in declared order whose path yields a value serves, and is published.
	@Test func declaredOrderDecidesTheServingUnit() async throws {
		let clusters: [(String, Any)] = [("user_id", "city"), (SB.unitType, SB.clusterPath)]
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([SB.switchback(clusters: clusters)]), units: [UnitType(SB.unitType): SB.uid, .userID: "u1"],
			attributes: [SB.clusterPath: "store-42", "city": "store-42"])
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[0])
		#expect(try await sb.publish(context) == [SB.exposure(SB.expected2Arms[0], SB.anchor, unit: "user_id")])

		// Reversed order serves the store unit.
		let reversed = SwitchbackEnv()
		let other = reversed.context(
			SB.data([SB.switchback(clusters: Array(clusters.reversed()))]),
			units: [.userID: "u1", UnitType(SB.unitType): SB.uid],
			attributes: [SB.clusterPath: "store-42", "city": "store-42"])
		_ = other.treatment(for: "exp_sb")
		#expect(try await reversed.publish(other) == [SB.exposure(SB.expected2Arms[0], SB.anchor)])
	}

	@Test func aUnitWithoutAValueIsSkipped() async throws {
		let clusters: [(String, Any)] = [("user_id", "city"), (SB.unitType, SB.clusterPath)]
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([SB.switchback(clusters: clusters)]), units: [UnitType(SB.unitType): SB.uid, .userID: "u1"])
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[0])
		#expect(try await sb.publish(context) == [SB.exposure(SB.expected2Arms[0], SB.anchor)])
	}

	// Disagreeing units, a value outside the allow-list or no value: a silent control.
	@Test func ineligibleClustersServeASilentControl() async throws {
		let two: [(String, Any)] = [("user_id", "city"), (SB.unitType, SB.clusterPath)]
		let units: [UnitType: String] = [UnitType(SB.unitType): SB.uid, .userID: "u1"]
		let cases: [(ContextData, [String: JSONValue])] = [
			(SB.data([SB.switchback(clusters: two)]), [SB.clusterPath: "store-42", "city": "porto"]),
			(SB.data([SB.switchback(extra: ["switchbackClusterValues": ["store-1"]])]), [SB.clusterPath: "store-42"]),
			(SB.data([SB.switchback()]), [:]),
			(SB.data([SB.switchback()]), [SB.clusterPath: 3.0]),
			(SB.data([SB.switchback()]), [SB.clusterPath: ""]),
			(SB.data([SB.switchback()]), [SB.clusterPath: true]),
			(SB.data([SB.switchback()]), ["other": "store-42"]),
		]
		for (data, attributes) in cases {
			let sb = SwitchbackEnv()
			let context = sb.context(data, units: units, attributes: attributes)
			#expect(context.treatment(for: "exp_sb") == 0, "\(attributes)")
			#expect(context.variableValue("sb.arm") == 0)
			#expect(context.pendingEventCount == 0)
		}
	}

	@Test func allowListAndIntegerClusterValues() {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([
				SB.switchback(1, "exp_allowed", extra: ["switchbackClusterValues": ["store-1", "store-42"]]),
				SB.switchback(2, "exp_empty", extra: ["switchbackClusterValues": [] as [Any]]),
				SB.switchback(3, "exp_null", extra: ["switchbackClusterValues": NSNull()]),
			]))
		#expect(context.treatment(for: "exp_allowed") == SB.expected2Arms[0])
		#expect(context.treatment(for: "exp_empty") == SB.expected2Arms[0])
		#expect(context.treatment(for: "exp_null") == SB.expected2Arms[0])

		let numeric = SwitchbackEnv()
		let byInt = numeric.context(SB.data([SB.switchback()]), attributes: [SB.clusterPath: 4_000_000_002])
		#expect(byInt.treatment(for: "exp_sb", exposing: false) == SB.draw("4000000002", 0, arms: 2))
		let nested = numeric.context(
			SB.data([SB.switchback(clusters: [(SB.unitType, "store/items/1/'id'")])]),
			attributes: ["store": ["items": [["id": "a"], ["id": "store-42"]]]])
		#expect(numeric.peekSchedule(nested) == SB.expected2Arms)
	}

	// No unit of a linked type: the experiment does not apply, and setting one later re-resolves it.
	@Test func absentUntilALinkedUnitIsSet() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback()]), units: [:])
		#expect(context.treatment(for: "exp_sb") == 0)
		#expect(context.pendingEventCount == 0)
		try context.setUnit(UnitType(SB.unitType), to: SB.uid)
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[0])
		#expect(try await sb.publish(context) == [SB.exposure(SB.expected2Arms[0], SB.anchor)])
	}

	// An override kept across setUnit (it was exposed) re-reads the cluster once it is removed.
	@Test func removingAKeptOverrideResolvesTheLateUnit() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback(arms: 10)]), units: [:], overrides: ["exp_sb": 3])
		#expect(context.treatment(for: "exp_sb") == 3)
		try context.setUnit(UnitType(SB.unitType), to: SB.uid)
		#expect(context.treatment(for: "exp_sb") == 3)
		context.setOverride(nil, for: "exp_sb")
		#expect(context.treatment(for: "exp_sb") == SB.expected10Arms[0])
	}

	// The legacy path is an ineligible control that is "assigned", so it wins a shared variable key
	// with its control value, as in java-sdk; with no unit of its type it does not apply and the
	// next candidate wins.
	@Test func legacyPathWinsASharedVariableKeyWithControl() {
		let unreadable = SB.switchback(1, "exp_sb", clusters: [(SB.unitType, "a.b")])
		var unit = SB.switchback(2, "exp_unit", extra: ["randomizationType": "unit", "fullOnVariant": 1])
		unit["unitType"] = SB.unitType
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([unreadable, unit]))
		#expect(context.variableValue("sb.arm", exposing: false) == 0)

		// The full-on unit experiment is assigned without its unit.
		let absent = sb.context(SB.data([unreadable, unit]), units: [.userID: "u"])
		#expect(absent.variableValue("sb.arm", exposing: false) == 1)
	}

	// An attribute set after the read's time (the clock went back) is not read.
	@Test func attributesSetAfterTheReadAreNotRead() {
		let sb = SwitchbackEnv(now: SB.anchor + 100)
		let context = sb.context(SB.data([SB.switchback()]), attributes: [:])
		context.setAttribute(SB.clusterPath, to: SB.clusterKey)
		sb.clock.now = SB.anchor + 50
		#expect(context.treatment(for: "exp_sb") == 0)
		#expect(context.pendingEventCount == 0)
	}

	// A missing, empty or unreadable cluster map takes the legacy path: a silent control.
	@Test func unreadableClusterMapsServeASilentControl() {
		for clusters: Any in [
			NSNull(), SB.OrderedObject([]), SB.OrderedObject([(SB.unitType, 3)]),
			SB.OrderedObject([(SB.unitType, "a.b")]), "store_key", [SB.clusterPath],
		] as [Any] {
			let sb = SwitchbackEnv()
			let context = sb.context(SB.data([SB.switchback(extra: ["switchbackClusters": clusters])]))
			#expect(context.treatment(for: "exp_sb") == 0, "\(clusters)")
			#expect(context.pendingEventCount == 0)
		}
		// The abandoned Phase 1E fields are ignored.
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([
				SB.switchback(
					clusters: nil,
					extra: [
						"switchbackClusterUnitType": SB.unitType, "switchbackClusterCount": 4,
						"switchbackClusterAttribute": SB.clusterPath,
					])
			]))
		#expect(context.treatment(for: "exp_sb") == 0)
		#expect(context.pendingEventCount == 0)
	}

	// The cluster is read once per period: a later setAttribute in that period keeps it.
	@Test func clusterIsReadOncePerPeriod() {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback(arms: 10)]))
		#expect(context.treatment(for: "exp_sb") == SB.expected10Arms[0])
		sb.clock.now = SB.anchor + 1
		context.setAttribute(SB.clusterPath, to: "store-7")
		#expect(context.treatment(for: "exp_sb") == SB.expected10Arms[0])
		sb.clock.now = SB.anchor + SB.hour
		#expect(context.treatment(for: "exp_sb") == SB.draw("store-7", 1, arms: 10))
	}

	// The attribute read is the one set at or before the read, latest `setAt`, by trimmed name.
	@Test func readsTheLatestAttributeSetByTheReadsTime() {
		let sb = SwitchbackEnv(now: SB.anchor + 10)
		let context = sb.context(SB.data([SB.switchback(arms: 10)]), attributes: [:])
		context.setAttribute(" \(SB.clusterPath) ", to: "store-7")
		sb.clock.now = SB.anchor + 5
		context.setAttribute(SB.clusterPath, to: SB.clusterKey)
		// At the reading, both are set; the one with the later setAt (store-7) wins.
		sb.clock.now = SB.anchor + 20
		#expect(context.treatment(for: "exp_sb", exposing: false) == SB.draw("store-7", 0, arms: 10))
	}

	// MARK: Precedence: override, rule, audience, full-on, traffic, custom, draw

	@Test func overrideWinsAndIsExposedPerPeriod() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([SB.switchback(extra: ["assignmentRules": Self.assignVariant1, "fullOnVariant": 1])]),
			overrides: ["exp_sb": 0])
		#expect(context.treatment(for: "exp_sb") == 0)
		sb.clock.now = SB.anchor + SB.hour
		#expect(context.treatment(for: "exp_sb") == 0)
		#expect(
			try await sb.publish(context) == [
				SB.exposure(0, SB.anchor, assigned: false, overridden: true),
				SB.exposure(0, SB.anchor + SB.hour, assigned: false, overridden: true),
			])
	}

	// An override is published under the serving unit, or with no linked unit under the first linked
	// type (never the declared unitType of a readable cluster map).
	@Test func overrideIsPublishedUnderTheServingOrFirstLinkedUnit() async throws {
		let clusters: [(String, Any)] = [(SB.unitType, SB.clusterPath), ("user_id", "city")]
		let data = SB.data([SB.switchback(clusters: clusters, extra: ["unitType": "legacy_type"])])
		let sb = SwitchbackEnv()
		let absent = sb.context(data, units: [.sessionID: "s"], overrides: ["exp_sb": 1])
		#expect(absent.treatment(for: "exp_sb") == 1)
		#expect(try await sb.publish(absent) == [SB.exposure(1, SB.anchor, assigned: false, overridden: true)])

		let serving = sb.context(data, units: [.userID: "u"], attributes: ["city": "porto"], overrides: ["exp_sb": 1])
		#expect(serving.treatment(for: "exp_sb") == 1)
		#expect(
			try await sb.publish(serving) == [
				SB.exposure(1, SB.anchor, unit: "user_id", assigned: false, overridden: true)
			])
	}

	@Test func ruleWinsOverAudienceFullOnTrafficAndCustom() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([
				SB.switchback(
					arms: 3,
					extra: [
						"assignmentRules": Self.assignVariant1, "audience": Self.goldAudience, "audienceStrict": true,
						"fullOnVariant": 2, "trafficSplit": [1.0, 0.0],
					])
			]), customAssignments: ["exp_sb": 2])
		#expect(context.treatment(for: "exp_sb") == 1)
		#expect(try await sb.publish(context) == [SB.exposure(1, SB.anchor, assigned: false, ruleOverride: true)])
	}

	// A split rule randomizes over the serving unit's hash, not the declared unitType's.
	@Test func splitRuleUsesTheServingUnit() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback(extra: ["assignmentRules": Self.splitAllVariant1])]))
		#expect(context.treatment(for: "exp_sb", exposing: false) == 1)

		// The declared unitType is "store_id", but "user_id" serves: the split hashes the user's uid.
		let clusters: [(String, Any)] = [("user_id", SB.clusterPath)]
		var uids: Set<Int> = []
		for uid in (0..<16).map({ "user-\($0)" }) {
			let env = SwitchbackEnv()
			let ctx = env.context(
				SB.data([SB.switchback(clusters: clusters, extra: ["assignmentRules": Self.split50])]),
				units: [UnitType(SB.unitType): SB.uid, .userID: uid])
			let expected = VariantAssigner(unitHash: Hashing.hashUnit(uid)).assign(
				[0.5, 0.5], seedHi: SB.seedHi, seedLo: SB.seedLo)
			#expect(ctx.treatment(for: "exp_sb") == expected, "\(uid)")
			uids.insert(expected)
			#expect(
				try await env.publish(ctx) == [
					SB.exposure(expected, SB.anchor, unit: "user_id", assigned: false, ruleOverride: true)
				])
		}
		// Both arms occur, so the check above can tell the units apart.
		#expect(uids == [0, 1])
	}

	// A rule is consulted only for an eligible cluster, and before the anchor still wins.
	@Test func rulesNeedAnEligibleCluster() async throws {
		let sb = SwitchbackEnv(now: SB.anchor - SB.hour)
		let context = sb.context(SB.data([SB.switchback(extra: ["assignmentRules": Self.assignVariant1])]))
		#expect(context.treatment(for: "exp_sb") == 1)
		let ineligible = sb.context(
			SB.data([SB.switchback(extra: ["assignmentRules": Self.assignVariant1])]), attributes: [:])
		#expect(ineligible.treatment(for: "exp_sb") == 0)
		#expect(ineligible.pendingEventCount == 0)
		#expect(
			try await sb.publish(context) == [SB.exposure(1, SB.anchor - SB.hour, assigned: false, ruleOverride: true)])
	}

	@Test func strictAudienceMismatchWinsOverFullOn() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([SB.switchback(extra: ["audience": Self.goldAudience, "audienceStrict": true, "fullOnVariant": 1])])
		)
		#expect(context.treatment(for: "exp_sb") == 0)
		#expect(try await sb.publish(context) == [SB.exposure(0, SB.anchor, assigned: false, audienceMismatch: true)])

		// A non-strict mismatch is recorded and still draws.
		let loose = SwitchbackEnv()
		let other = loose.context(SB.data([SB.switchback(extra: ["audience": Self.goldAudience])]))
		#expect(other.treatment(for: "exp_sb") == SB.expected2Arms[0])
		#expect(try await loose.publish(other) == [SB.exposure(SB.expected2Arms[0], SB.anchor, audienceMismatch: true)])
	}

	// An audience change re-resolves the slot but keeps its cluster.
	@Test func audienceChangeReResolvesTheSlot() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([SB.switchback(arms: 10, extra: ["audience": Self.goldAudience, "audienceStrict": true])]))
		#expect(context.treatment(for: "exp_sb", exposing: false) == 0)
		context.setAttribute("tier", to: "gold")
		#expect(context.treatment(for: "exp_sb", exposing: false) == SB.expected10Arms[0])
	}

	// Full-on wins over traffic and custom, and even before the anchor.
	@Test func fullOnWinsOverTrafficAndCustom() async throws {
		let sb = SwitchbackEnv(now: SB.anchor - 1)
		let context = sb.context(
			SB.data([SB.switchback(arms: 3, extra: ["fullOnVariant": 2, "trafficSplit": [1.0, 0.0]])]),
			customAssignments: ["exp_sb": 1])
		#expect(context.treatment(for: "exp_sb") == 2)
		#expect(try await sb.publish(context) == [SB.exposure(2, SB.anchor - 1, fullOn: true)])
	}

	@Test func trafficMissIsRecordedAndWinsOverCustom() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([SB.switchback(extra: ["trafficSplit": [1.0, 0.0]])]), customAssignments: ["exp_sb": 1])
		#expect(context.treatment(for: "exp_sb") == 0)
		#expect(try await sb.publish(context) == [SB.exposure(0, SB.anchor, eligible: false)])
	}

	@Test func customWinsOverTheDrawAndAChangeReResolves() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback(arms: 10)]), customAssignments: ["exp_sb": 9])
		#expect(context.treatment(for: "exp_sb") == 9)
		context.setCustomAssignment(7, for: "exp_sb")
		#expect(context.treatment(for: "exp_sb") == 7)
		context.setCustomAssignment(nil, for: "exp_sb")
		#expect(context.treatment(for: "exp_sb") == SB.expected10Arms[0])
		#expect(
			try await sb.publish(context) == [
				SB.exposure(9, SB.anchor, custom: true), SB.exposure(7, SB.anchor, custom: true),
				SB.exposure(SB.expected10Arms[0], SB.anchor),
			])
	}

	// MARK: Holdouts

	@Test func holdoutsNeverApplyToASwitchback() async throws {
		let holdout: [String: Any] = [
			"id": 11, "name": "holdout_all", "unitType": SB.unitType, "iteration": 1, "seedHi": 13, "seedLo": 111,
			"split": [1.0, 0.0], "trafficSplit": [0.0, 1.0], "fullOnVariant": 0, "variants": [] as [Any],
		]
		let sb = SwitchbackEnv()
		let context = sb.context(
			SB.data([SB.switchback(extra: ["holdoutIds": [11]])], holdouts: [holdout]))
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[0])
		#expect(try await sb.publish(context) == [SB.exposure(SB.expected2Arms[0], SB.anchor)])
	}

	// MARK: Refresh and epochs

	// A refresh that keeps the switchback identity keeps the period's slot and exposure; a seed or
	// split edit is not identity.
	@Test func sameIdentityRefreshKeepsThePeriod() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback(arms: 10)]))
		#expect(context.treatment(for: "exp_sb") == SB.expected10Arms[0])
		try await sb.refresh(
			context, SB.data([SB.switchback(arms: 10, extra: ["seedHi": 99, "switchbackEstimand": "x"])]))
		#expect(context.treatment(for: "exp_sb") == SB.expected10Arms[0])
		#expect(context.pendingEventCount == 1)
	}

	// An identity change (here the period length) starts a new epoch: re-resolved and exposed again.
	@Test(arguments: 0..<5)
	func identityChangeStartsANewEpoch(_ index: Int) async throws {
		let change: [String: Any] = [
			["switchbackPeriodMs": 2 * SB.hour], ["iteration": 2], ["switchbackDesignType": "other"],
			["switchbackClusterValues": ["store-42"]], ["switchbackStartAt": SB.anchor - SB.hour],
		][index]
		let sb = SwitchbackEnv(now: SB.anchor + 2 * SB.hour)
		let context = sb.context(SB.data([SB.switchback(arms: 10)]))
		_ = context.treatment(for: "exp_sb")
		try await sb.refresh(context, SB.data([SB.switchback(arms: 10, extra: change)]))
		_ = context.treatment(for: "exp_sb")
		#expect(context.pendingEventCount == 2, "\(change)")
	}

	// A period-length change is identity even when the period index stays the same.
	@Test func periodLengthChangeAtTheSamePeriodIndexStartsANewEpoch() async throws {
		let sb = SwitchbackEnv(now: SB.anchor + 10)
		let context = sb.context(SB.data([SB.switchback(arms: 10)]))
		_ = context.treatment(for: "exp_sb")
		try await sb.refresh(context, SB.data([SB.switchback(arms: 10, periodMs: SB.day)]))
		_ = context.treatment(for: "exp_sb")
		#expect(context.pendingEventCount == 2)
	}

	// A switchback that becomes a unit experiment, and back, never reuses an earlier slot.
	@Test func switchbackToUnitAndBackStartsFresh() async throws {
		let sb = SwitchbackEnv()
		let context = sb.context(SB.data([SB.switchback()]))
		_ = context.treatment(for: "exp_sb")
		try await sb.refresh(context, SB.data([SB.switchback(extra: ["randomizationType": "unit"])]))
		_ = context.treatment(for: "exp_sb")
		try await sb.refresh(context, SB.data([SB.switchback()]))
		#expect(context.treatment(for: "exp_sb") == SB.expected2Arms[0])
		#expect(context.pendingEventCount == 3)
	}

	// MARK: Decoding

	@Test func decodesTheSwitchbackFieldsAndKeepsClusterOrder() throws {
		let clusters: [(String, Any)] = [("z_unit", "z"), ("a_unit", "a/b"), ("m_unit", "m")]
		let data = SB.data([SB.switchback(clusters: clusters)])
		let experiment = try #require(data.experiments.first)
		#expect(experiment.randomizationType == "switchback")
		#expect(
			experiment.switchbackClusters == [
				SwitchbackCluster(unitType: "z_unit", attributePath: "z"),
				SwitchbackCluster(unitType: "a_unit", attributePath: "a/b"),
				SwitchbackCluster(unitType: "m_unit", attributePath: "m"),
			])
		#expect(experiment.switchbackStartAt == SB.anchor)
		#expect(experiment.switchbackPeriodMs == SB.hour)
		#expect(experiment.switchbackCarryoverDurationMs == 0)
		#expect(experiment.switchbackDesignType == "balanced_block")
		#expect(experiment.switchbackEstimand == "global_average_treatment_effect")

		// The encoder writes the ordered array, which round-trips through any decoder.
		let roundTripped = try JSONDecoder().decode(ContextData.self, from: JSONEncoder().encode(data))
		#expect(roundTripped == data)
	}

	// `JSONDecoder` cannot see key order: a map with several entries is dropped (logged), one entry is kept.
	@Test func plainDecoderDropsAMultiEntryClusterMap() throws {
		let json = SB.json([
			SB.switchback(1, "multi", clusters: [("a", "x"), ("b", "y")]), SB.switchback(2, "single"),
		])
		let data = try JSONDecoder().decode(ContextData.self, from: json)
		#expect(data.experiments[0].switchbackClusters == nil)
		#expect(
			data.experiments[1].switchbackClusters == [
				SwitchbackCluster(unitType: SB.unitType, attributePath: SB.clusterPath)
			])
	}

	@Test func wrongShapedSwitchbackFieldsAreNilOnTheirOwn() throws {
		let data = SB.data([
			SB.switchback(
				extra: [
					"switchbackStartAt": "x", "switchbackPeriodMs": [1], "switchbackDesignType": 3,
					"switchbackClusterValues": [1, 2],
				])
		])
		let experiment = try #require(data.experiments.first)
		#expect(experiment.switchbackStartAt == nil)
		#expect(experiment.switchbackPeriodMs == nil)
		#expect(experiment.switchbackDesignType == nil)
		// An unreadable allow-list drops the cluster map with it, so nothing is served to every value.
		#expect(experiment.switchbackClusterValues == nil)
		#expect(experiment.switchbackClusters == nil)
		#expect(experiment.name == "exp_sb")
	}

	@Test func contextDataJSONInitThrowsADecodingError() {
		#expect(throws: ABsmartlyError.self) { try ContextData(json: Data("{".utf8)) }
	}

	// The SDK's own fetch keeps cluster order.
	@Test func fetchedContextDataKeepsClusterOrder() async throws {
		let sb = SwitchbackEnv()
		let clusters: [(String, Any)] = [("user_id", "city"), (SB.unitType, SB.clusterPath)]
		sb.env.transport.contextData = SB.json([SB.switchback(clusters: clusters)])
		let data = try await sb.env.client.fetchContextData()
		#expect(data.experiments[0].switchbackClusters?.map(\.unitType) == ["user_id", SB.unitType])
	}

	// A payload without switchbacks publishes exactly what 2.1.0 did, R33 fields on a unit experiment
	// included.
	@Test func unitExperimentWithSwitchbackFieldsIsServedAsAUnitExperiment() {
		let env = ContextEnv()
		var unit = SB.switchback(extra: ["randomizationType": "unit"])
		unit["unitType"] = "session_id"
		let plain = env.context(data: SB.data([unit]), units: Fixtures.units)
		var bare = unit
		for key in bare.keys where key.hasPrefix("switchback") || key == "randomizationType" {
			bare[key] = nil
		}
		let baseline = env.context(data: SB.data([bare]), units: Fixtures.units)
		#expect(plain.treatment(for: "exp_sb") == baseline.treatment(for: "exp_sb"))
		#expect(env.log.exposures.count == 2)
		#expect(env.log.exposures[0] == env.log.exposures[1])
	}
}
