// swift-tools-version:5.9
// Records the behaviour of swift-sdk 1.5.0 (pinned commit) on the parity probe. Run from this
// directory: `swift run ParityRecorder ../../Tests/ABsmartlyTests/Resources/parity`. ParityTests
// replays the recording against 2.0. See docs/plans/swift-2.0.md, "Parity with 1.5.0".
import PackageDescription

let package = Package(
	name: "ParityRecorder",
	platforms: [.macOS(.v12)],
	dependencies: [
		// main at b67a2a9, the 1.5.0 release candidate. Re-pin to the v1.5.0 tag once it exists.
		.package(url: "https://github.com/absmartly/swift-sdk.git", revision: "b67a2a9fd9ebbdda46fe1fede873a03102b449f0"),
		.package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.8.4")),
	],
	targets: [
		.executableTarget(
			name: "ParityRecorder",
			dependencies: [.product(name: "ABSmartly", package: "swift-sdk"), "PromiseKit"])
	]
)
