import Testing
import Foundation
@testable import HydraHealth
@testable import HydraVault

@Test func healthCheckerProducesReport() {
    let inventory = VaultInventory(vaultRoot: "/test", notes: [], scannedAt: Date())
    let checker = HealthChecker()
    let report = checker.checkAll(inventory)
    #expect(report.checks.count == 7)
}

@Test func emptyVaultIsStale() {
    let inventory = VaultInventory(vaultRoot: "/test", notes: [], scannedAt: Date())
    let checker = HealthChecker()
    let report = checker.checkAll(inventory)
    #expect(report.overallStatus == .critical)  // empty vault = stale + missing digests
}
