import Foundation
import Testing
@testable import HydraCore

@Test func vaultLocationRoundTripsThroughJSON() throws {
    let original = VaultLocation.tailscale(host: "studio.local", path: "/Users/admin/wiki")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(VaultLocation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.kind == .tailscale(host: "studio.local"))
}

@Test func vaultLocationKindCasesAreCodable() throws {
    let cases: [VaultLocationKind] = [
        .local,
        .iCloud,
        .tailscale(host: "100.89.167.39"),
        .ssh(host: "mini.local"),
    ]
    for kind in cases {
        let data = try JSONEncoder().encode(kind)
        #expect(try JSONDecoder().decode(VaultLocationKind.self, from: data) == kind)
    }
}

@Test func sourceLocationRoundTripsThroughJSON() throws {
    let original = HydraCore.SourceLocation(
        kind: SourceKind.claudePlans,
        vaultLocation: VaultLocation.local("~/Documents/MyVault", name: "MyVault"),
        subpath: ".claude/plans"
    )
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(HydraCore.SourceLocation.self, from: encoded)
    #expect(decoded == original)
    #expect(decoded.kind == SourceKind.claudePlans)
}

@Test func artifactAndDeliveryEnumsRoundTrip() throws {
    let kind = ArtifactKind.other("spike")
    #expect(try JSONDecoder().decode(ArtifactKind.self, from: JSONEncoder().encode(kind)) == kind)

    let life = LifecycleState.accepted
    #expect(try JSONDecoder().decode(LifecycleState.self, from: JSONEncoder().encode(life)) == life)

    let delivery = DeliveryState.canonicalCommitted
    #expect(try JSONDecoder().decode(DeliveryState.self, from: JSONEncoder().encode(delivery)) == delivery)
    #expect(delivery.rawValue == "canonical-committed")
}
