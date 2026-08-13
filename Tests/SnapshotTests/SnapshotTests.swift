import Testing
import SwiftUI
import AppKit
import SnapshotTesting
@testable import HydraApp

// MARK: - Snapshot Tests

@MainActor
struct SnapshotTests {

    @Test
    func hydrationViewDefault() {
        let view = HydrationView().frame(width: 900, height: 600)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        assertSnapshot(of: hosting, as: .image)
    }

    @Test
    func vaultExplorerView() {
        let view = VaultExplorerView().frame(width: 900, height: 600)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        assertSnapshot(of: hosting, as: .image)
    }

    @Test
    func oracleView() {
        let view = OracleView().frame(width: 900, height: 600)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        assertSnapshot(of: hosting, as: .image)
    }

    @Test
    func healthView() {
        let view = HealthView().frame(width: 900, height: 600)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        assertSnapshot(of: hosting, as: .image)
    }

    @Test
    func sourceKindPicker() {
        let view = SourceKindPicker().frame(width: 400, height: 100)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        assertSnapshot(of: hosting, as: .image)
    }

    @Test
    func exportDestinationsRow() {
        let view = ExportDestinationsRow().frame(width: 400, height: 150)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 150)
        assertSnapshot(of: hosting, as: .image)
    }

    @Test
    func outboxConfigRow() {
        let view = OutboxConfigRow().frame(width: 400, height: 100)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        assertSnapshot(of: hosting, as: .image)
    }

    @Test
    func contentView() {
        let view = ContentView().frame(width: 900, height: 600)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        assertSnapshot(of: hosting, as: .image)
    }
}
