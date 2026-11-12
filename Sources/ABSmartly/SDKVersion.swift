import Foundation

// Sent as the X-Agent header ("absmartly-swift-sdk/<version>"). Keep `version` equal to the podspec's
// `spec.version`: the release workflow refuses to publish a tag where they differ.
enum SDKVersion {
	static let name = "absmartly-swift-sdk"
	static let version = "1.5.0"
	static let agent = "\(name)/\(version)"
}
