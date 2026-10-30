// swift-tools-version: 6.0
import PackageDescription

// Platform-independent core: body atlas mapping, pathway matching, red-flag rules,
// procedural stock-body geometry and ray hit-testing. No UIKit/RealityKit here, so it
// builds and tests with plain `swift test` on macOS (and Linux).
let package = Package(
    name: "SkeletonCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SkeletonCore", targets: ["SkeletonCore"]),
    ],
    targets: [
        .target(name: "SkeletonCore"),
        .testTarget(name: "SkeletonCoreTests", dependencies: ["SkeletonCore"]),
    ]
)
