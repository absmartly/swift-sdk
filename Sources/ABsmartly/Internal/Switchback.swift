import Foundation

/// A switchback cluster attribute path, resolved like the Collector's SwitchbackAttributePath (as
/// ported by java-sdk): "/" separates segments, a segment wrapped in ' or " is a literal key, and an
/// unquoted segment that Guava's `Ints.tryParse` accepts (ASCII digits, optional leading '-') indexes
/// an array and nothing else. Every other segment reads an object key. A path is malformed, and its
/// experiment unservable, when a quote is left unterminated or the path contains a '.' anywhere,
/// quoted or not (dotted paths are not a nesting syntax; nesting is written with '/').
struct SwitchbackAttributePath: Sendable, Equatable {
	private let keys: [String]
	// Parallel to `keys`; nil where the segment is an object key.
	private let indices: [Int?]

	/// Nil for an unsupported path: malformed (see above), empty, or with an array index that is
	/// negative, first, last, or directly after another index. Analysis cannot read those.
	static func parseSupported(_ path: String?) -> SwitchbackAttributePath? {
		guard let path, let parsed = parse(path), !parsed.keys.isEmpty else { return nil }
		let n = parsed.keys.count
		for (i, index) in parsed.indices.enumerated() {
			if let index, index < 0 || i == 0 || i == n - 1 || parsed.indices[i - 1] != nil {
				return nil
			}
		}
		return parsed
	}

	/// The attribute name the path starts at; a supported path always starts with a key segment.
	var rootKey: String { keys[0] }

	/// Resolves the path below `rootKey` in that attribute's value.
	func resolve(in rootValue: JSONValue) -> JSONValue? {
		var current = rootValue
		for i in 1..<keys.count {
			if let index = indices[i] {
				guard case .array(let array) = current, array.indices.contains(index) else { return nil }
				current = array[index]
			} else {
				guard case .object(let object) = current, let next = object[keys[i]] else { return nil }
				current = next
			}
		}
		return current
	}

	// Nil when the path is malformed. Scans Unicode scalars, so a quote followed by a combining mark
	// is still a quote.
	private static func parse(_ path: String) -> SwitchbackAttributePath? {
		let scalars = Array(path.unicodeScalars)
		if scalars.contains(".") {
			return nil
		}
		var keys: [String] = []
		var indices: [Int?] = []
		var i = 0
		while i < scalars.count {
			let first = scalars[i]
			if first == "/" {
				i += 1
				continue
			}
			if first == "'" || first == "\"" {
				guard let end = scalars[(i + 1)...].firstIndex(of: first) else { return nil }
				keys.append(string(scalars[(i + 1)..<end]))
				indices.append(nil)
				i = end + 1
			} else {
				let stop = scalars[i...].firstIndex(of: "/") ?? scalars.count
				let key = string(scalars[i..<stop])
				keys.append(key)
				indices.append(tryParseInt(key))
				i = stop
			}
		}
		return SwitchbackAttributePath(keys: keys, indices: indices)
	}

	private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
		var view = String.UnicodeScalarView()
		view.append(contentsOf: scalars)
		return String(view)
	}

	/// Guava's `Ints.tryParse(String)`: an optional '-', then one or more ASCII digits, within Int32
	/// range; otherwise nil. "+1" and non-ASCII digits are not numbers; "-0" is 0.
	static func tryParseInt(_ s: String) -> Int? {
		let scalars = Array(s.unicodeScalars)
		let negative = scalars.first == "-"
		var i = negative ? 1 : 0
		if i == scalars.count {
			return nil
		}
		var magnitude: Int64 = 0
		while i < scalars.count {
			let c = scalars[i].value
			if c < 0x30 || c > 0x39 {
				return nil
			}
			magnitude = magnitude * 10 + Int64(c - 0x30)
			if magnitude > (Int64(1) << 31) {
				return nil
			}
			i += 1
		}
		let value = negative ? -magnitude : magnitude
		return value > Int64(Int32.max) ? nil : Int(value)
	}
}

/// One linked unit type of a switchback with its parsed cluster attribute path.
struct SwitchbackSource: Sendable, Equatable {
	let unitType: String
	let path: SwitchbackAttributePath

