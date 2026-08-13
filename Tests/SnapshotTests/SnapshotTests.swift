import Testing
import SnapshotTesting
import SwiftUI
import AppKit
import HydraCore
import HydraVault
@testable import HydraApp

/// Wraps a SwiftUI view in NSHostingController for snapshot testing.
@MainActor
func snapView<V: View>(_ view: V, named: String, width: CGFloat = 800, height: CGFloat = 600) {
    let controller = NSHostingController(rootView: view)
    controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    controller.view.needsLayout = true
    controller.view.layoutSubtreeIfNeeded()
    assertSnapshot(of: controller, as: .image(size: .init(width: width, height: height)), named: named, timeout: 30)
}

// MARK: - Component Snapshots

@Suite("Tag Chip")
@MainActor
struct TagChipSnapshots {
    @Test("All color axes")
    func tagChipAllAxes() {
        for axis in ColorAxis.allCases {
            let tag = ColorTag(axis: axis, value: "test", color: defaultColor(for: axis))
            snapView(TagChip(colorTag: tag), named: "\(axis.rawValue)", width: 200, height: 40)
        }
    }
    @Test("Selected state")
    func tagChipSelected() {
        let tag = ColorTag(axis: .project, value: "ai-config", color: .projectWarm)
        snapView(TagChip(colorTag: tag, isSelected: true), named: "selected", width: 200, height: 40)
    }
}

@Suite("Confidence Meter")
@MainActor
struct ConfidenceMeterSnapshots {
    @Test("All levels", arguments: [0.0, 0.25, 0.5, 0.75, 0.92, 1.0])
    func confidenceMeter(value: Double) {
        snapView(ConfidenceMeter(value: value), named: "confidence_\(Int(value * 100))", width: 200, height: 30)
    }
}

@Suite("Provenance Badge")
@MainActor
struct ProvenanceBadgeSnapshots {
    @Test("All authority levels")
    func provenanceBadges() {
        for authority in [Authority.gitReceipt, .controlPlaneLedger, .changelog, .observation, .wikiNote] {
            snapView(ProvenanceBadge(authority: authority), named: authority.rawValue, width: 200, height: 30)
        }
    }
}

@Suite("Lifecycle Badge")
@MainActor
struct LifecycleBadgeSnapshots {
    @Test("All states")
    func lifecycleBadges() {
        for state in LifecycleState.allCases {
            snapView(LifecycleBadge(state: state), named: state.rawValue, width: 200, height: 30)
        }
    }
}

@Suite("Delivery State Pill")
@MainActor
struct DeliveryStatePillSnapshots {
    @Test("All delivery states")
    func deliveryPills() {
        for state in DeliveryState.allCases {
            snapView(DeliveryStatePill(state: state), named: state.rawValue, width: 250, height: 30)
        }
    }
}

// MARK: - Panel Snapshots

@Suite("Hydration Panel")
@MainActor
struct HydrationPanelSnapshots {
    @Test("Default light")
    func hydrationDefault() {
        snapView(HydrationView(), named: "default_light", width: 900, height: 600)
    }
    @Test("Default dark")
    func hydrationDark() {
        snapView(HydrationView().preferredColorScheme(.dark), named: "default_dark", width: 900, height: 600)
    }
}

@Suite("Vault Explorer")
@MainActor
struct VaultExplorerSnapshots {
    @Test("Empty state")
    func vaultEmpty() {
        snapView(VaultExplorerView(), named: "vault_empty", width: 900, height: 600)
    }
}

@Suite("Oracle Panel")
@MainActor
struct OraclePanelSnapshots {
    @Test("Empty state")
    func oracleEmpty() {
        snapView(OracleView(), named: "oracle_empty", width: 900, height: 600)
    }
}

@Suite("Health Panel")
@MainActor
struct HealthPanelSnapshots {
    @Test("Empty state")
    func healthEmpty() {
        snapView(HealthView(), named: "health_empty", width: 900, height: 600)
    }
}

// MARK: - Full App

@Suite("Full App Window")
@MainActor
struct FullAppSnapshots {
    @Test("Light mode")
    func fullAppLight() {
        snapView(ContentView(), named: "light", width: 1000, height: 650)
    }
    @Test("Dark mode")
    func fullAppDark() {
        snapView(ContentView().preferredColorScheme(.dark), named: "dark", width: 1000, height: 650)
    }
}

// MARK: - Helpers

func defaultColor(for axis: ColorAxis) -> VaultColor {
    switch axis {
    case .project: .projectWarm
    case .type: .typeCool
    case .status: .statusGreen
    case .integration: .integrationPurple
    case .severity: .severityInfo
    }
}
