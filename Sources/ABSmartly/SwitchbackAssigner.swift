import Foundation

// Balanced-block switchback assignment. Port of java-sdk internal/SwitchbackAssigner.java, itself a
// port of the platform's SwitchbackAssignment (murmur3_32, seed 0):
//   key       = utf8(clusterUnit + "\u{1F}" + cycleIndex)
//   baseHash  = murmur3_32(le64(seed) ++ le32(murmur3_32(key)))
//   stepHash  = murmur3_32(le32(baseHash) ++ le32(i)),  i = armCount-1 .. 1
//   j         = min(i, floor(u32(stepHash) / 0xffffffff * (i + 1)))
//   variant   = permutation[floorMod(periodIndex, armCount)], cycle = floorDiv(periodIndex, armCount)
// Any change here breaks parity with the platform golden vectors and the analysis-side schedule.
/// The switchback schedule draw the Collector and analysis use. A context serves switchbacks on its
/// own; these functions are public for conformance tooling.
public enum SwitchbackAssigner {
	/// The variant of `clusterUnit` (a raw cluster key, never hashed) in period `periodIndex`, with
	/// `seed = (seedHi << 32) | (seedLo & 0xffffffff)`; nil when `armCount` is less than 2.
	public static func variant(clusterUnit: String, periodIndex: Int64, seed: Int64, armCount: Int) -> Int? {
		return armCount >= 2 ? assign(clusterUnit, periodIndex: periodIndex, seed: seed, armCount: armCount) : nil
	}

	/// The permutation of `0..<armCount` served over cycle `cycleIndex`; nil when `armCount` is less than 2.
	public static func permutation(clusterUnit: String, cycleIndex: Int64, seed: Int64, armCount: Int) -> [Int]? {
		guard armCount >= 2 else { return nil }
		return fisherYatesPermutation(armCount, baseHash: baseHash(clusterUnit, cycleIndex: cycleIndex, seed: seed))
	}

	private static let normalizer: Double = 1.0 / 0xFFFF_FFFF
	private static let separator = "\u{1F}"

	// armCount must be at least 2.
	static func assign(_ clusterUnit: String, periodIndex: Int64, seed: Int64, armCount: Int) -> Int {
		precondition(armCount >= 2, "armCount must be >= 2, got \(armCount)")
		let arms = Int64(armCount)
		let cycleIndex = floorDiv(periodIndex, arms)
		// floorMod; the product may wrap near Int64.min but the difference is exact mod 2^64.
		let cycleSlot = Int(periodIndex &- cycleIndex &* arms)
		return fisherYatesPermutation(armCount, baseHash: baseHash(clusterUnit, cycleIndex: cycleIndex, seed: seed))[
			cycleSlot]
	}

	static func baseHash(_ clusterUnit: String, cycleIndex: Int64, seed: Int64) -> UInt32 {
		let keyHash = MurmurHash.murmurHash(Array((clusterUnit + separator + String(cycleIndex)).utf8), 0)

		var buffer = [UInt8](repeating: 0, count: 12)
		Buffers.putUInt64(&buffer, 0, UInt64(bitPattern: seed))
		Buffers.putUInt32(&buffer, 8, keyHash)
		return MurmurHash.murmurHash(buffer, 0)
	}

	static func fisherYatesPermutation(_ armCount: Int, baseHash: UInt32) -> [Int] {
		precondition(armCount >= 2, "armCount must be >= 2, got \(armCount)")
		var permutation = Array(0..<armCount)

		var buffer = [UInt8](repeating: 0, count: 8)
		Buffers.putUInt32(&buffer, 0, baseHash)
		var i = armCount - 1
		while i > 0 {
			Buffers.putUInt32(&buffer, 4, UInt32(i))
			let prob = Double(MurmurHash.murmurHash(buffer, 0)) * normalizer
			// prob == 1.0 would map to i + 1
			let j = min(i, Int((prob * Double(i + 1)).rounded(.down)))
			permutation.swapAt(i, j)
			i -= 1
		}
		return permutation
	}

	// The divisor is always positive here.
	static func floorDiv(_ dividend: Int64, _ divisor: Int64) -> Int64 {
		let q = dividend / divisor
		return (dividend % divisor != 0 && (dividend ^ divisor) < 0) ? q - 1 : q
	}
}
