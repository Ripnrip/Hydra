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
