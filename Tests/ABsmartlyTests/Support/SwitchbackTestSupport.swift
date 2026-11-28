import Foundation
import Testing

@testable import ABsmartly

/// A clock the test moves by hand; timers never fire (as with `FixedClock`).
final class ManualClock: Clock, @unchecked Sendable {
	private let lock = NSLock()
	private var value: Int64
	private var readCount = 0

	init(_ value: Int64) { self.value = value }

	var now: Int64 {
		get { lock.withLock { value } }
		set { lock.withLock { value = newValue } }
	}

	/// How many times the SDK read the time.
	var reads: Int { lock.withLock { readCount } }

	func millis() -> Int64 {
		lock.withLock {
			readCount += 1
			return value
		}
	}

	func sleep(seconds: TimeInterval) async throws {
		try await TestClock.sleepZeroOrForever(seconds)
	}
}

/// Payload builders and expectations for the switchback tests, with the values of 1.x's and
/// java-sdk's ContextSwitchbackTest so every line pins the same schedule.
enum SB {
	static let unitType = "store_id"
	static let uid = "e791e240fcd3df7d238cfc285f475e8152fcc0ec"

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
	// Periods 0..11 of the raw cluster key "store-42" under seed (seedHi, seedLo).
	static let expected2Arms = [0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1]
	static let expected3Arms = [0, 2, 1, 2, 1, 0, 1, 2, 0, 1, 0, 2]
	static let expected10Arms = [8, 3, 7, 4, 2, 0, 5, 1, 9, 6, 3, 7]
	// What keying by the hashed unit, or the raw unit, instead of the cluster value would serve.
	static let uidHash3Arms = [1, 2, 0, 2, 1, 0, 2, 0, 1, 1, 2, 0]
	static let uid3Arms = [2, 0, 1, 0, 1, 2, 1, 2, 0, 0, 1, 2]

	static func draw(_ key: String, _ period: Int64, arms: Int) -> Int {
		SwitchbackAssigner.assign(key, periodIndex: period, seed: seed, armCount: arms)
	}

	/// A switchback experiment as a JSON object. Variant `i` has the config `{"sb.arm": i}`.
	/// `clusters` is written in the given order.
	static func switchback(
		_ id: Int = 1, _ name: String = "exp_sb", arms: Int = 2, periodMs: Int64? = hour,
		clusters: [(String, Any)]? = [(unitType, clusterPath)], extra: [String: Any] = [:]
	) -> [String: Any] {
		var experiment: [String: Any] = [
			"id": id, "name": name, "unitType": unitType, "iteration": 1, "seedHi": seedHi, "seedLo": seedLo,
			"split": [Double](repeating: 1.0 / Double(arms), count: arms), "trafficSeedHi": 1, "trafficSeedLo": 2,
			"trafficSplit": [0.0, 1.0], "fullOnVariant": 0, "applications": [["name": "website"]],
			"variants": (0..<arms).map { ["name": "\($0)", "config": "{\"sb.arm\":\($0)}"] },
			"audienceStrict": false, "audience": NSNull(), "randomizationType": "switchback",
			"switchbackStartAt": anchor, "switchbackCarryoverDurationMs": 0, "switchbackBurnInDurationMs": 0,
			"switchbackBurnOutDurationMs": 0, "switchbackDesignType": "balanced_block",
			"switchbackEstimand": "global_average_treatment_effect",
		]
		experiment["switchbackPeriodMs"] = periodMs.map { $0 as Any } ?? NSNull()
		if let clusters {
			experiment["switchbackClusters"] = OrderedObject(clusters)
		}
		experiment.merge(extra) { _, new in new }
		return experiment
	}

	/// The context data JSON text, with every `OrderedObject`'s keys in order.
	static func json(_ experiments: [[String: Any]], holdouts: [[String: Any]]? = nil) -> Data {
		var root: [(String, Any)] = [("experiments", experiments)]
		if let holdouts {
			root.append(("holdouts", holdouts))
		}
		return Data(serialize(OrderedObject(root)).utf8)
	}

	/// Decoded through `ContextData(json:)`, the path the SDK's own fetch takes.
	static func data(_ experiments: [[String: Any]], holdouts: [[String: Any]]? = nil) -> ContextData {
		try! ContextData(json: json(experiments, holdouts: holdouts))
	}

