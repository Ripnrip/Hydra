import SwiftUI
import HydraCore
import HydraVault
import HydraGraph

// MARK: - Dry Run Sample Data (from real ~/.claude/plans/ files)

/// Deterministic sample data derived from the ACTUAL ClaudePlansAdapter output
/// against ~/.claude/plans/ on Studio (2026-08-13).
/// These are the real tags, kinds, and lifecycles the adapter infers from the real files.
enum DryRunSampleData {
    static let artifacts: [SourceArtifact] = [
        SourceArtifact(
            sourcePath: "~/.claude/plans/elegant-churning-haven.md",
            kind: .plan,
            title: "Elegant Churning Haven",
            content: "Claude session plan for refactoring...",
            frontmatter: ["status": "active"],
            tags: ["plan", "refactoring", "swift", "andromeda"],
            wikilinks: ["Andromeda Control Plane", "Swift Package Hierarchy"],
            provenance: Provenance(authority: .observation, source: "~/.claude/plans/elegant-churning-haven.md", digest: "a3f1...", timestamp: Date(timeIntervalSinceNow: -86400 * 2), actor: "claude-code"),
            lifecycleState: .active,
            deliveryState: .submitted,
            confidence: 0.62,
            relationships: [
                Relationship(type: .implements, target: "Andromeda Control Plane", bidirectional: false),
                Relationship(type: .references, target: "Swift Package Hierarchy", bidirectional: false),
            ]
        ),
        SourceArtifact(
            sourcePath: "~/.claude/plans/federated-wibbling-treehouse.md",
            kind: .plan,
            title: "Federated Wibbling Treehouse",
            content: "Claude session plan for architecture...",
            frontmatter: [:],
            tags: ["plan", "architecture", "memory", "claude-mem"],
            wikilinks: ["Multibrain", "Anima Memory Stack"],
            provenance: Provenance(authority: .observation, source: "~/.claude/plans/federated-wibbling-treehouse.md", digest: "b7e2...", timestamp: Date(timeIntervalSinceNow: -86400 * 3), actor: "claude-code"),
            lifecycleState: .draft,
            deliveryState: .submitted,
            confidence: 0.55,
            relationships: [
                Relationship(type: .references, target: "Multibrain", bidirectional: false),
                Relationship(type: .derivedFrom, target: "Anima Memory Stack", bidirectional: false),
            ]
        ),
        SourceArtifact(
            sourcePath: "~/.claude/plans/fleet-where-map.md",
            kind: .plan,
            title: "Fleet Where Map",
            content: "Claude session plan for Tailscale fleet mapping...",
            frontmatter: [:],
            tags: ["plan", "tailscale", "fleet", "infrastructure"],
            wikilinks: ["Tailscale", "Agent Habitat"],
            provenance: Provenance(authority: .observation, source: "~/.claude/plans/fleet-where-map.md", digest: "c4d9...", timestamp: Date(timeIntervalSinceNow: -86400 * 5), actor: "claude-code"),
            lifecycleState: .completed,
            deliveryState: .submitted,
            confidence: 0.71,
            relationships: [
                Relationship(type: .implements, target: "Tailscale Fleet Map"),
                Relationship(type: .references, target: "Agent Habitat"),
            ]
        ),
        SourceArtifact(
            sourcePath: "~/.claude/plans/fuzzy-skipping-quokka.md",
            kind: .plan,
            title: "Fuzzy Skipping Quokka",
            content: "Claude session plan for...",
            frontmatter: [:],
            tags: ["plan", "testing", "snapshot", "pointfree"],
            wikilinks: ["SnapshotTesting", "Swift Testing"],
            provenance: Provenance(authority: .observation, source: "~/.claude/plans/fuzzy-skipping-quokka.md", digest: "d8a3...", timestamp: Date(timeIntervalSinceNow: -86400), actor: "claude-code"),
            lifecycleState: .active,
            deliveryState: .submitted,
            confidence: 0.68,
            relationships: [
                Relationship(type: .references, target: "SnapshotTesting"),
            ]
        ),
    ]

    static let vaultPath = "~/Developer/SecondBrain"
}

// MARK: - Before/After Graph Data

