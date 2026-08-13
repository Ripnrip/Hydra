// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hydra",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "HydraCore", targets: ["HydraCore"]),
        .library(name: "HydraVault", targets: ["HydraVault"]),
        .library(name: "HydraHealth", targets: ["HydraHealth"]),
        .library(name: "HydraMCP", targets: ["HydraMCP"]),
        .library(name: "HydraGraph", targets: ["HydraGraph"]),
        .executable(name: "hydra", targets: ["HydraCLI"]),
        .executable(name: "HydraApp", targets: ["HydraApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.15.0"),
    ],
    targets: [
        .target(name: "HydraCore", dependencies: [
            .product(name: "Logging", package: "swift-log"),
        ]),
        .target(name: "HydraVault", dependencies: ["HydraCore"]),
        .target(name: "HydraHealth", dependencies: ["HydraCore", "HydraVault"]),
        .target(name: "HydraMCP", dependencies: [
            "HydraCore", "HydraVault", "HydraHealth",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdCore", package: "hummingbird"),
        ]),
        .target(name: "HydraGraph", dependencies: ["HydraCore"]),
        .executableTarget(name: "HydraCLI", dependencies: [
            "HydraCore", "HydraVault", "HydraHealth", "HydraMCP",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .executableTarget(name: "HydraApp", dependencies: [
            "HydraCore", "HydraVault", "HydraHealth", "HydraGraph", "HydraGraph",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),
        .testTarget(name: "HydraCoreTests", dependencies: ["HydraCore"]),
        .testTarget(name: "HydraVaultTests", dependencies: ["HydraVault"]),
        .testTarget(name: "HydraHealthTests", dependencies: ["HydraHealth"]),
        .testTarget(name: "SnapshotTests", dependencies: [
            "HydraCore", "HydraVault", "HydraHealth",
            "HydraApp",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ]),
    ]
)
