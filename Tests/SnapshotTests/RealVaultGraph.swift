import Testing
import SwiftUI
import AppKit
import HydraCore
import HydraVault
@testable import HydraApp

@Suite("Real Vault Graph")
@MainActor
struct RealVaultGraphTest {
    @Test("Graph from real vault — big visible nodes")
    func realGraph() async throws {
        let scanner = VaultScanner(vaultRoot: "/Users/gurindersingh/Developer/SecondBrain")
        guard let inv = try? await scanner.scan(), inv.noteCount > 0 else {
            throw CocoaError(.fileReadUnknown)
        }

        // Top 18 most-connected notes — FEWER nodes, BIGGER nodes
        let connectedNotes = inv.notes.sorted { $0.wikilinks.count > $1.wikilinks.count }.prefix(18)

        var nodes: [GraphNode] = connectedNotes.enumerated().map { idx, note in
            GraphNode(
                id: note.id.uuidString,
                label: String((note.title.isEmpty ? note.relativePath : note.title).prefix(24)),
                position: SIMD2<Float>(
                    Float(140 + (idx % 4) * 220 + ((idx * 37) % 60 - 30)),
                    Float(120 + (idx / 4) * 160 + ((idx * 23) % 40 - 20))
                ),
                velocity: .zero,
                radius: Float(16 + min(note.wikilinks.count, 14)),  // BIG nodes
                color: GraphNodeKind.note.baseColor,
                kind: .note
            )
        }

        // 5 tag hubs — big purple
        for (i, tagItem) in inv.tagFrequency.prefix(5).enumerated() {
            nodes.append(GraphNode(
                id: "tag-\(tagItem.tag)",
                label: "#\(String(tagItem.tag.prefix(20)))",
                position: SIMD2<Float>(Float(250 + i * 160), Float(660)),
                velocity: .zero,
                radius: Float(22 + min(tagItem.count / 6, 10)),  // BIGGEST nodes
                color: SIMD4<Float>(0.68, 0.52, 0.98, 1.0),
                kind: .note
            ))
        }

        // Edges
        var edges: [GraphEdge] = []
        let titleToId = Dictionary(inv.notes.map { ($0.title, $0.id.uuidString) }, uniquingKeysWith: { first, _ in first })
        for note in connectedNotes {
            for link in note.wikilinks.prefix(4) {
                if let targetId = titleToId[link] {
                    edges.append(GraphEdge(id: "\(note.id.uuidString)-\(link)", source: note.id.uuidString, target: targetId, strength: 0.8, type: .references))
                }
            }
            for tag in note.tags.prefix(2) {
                edges.append(GraphEdge(id: "\(note.id.uuidString)-tag-\(tag)", source: note.id.uuidString, target: "tag-\(tag)", strength: 0.5, type: .relatesTo))
            }
        }

        // Use RelationshipGraphView which labels nodes
        let view = RelationshipGraphView(nodes: nodes, edges: Array(edges.prefix(70)))

        let controller = NSHostingController(rootView: view.preferredColorScheme(.dark))
        controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 760)
        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 600_000_000)

        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
            throw CocoaError(.fileReadUnknown)
        }
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-graph-big.png"))
            print("✓ REAL GRAPH BIG — \(nodes.count) nodes, \(edges.count) edges")
        }
    }
}
