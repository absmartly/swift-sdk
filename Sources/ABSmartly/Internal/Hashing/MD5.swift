#if !canImport(CommonCrypto)
// MD5 (RFC 1321) for platforms without CommonCrypto (Linux), so the SDK needs no extra package
// dependency there. Apple platforms keep using CommonCrypto. Only used to bucket unit IDs.
enum MD5 {
	private static let shifts: [UInt32] = [
		7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
		5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
		4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
		6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
	]

	// floor(abs(sin(i + 1)) * 2^32)
	private static let k: [UInt32] = [
		0xd76a_a478, 0xe8c7_b756, 0x2420_70db, 0xc1bd_ceee, 0xf57c_0faf, 0x4787_c62a, 0xa830_4613, 0xfd46_9501,
		0x6980_98d8, 0x8b44_f7af, 0xffff_5bb1, 0x895c_d7be, 0x6b90_1122, 0xfd98_7193, 0xa679_438e, 0x49b4_0821,
		0xf61e_2562, 0xc040_b340, 0x265e_5a51, 0xe9b6_c7aa, 0xd62f_105d, 0x0244_1453, 0xd8a1_e681, 0xe7d3_fbc8,
		0x21e1_cde6, 0xc337_07d6, 0xf4d5_0d87, 0x455a_14ed, 0xa9e3_e905, 0xfcef_a3f8, 0x676f_02d9, 0x8d2a_4c8a,
		0xfffa_3942, 0x8771_f681, 0x6d9d_6122, 0xfde5_380c, 0xa4be_ea44, 0x4bde_cfa9, 0xf6bb_4b60, 0xbebf_bc70,
		0x289b_7ec6, 0xeaa1_27fa, 0xd4ef_3085, 0x0488_1d05, 0xd9d4_d039, 0xe6db_99e5, 0x1fa2_7cf8, 0xc4ac_5665,
		0xf429_2244, 0x432a_ff97, 0xab94_23a7, 0xfc93_a039, 0x655b_59c3, 0x8f0c_cc92, 0xffef_f47d, 0x8584_5dd1,
		0x6fa8_7e4f, 0xfe2c_e6e0, 0xa301_4314, 0x4e08_11a1, 0xf753_7e82, 0xbd3a_f235, 0x2ad7_d2bb, 0xeb86_d391,
	]

	static func digest(_ input: [UInt8]) -> [UInt8] {
		var message = input
		let bitLength = UInt64(input.count) &* 8
		message.append(0x80)
		while message.count % 64 != 56 {
			message.append(0)
		}
		for i in 0..<8 {
			message.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i))))
		}

		var a0: UInt32 = 0x6745_2301
		var b0: UInt32 = 0xefcd_ab89
		var c0: UInt32 = 0x98ba_dcfe
		var d0: UInt32 = 0x1032_5476

		var m = [UInt32](repeating: 0, count: 16)
		for chunk in stride(from: 0, to: message.count, by: 64) {
			for i in 0..<16 {
				let j = chunk + i * 4
				m[i] =
					UInt32(message[j]) | (UInt32(message[j + 1]) << 8) | (UInt32(message[j + 2]) << 16)
					| (UInt32(message[j + 3]) << 24)
			}

			var a = a0
			var b = b0
			var c = c0
			var d = d0
			for i in 0..<64 {
				var f: UInt32
				let g: Int
				switch i {
				case 0..<16:
					f = (b & c) | (~b & d)
					g = i
				case 16..<32:
					f = (d & b) | (~d & c)
					g = (5 * i + 1) % 16
				case 32..<48:
					f = b ^ c ^ d
					g = (3 * i + 5) % 16
				default:
					f = c ^ (b | ~d)
					g = (7 * i) % 16
				}
				f = f &+ a &+ k[i] &+ m[g]
				a = d
				d = c
				c = b
				b = b &+ ((f << shifts[i]) | (f >> (32 - shifts[i])))
			}

			a0 = a0 &+ a
			b0 = b0 &+ b
			c0 = c0 &+ c
			d0 = d0 &+ d
		}

		var result: [UInt8] = []
		result.reserveCapacity(16)
		for word in [a0, b0, c0, d0] {
			for i in 0..<4 {
				result.append(UInt8(truncatingIfNeeded: word >> (8 * UInt32(i))))
			}
		}
		return result
	}
}
#endif
