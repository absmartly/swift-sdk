// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "ABsmartly",
	platforms: [
		.iOS(.v15),
		.macOS(.v12),
		.tvOS(.v15),
		.watchOS(.v8),
		.visionOS(.v1),
		.macCatalyst(.v15),
	],
	products: [
		.library(name: "ABsmartly", targets: ["ABsmartly"]),
		.library(name: "ABsmartlyUI", targets: ["ABsmartlyUI"]),
	],
	dependencies: [
		// Only used for MD5 on Linux; Apple platforms use CryptoKit. The lockfiles are resolved with
		// Swift 6.0 (the floor), because swift-crypto 4.4+ and swift-asn1 1.7+ need tools 6.1.
		.package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")
	],
	targets: [
		.target(
			name: "ABsmartly",
			dependencies: [
				.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
			]),
		.target(name: "ABsmartlyUI", dependencies: ["ABsmartly"]),
		.testTarget(
			name: "ABsmartlyTests",
			dependencies: ["ABsmartly"],
			resources: [.copy("Resources")]),
		.testTarget(name: "ABsmartlyUITests", dependencies: ["ABsmartly", "ABsmartlyUI"]),
	],
	swiftLanguageModes: [.v6]
)
