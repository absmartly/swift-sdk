// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "ABSmartly",
    platforms: [
        .iOS(.v12),
        .tvOS(.v12),
        .macOS(.v10_14),
        .watchOS(.v4)
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
        // Only used for MD5 on Linux (Apple platforms use CommonCrypto).
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.0.0"))
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
    swiftLanguageModes: [.v5]
)