	/// A JSON object whose keys serialize in the given order.
	struct OrderedObject {
		let entries: [(String, Any)]
		init(_ entries: [(String, Any)]) { self.entries = entries }
	}

	static func serialize(_ value: Any) -> String {
		switch value {
		case let ordered as OrderedObject:
			return "{" + ordered.entries.map { quote($0.0) + ":" + serialize($0.1) }.joined(separator: ",") + "}"
		case let dictionary as [String: Any]:
			return "{"
				+ dictionary.keys.sorted().map { quote($0) + ":" + serialize(dictionary[$0]!) }.joined(separator: ",")
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
		let data = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
		let text = String(decoding: data, as: UTF8.self)
		return String(text.dropFirst().dropLast())
	}

	/// The switchback's own exposure, published under the store unit.
	static func exposure(
		_ variant: Int, _ exposedAt: Int64, id: Int = 1, name: String = "exp_sb", unit: String = unitType,
		assigned: Bool = true, eligible: Bool = true, overridden: Bool = false, fullOn: Bool = false,
		custom: Bool = false, audienceMismatch: Bool = false, ruleOverride: Bool = false
	) -> Exposure {
		Exposure(
			id: id, name: name, unit: unit, variant: variant, exposedAt: exposedAt, assigned: assigned,
			eligible: eligible, overridden: overridden, fullOn: fullOn, custom: custom,
			audienceMismatch: audienceMismatch, ruleOverride: ruleOverride)
	}
}

/// A `ContextEnv` on a `ManualClock` starting at the anchor, with contexts on the store unit whose
/// cluster attribute is set at the anchor.
struct SwitchbackEnv {
	let clock: ManualClock
	let env: ContextEnv

	init(now: Int64 = SB.anchor) {
		clock = ManualClock(now)
		env = ContextEnv(clock: clock)
	}

	func context(
		_ data: ContextData, units: [UnitType: String] = [UnitType(SB.unitType): SB.uid],
		attributes: [String: JSONValue] = [SB.clusterPath: .string(SB.clusterKey)], overrides: [String: Int] = [:],
		customAssignments: [String: Int] = [:]
	) -> Context {
		env.directContext(
			data: data, units: units, attributes: attributes, overrides: overrides,
			customAssignments: customAssignments)
	}

	/// Installs `data` through a refresh. The encoder writes each cluster map as an ordered array.
	func refresh(_ context: Context, _ data: ContextData) async throws {
		env.serveNext(data)
		try await context.refresh()
	}

	/// The exposures logged so far.
	var exposures: [Exposure] { env.log.exposures }

	/// Publishes and returns the exposures the collector received (nil when nothing was sent).
	func publish(_ context: Context) async throws -> [Exposure]? {
		let before = env.publishCount
		try await context.publish()
		guard env.publishCount > before, case .array(let exposures)? = env.lastSentEvent?["exposures"] else {
			return env.publishCount > before ? [] : nil
		}
		return exposures.map { e in
			Exposure(
				id: e["id"]?.intValue ?? 0, name: e["name"]?.stringValue ?? "", unit: e["unit"]?.stringValue,
				variant: e["variant"]?.intValue ?? 0, exposedAt: Int64(e["exposedAt"]?.intValue ?? 0),
				assigned: e["assigned"]?.boolValue ?? false, eligible: e["eligible"]?.boolValue ?? false,
				overridden: e["overridden"]?.boolValue ?? false, fullOn: e["fullOn"]?.boolValue ?? false,
				custom: e["custom"]?.boolValue ?? false, audienceMismatch: e["audienceMismatch"]?.boolValue ?? false,
				ruleOverride: e["ruleOverride"]?.boolValue ?? false)
		}
	}

	/// The variants served over periods 0..<count, peeking.
	func peekSchedule(_ context: Context, _ name: String = "exp_sb", count: Int = 12, periodMs: Int64 = SB.hour)
		-> [Int]
	{
		(0..<count).map { i in
			clock.now = SB.anchor + Int64(i) * periodMs
			return context.treatment(for: name, exposing: false)
		}
	}
}
