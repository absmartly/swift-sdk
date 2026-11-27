import Foundation

#if canImport(CryptoKit)
	import CryptoKit
#else
	import Crypto
#endif

// MD5 is used for non-cryptographic purposes only: a fast, deterministic hash of the unit UID for
// bucketing, identical across SDKs and the collector.
enum Hashing {
	/// base64url (no padding) of the MD5 of the UTF-8 bytes of `unit`, as ASCII bytes.
	static func hashUnit(_ unit: String) -> [UInt8] {
		let digest = Insecure.MD5.hash(data: Data(unit.utf8))
		return Array(base64URL(Data(digest)).utf8)
	}

	static func base64URL(_ data: Data) -> String {
		var string = data.base64EncodedString()
		string = string.replacingOccurrences(of: "+", with: "-")
		string = string.replacingOccurrences(of: "/", with: "_")
		while string.hasSuffix("=") {
			string.removeLast()
		}
		return string
	}

	/// JavaScript's `Number.prototype.toFixed(0)`, the string a numeric UID is hashed from: the sign
	/// is kept for any negative input (`-0.1` gives "-0"), halves round away from zero, and
	/// magnitudes of 1e21 or more use the exponent form of `String(number)` ("1e+21").
	static func unitString(_ value: Double) -> String {
		if value.isNaN { return "NaN" }
		let negative = value < 0
		let magnitude = Swift.abs(value)
		let body: String
		if magnitude >= 1e21 {
			// Swift prints large doubles as "1e+21" / "1.5e+22", the same shortest form as JS.
			body = magnitude.isInfinite ? "Infinity" : "\(magnitude)"
		} else {
			body = String(format: "%.0f", magnitude.rounded(.toNearestOrAwayFromZero))
		}
		return negative ? "-" + body : body
	}
}

enum MurmurHash {
	private static let c1: UInt32 = 0xcc9e_2d51
	private static let c2: UInt32 = 0x1b87_3593

	private static func scramble(_ value: UInt32) -> UInt32 {
		var k = value &* c1
		k = (k << 15) | (k >> 17)
		return k &* c2
	}

	static func hash(_ bytes: [UInt8], seed: UInt32 = 0) -> UInt32 {
		let count = bytes.count
		var hash = seed
		var i = 0

		while i + 4 <= count {
			let chunk =
				UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8) | (UInt32(bytes[i + 2]) << 16)
				| (UInt32(bytes[i + 3]) << 24)
			hash ^= scramble(chunk)
			hash = (hash << 13) | (hash >> 19)
			hash = hash &* 5 &+ 0xe654_6b64
			i += 4
		}

		var tail: UInt32 = 0
		switch count & 3 {
		case 3:
			tail ^= UInt32(bytes[i + 2]) << 16
			fallthrough
		case 2:
			tail ^= UInt32(bytes[i + 1]) << 8
			fallthrough
		case 1:
			tail ^= UInt32(bytes[i])
			hash ^= scramble(tail)
		default:
			break
		}

		hash ^= UInt32(truncatingIfNeeded: count)
		hash ^= hash >> 16
		hash = hash &* 0x85eb_ca6b
		hash ^= hash >> 13
		hash = hash &* 0xc2b2_ae35
		hash ^= hash >> 16
		return hash
	}
}

/// Picks a variant from a split for one unit, as every ABsmartly SDK does.
struct VariantAssigner: Sendable {
	private let unitHash: UInt32

	init(unitHash: [UInt8]) {
		self.unitHash = MurmurHash.hash(unitHash)
	}

	func assign(_ split: [Double], seedHi: Int, seedLo: Int) -> Int {
		var buffer = [UInt8](repeating: 0, count: 12)
		Self.put(&buffer, 0, UInt32(truncatingIfNeeded: seedLo))
		Self.put(&buffer, 4, UInt32(truncatingIfNeeded: seedHi))
		Self.put(&buffer, 8, unitHash)
		let probability = Double(MurmurHash.hash(buffer)) * (1.0 / 0xFFFF_FFFF)
		return Self.chooseVariant(split, probability)
	}

	static func chooseVariant(_ split: [Double], _ probability: Double) -> Int {
		var cumulative = 0.0
		for (i, value) in split.enumerated() {
			cumulative += value
			if probability < cumulative {
				return i
			}
		}
		return split.count - 1
	}

	private static func put(_ buffer: inout [UInt8], _ offset: Int, _ x: UInt32) {
		buffer[offset] = UInt8(x & 0xff)
		buffer[offset + 1] = UInt8((x >> 8) & 0xff)
		buffer[offset + 2] = UInt8((x >> 16) & 0xff)
		buffer[offset + 3] = UInt8((x >> 24) & 0xff)
	}
}

/// The unit hashing the SDK publishes, for conformance tests (cross-sdk-tests' `diagnostic` action).
/// Not public API: import with `@_spi(Diagnostics) import ABsmartly`. It may change in any release.
@_spi(Diagnostics)
public enum Diagnostics {
	/// The hash a string UID is published as.
	public static func hashUnit(_ uid: String) -> String {
		String(decoding: Hashing.hashUnit(uid), as: UTF8.self)
	}

	/// The hash a numeric UID is published as (rounded like JavaScript's `toFixed(0)` first).
	public static func hashUnit(_ uid: Double) -> String {
		hashUnit(Hashing.unitString(uid))
	}

	/// The UTF-8 bytes a UID is hashed from.
	public static func utf8Bytes(_ value: String) -> [UInt8] {
		Array(value.utf8)
	}

	/// The switchback variant of the raw cluster key `clusterUnit` in period `periodIndex`, with
	/// `seed = (seedHi << 32) | (seedLo & 0xffffffff)`; nil when `armCount` is less than 2.
	public static func switchbackVariant(clusterUnit: String, periodIndex: Int64, seed: Int64, armCount: Int) -> Int? {
		armCount >= 2
			? SwitchbackAssigner.assign(clusterUnit, periodIndex: periodIndex, seed: seed, armCount: armCount) : nil
	}

	/// The switchback order of `0..<armCount` over cycle `cycleIndex`; nil when `armCount` is less than 2.
	public static func switchbackPermutation(clusterUnit: String, cycleIndex: Int64, seed: Int64, armCount: Int)
		-> [Int]?
	{
		armCount >= 2
			? SwitchbackAssigner.permutation(clusterUnit, cycleIndex: cycleIndex, seed: seed, armCount: armCount) : nil
	}
}
