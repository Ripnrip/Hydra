import Testing
import SwiftUI
import AppKit
import HydraCore
import HydraVault
@testable import HydraApp

/// The money shot: real vault + real RAG query + graph highlighting the retrieval path.
@Suite("Real RAG Highlight Screenshots")
@MainActor
struct RealHighlightScreenshots {

    @Test("Retrieval path lit up on graph")
    func realHighlight() async throws {
        // Scan real vault
        let scanner = VaultScanner(vaultRoot: "/Users/gurindersingh/Developer/SecondBrain")
        guard let inv = try? await scanner.scan(), inv.noteCount > 0 else {
            throw CocoaError(.fileReadUnknown)
        }

        // Build links + index
        let titleToID = Dictionary(inv.notes.map { ($0.title, $0.id.uuidString) }, uniquingKeysWith: { a, _ in a })
        var links: [HydraCore.NoteLink] = []
        for note in inv.notes {
            for link in note.wikilinks {
                if let target = titleToID[link] {
                    links.append(HydraCore.NoteLink(source: note.id.uuidString, target: target))
                }
            }
        }
        let index = LocalSemanticIndex()
        await index.build(from: inv.notes.map { (id: $0.id.uuidString, title: $0.title, tags: $0.tags, content: $0.relativePath) })

        // Run the real query
        let noteTitles = Dictionary(inv.notes.map { ($0.id.uuidString, $0.title) }, uniquingKeysWith: { a, _ in a })
        let titleFor: @Sendable (String) -> String = { noteTitles[$0] ?? $0 }
        let query = HybridRAGQuery()
        let result = await query.run(query: "tailscale network setup agents", index: index, links: links, titleFor: titleFor)

        print("Query: \(result.semanticHits.count) semantic + \(result.graphHits.count) graph hits")

        // Render the graph WITH highlights
        let seeds = Set(result.semanticHits.map(\.id))
        let graphHits = Set(result.allNoteIDs).subtracting(seeds)

        let graphView = VaultGraphView(
            inventory: inv,
            highlightedSemanticIDs: seeds,
            highlightedGraphIDs: graphHits
        )
        .frame(width: 1000, height: 620)

        let png = await Self.render(graphView, width: 1000, height: 620)
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-highlight.png"))
        print("✓ HIGHLIGHT GRAPH saved — seeds: \(seeds.count), graph: \(graphHits.count)")

        // Second: knowledge graph query
        let result2 = await query.run(query: "knowledge graph analysis understand anything", index: index, links: links, titleFor: titleFor)
        let seeds2 = Set(result2.semanticHits.map(\.id))
        let graph2 = Set(result2.allNoteIDs).subtracting(seeds2)

        let graphView2 = VaultGraphView(
            inventory: inv,
            highlightedSemanticIDs: seeds2,
            highlightedGraphIDs: graph2
        )
        .frame(width: 1000, height: 620)

        let png2 = await Self.render(graphView2, width: 1000, height: 620)
        try png2.write(to: URL(fileURLWithPath: "/tmp/hydra-real-highlight-2.png"))
        print("✓ HIGHLIGHT GRAPH 2 saved — seeds: \(seeds2.count), graph: \(graph2.count)")
    }

    @MainActor
    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) async -> Data {
        let controller = NSHostingController(rootView: view.preferredColorScheme(.dark))
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else { return Data() }
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }
}
