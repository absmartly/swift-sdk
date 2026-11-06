// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "ABSmartly",
    platforms: [
        .iOS(.v10),
        .tvOS(.v10),
        .macOS(.v10_14),
        .watchOS(.v3)
    ],
    products: [
        .library(
            name: "ABSmartly",
            targets: ["ABSmartly"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.0.2")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.8.4")),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", .upToNextMajor(from: "5.0.0")),
        // Only used for MD5 on Linux (Apple platforms use CommonCrypto). The wide range lets
        // older toolchains resolve an older swift-crypto, whose tools-version they can read.
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0"..<"4.0.0")
    ],
    targets: [
        .target(
            name: "ABSmartly",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                "PromiseKit",
                "SwiftyJSON",
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/ABSmartly"),
        .testTarget(
            name: "ABSmartlyTests",
            dependencies: ["ABSmartly"],
            path: "Tests/ABSmartlyTests",
            resources: [.copy("Resources")]),
    ],
    swiftLanguageVersions: [.v5]
)

