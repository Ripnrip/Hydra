import Testing
import SnapshotTesting
import SwiftUI
import AppKit
import HydraCore
import HydraVault
import HydraHealth
@testable import HydraApp

/// Snapshots rendered from the REAL vault on this machine — not mocks.
@Suite("Real Vault Snapshots")
@MainActor
struct RealVaultSnapshots {

    static func realInventory() async -> VaultInventory {
        let vaultPath = "/Users/gurindersingh/Developer/SecondBrain"
        let scanner = VaultScanner(vaultRoot: vaultPath)
        if let inv = try? await scanner.scan() {
            return inv
        }
        return VaultInventory(vaultRoot: vaultPath, notes: [], scannedAt: Date())
    }

    @Test("Oracle — real vault, dark")
    func realOracleDark() async throws {
        let inv = await Self.realInventory()
        try requireNotes(inv)

        let png = await Self.render(OracleViewWithData(inventory: inv), scheme: .dark, width: 1000, height: 760)
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-oracle-dark.png"))
        print("✓ REAL ORACLE DARK — \(inv.noteCount) notes, \(inv.tagFrequency.count) tags, \(inv.orphanedNotes.count) orphans")
    }

    @Test("Oracle — real vault, light")
    func realOracleLight() async throws {
        let inv = await Self.realInventory()
        try requireNotes(inv)

        let png = await Self.render(OracleViewWithData(inventory: inv), scheme: .light, width: 1000, height: 760)
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-oracle-light.png"))
        print("✓ REAL ORACLE LIGHT")
    }

    @Test("Health — real vault, dark")
    func realHealthDark() async throws {
        let inv = await Self.realInventory()
        try requireNotes(inv)
        let report = HealthChecker().checkAll(inv)

        let png = await Self.render(HealthViewWithData(report: report), scheme: .dark, width: 1000, height: 760)
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-health-dark.png"))
        print("✓ REAL HEALTH DARK — \(report.checks.count) checks, \(report.summary)")
    }

    @Test("Hydration — smart detection, dark")
    func realHydrationDark() async throws {
        let png = await Self.render(HydrationView(), scheme: .dark, width: 1000, height: 760)
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-hydration-dark.png"))
        print("✓ REAL HYDRATION DARK")
    }

    @Test("Full app — real vault, dark")
    func realFullAppDark() async throws {
        let png = await Self.render(ContentView(), scheme: .dark, width: 1200, height: 760)
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-fullapp-dark.png"))
        print("✓ REAL FULLAPP DARK")
    }

    // MARK: - Helpers

    private func requireNotes(_ inv: VaultInventory) throws {
        guard inv.noteCount > 0 else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Vault scan returned 0 notes"])
        }
    }

    @MainActor
    static func render<V: View>(_ view: V, scheme: ColorScheme, width: CGFloat, height: CGFloat) async -> Data {
        let controller = await NSHostingController(rootView: view.preferredColorScheme(scheme))
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        controller.view.appearance = scheme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()

        // Let SwiftUI settle
        try? await Task.sleep(nanoseconds: 300_000_000)

        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
            return Data()
        }
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }
}

// MARK: - Real Graph (Berserker) — renders VaultGraphView from the real vault

@Suite("Real Graph Render")
@MainActor
struct RealGraphRenderSnapshots {
    @Test("VaultGraphView — real vault relationships")
    func realGraphBerserker() async throws {
        let vaultPath = NSHomeDirectory() + "/Developer/SecondBrain"
        guard FileManager.default.fileExists(atPath: vaultPath + "/.obsidian") else {
            Issue.record("SecondBrain vault not present")
            return
        }
        let scanner = VaultScanner(vaultRoot: vaultPath)
        let inventory = try await scanner.scan()

        let controller = NSHostingController(rootView: VaultGraphView(inventory: inventory).frame(width: 1000, height: 600))
        controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        controller.view.layoutSubtreeIfNeeded()

        guard let image = controller.view.bitmapImage() else {
            Issue.record("Failed to render image")
            return
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to convert to PNG")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-graph.png"))
        print("✓ REAL GRAPH — \(inventory.noteCount) notes rendered")
    }
}

extension NSView {
    func bitmapImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage()
        image.addRepresentation(rep)
        return image
    }
}
