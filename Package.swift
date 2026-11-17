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
            // ABSmartlyAsync adds async/await overloads; apps opt in with `import ABSmartlyAsync`.
            targets: ["ABSmartly", "ABSmartlyAsync"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.0.2")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.8.4")),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", .upToNextMajor(from: "5.0.0"))
    ],
    targets: [
        .target(
            name: "ABSmartly",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                "PromiseKit",
                // Apple platforms only: SwiftyJSON does not compile on Linux, where the SDK uses
                // a vendored copy (see JSON.swift). Toolchains 5.9+ read Package@swift-5.9.swift,
                // which also lists Mac Catalyst and visionOS.
                .product(name: "SwiftyJSON", package: "SwiftyJSON", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS]))
            ],
            path: "Sources/ABSmartly"),
        .target(
            name: "ABSmartlyAsync",
            dependencies: ["ABSmartly", "PromiseKit"],
            path: "Sources/ABSmartlyAsync"),
        .testTarget(
            name: "ABSmartlyTests",
            dependencies: [
                "ABSmartly",
                "ABSmartlyAsync",
                // For SwiftyJSONCompatibilityTest.
                .product(name: "SwiftyJSON", package: "SwiftyJSON", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS]))
            ],
            path: "Tests/ABSmartlyTests",
            resources: [.copy("Resources")]),
    ],
    swiftLanguageVersions: [.v5]
)

