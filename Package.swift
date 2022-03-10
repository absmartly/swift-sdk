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
    dependencies: [],
    targets: [
        .target(
            name: "ABSmartly",
            dependencies: [],
            path: "Sources/ABSmartly"),
        .testTarget(
            name: "ABSmartlyTests",
            dependencies: ["ABSmartly"],
            path: "Tests/ABSmartlyTests",
            resources: [.copy("Resources")]),
    ],
    swiftLanguageVersions: [.v5]
)

