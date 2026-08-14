import Testing
import SwiftUI
import AppKit
import HydraCore
import HydraVault
@testable import HydraApp

/// Screenshots of the RAG in action — real vault, real queries, real answers.
@Suite("Real RAG Screenshots")
@MainActor
struct RealRAGScreenshots {

    static func scan() async -> (VaultInventory, [HydraCore.NoteLink], LocalSemanticIndex) {
        let scanner = VaultScanner(vaultRoot: "/Users/gurindersingh/Developer/SecondBrain")
        guard let inv = try? await scanner.scan() else {
            return (VaultInventory(vaultRoot: "", notes: [], scannedAt: Date()), [], LocalSemanticIndex())
        }

        // Build links from wikilinks
        let titleToID = Dictionary(inv.notes.map { ($0.title, $0.id.uuidString) }, uniquingKeysWith: { a, _ in a })
        var links: [HydraCore.NoteLink] = []
        for note in inv.notes {
            for link in note.wikilinks {
                if let target = titleToID[link] {
                    links.append(HydraCore.NoteLink(source: note.id.uuidString, target: target))
                }
            }
        }

        // Build semantic index
        let index = LocalSemanticIndex()
        let docs = inv.notes.map { (id: $0.id.uuidString, title: $0.title, tags: $0.tags, content: $0.relativePath) }
        await index.build(from: docs)

        return (inv, links, index)
    }

    @Test("Ask the vault — 3 real queries")
    func realRAGQueries() async throws {
        let (inv, links, index) = await Self.scan()
        guard inv.noteCount > 0 else { throw CocoaError(.fileReadUnknown) }

        let noteTitles = Dictionary(inv.notes.map { ($0.id.uuidString, $0.title) }, uniquingKeysWith: { a, _ in a })
        let titleFor: @Sendable (String) -> String = { id in noteTitles[id] ?? id }

        let query = HybridRAGQuery()
        var queryNum = 1

        for question in [
            "how does the knowledge graph analysis work",
            "tailscale network setup",
            "session learning observations",
        ] {
            let result = await query.run(query: question, index: index, links: links, titleFor: titleFor)

            let panel = RealRAGPanel(
                question: question,
                result: result
            )

            let png = await Self.render(panel, width: 900, height: 680)
            let path = "/tmp/hydra-real-rag-\(queryNum).png"
            try png.write(to: URL(fileURLWithPath: path))
            print("✓ RAG #\(queryNum): '\(question)' → \(result.semanticHits.count) semantic + \(result.graphHits.count) graph")
            queryNum += 1
        }
    }

    @MainActor
    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) async -> Data {
        let controller = NSHostingController(rootView: view.preferredColorScheme(.dark))
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else { return Data() }
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }
}

/// Renders a real HybridRAGQuery.Result in the Hydra theme.
struct RealRAGPanel: View {
    let question: String
    let result: HybridRAGQuery.Result

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Question bar
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(Color.hydraAccent)
                        .font(.system(size: 16))
                    Text(question)
                        .font(HydraTheme.mono(.headline))
                        .foregroundStyle(Color.hydraInk)
                        .italic()
                    Spacer()
                    HydraStatusDot(color: .hydraLive, pulsing: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.hydraCard)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hydraLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Stats
                HStack(spacing: 12) {
                    HydraStatCard(title: "Semantic", value: "\(result.semanticHits.count)", icon: "sparkles", accentColor: .hydraAccent)
                    HydraStatCard(title: "Graph", value: "\(result.graphHits.count)", icon: "link.circle.fill", accentColor: .hydraLive)
                    HydraStatCard(title: "Total", value: "\(result.semanticHits.count + result.graphHits.count)", icon: "square.stack.3d.up.fill", accentColor: .hydraPartial)
                }

                // Answer
                HydraPanel(title: "Answer", icon: "brain.head.profile.fill") {
                    Text(result.answer)
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraInk)
                        .lineSpacing(5)
                }

                // Semantic hits with scores
                if !result.semanticHits.isEmpty {
                    HydraPanel(title: "Semantic Matches", icon: "sparkles") {
                        VStack(spacing: 8) {
                            ForEach(Array(result.semanticHits.prefix(6).enumerated()), id: \.offset) { _, hit in
                                HStack(spacing: 10) {
                                    HydraTagChip(label: String(hit.title.prefix(30)), color: .hydraAccent)
                                    Spacer()
                                    Text("\(Int(hit.score * 100))%")
                                        .font(HydraTheme.mono(.caption2, weight: .bold))
                                        .foregroundStyle(Color.hydraLive)
                                }
                            }
                        }
                    }
                }

                // Graph hits
                if !result.graphHits.isEmpty {
                    HydraPanel(title: "Discovered via Graph", icon: "link.circle.fill") {
                        VStack(spacing: 6) {
                            ForEach(Array(result.graphHits.prefix(8).enumerated()), id: \.offset) { _, hit in
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .foregroundStyle(Color.hydraMuted)
                                        .font(.system(size: 10))
                                    Text(hit.title)
                                        .font(HydraTheme.mono(.caption))
                                        .foregroundStyle(Color.hydraInk)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color.hydraVoid)
    }
}
