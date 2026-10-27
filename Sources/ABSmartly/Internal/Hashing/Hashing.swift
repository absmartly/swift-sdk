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

	static func unitString(_ value: Double) -> String {
		let rounded = value.rounded(.toNearestOrAwayFromZero)
		if let exact = Int64(exactly: rounded) {
			return String(exact)
		}
		return String(format: "%.0f", rounded)
	}

	static func hashBytes(_ unit: String) -> [UInt8] {
		return Array(MD5Base64Url(unit).utf8)
	}
}
