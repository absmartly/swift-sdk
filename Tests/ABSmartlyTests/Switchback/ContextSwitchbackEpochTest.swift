import Foundation
import XCTest

@testable import ABSmartly

// Epoch identity across A-B-A refreshes, one clock reading per call, and no audience re-evaluation
// on cached slots.
final class ContextSwitchbackEpochTest: SwitchbackTestCase {
	// An allow-list change is a switchback identity change, so an A-B-A refresh through a
	// different allow-list starts a new epoch and the next read exposes again (java-sdk
	// sameSwitchbackIdentity compares switchbackClusterValues).
	func testAllowListChangeWithoutAnInterveningLookupStillReresolves() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(1, context.getPendingCount())

		var allowList = SB.switchback(arms: 2, periodMs: SB.hour)
		allowList["switchbackClusterValues"] = [SB.clusterKey]
		refresh(context, SB.data([allowList]))
		refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())
	}

	func testUnicodeAllowListAndPathEditsStartFreshEpochsInTheSamePeriod() {
		let composed = "caf\u{E9}"
		let decomposed = "cafe\u{301}"
		for editPath in [false, true] {
			var a = SB.switchback(arms: 2, periodMs: SB.hour,
				clusters: [(SB.unitType, editPath ? composed : "city")])
			a["switchbackClusterValues"] = [composed]
			var b = a
			if editPath {
				b["switchbackClusters"] = SB.OrderedObject([(SB.unitType, decomposed)])
			} else {
				b["switchbackClusterValues"] = [decomposed]
			}
			let context = createContext(SB.data([a]), clusterAttribute: false)
			clock.now = SB.anchor + 10
			context.setAttribute(name: editPath ? composed : "city", value: JSON(composed))
			_ = context.getTreatment("exp_sb")
			XCTAssertEqual(1, context.getPendingCount())
			refresh(context, SB.data([b]))
			XCTAssertEqual(0, context.getTreatment("exp_sb"))
			XCTAssertEqual(1, context.getPendingCount())
			refresh(context, SB.data([a]))
			_ = context.getTreatment("exp_sb")
			XCTAssertEqual(2, context.getPendingCount())
		}
	}

	func testUnicodeDesignAndLegacyUnitInterludesBreakTheEpoch() {
		for legacy in [false, true] {
			var a = SB.switchback(arms: 2, periodMs: SB.hour)
			var b = a
			if legacy {
				a["switchbackClusters"] = NSNull()
				a["unitType"] = "caf\u{E9}"
				b = a
				b["unitType"] = "cafe\u{301}"
			} else {
				a["switchbackDesignType"] = "caf\u{E9}"
				b = a
				b["switchbackDesignType"] = "cafe\u{301}"
			}
			let context = createContext(SB.data([a]))
			clock.now = SB.anchor + 10
			if legacy { context.setOverride(experimentName: "exp_sb", variant: 1) }
			_ = context.getTreatment("exp_sb")
			XCTAssertEqual(1, context.getPendingCount())
			refresh(context, SB.data([b]))
			refresh(context, SB.data([a]))
			_ = context.getTreatment("exp_sb")
			XCTAssertEqual(2, context.getPendingCount())
		}
	}

	// One getVariableValue call takes one clock reading (SWITCHBACK.md "Serving"; java-sdk
	// reads `now` once per call), so every switchback visited on a shared key resolves in the same period:
	// the strict-mismatched first candidate consumes the only pre-boundary reading, and the winner still
	// serves (and is stamped with) period 0.
	func testSharedVariableKeyWalkUsesOneClockReading() {
		var first = SB.switchback(1, "exp_sb", arms: 2, periodMs: SB.hour)
		first["audience"] = "{\"filter\":[{\"eq\":[{\"var\":\"tier\"},{\"value\":\"gold\"}]}]}"
		first["audienceStrict"] = true
		let second = SB.switchback(2, "exp_sb2", arms: 2, periodMs: SB.hour)
		let context = createContext(SB.data([first, second]))
		clock.now = SB.anchor + SB.hour + 5
		clock.nextRead = SB.anchor + SB.hour - 1
		XCTAssertEqual(SB.expected2Arms[0], context.getVariableValue("sb.arm", defaultValue: JSON(-1))?.int)
		let exposures = publishExposures(context)
		XCTAssertEqual(["exp_sb2"], exposures.map { $0.name })
		XCTAssertEqual([SB.anchor + SB.hour - 1], exposures.map { $0.exposedAt })
	}

	// A unit definition in between breaks the switchback chain every time, not only the
	// first (SWITCHBACK.md "Refresh and epochs"; java-sdk sameSwitchbackIdentity requires a switchback
	// previous). Two switchback -> unit -> switchback round trips each re-expose.
	func testEveryUnitInterludeStartsANewEpoch() {
		let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		_ = context.getTreatment("exp_sb")
		XCTAssertEqual(1, context.getPendingCount())
		var toUnit = SB.switchback(arms: 2, periodMs: SB.hour)
		toUnit["randomizationType"] = "unit"
		for round in 2...3 {
			refresh(context, SB.data([toUnit]))
			refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
			XCTAssertEqual(SB.expected2Arms[0], context.getTreatment("exp_sb"))
			XCTAssertEqual(round, Int(context.getPendingCount()))
		}
	}

	// Each identity field changed and restored with no lookup in between
	// starts a new epoch, so the next read exposes again.
	func testEveryIdentityFieldAbaStartsANewEpoch() {
		let edits: [(String, Any)] = [
			("switchbackStartAt", SB.anchor - SB.hour), ("switchbackPeriodMs", 2 * SB.hour), ("iteration", 2),
			("switchbackClusterValues", [SB.clusterKey]),
		]
		for (field, value) in edits {
			setUp()
			let context = createContext(SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
			clock.now = SB.anchor + 10
			_ = context.getTreatment("exp_sb")
			var edited = SB.switchback(arms: 2, periodMs: SB.hour)
			edited[field] = value
			refresh(context, SB.data([edited]))
			refresh(context, SB.data([SB.switchback(arms: 2, periodMs: SB.hour)]))
			_ = context.getTreatment("exp_sb")
			XCTAssertEqual(2, context.getPendingCount(), field)
		}
	}

	// A cached switchback slot with an audience is not re-evaluated on reads
	// after its resolution.
	final class CountingMatcher: AudienceMatcher {
		var evaluations = 0
		override func evaluate(_ audience: String, _ attributes: [String: JSON]) -> Bool? {
			evaluations += 1
			return super.evaluate(audience, attributes)
		}
	}

	func testCachedSwitchbackSlotDoesNotReevaluateItsAudience() {
		var sb = SB.switchback(arms: 2, periodMs: SB.hour)
		sb["audience"] = "{\"filter\":[{\"value\":true}]}"
		let matcher = CountingMatcher()
		let context = createContext(SB.data([sb]), matcher: matcher)
		clock.now = SB.anchor + 10
		_ = context.getTreatment("exp_sb")
		let afterResolve = matcher.evaluations
		for _ in 0..<3 {
			_ = context.getTreatment("exp_sb")
		}
		XCTAssertEqual(afterResolve, matcher.evaluations)
	}
}

