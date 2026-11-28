import Foundation

/// The balanced-block switchback draw the Collector and analysis use (the platform's
/// SwitchbackAssignment, ported as java-sdk's internal SwitchbackAssigner; murmur3_32, seed 0):
///
///     key       = utf8(clusterUnit + "\u{1F}" + cycleIndex)
///     baseHash  = murmur3_32(le64(seed) ++ le32(murmur3_32(key)))
///     stepHash  = murmur3_32(le32(baseHash) ++ le32(i)),  i = armCount-1 ... 1
///     j         = min(i, floor(u32(stepHash) / 0xffffffff * (i + 1)))
///     variant   = permutation[floorMod(periodIndex, armCount)], cycle = floorDiv(periodIndex, armCount)
///
/// Any change here breaks parity with the platform golden vectors and the analysis-side schedule.
enum SwitchbackAssigner {
	private static let normalizer: Double = 1.0 / 0xFFFF_FFFF
	private static let separator = "\u{1F}"

	/// The variant of `clusterUnit` (a raw cluster key, never hashed) in period `periodIndex`.
	/// `armCount` must be at least 2.
	static func assign(_ clusterUnit: String, periodIndex: Int64, seed: Int64, armCount: Int) -> Int {
		precondition(armCount >= 2, "armCount must be >= 2, got \(armCount)")
		let arms = Int64(armCount)
		let cycleIndex = floorDiv(periodIndex, arms)
		// floorMod; the product may wrap near Int64.min but the difference is exact mod 2^64.
		let cycleSlot = Int(periodIndex &- cycleIndex &* arms)
		return permutation(clusterUnit, cycleIndex: cycleIndex, seed: seed, armCount: armCount)[cycleSlot]
	}

	/// The order of `0..<armCount` served over cycle `cycleIndex`. `armCount` must be at least 2.
	static func permutation(_ clusterUnit: String, cycleIndex: Int64, seed: Int64, armCount: Int) -> [Int] {
		fisherYates(armCount, baseHash: baseHash(clusterUnit, cycleIndex: cycleIndex, seed: seed))
	}

	static func fisherYates(_ armCount: Int, baseHash: UInt32) -> [Int] {
		precondition(armCount >= 2, "armCount must be >= 2, got \(armCount)")
		var permutation = Array(0..<armCount)
		var buffer = [UInt8](repeating: 0, count: 8)
		putUInt32(&buffer, 0, baseHash)
		var i = armCount - 1
		while i > 0 {
			putUInt32(&buffer, 4, UInt32(i))
			let probability = Double(MurmurHash.hash(buffer)) * normalizer
			// A probability of exactly 1.0 would map to i + 1.
			let j = min(i, Int((probability * Double(i + 1)).rounded(.down)))
			permutation.swapAt(i, j)
			i -= 1
		}
		return permutation
	}

	static func baseHash(_ clusterUnit: String, cycleIndex: Int64, seed: Int64) -> UInt32 {
		let keyHash = MurmurHash.hash(Array((clusterUnit + separator + String(cycleIndex)).utf8))
		var buffer = [UInt8](repeating: 0, count: 12)
		let bits = UInt64(bitPattern: seed)
		putUInt32(&buffer, 0, UInt32(truncatingIfNeeded: bits))
		putUInt32(&buffer, 4, UInt32(truncatingIfNeeded: bits >> 32))
		putUInt32(&buffer, 8, keyHash)
		return MurmurHash.hash(buffer)
	}

	/// Floor division; `divisor` is always positive here.
	static func floorDiv(_ dividend: Int64, _ divisor: Int64) -> Int64 {
		let quotient = dividend / divisor
		return (dividend % divisor != 0 && (dividend < 0) != (divisor < 0)) ? quotient - 1 : quotient
	}

	private static func putUInt32(_ buffer: inout [UInt8], _ offset: Int, _ x: UInt32) {
		buffer[offset] = UInt8(x & 0xff)
		buffer[offset + 1] = UInt8((x >> 8) & 0xff)
		buffer[offset + 2] = UInt8((x >> 16) & 0xff)
		buffer[offset + 3] = UInt8((x >> 24) & 0xff)
	}
}
