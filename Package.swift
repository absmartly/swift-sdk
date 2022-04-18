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
    dependencies: [.package(
        url: "https://github.com/apple/swift-atomics.git",
        .upToNextMajor(from: "1.0.2")
      ),
                   .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.8.4")),],
    targets: [
        .target(
            name: "ABSmartly",
            dependencies: [.product(name: "Atomics", package: "swift-atomics"), "PromiseKit"],
            path: "Sources/ABSmartly"),
        .testTarget(
            name: "ABSmartlyTests",
            dependencies: ["ABSmartly"],
            path: "Tests/ABSmartlyTests",
            resources: [.copy("Resources")]),
    ],
    swiftLanguageVersions: [.v5]
)

