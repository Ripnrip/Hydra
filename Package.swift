// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BrainOracle",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BrainCore", targets: ["BrainCore"]),
        .library(name: "BrainVault", targets: ["BrainVault"]),
        .library(name: "BrainHealth", targets: ["BrainHealth"]),
        .library(name: "BrainMCP", targets: ["BrainMCP"]),
        .executable(name: "brain-oracle", targets: ["BrainCLI"]),
        .executable(name: "BrainOracleApp", targets: ["BrainApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.15.0"),
    ],
    targets: [
        // Core domain models + pipeline contracts — pure Swift, no UI/server deps
        .target(name: "BrainCore", dependencies: [
            .product(name: "Logging", package: "swift-log"),
        ]),

        // Vault integration — scanner, writer, frontmatter renderer, PARA mapping
        .target(name: "BrainVault", dependencies: ["BrainCore"]),

        // Health + maintenance — file watchers, staleness, tag consistency, cron jobs
        .target(name: "BrainHealth", dependencies: [
            "BrainCore",
            "BrainVault",
        ]),

        // MCP server — Hummingbird, Claude stdio
        .target(name: "BrainMCP", dependencies: [
            "BrainCore",
            "BrainVault",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdCore", package: "hummingbird"),
        ]),

        // CLI executable
        .executableTarget(name: "BrainCLI", dependencies: [
            "BrainCore",
            "BrainVault",
            "BrainHealth",
            "BrainMCP",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),

        // SwiftUI app
        .executableTarget(name: "BrainApp", dependencies: [
            "BrainCore",
            "BrainVault",
            "BrainHealth",
            "BrainMCP",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        ]),

        // Tests
        .testTarget(name: "BrainCoreTests", dependencies: ["BrainCore"]),
        .testTarget(name: "BrainVaultTests", dependencies: ["BrainVault"]),
        .testTarget(name: "BrainHealthTests", dependencies: ["BrainHealth"]),
        .testTarget(name: "SnapshotTests", dependencies: [
            "BrainCore",
            "BrainVault",
            "BrainHealth",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ]),
    ]
)
