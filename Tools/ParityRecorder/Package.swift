// swift-tools-version:5.9
// Records the behaviour of swift-sdk 1.5.0 (pinned commit) on the parity probe. Run from this
// directory: `swift run ParityRecorder ../../Tests/ABsmartlyTests/Resources/parity`. ParityTests
// replays the recording against 2.0. See docs/plans/swift-2.0.md, "Parity with 1.5.0".
import PackageDescription

let package = Package(
	name: "ParityRecorder",
	platforms: [.macOS(.v12)],
	dependencies: [
		// release/1.5.0-prep at 2b44de4 (swift-sdk#14), the 1.5.0 release candidate. Re-pin to the v1.5.0 tag once it exists.
		.package(url: "https://github.com/absmartly/swift-sdk.git", revision: "2b44de40861a92385b1b77f14c8606d68469ce83"),
		.package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.8.4")),
	],
	targets: [
		.executableTarget(
			name: "ParityRecorder",
			dependencies: [.product(name: "ABSmartly", package: "swift-sdk"), "PromiseKit"])
	]
)
