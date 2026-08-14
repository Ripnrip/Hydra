import SwiftUI
import HydraCore
import HydraVault
import HydraHealth

// MARK: - Oracle View (real data)

struct OracleView: View {
    @State private var inventory: VaultInventory?
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var vaultPath = "~/Documents/MyVault"
    @State private var showVaultPicker = false
    @State private var ragResult: HybridRAGQuery.Result?
    @State private var semanticIndex: LocalSemanticIndex?
    @State private var isQuerying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle")
                            .font(HydraTheme.display(.largeTitle))
                            .foregroundStyle(Color.hydraInk)
                        Text("Ask your vault — semantic search + graph expansion")
                            .font(HydraTheme.mono(.subheadline))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                    HydraButton("Scan", icon: "magnifyingglass") {
                        Task { await scanVault() }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                // Ask-your-vault search bar
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(Color.hydraAccent)
                    TextField("Ask your vault...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraInk)
                        .onSubmit { Task { await runQuery() } }
                    if isQuerying {
                        HydraStaticSpinner()
                    } else if !searchText.isEmpty {
                        Button {
                            Task { await runQuery() }
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(Color.hydraAccent)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.hydraAccent.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                // RAG answer
                if let result = ragResult {
                    ragAnswerView(result)
                        .padding(.horizontal, 24)
                }

                if isLoading {
                    VStack(spacing: 16) {
                        HydraStaticSpinner()
                        Text("Scanning vault...")
                            .font(HydraTheme.mono(.headline))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else if let inv = inventory {
                    oracleContent(inv)
                } else {
                    emptyState
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
        .task { await scanVault() }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.hydraAccent.opacity(0.6))
                Text("No vault scanned")
                    .font(HydraTheme.display(.title))
                    .foregroundStyle(Color.hydraInk)
                Text("Click Scan to analyze your vault")
                    .font(HydraTheme.mono(.subheadline))
                    .foregroundStyle(Color.hydraMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func oracleContent(_ inv: VaultInventory) -> some View {
        // Relationship graph — the Oracle's signature view
        RelationshipGraphView(nodes: graphNodes(from: inv), edges: graphEdges(from: inv))
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: HydraTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: HydraTheme.cornerRadius).strokeBorder(Color.hydraLine, lineWidth: 1))
            .padding(.horizontal, 24)

        // Stats row
        HStack(spacing: 12) {
            HydraStatCard(title: "Notes", value: "\(inv.noteCount)", icon: "doc.text.fill")
            HydraStatCard(title: "Tags", value: "\(inv.tagFrequency.count)", icon: "tag.fill", accentColor: .hydraLive)
            HydraStatCard(title: "Orphans", value: "\(inv.orphanedNotes.count)", icon: "questionmark.circle.fill", accentColor: .hydraAlert)
            HydraStatCard(title: "Broken Links", value: "\(inv.brokenWikilinks.count)", icon: "link.badge.plus", accentColor: .hydraPartial)
        }
        .padding(.horizontal, 24)

        // Top tags
        HydraPanel(title: "Top Tags", icon: "tag.fill") {
            VStack(spacing: 6) {
                ForEach(inv.tagFrequency.prefix(15), id: \.tag) { item in
                    HStack(spacing: 10) {
                        HydraTagChip(label: item.tag, color: tagColor(item.tag))
                        Spacer()
                        Text("\(item.count)")
                            .font(HydraTheme.mono(.caption2, weight: .bold))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.horizontal, 24)

        // Orphaned notes
        if !inv.orphanedNotes.isEmpty {
            HydraPanel(title: "Orphaned Notes (\(inv.orphanedNotes.count))", icon: "questionmark.circle.fill") {
                VStack(spacing: 6) {
                    ForEach(inv.orphanedNotes.prefix(10)) { note in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(Color.hydraAlert)
                                .font(.system(size: 11))
                            Text(note.title.isEmpty ? note.relativePath : note.title)
                                .font(HydraTheme.mono(.caption))
                                .foregroundStyle(Color.hydraInk)
                                .lineLimit(1)
                            Spacer()
                            HydraTagChip(label: "0 links", color: .hydraAlert)
                        }
                        .padding(.vertical, 3)
                    }
                    if inv.orphanedNotes.count > 10 {
                        Text("+ \(inv.orphanedNotes.count - 10) more...")
                            .font(HydraTheme.mono(.caption2))
                            .foregroundStyle(Color.hydraMuted)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
        }

        // Broken wikilinks
        if !inv.brokenWikilinks.isEmpty {
            HydraPanel(title: "Broken Wikilinks (\(inv.brokenWikilinks.count))", icon: "link.badge.plus") {
                VStack(spacing: 6) {
                    ForEach(inv.brokenWikilinks.prefix(10), id: \.self) { link in
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.hydraPartial)
                                .font(.system(size: 11))
                            Text("[[\(link)]]")
                                .font(HydraTheme.mono(.caption))
                                .foregroundStyle(Color.hydraPartial)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                    if inv.brokenWikilinks.count > 10 {
                        Text("+ \(inv.brokenWikilinks.count - 10) more...")
                            .font(HydraTheme.mono(.caption2))
                            .foregroundStyle(Color.hydraMuted)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func tagColor(_ tag: String) -> Color {
        if tag.contains("project") { .hydraAccent }
        else if tag.contains("type") { Color(red: 0.45, green: 0.75, blue: 0.95) }
        else if tag.contains("status") { .hydraLive }
        else if tag.contains("integration") { Color(red: 0.75, green: 0.55, blue: 0.95) }
        else { .hydraMuted }
    }

    // Convert vault notes → graph nodes
    private func graphNodes(from inv: VaultInventory) -> [GraphNode] {
        // Top 30 most-connected notes + top tags as hub nodes
        let connectedNotes = inv.notes
            .sorted { $0.wikilinks.count > $1.wikilinks.count }
            .prefix(24)

        var nodes: [GraphNode] = connectedNotes.enumerated().map { idx, note in
            GraphNode(
                id: note.id.uuidString,
                label: note.title.isEmpty ? note.relativePath : note.title,
                position: SIMD2<Float>(
                    Float(100 + (idx % 6) * 120 + ((idx * 37) % 40 - 20)),
                    Float(80 + (idx / 6) * 100 + ((idx * 23) % 30 - 15))
                ),
                velocity: .zero,
                radius: Float(6 + min(note.wikilinks.count, 12)),
                color: GraphNodeKind.note.baseColor,
                kind: .note
            )
        }

        // Tag hubs
        for (i, tagItem) in inv.tagFrequency.prefix(6).enumerated() {
            nodes.append(GraphNode(
                id: "tag-\(tagItem.tag)",
                label: "#\(tagItem.tag)",
                position: SIMD2<Float>(Float(200 + i * 130), Float(420 + ((i * 37) % 40 - 20))),
                velocity: .zero,
                radius: Float(8 + min(tagItem.count / 10, 8)),
                color: tagColor(tagItem.tag) != .hydraMuted
                    ? SIMD4<Float>(0.68, 0.52, 0.98, 1.0)
                    : GraphNodeKind.note.baseColor,
                kind: .note
            ))
        }

        return nodes
    }

    // Convert wikilinks → graph edges
    private func graphEdges(from inv: VaultInventory) -> [GraphEdge] {
        var edges: [GraphEdge] = []
        let titleToId = Dictionary(
            inv.notes.map { ($0.title, $0.id.uuidString) },
            uniquingKeysWith: { first, _ in first }
        )

        for note in inv.notes.prefix(24) {
            for link in note.wikilinks.prefix(5) {
                if let targetId = titleToId[link] {
                    edges.append(GraphEdge(
                        id: "\(note.id.uuidString)-\(link)",
                        source: note.id.uuidString,
                        target: targetId,
                        strength: 0.6,
                        type: .references
                    ))
                }
            }
            // Connect to tag hubs
            for tag in note.tags.prefix(2) {
                edges.append(GraphEdge(
                    id: "\(note.id.uuidString)-tag-\(tag)",
                    source: note.id.uuidString,
                    target: "tag-\(tag)",
                    strength: 0.3,
                    type: .relatesTo
                ))
            }
        }

        return Array(edges.prefix(60))
    }

    private func scanVault() async {
        isLoading = true
        let scanner = VaultScanner(vaultRoot: vaultPath.expandingTildeInPath)
        do {
            inventory = try await scanner.scan()
            // Build semantic index from the scan
            let index = LocalSemanticIndex()
            await index.build(from: inventory!.notes.map { note in
                (id: note.title.lowercased(),
                 title: note.title.isEmpty ? note.relativePath : note.title,
                 tags: note.tags,
                 content: note.frontmatter.values.joined(separator: " "))
            })
            semanticIndex = index
        } catch {
            isLoading = false
        }
        isLoading = false
    }

    // MARK: - Hybrid RAG query

    private func runQuery() async {
        guard !searchText.isEmpty, let index = semanticIndex, let inv = inventory else { return }
        isQuerying = true
        defer { isQuerying = false }

        // Build links from wikilinks
        let links = inv.notes.flatMap { note -> [NoteLink] in
            note.wikilinks.map { NoteLink(source: note.title.lowercased(), target: $0.lowercased()) }
        }

        let titleMap = Dictionary(
            inv.notes.map { ($0.title.lowercased(), $0.title.isEmpty ? $0.relativePath : $0.title) },
            uniquingKeysWith: { a, _ in a }
        )

        let query = HybridRAGQuery()
        ragResult = await query.run(
            query: searchText,
            index: index,
            links: links,
            titleFor: { titleMap[$0] ?? $0 }
        )
    }

    // MARK: - RAG answer rendering

    @ViewBuilder
    private func ragAnswerView(_ result: HybridRAGQuery.Result) -> some View {
        HydraPanel(title: "Answer", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                Text(result.answer)
                    .font(HydraTheme.mono(.callout))
                    .foregroundStyle(Color.hydraInk)
                    .lineSpacing(4)

                // Retrieved note pills
                if !result.allNoteIDs.isEmpty {
                    Text("RETRIEVED (\(result.allNoteIDs.count))")
                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.hydraMuted)

                    // Show semantic hits as purple pills, graph hits as muted
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(result.semanticHits, id: \.id) { hit in
                                Text(hit.title)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Color.hydraAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.hydraAccent.opacity(0.1), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.hydraAccent.opacity(0.3), lineWidth: 0.5))
                            }
                            ForEach(result.graphHits.prefix(8), id: \.id) { hit in
                                Text(hit.title)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Color.hydraMuted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.hydraMuted.opacity(0.08), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Health View (real data)

struct HealthView: View {
    @State private var report: HealthReport?
    @State private var inventory: VaultInventory?
    @State private var isLoading = false
    @State private var vaultPath = "~/Documents/MyVault"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vault Health")
                            .font(HydraTheme.display(.largeTitle))
                            .foregroundStyle(Color.hydraInk)
                        Text("Diagnostics and maintenance")
                            .font(HydraTheme.mono(.subheadline))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                    if let report {
                        statusBadge(report.overallStatus)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                if isLoading {
                    VStack(spacing: 16) {
                        HydraStaticSpinner()
                        Text("Running health checks...")
                            .font(HydraTheme.mono(.headline))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else if let report {
                    healthContent(report)
                } else {
                    emptyState
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
        .task { await runChecks() }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.hydraAccent.opacity(0.6))
                Text("No vault scanned")
                    .font(HydraTheme.display(.title))
                    .foregroundStyle(Color.hydraInk)
                Text("Health checks will appear here")
                    .font(HydraTheme.mono(.subheadline))
                    .foregroundStyle(Color.hydraMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func healthContent(_ report: HealthReport) -> some View {
        // Summary stats
        HStack(spacing: 12) {
            let healthy = report.checks.filter { $0.status == .healthy }.count
            let warnings = report.checks.filter { $0.status == .warning }.count
            let critical = report.checks.filter { $0.status == .critical }.count
            HydraStatCard(title: "Healthy", value: "\(healthy)", icon: "checkmark.circle.fill", accentColor: .hydraLive)
            HydraStatCard(title: "Warnings", value: "\(warnings)", icon: "exclamationmark.triangle.fill", accentColor: .hydraPartial)
            HydraStatCard(title: "Critical", value: "\(critical)", icon: "xmark.octagon.fill", accentColor: .hydraAlert)
        }
        .padding(.horizontal, 24)

        // Check results
        HydraPanel(title: "Checks", icon: "stethoscope") {
            VStack(spacing: 12) {
                ForEach(report.checks) { check in
                    healthCheckRow(check)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func healthCheckRow(_ check: HealthCheck) -> some View {
        HStack(spacing: 12) {
            // Status dot
            HydraStatusDot(color: statusColor(check.status), pulsing: check.status == .critical)

            VStack(alignment: .leading, spacing: 3) {
                Text(check.name)
                    .font(HydraTheme.mono(.callout, weight: .semibold))
                    .foregroundStyle(Color.hydraInk)
                Text(check.message)
                    .font(HydraTheme.mono(.caption))
                    .foregroundStyle(Color.hydraMuted)
            }

            Spacer()

            if check.affectedCount > 0 {
                Text("\(check.affectedCount)")
                    .font(HydraTheme.mono(.callout, weight: .bold))
                    .foregroundStyle(statusColor(check.status))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(statusColor(check.status).opacity(0.1)))
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.hydraLive)
                    .font(.system(size: 14))
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: HealthStatus) -> some View {
        HStack(spacing: 6) {
            HydraStatusDot(color: statusColor(status), pulsing: true)
            Text(status.rawValue.uppercased())
                .font(HydraTheme.mono(.caption2, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(statusColor(status).opacity(0.1)))
        .overlay(Capsule().strokeBorder(statusColor(status).opacity(0.3), lineWidth: 1))
    }

    private func statusColor(_ status: HealthStatus) -> Color {
        switch status {
        case .healthy: .hydraLive
        case .warning: .hydraPartial
        case .critical: .hydraAlert
        }
    }

    private func runChecks() async {
        isLoading = true
        let scanner = VaultScanner(vaultRoot: vaultPath.expandingTildeInPath)
        do {
            let inv = try await scanner.scan()
            inventory = inv
            report = HealthChecker().checkAll(inv)
        } catch {
            isLoading = false
        }
        isLoading = false
    }
}

// MARK: - Tilde expansion

extension String {
    var expandingTildeInPath: String {
        guard hasPrefix("~") else { return self }
        return FileManager.default.homeDirectoryForCurrentUser.path + dropFirst()
    }
}
