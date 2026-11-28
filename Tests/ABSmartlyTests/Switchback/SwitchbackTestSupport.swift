import Foundation
import PromiseKit
import XCTest

@testable import ABSmartly

// Helpers shared by the switchback test classes, the Swift counterpart of java-sdk
// SwitchbackTestSupport and the fixtures of ContextSwitchbackTest.
enum SB {
	static let unitType = "store_id"
	static let uid = "e791e240fcd3df7d238cfc285f475e8152fcc0ec"
	// Hashing.hash(uid): the MD5/base64url string the Collector's UnitHasher also produces.
	static let uidHash = "pAE3a1i5Drs5mKRNq56adA"

	static let hour: Int64 = 3_600_000
	static let day: Int64 = 24 * hour
	// 2026-01-01T00:00:00Z, hour aligned.
	static let anchor: Int64 = 1_767_225_600_000

	static let seedHi = -5
	static let seedLo = -7
	static let seed: Int64 = (Int64(seedHi) << 32) | (Int64(seedLo) & 0xFFFF_FFFF)

	// The store unit's cluster value: attribute `clusterPath`, set on every default context.
	static let clusterPath = "store_key"
	static let clusterKey = "store-42"
	// Periods 0..11 of the raw cluster key "store-42" under seed (seedHi, seedLo) (java-sdk
	// ContextSwitchbackTest, from an independent reference that reproduces every golden vector).
	static let expected2Arms = [0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1]
	static let expected3Arms = [0, 2, 1, 2, 1, 0, 1, 2, 0, 1, 0, 2]
	static let expected10Arms = [8, 3, 7, 4, 2, 0, 5, 1, 9, 6, 3, 7]
	// What keying by the unit (hashed, or raw) instead of the cluster value would serve.
	static let uidHash3Arms = [1, 2, 0, 2, 1, 0, 2, 0, 1, 1, 2, 0]
	static let uid3Arms = [2, 0, 1, 0, 1, 2, 1, 2, 0, 0, 1, 2]

	// The Collector's draw over the raw cluster key.
	static func draw(_ key: String, _ periodIndex: Int64, arms: Int, seed: Int64 = seed) -> Int {
		return SwitchbackAssigner.assign(key, periodIndex: periodIndex, seed: seed, armCount: arms)
	}

	// A switchback experiment as a JSON object (java-sdk ContextSwitchbackTest.switchback). Each variant
	// `i` has the config `{"sb.arm": i}`. `clusters` is written in the given order.
	static func switchback(
		_ id: Int = 1, _ name: String = "exp_sb", arms: Int, periodMs: Int64?,
		clusters: [(String, Any)]? = [(unitType, clusterPath)]
	) -> [String: Any] {
		var experiment: [String: Any] = [
			"id": id, "name": name, "unitType": unitType, "iteration": 1, "seedHi": seedHi, "seedLo": seedLo,
			"split": [Double](repeating: 1.0 / Double(arms), count: arms), "trafficSeedHi": 1, "trafficSeedLo": 2,
			"trafficSplit": [0.0, 1.0], "fullOnVariant": 0, "applications": [["name": "website"]],
			"variants": (0..<arms).map { ["name": String(UnicodeScalar(65 + $0)!), "config": "{\"sb.arm\":\($0)}"] },
			"audienceStrict": false, "audience": NSNull(), "randomizationType": "switchback",
			"switchbackStartAt": anchor, "switchbackCarryoverDurationMs": 0, "switchbackBurnInDurationMs": 0,
			"switchbackBurnOutDurationMs": 0, "switchbackDesignType": "balanced_block",
			"switchbackEstimand": "global_average_treatment_effect",
		]
		experiment["switchbackPeriodMs"] = periodMs.map { $0 as Any } ?? NSNull()
		if let clusters = clusters {
			experiment["switchbackClusters"] = OrderedObject(clusters)
		}
		return experiment
	}