	/// The sources of a `switchbackClusters` map in declared order; nil for a missing or empty map, or
	/// one with a path that is not a supported attribute path (the Collector's legacy path).
	static func sources(_ clusters: [SwitchbackCluster]?) -> [SwitchbackSource]? {
		guard let clusters, !clusters.isEmpty else { return nil }
		var sources: [SwitchbackSource] = []
		for cluster in clusters {
			guard let path = SwitchbackAttributePath.parseSupported(cluster.attributePath) else { return nil }
			sources.append(SwitchbackSource(unitType: cluster.unitType, path: path))
		}
		return sources
	}
}

/// Which unit serves a switchback experiment and under which cluster key (the Collector's
/// `ContextAPI.switchbackServing`, R33, as java-sdk's SwitchbackServing ports it):
///
/// - The sources are the experiment's `switchbackClusters` entries in their declared order.
/// - No context unit of a linked type: the experiment does not apply (`absent`).
/// - Otherwise each linked unit, in source order, reads the attribute at its source's path,
///   normalised by `clusterKey(_:)`. The first unit yielding a value is the serving unit and the
///   value is the cluster key; units yielding no value are skipped.
/// - `ineligible`, served under the first linked unit: no unit yields a value, two units yield
///   different values, or an allow-list is set and lacks the key.
/// - `eligible` otherwise.
/// - A missing, empty or unreadable cluster map takes the Collector's legacy path (`legacy`).
struct SwitchbackServing: Sendable, Equatable {
	enum Status: Sendable {
		case absent
		case ineligible
		case eligible
	}

	let status: Status
	/// The serving unit's type when eligible, the first linked unit's type when ineligible, nil when absent.
	let unitType: String?
	/// The raw normalised cluster key when eligible; never hashed.
	let clusterKey: String?

	static let absent = SwitchbackServing(status: .absent, unitType: nil, clusterKey: nil)

	/// A context has at most one unit per type, so the source loop alone orders the units.
	static func resolve(
		_ sources: [SwitchbackSource], allowedValues: [String]?, hasUnit: (String) -> Bool,
		read: (SwitchbackAttributePath) -> JSONValue?
	) -> SwitchbackServing {
		var first: String?
		var serving: String?
		var key: String?
		var disagreement = false
		for source in sources where hasUnit(source.unitType) {
			if first == nil {
				first = source.unitType
			}
			guard let value = clusterKey(read(source.path)) else { continue }
			if key == nil {
				key = value
				serving = source.unitType
			} else if key != value {
				disagreement = true
			}
		}

		guard let first else { return .absent }
		guard let key, !disagreement, allowed(allowedValues, key) else {
			return SwitchbackServing(status: .ineligible, unitType: first, clusterKey: nil)
		}
		return SwitchbackServing(status: .eligible, unitType: serving, clusterKey: key)
	}

	/// The Collector's compatibility path for a missing, empty or unreadable cluster map: the declared
	/// unitType only identifies an ineligible control (never an assignment or a cluster); without a
	/// unit of that type the experiment does not apply.
	static func legacy(unitType: String?, hasUnit: (String) -> Bool) -> SwitchbackServing {
		guard let unitType, hasUnit(unitType) else { return .absent }
		return SwitchbackServing(status: .ineligible, unitType: unitType, clusterKey: nil)
	}

	/// A nil or empty allow-list admits every value, as in the Collector.
	static func allowed(_ allowedValues: [String]?, _ key: String) -> Bool {
		guard let allowedValues, !allowedValues.isEmpty else { return true }
		return allowedValues.contains(key)
	}

	/// The cluster key an attribute value yields (the Collector's `SwitchbackClusterKeys.normalize`):
	/// a non-empty string as-is and an integer as its base-10 text. Null, empty strings, booleans,
	/// floating-point numbers (`3.0` included), objects and arrays yield none.
	static func clusterKey(_ value: JSONValue?) -> String? {
		switch value {
		case .string(let string)?: return string.isEmpty ? nil : string
		case .int(let int)?: return String(int)
		default: return nil
		}
	}
}

