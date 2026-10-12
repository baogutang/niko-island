// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "niko-island",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "niko-island", targets: ["niko-island"]),
        .executable(name: "niko-bridge", targets: ["niko-bridge"]),
        .library(name: "NikoCore", targets: ["NikoCore"]),
    ],
    targets: [
        // Everything that is not UI: protocols, ingress, bridge logic, installer, usage engine.
        .target(
            name: "NikoCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // AppKit/SwiftUI layer. Kept as a library so the app model is unit-testable.
        .target(
            name: "NikoIslandApp",
            dependencies: ["NikoCore"]
        ),
        .executableTarget(
            name: "niko-island",
            dependencies: ["NikoIslandApp", "NikoCore"]
        ),
        .executableTarget(
            name: "niko-bridge",
            dependencies: ["NikoCore"]
        ),
        .testTarget(
            name: "NikoCoreTests",
            dependencies: ["NikoCore", "niko-bridge"]
        ),
        .testTarget(
            name: "NikoAppTests",
            dependencies: ["NikoIslandApp", "NikoCore", "niko-bridge"]
        ),
    ]
)
