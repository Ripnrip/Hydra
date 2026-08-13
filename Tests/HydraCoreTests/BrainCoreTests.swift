import Testing
import Foundation
@testable import HydraCore

@Test func sourceArtifactDefaults() {
    let artifact = SourceArtifact(sourcePath: "/test/path")
    #expect(artifact.kind == .other(""))
    #expect(artifact.lifecycleState == .draft)
    #expect(artifact.deliveryState == .submitted)
    #expect(artifact.confidence == 0.0)
}

@Test func authorityOrdering() {
    #expect(Authority.gitReceipt < Authority.wikiNote)
    #expect(Authority.controlPlaneLedger < Authority.observation)
    #expect(Authority.changelog < Authority.wikiNote)
}

@Test func deliveryStateTracking() {
    #expect(DeliveryState.submitted.isMechanicallyTracked)
    #expect(!DeliveryState.validated.isMechanicallyTracked)
    #expect(!DeliveryState.certified.isMechanicallyTracked)  // aspirational, not in outbox code
    #expect(DeliveryState.blocked.isMechanicallyTracked)
}

@Test func conflictResolutionPicksHigherAuthority() {
    let conflict = Conflict(
        field: "status",
        witnessA: ConflictWitness(authority: .gitReceipt, value: "completed"),
        witnessB: ConflictWitness(authority: .wikiNote, value: "draft")
    )
    #expect(conflict.resolvedValue == "completed")
}