/// A switchback assignment's own state, pinned when it was resolved.
/// Its grid is not pinned: a change to the switchback's identity starts a new generation, whose
/// epoch drops every slot of the old one before a cached slot is read.
final class SwitchbackSlot {
	/// The serving unit and cluster key read for this slot, once per slot.
	let serving: SwitchbackServing
	/// The custom assignment set when it was resolved.
	let customAssignment: Int?
	/// A resolution the Collector records nothing for: no linked unit, an ineligible cluster, or no
	/// draw (before the anchor or an unservable schedule).
	var silent = false

	init(serving: SwitchbackServing, customAssignment: Int?) {
		self.serving = serving
		self.customAssignment = customAssignment
	}
}

/// One switchback experiment's cache slots: the bare-name slot (before the anchor or an unservable
/// grid) and its period slots, all created under one generation of its definition.
struct SwitchbackEpoch {
	let generation: Int
	var periods: [Int64] = []
}

/// A switchback schedule and its period grid (the Collector's Registry and ContextAPI).
enum SwitchbackSchedule {
	// The Collector's anchor bounds: hour aligned and in [0, 10000-01-01T00:00:00Z).
	static let anchorAlignmentMs: Int64 = 3_600_000
	static let maxAnchorMs: Int64 = 253_402_300_800_000

	/// Whether the Collector can serve the schedule: a start that is set, hour aligned and in range
	/// (used as served, never rounded), a period above 0 and at least two arms. An unservable
	/// schedule only replaces the draw: assignment rules, audience and full-on still apply.
	static func servable(_ experiment: Experiment) -> Bool {
		guard let startAt = experiment.switchbackStartAt, startAt >= 0, startAt < maxAnchorMs,
			startAt % anchorAlignmentMs == 0, let periodMs = experiment.switchbackPeriodMs, periodMs > 0
		else {
			return false
		}
		return experiment.split.count >= 2
	}

	/// `floorDiv(now - switchbackStartAt, switchbackPeriodMs)`, as the Collector computes it. Nil
	/// before the start, for an unservable schedule and for a cluster map taking the legacy path.
	static func period(_ entry: DataIndex.Entry, now: Int64) -> Int64? {
		let data = entry.data
		guard entry.switchbackSources != nil, servable(data), let startAt = data.switchbackStartAt,
			let periodMs = data.switchbackPeriodMs, now >= startAt
		else {
			return nil
		}
		return SwitchbackAssigner.floorDiv(now - startAt, periodMs)
	}

	/// `seed = (seedHi << 32) | (seedLo & 0xffffffff)`.
	static func seed(_ experiment: Experiment) -> Int64 {
		(Int64(truncatingIfNeeded: experiment.seedHi) << 32)
			| (Int64(truncatingIfNeeded: experiment.seedLo) & 0xFFFF_FFFF)
	}

	/// The cache slot of a resolution: the bare name before the anchor or for an unservable grid.
	static func cacheKey(_ experimentName: String, _ period: Int64?) -> String {
		guard let period else { return experimentName }
		return experimentName + "\u{1F}" + String(period)
	}

	/// Switchback identity: id, iteration, the ordered cluster map, the allow-list, start, period
	/// length and design (every input to the grid and the cluster key), plus unitType when either side
	/// takes the legacy path. Seed, split and the analysis-only fields are not identity.
	static func sameIdentity(_ previous: DataIndex.Entry, _ installed: DataIndex.Entry) -> Bool {
		guard previous.data.isSwitchback else { return false }
		let a = previous.data
		let b = installed.data
		return a.id == b.id && a.iteration == b.iteration && a.switchbackClusters == b.switchbackClusters
			&& a.switchbackClusterValues == b.switchbackClusterValues && a.switchbackStartAt == b.switchbackStartAt
			&& a.switchbackPeriodMs == b.switchbackPeriodMs && a.switchbackDesignType == b.switchbackDesignType
			&& ((previous.switchbackSources != nil && installed.switchbackSources != nil) || a.unitType == b.unitType)
	}
}

/// Java's `String.trim()`: strips leading and trailing characters up to U+0020.
func javaTrim(_ s: String) -> String {
	let scalars = s.unicodeScalars
	guard let first = scalars.firstIndex(where: { $0.value > 0x20 }),
		let last = scalars.lastIndex(where: { $0.value > 0x20 })
	else { return "" }
	return String(scalars[first...last])
}
