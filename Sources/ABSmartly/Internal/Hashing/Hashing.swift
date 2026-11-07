import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#else
import Crypto
#endif

// NOTE: MD5 is used here for non-cryptographic purposes only.
// It provides a fast, deterministic hash for unit ID bucketing in A/B test assignment.
// Security properties (collision resistance, pre-image resistance) are not required
// for this use case. The hash is used to consistently assign users to experiment variants.
public class Hashing {

	private static func MD5Base64Url(_ string: String) -> String {
		let data = Data(string.utf8)

		#if canImport(CommonCrypto)
		// Apple platforms
		let md5 = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
			var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
			CC_MD5(bytes.baseAddress, CC_LONG(data.count), &hash)
			return hash
		}
		#else
		// Linux with Swift Crypto
		let digest = Insecure.MD5.hash(data: data)
		let md5 = Array(digest)
		#endif

		let base64Str = Data(md5).base64EncodedString()

		return base64ToBase64url(base64Str)
	}

	private static func base64ToBase64url(_ base64: String) -> String {
		let base64url =
			base64
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
		return base64url
	}

	public static func hash(_ unit: String) -> String {
		return MD5Base64Url(unit)
	}

	/// Hashes a numeric unit UID the way the JavaScript SDK does: the number rounded to an
	/// integer (`toFixed(0)`), so 125.75 hashes as "126".
	public static func hash(_ unit: Double) -> String {
		return MD5Base64Url(unitString(unit))
	}

	public static func base64UrlNoPadding(_ data: Data) -> String {
		return base64ToBase64url(data.base64EncodedString())
	}

	public static func utf8Bytes(_ value: String) -> [UInt8] {
		return Buffers.encodeUTF8(value)
	}

	/// JavaScript's `Number.prototype.toFixed(0)`: the sign is kept for any negative input
	/// (`-0.1` gives "-0"), halves round away from zero, and magnitudes of 1e21 or more use
	/// the exponent form of `String(number)` ("1e+21").
	static func unitString(_ value: Double) -> String {
		if value.isNaN { return "NaN" }
		let negative = value < 0
		let magnitude = Swift.abs(value)
		let body: String
		if magnitude >= 1e21 {
			body = magnitude.isInfinite ? "Infinity" : jsExponent(magnitude)
		} else {
			body = String(format: "%.0f", magnitude.rounded(.toNearestOrAwayFromZero))
		}
		return negative ? "-" + body : body
	}

	private static func jsExponent(_ magnitude: Double) -> String {
		// Swift prints large doubles as "1e+21" / "1.5e+22", the same shortest form as JS.
		return "\(magnitude)"
	}

	static func hashBytes(_ unit: String) -> [UInt8] {
		return Array(MD5Base64Url(unit).utf8)
	}
}
