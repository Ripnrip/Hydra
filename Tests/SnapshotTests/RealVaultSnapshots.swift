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

// MARK: - Real RAG Query Render (Berserker)

@Suite("Real RAG Query")
@MainActor
struct RealRAGQuerySnapshots {
    @Test("Oracle answer from real vault query")
    func realRAGQuery() async throws {
        let vaultPath = NSHomeDirectory() + "/Developer/SecondBrain"
        guard FileManager.default.fileExists(atPath: vaultPath + "/.obsidian") else {
            Issue.record("SecondBrain vault not present")
            return
        }
        let scanner = VaultScanner(vaultRoot: vaultPath)
        let inventory = try await scanner.scan()

        // Build semantic index from real vault
        let index = LocalSemanticIndex()
        await index.build(from: inventory.notes.map { note in
            (id: note.title.lowercased(),
             title: note.title.isEmpty ? note.relativePath : note.title,
             tags: note.tags,
             content: note.frontmatter.values.joined(separator: " "))
        })

        // Build links from real wikilinks
        let links = inventory.notes.flatMap { note -> [NoteLink] in
            note.wikilinks.map { NoteLink(source: note.title.lowercased(), target: $0.lowercased()) }
        }
        let titleMap = Dictionary(
            inventory.notes.map { ($0.title.lowercased(), $0.title.isEmpty ? $0.relativePath : $0.title) },
            uniquingKeysWith: { a, _ in a }
        )

        // Run a real query
        let query = HybridRAGQuery()
        let result = await query.run(
            query: "andromeda memory control plane",
            index: index,
            links: links,
            titleFor: { titleMap[$0] ?? $0 }
        )

        // Render the answer view
        let answerView = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Ask your vault — semantic search + graph expansion")
                            .font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                // Search bar with query
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile").foregroundStyle(Color.hydraAccent)
                    Text("andromeda memory control plane")
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraInk)
                    Spacer()
                }
                .padding(12)
                .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hydraAccent.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 24)

                // RAG answer
                HydraPanel(title: "Answer", icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.answer)
                            .font(HydraTheme.mono(.callout))
                            .foregroundStyle(Color.hydraInk)
                            .lineSpacing(4)

                        if !result.semanticHits.isEmpty {
                            Text("SEMANTIC MATCHES (\(result.semanticHits.count))")
                                .font(.system(size: 8, design: .monospaced).weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(Color.hydraMuted)
                            ForEach(result.semanticHits.prefix(5), id: \.id) { hit in
                                HStack(spacing: 8) {
                                    Circle().fill(Color.hydraAccent).frame(width: 5, height: 5)
                                    Text(hit.title).font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraInk)
                                    Spacer()
                                    Text("\(Int(hit.score * 100))%")
                                        .font(HydraTheme.mono(.caption2, weight: .bold))
                                        .foregroundStyle(Color.hydraAccent)
                                }
                            }
                        }

                        if !result.graphHits.isEmpty {
                            Text("RELATED VIA GRAPH (\(result.graphHits.count))")
                                .font(.system(size: 8, design: .monospaced).weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(Color.hydraMuted)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(result.graphHits.prefix(10), id: \.id) { hit in
                                        Text(hit.title)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(Color.hydraMuted)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Color.hydraMuted.opacity(0.08), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Graph from real vault
                VaultGraphView(inventory: inventory)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.hydraAccent.opacity(0.15), lineWidth: 1))
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)

        let hosting = NSHostingView(rootView: answerView.frame(width: 1000, height: 900))
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 900)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("no rep")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage()
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("png fail")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-real-rag-query.png"))
        print("✓ REAL RAG QUERY — \(result.semanticHits.count) semantic, \(result.graphHits.count) graph hits")
    }
}

// MARK: - LLM Config + Graph Highlight Render

@Suite("LLM + Highlights")
@MainActor
struct LLMHighlightSnapshots {
    @Test("Oracle with LLM config + retrieval-highlighted graph")
    func llmAndHighlights() async throws {
        let vaultPath = NSHomeDirectory() + "/Developer/SecondBrain"
        guard FileManager.default.fileExists(atPath: vaultPath + "/.obsidian") else {
            Issue.record("vault missing")
            return
        }
        let scanner = VaultScanner(vaultRoot: vaultPath)
        let inventory = try await scanner.scan()

        // Run a real RAG query to get highlight sets
        let index = LocalSemanticIndex()
        await index.build(from: inventory.notes.map { note in
            (id: note.title.lowercased(),
             title: note.title.isEmpty ? note.relativePath : note.title,
             tags: note.tags,
             content: note.frontmatter.values.joined(separator: " "))
        })
        let links = inventory.notes.flatMap { note -> [NoteLink] in
            note.wikilinks.map { NoteLink(source: note.title.lowercased(), target: $0.lowercased()) }
        }
        let query = HybridRAGQuery()
        let result = await query.run(query: "andromeda memory control plane", index: index, links: links, titleFor: { $0 })

        let semanticIDs = Set(result.semanticHits.map(\.id))
        let graphIDs = Set(result.graphHits.map(\.id))

        // Render: answer panel + highlighted graph + LLM config
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with LLM sparkles active
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Ask your vault — semantic search + graph expansion")
                            .font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.hydraAccent)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 24).padding(.top, 24)

                // Search bar with query
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile").foregroundStyle(Color.hydraAccent)
                    Text("andromeda memory control plane")
                        .font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.hydraAccent).font(.title3)
                }
                .padding(12)
                .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hydraAccent.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 24)

                // Highlighted graph (semantic + graph IDs from real query)
                VaultGraphView(inventory: inventory, highlightedSemanticIDs: semanticIDs, highlightedGraphIDs: graphIDs)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.hydraAccent.opacity(0.15), lineWidth: 1))
                    .padding(.horizontal, 24)

                // Offline answer
                HydraPanel(title: "Answer", icon: "sparkles") {
                    Text(result.answer)
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraInk)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 24)

                // LLM config panel (open)
                HydraPanel(title: "LLM Settings (optional)", icon: "gearshape") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add an OpenAI-compatible endpoint for AI-reasoned answers.")
                            .font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraMuted)
                        Text("BASE URL").font(.system(size: 8, design: .monospaced).weight(.semibold)).tracking(1.5).foregroundStyle(Color.hydraMuted)
                        Text("https://api.openai.com/v1").font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.hydraVoid, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.hydraLine, lineWidth: 1))
                        Text("MODEL").font(.system(size: 8, design: .monospaced).weight(.semibold)).tracking(1.5).foregroundStyle(Color.hydraMuted)
                        Text("gpt-4o-mini").font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.hydraVoid, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.hydraLine, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)

        let hosting = NSHostingView(rootView: view.frame(width: 1000, height: 1000))
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage()
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: "/tmp/hydra-llm-highlights.png"))
        print("✓ LLM + HIGHLIGHTS — \(semanticIDs.count) semantic, \(graphIDs.count) graph highlighted")
    }
}
