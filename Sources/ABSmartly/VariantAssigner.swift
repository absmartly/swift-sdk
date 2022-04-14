import Foundation

class VariantAssigner {
	let normalizer: Double = 1.0 / 0xFFFF_FFFF
	var unitHash: UInt32

	init(_ unitHash: [UInt8]) {
		self.unitHash = MurmurHash.murmurHash(unitHash, 0)
	}

	func assign(_ split: [Double], _ seedHi: Int, _ seedLo: Int) -> Int {
		let prob: Double = probability(seedHi, seedLo)
		return VariantAssigner.chooseVariant(split, prob)
	}

	private func probability(_ seedHi: Int, _ seedLo: Int) -> Double {
		var buffer = [UInt8].init(repeating: 0, count: 12)

		Buffers.putUInt32(&buffer, 0, seedLo)
		Buffers.putUInt32(&buffer, 4, seedHi)
		Buffers.putUInt32(&buffer, 8, unitHash)

		let hash = MurmurHash.murmurHash(buffer, 0)
		return Double(hash & 0xFFFF_FFFF) * normalizer
	}

	static func chooseVariant(_ split: [Double], _ prob: Double) -> Int {
		var cumSum: Double = 0

		for (i, _) in split.enumerated() {
			cumSum += split[i]

			if prob < cumSum {
				return i
			}
		}

		return split.count - 1
	}
}