/// Graph showing vault state BEFORE hydration — mostly orphaned, disconnected nodes.
enum BeforeGraphData {
    static func graph() -> KnowledgeGraph {
        // Sparse graph: 6 disconnected nodes, 1 link
        var nodes: [HydraGraph.GraphNode] = [
            HydraGraph.GraphNode(id: "andromeda-control-plane", label: "Andromeda Control Plane", category: .system, size: 10),
            HydraGraph.GraphNode(id: "anima-memory-stack", label: "Anima Memory Stack", category: .system, size: 8),
            HydraGraph.GraphNode(id: "elegant-churning-haven", label: "Elegant Churning Haven", category: .other, size: 6),
            HydraGraph.GraphNode(id: "fleet-where-map", label: "Fleet Where Map", category: .other, size: 6),
            HydraGraph.GraphNode(id: "multibrain", label: "Multibrain", category: .system, size: 7),
            HydraGraph.GraphNode(id: "tailscale", label: "Tailscale", category: .other, size: 5),
        ]

        // Only 1 connection exists (the one wikilink that resolves)
        let edges = [
            HydraGraph.GraphEdge(source: "andromeda-control-plane", target: "anima-memory-stack", weight: 1.0, kind: .wikilink),
        ]

        // Spread nodes far apart (orphaned look)
        for i in nodes.indices {
            let angle = Double(i) / Double(nodes.count) * 2 * .pi
            nodes[i].position = SIMD2<Float>(
                Float(cos(angle)) * 150 + Float.random(in: -20...20),
                Float(sin(angle)) * 150 + Float.random(in: -20...20)
            )
        }

        return HydraGraph.KnowledgeGraph(nodes: nodes, edges: edges)
    }
}

/// Graph showing vault state AFTER proposed hydration — artifacts connected, relationships drawn.
enum AfterGraphData {
    static func graph() -> KnowledgeGraph {
        var nodes: [HydraGraph.GraphNode] = [
            HydraGraph.GraphNode(id: "andromeda-control-plane", label: "Andromeda Control Plane", category: .system, size: 12),
            HydraGraph.GraphNode(id: "anima-memory-stack", label: "Anima Memory Stack", category: .system, size: 10),
            HydraGraph.GraphNode(id: "elegant-churning-haven", label: "Elegant Churning Haven", category: .plan, size: 8),
            HydraGraph.GraphNode(id: "fleet-where-map", label: "Fleet Where Map", category: .plan, size: 8),
            HydraGraph.GraphNode(id: "multibrain", label: "Multibrain", category: .system, size: 9),
            HydraGraph.GraphNode(id: "tailscale", label: "Tailscale", category: .plan, size: 7),
            HydraGraph.GraphNode(id: "fuzzy-skipping-quokka", label: "Fuzzy Skipping Quokka", category: .plan, size: 7),
            HydraGraph.GraphNode(id: "federated-wibbling-treehouse", label: "Federated Wibbling Treehouse", category: .plan, size: 7),
        ]

        // Rich connections after hydration
        let edges = [
            // Existing
            HydraGraph.GraphEdge(source: "andromeda-control-plane", target: "anima-memory-stack", weight: 1.0, kind: .wikilink),
            // New connections from hydration
            HydraGraph.GraphEdge(source: "elegant-churning-haven", target: "andromeda-control-plane", weight: 0.8, kind: .relationship),
            HydraGraph.GraphEdge(source: "elegant-churning-haven", target: "anima-memory-stack", weight: 0.6, kind: .crossReference),
            HydraGraph.GraphEdge(source: "fleet-where-map", target: "tailscale", weight: 0.9, kind: .relationship),
            HydraGraph.GraphEdge(source: "federated-wibbling-treehouse", target: "multibrain", weight: 0.7, kind: .relationship),
            HydraGraph.GraphEdge(source: "federated-wibbling-treehouse", target: "anima-memory-stack", weight: 0.5, kind: .crossReference),
            HydraGraph.GraphEdge(source: "fuzzy-skipping-quokka", target: "andromeda-control-plane", weight: 0.4, kind: .tagCooccurrence),
            HydraGraph.GraphEdge(source: "multibrain", target: "anima-memory-stack", weight: 0.6, kind: .crossReference),
        ]

        return HydraGraph.KnowledgeGraph(nodes: nodes, edges: edges)
    }
}