extension ContextSwitchbackEpochTest {
	// java-sdk SWITCHBACK.md "Refresh and epochs": seed and split edits do not invalidate an already
	// cached assignment (as for unit experiments, which also keep their variant across such edits); the
	// next period draws with them.
	func testSeedAndSplitEditsKeepTheCachedPeriodAndApplyFromTheNextPeriod() {
		let context = createContext(SB.data([SB.switchback(arms: 3, periodMs: SB.hour)]))
		clock.now = SB.anchor + 10
		XCTAssertEqual(SB.expected3Arms[0], context.getTreatment("exp_sb"))

		var reseeded = SB.switchback(arms: 3, periodMs: SB.hour)
		reseeded["seedHi"] = 7
		reseeded["seedLo"] = 11
		reseeded["split"] = [0.5, 0.25, 0.25]
		refresh(context, SB.data([reseeded]))
		XCTAssertEqual(SB.expected3Arms[0], context.getTreatment("exp_sb"))
		XCTAssertEqual(1, context.getPendingCount())

		clock.now = SB.anchor + SB.hour
		let newSeed: Int64 = (Int64(7) << 32) | 11
		XCTAssertEqual(SB.draw(SB.clusterKey, 1, arms: 3, seed: newSeed), context.getTreatment("exp_sb"))
		XCTAssertEqual(2, context.getPendingCount())
	}
}