	// Holdout 11 for `uid` under seed (13, 111); split decides whether `uid` is held out.
	static func holdout(split: [Double]) -> [String: Any] {
		return [
			"id": 11, "name": "holdout_a", "unitType": unitType, "iteration": 1, "seedHi": 13, "seedLo": 111,
			"split": split, "trafficSplit": [0.0, 1.0], "fullOnVariant": 0, "variants": [] as [Any],
		]
	}

	// The context data JSON text for these experiments, with every object's keys in insertion order.
	static func json(_ experiments: [[String: Any]], holdouts: [[String: Any]]? = nil) -> Data {
		var root: [(String, Any)] = [("experiments", experiments)]
		if let holdouts = holdouts {
			root.append(("holdouts", holdouts))
		}
		return Data(serialize(OrderedObject(root)).utf8)
	}

	// Decoded through `ContextData.decode(from:)`, the path the SDK's own client takes.
	static func data(_ experiments: [[String: Any]], holdouts: [[String: Any]]? = nil) -> ContextData {
		return try! ContextData.decode(from: json(experiments, holdouts: holdouts))
	}

	// A JSON object whose keys serialize in the given order.
	struct OrderedObject {
		let entries: [(String, Any)]

		init(_ entries: [(String, Any)]) {
			self.entries = entries
		}
	}

	// Serializes a JSON value; dictionaries are written with sorted keys, `OrderedObject`s in order.
	static func serialize(_ value: Any) -> String {
		switch value {
		case let ordered as OrderedObject:
			return "{" + ordered.entries.map { quote($0.0) + ":" + serialize($0.1) }.joined(separator: ",") + "}"
		case let dictionary as [String: Any]:
			return "{" + dictionary.keys.sorted().map { quote($0) + ":" + serialize(dictionary[$0]!) }.joined(separator: ",")
				+ "}"
		case let array as [Any]:
			return "[" + array.map(serialize).joined(separator: ",") + "]"
		case let string as String:
			return quote(string)
		case is NSNull:
			return "null"
		case let bool as Bool:
			return bool ? "true" : "false"
		case let int as Int:
			return String(int)
		case let int as Int64:
			return String(int)
		case let double as Double:
			return String(double)
		default:
			fatalError("unsupported JSON value \(value)")
		}
	}

	static func quote(_ s: String) -> String {
		let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
		let text = String(data: data, encoding: .utf8)!
		return String(text.dropFirst().dropLast())
	}
}

// A clock the test moves; when `nextRead` is set, the next read returns it once.
final class MutableClock: Clock {
	private let lock = NSLock()
	private var nowValue: Int64
	private var nextReadValue: Int64?
	private(set) var reads = 0

	init(_ now: Int64) {
		nowValue = now
	}

	var now: Int64 {
		get { lock.lock(); defer { lock.unlock() }; return nowValue }
		set { lock.lock(); nowValue = newValue; lock.unlock() }
	}

	var nextRead: Int64? {
		get { lock.lock(); defer { lock.unlock() }; return nextReadValue }
		set { lock.lock(); nextReadValue = newValue; lock.unlock() }
	}

	func millis() -> Int64 {
		lock.lock()
		defer { lock.unlock() }
		reads += 1
		if let value = nextReadValue {
			nextReadValue = nil
			return value
		}
		return nowValue
	}
}

// Shared state and helpers for a Context-level switchback test case.
class SwitchbackTestCase: XCTestCase {
	var clock = MutableClock(SB.anchor)
	var handler = ContextEventHandlerMock()
	var logger = ContextEventLoggerMock()
	var scheduler = SchedulerMock()
	var provider = ContextDataProviderMock()

	override func setUp() {
		super.setUp()
		clock = MutableClock(SB.anchor)
		handler = ContextEventHandlerMock()
		handler.publishEventReturnValue = Promise<Void>.value(())
		logger = ContextEventLoggerMock()
		scheduler = SchedulerMock()
		scheduler.scheduleAfterExecuteReturnValue = ScheduledHandleMock()
		scheduler.scheduleWithFixedDelayAfterRepeatingExecuteReturnValue = ScheduledHandleMock()
		provider = ContextDataProviderMock()
	}

	// A context with `units` (default: the store unit) and the cluster attribute set at creation.
	func createContext(
		_ data: ContextData, units: [String: String]? = [SB.unitType: SB.uid], clusterAttribute: Bool = true,
		matcher: AudienceMatcher = AudienceMatcher(), configure: (ContextConfig) -> Void = { _ in }
	) -> Context {
		let config = ContextConfig()
		for (unitType, uid) in units ?? [:] {
			config.setUnit(unitType: unitType, uid: uid)
		}
		if clusterAttribute {
			config.setAttribute(name: SB.clusterPath, value: JSON(SB.clusterKey))
		}
		configure(config)
		return Context(
			config: config, clock: clock, scheduler: scheduler, handler: handler, provider: provider, logger: logger,
			parser: DefaultVariableParser(), matcher: matcher, promise: Promise<ContextData>.value(data),
			application: "website", environment: "production")
	}

	func refresh(_ context: Context, _ data: ContextData, file: StaticString = #filePath, line: UInt = #line) {
		provider.getContextDataReturnValue = Promise<ContextData>.value(data)
		XCTAssertNoThrow(try context.refresh().wait(), file: file, line: line)
	}

	func peekSchedule(_ context: Context, _ name: String = "exp_sb", periodMs: Int64 = SB.hour, periods: Int = 12)
		-> [Int]
	{
		return (0..<periods).map { i in
			clock.now = SB.anchor + Int64(i) * periodMs
			return context.peekTreatment(name)
		}
	}

	// Publishes and returns the one publish event (nil when nothing was published).
	func publish(_ context: Context, file: StaticString = #filePath, line: UInt = #line) -> PublishEvent? {
		handler.clearInvocations()
		XCTAssertNoThrow(try context.publish().wait(), file: file, line: line)
		XCTAssertLessThanOrEqual(handler.publishEventCallsCount, 1, file: file, line: line)
		return handler.publishEventReceivedEvent
	}

	func publishExposures(_ context: Context, file: StaticString = #filePath, line: UInt = #line) -> [Exposure] {
		return publish(context, file: file, line: line)?.exposures ?? []
	}

	func loggedExposures() -> [Exposure] {
		return logger.handleEventContextEventReceivedInvocations.compactMap {
			if case let .exposure(exposure) = $0.event { return exposure }
			return nil
		}
	}

	func exposure(
		_ variant: Int, _ exposedAt: Int64, id: Int = 1, name: String = "exp_sb", unit: String = SB.unitType,
		assigned: Bool = true, eligible: Bool = true, overridden: Bool = false, fullOn: Bool = false,
		custom: Bool = false, audienceMismatch: Bool = false, ruleOverride: Bool = false
	) -> Exposure {
		return Exposure(
			id, name, unit, variant, exposedAt, assigned, eligible, overridden, fullOn, custom, audienceMismatch,
			ruleOverride: ruleOverride)
	}

	// The exposure encoded the way the publisher sends it, keys sorted.
	func encoded<T: Encodable>(_ value: T) -> String {
		let encoder = JSONEncoder()
		if #available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *) {
			encoder.outputFormatting = .sortedKeys
		}
		return String(data: try! encoder.encode(value), encoding: .utf8)!
	}
}

// A value shared with detached threads, guarded by a lock (Sendable-clean under Swift 6 checking).
final class LockedBox<Value>: @unchecked Sendable {
	private let lock = NSLock()
	private var stored: Value

	init(_ value: Value) {
		stored = value
	}

	var value: Value {
		get {
			lock.lock()
			defer { lock.unlock() }
			return stored
		}
		set {
			lock.lock()
			stored = newValue
			lock.unlock()
		}
	}

	func update(_ body: (inout Value) -> Void) {
		lock.lock()
		body(&stored)
		lock.unlock()
	}
}
