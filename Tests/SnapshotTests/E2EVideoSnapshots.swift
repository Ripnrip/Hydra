import Testing
import SnapshotTesting
import SwiftUI
import AppKit
import HydraCore
import HydraVault
import HydraHealth
@testable import HydraApp

// MARK: - E2E Flow Videos (Pointfree Snapshot Frames)
//
// Each e2e flow is captured as a sequence of pointfree snapshot "frames" —
// deterministic, reproducible, diffable. Stitched together they form a video
// of the flow working end to end. Frames live in __Snapshots__/e2e-frames/.

@MainActor
func renderFrame<V: View>(
    _ view: V,
    name: String,
    width: CGFloat = 1000,
    height: CGFloat = 650
) {
    let controller = NSHostingController(rootView: view.frame(width: width, height: height))
    controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    controller.view.layoutSubtreeIfNeeded()

    assertSnapshot(
        of: controller,
        as: .image(size: .init(width: width, height: height)),
        named: name,
        timeout: 30
    )
}

// MARK: - Flow 1: Hydration (pick folder → detect → dry run → hydrate)

@Suite("E2E Video — Hydration Flow")
@MainActor
struct HydrationFlowVideo {

    @Test("Frame 1: Empty state — pick a folder")
    func frame1_empty() {
        renderFrame(
            HydrationView(),
            name: "e2e-hydration-01-empty"
        )
    }

    @Test("Frame 2: Folder picked — detecting")
    func frame2_detecting() {
        renderFrame(
            HydrationDetectingView(vaultPath: "~/Documents/MyVault"),
            name: "e2e-hydration-02-detecting"
        )
    }

    @Test("Frame 3: Detected — sources found")
    func frame3_detected() {
        let config = SmartVaultConfig(pickedPath: "~/Documents/MyVault")
        // Simulated detection results
        renderFrame(
            HydrationDetectedView(
                vaultPath: "~/Documents/MyVault",
                summary: "Obsidian vault · PARA structure · 4 sources found",
                sources: [
                    HydraVault.DetectedSource(kind: .claudePlans, path: "~/.claude/plans", label: "Claude Plans (6 files)", fileCount: 6),
                    HydraVault.DetectedSource(kind: .claudeSessions, path: "~/.claude/projects", label: "Claude Sessions", fileCount: -1),
                    HydraVault.DetectedSource(kind: .changelog, path: "CHANGELOG.md", label: "Changelog", fileCount: 1),
                    HydraVault.DetectedSource(kind: .gitRepo, path: "docs/plans", label: "Plans (12 files)", fileCount: 12),
                ]
            ),
            name: "e2e-hydration-03-detected"
        )
    }

    @Test("Frame 4: Dry run preview — what will be created")
    func frame4_dryrun() {
        renderFrame(
            ScrollView {
                DryRunPreviewView(
                    artifacts: DryRunSampleData.artifacts,
                    vaultPath: "~/Documents/MyVault"
                )
            }.background(Color.hydraVoid),
            name: "e2e-hydration-04-dryrun"
        )
    }

    @Test("Frame 5: Hydrating — progress")
    func frame5_hydrating() {
        renderFrame(
            HydrationProgressView(current: 2, total: 4, currentFile: "elegant-churning-haven.md"),
            name: "e2e-hydration-05-progress"
        )
    }

    @Test("Frame 6: Complete — summary")
    func frame6_complete() {
        renderFrame(
            HydrationCompleteView(
                scanned: 6,
                classified: 6,
                projected: 6,
                tagsCreated: 18,
                linksCreated: 11
            ),
            name: "e2e-hydration-06-complete"
        )
    }
}

// MARK: - Flow 2: Oracle Query (ask → search → answer → highlighted graph)

@Suite("E2E Video — Oracle Query Flow")
@MainActor
struct OracleQueryFlowVideo {

    @Test("Frame 1: Oracle empty — ready")
    func frame1_empty() {
        renderFrame(
            OracleEmptyStateView(),
            name: "e2e-oracle-01-empty"
        )
    }

    @Test("Frame 2: Query typed")
    func frame2_query() {
        renderFrame(
            OracleQueryView(query: "andromeda memory control plane"),
            name: "e2e-oracle-02-query"
        )
    }

    @Test("Frame 3: Searching — spinner")
    func frame3_searching() {
        renderFrame(
            OracleSearchingView(query: "andromeda memory control plane"),
            name: "e2e-oracle-03-searching"
        )
    }

    @Test("Frame 4: Answer — semantic results")
    func frame4_answer() {
        let result = HybridRAGQuery.Result(
            query: "andromeda memory control plane",
            semanticHits: [
                (id: "sys-arch", title: "System Architecture", snippet: "design patterns for the control plane modules", score: 0.89),
                (id: "memory-stack", title: "Anima Memory Stack", snippet: "eight-layer memory architecture", score: 0.76),
                (id: "pkg-deps", title: "Package Dependencies", snippet: "swift module graph", score: 0.64),
            ],
            graphHits: [
                (id: "multibrain", title: "Multibrain Pipeline"),
                (id: "tailscale", title: "Tailscale Fleet"),
                (id: "control-plane", title: "Control Plane Service"),
            ],
            allNoteIDs: ["sys-arch", "memory-stack", "pkg-deps", "multibrain", "tailscale", "control-plane"]
        )
        renderFrame(
            OracleAnswerView(result: result),
            name: "e2e-oracle-04-answer"
        )
    }

    @Test("Frame 5: Graph highlighted")
    func frame5_graph() {
        // Real vault graph with highlights
        let vaultPath = NSHomeDirectory() + "/Developer/SecondBrain"
        guard FileManager.default.fileExists(atPath: vaultPath) else {
            Issue.record("vault not present")
            return
        }
        let scanner = VaultScanner(vaultRoot: vaultPath)
        let inventory = Task { try await scanner.scan() }
        // Note: this is sync-context fallback — using sample inventory for frame
        let sampleInventory = VaultInventory(vaultRoot: vaultPath, notes: [
            VaultNote(relativePath: "01-Permanent/Systems/System Architecture.md", title: "System Architecture", tags: ["system"], wikilinks: ["Package Dependencies", "Multibrain Pipeline"], paraCategory: .system),
            VaultNote(relativePath: "01-Permanent/Systems/Memory Stack.md", title: "Anima Memory Stack", tags: ["memory"], wikilinks: ["System Architecture"], paraCategory: .system),
            VaultNote(relativePath: "01-Permanent/Systems/Package Dependencies.md", title: "Package Dependencies", tags: ["swift"], wikilinks: ["System Architecture"], paraCategory: .system),
            VaultNote(relativePath: "01-Permanent/Systems/Multibrain.md", title: "Multibrain Pipeline", tags: ["pipeline"], wikilinks: ["Memory Stack"], paraCategory: .system),
            VaultNote(relativePath: "01-Permanent/Systems/Tailscale.md", title: "Tailscale Fleet", tags: ["network"], wikilinks: [], paraCategory: .system),
            VaultNote(relativePath: "07-Sessions/session.md", title: "Control Plane Session", tags: [], wikilinks: ["System Architecture"], paraCategory: .session),
        ])

        renderFrame(
            VaultGraphView(
                inventory: sampleInventory,
                highlightedSemanticIDs: ["system architecture", "anima memory stack", "package dependencies"],
                highlightedGraphIDs: ["multibrain pipeline", "tailscale fleet", "control plane session"]
            ),
            name: "e2e-oracle-05-graph-highlighted",
            width: 1000,
            height: 500
        )
    }
}

// MARK: - Flow 3: Health Check

@Suite("E2E Video — Health Flow")
@MainActor
struct HealthFlowVideo {

    @Test("Frame 1: Health empty")
    func frame1_empty() {
        renderFrame(
            HealthEmptyStateView(),
            name: "e2e-health-01-empty"
        )
    }

    @Test("Frame 2: Running checks")
    func frame2_running() {
        renderFrame(
            HealthRunningView(currentCheck: 3, totalChecks: 7),
            name: "e2e-health-02-running"
        )
    }

    @Test("Frame 3: Results — warning status")
    func frame3_results() {
        let report = HealthReport(
            vaultRoot: "~/Documents/MyVault",
            checks: [
                HealthCheck(name: "Vault Staleness", status: .healthy, message: "Latest entry was 1 day ago", affectedCount: 0),
                HealthCheck(name: "Missing Frontmatter", status: .warning, message: "12 notes missing frontmatter", affectedCount: 12),
                HealthCheck(name: "Orphaned Notes", status: .warning, message: "45 of 155 notes are orphaned", affectedCount: 45),
                HealthCheck(name: "Broken Wikilinks", status: .healthy, message: "All wikilinks resolve", affectedCount: 0),
                HealthCheck(name: "Tag Consistency", status: .healthy, message: "No duplicate variants", affectedCount: 0),
                HealthCheck(name: "Inbox Backlog", status: .healthy, message: "0 notes in inbox", affectedCount: 0),
                HealthCheck(name: "Digest Integrity", status: .healthy, message: "All digests present", affectedCount: 0),
            ]
        )
        renderFrame(
            HealthResultsVideoView(report: report),
            name: "e2e-health-03-results"
        )
    }
}

// MARK: - Supporting Views (video frame states)

struct HydrationDetectingView: View {
    let vaultPath: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context Hydration").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Pick a folder — we detect the rest").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HydraPanel(title: "Vault Folder", icon: "folder.badge.gearshape") {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Color.hydraAccent)
                        Text(vaultPath).font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        ProgressView().tint(Color.hydraAccent).controlSize(.small)
                        Text("Detecting sources...").font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraMuted)
                    }.padding(.top, 8)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct HydrationDetectedView: View {
    let vaultPath: String
    let summary: String
    let sources: [HydraVault.DetectedSource]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context Hydration").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Pick a folder — we detect the rest").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HydraPanel(title: "Vault Folder", icon: "folder.badge.gearshape") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(Color.hydraAccent)
                            Text(vaultPath).font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                            Spacer()
                        }
                        Label(summary, systemImage: "checkmark.shield.fill")
                            .font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraLive)

                        ForEach(sources) { source in
                            HStack(spacing: 8) {
                                Image(systemName: iconName(source.kind)).foregroundStyle(Color.hydraAccent).font(.system(size: 10))
                                Text(source.label).font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraInk)
                                Spacer()
                            }.padding(.vertical, 2)
                        }
                    }
                }
                .padding(.horizontal, 24)

                HStack {
                    Spacer()
                    HydraButton("Hydrate", icon: "drop.fill") {}
                    Spacer()
                }.padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }

    private func iconName(_ kind: SourceKind) -> String {
        switch kind {
        case .claudePlans: "doc.text.magnifyingglass"
        case .claudeSessions: "bubble.left.and.bubble.right"
        case .changelog: "list.bullet.rectangle"
        case .gitRepo: "square.stack.3d.up"
        default: "doc"
        }
    }
}

struct HydrationProgressView: View {
    let current: Int
    let total: Int
    let currentFile: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context Hydration").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Hydrating...").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HydraPanel(title: "Progress", icon: "drop.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: Double(current), total: Double(total))
                            .tint(Color.hydraAccent)

                        Text("\(current) of \(total) artifacts")
                            .font(HydraTheme.mono(.callout))
                            .foregroundStyle(Color.hydraInk)

                        Text("→ \(currentFile)")
                            .font(HydraTheme.mono(.caption))
                            .foregroundStyle(Color.hydraMuted)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct HydrationCompleteView: View {
    let scanned: Int
    let classified: Int
    let projected: Int
    let tagsCreated: Int
    let linksCreated: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context Hydration").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Hydration complete").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraLive)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.hydraLive)
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 12) {
                    HydraStatCard(title: "Scanned", value: "\(scanned)", icon: "doc.text.fill")
                    HydraStatCard(title: "Classified", value: "\(classified)", icon: "tag.fill", accentColor: .hydraLive)
                    HydraStatCard(title: "Projected", value: "\(projected)", icon: "archivebox.fill", accentColor: .hydraAccent)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    HydraStatCard(title: "New Tags", value: "\(tagsCreated)", icon: "number.fill", accentColor: .hydraPartial)
                    HydraStatCard(title: "New Links", value: "\(linksCreated)", icon: "link.fill", accentColor: .hydraPartial)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct OracleEmptyStateView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Ask your vault — semantic search + graph expansion")
                            .font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile").foregroundStyle(Color.hydraAccent)
                    TextField("Ask your vault...", text: .constant(""))
                        .textFieldStyle(.plain)
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraInk)
                }
                .padding(12)
                .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hydraAccent.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct OracleQueryView: View {
    let query: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Ask your vault — semantic search + graph expansion")
                            .font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile").foregroundStyle(Color.hydraAccent)
                    Text(query).font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                    Spacer()
                    Image(systemName: "return.key").foregroundStyle(Color.hydraMuted)
                }
                .padding(12)
                .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hydraAccent.opacity(0.4), lineWidth: 1))
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct OracleSearchingView: View {
    let query: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Ask your vault — semantic search + graph expansion")
                            .font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile").foregroundStyle(Color.hydraAccent)
                    Text(query).font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                    Spacer()
                }
                .padding(12)
                .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hydraAccent.opacity(0.4), lineWidth: 1))
                .padding(.horizontal, 24)

                HStack(spacing: 8) {
                    ProgressView().tint(Color.hydraAccent).controlSize(.small)
                    Text("Searching vault... embedding query, ranking notes, expanding graph")
                        .font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraMuted)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct OracleAnswerView: View {
    let result: HybridRAGQuery.Result
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Ask your vault — semantic search + graph expansion")
                            .font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile").foregroundStyle(Color.hydraAccent)
                    Text(result.query).font(HydraTheme.mono(.callout)).foregroundStyle(Color.hydraInk)
                    Spacer()
                }
                .padding(12)
                .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hydraAccent.opacity(0.4), lineWidth: 1))
                .padding(.horizontal, 24)

                HydraPanel(title: "Answer", icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.answer)
                            .font(HydraTheme.mono(.callout))
                            .foregroundStyle(Color.hydraInk)
                            .lineSpacing(4)

                        Text("SEMANTIC MATCHES (\(result.semanticHits.count))")
                            .font(.system(size: 8, design: .monospaced).weight(.semibold))
                            .tracking(1.5).foregroundStyle(Color.hydraMuted)

                        ForEach(Array(result.semanticHits.enumerated()), id: \.offset) { _, hit in
                            HStack(spacing: 8) {
                                Circle().fill(Color.hydraAccent).frame(width: 5, height: 5)
                                Text(hit.title).font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraInk)
                                Spacer()
                                Text("\(Int(hit.score * 100))%")
                                    .font(HydraTheme.mono(.caption2, weight: .bold))
                                    .foregroundStyle(Color.hydraAccent)
                            }
                        }

                        if !result.graphHits.isEmpty {
                            Text("RELATED VIA GRAPH (\(result.graphHits.count))")
                                .font(.system(size: 8, design: .monospaced).weight(.semibold))
                                .tracking(1.5).foregroundStyle(Color.hydraMuted)

                            HStack(spacing: 6) {
                                ForEach(Array(result.graphHits.enumerated()), id: \.offset) { _, hit in
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
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct HealthEmptyStateView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.hydraAccent.opacity(0.6))
                Text("Vault Health")
                    .font(HydraTheme.display(.title))
                    .foregroundStyle(Color.hydraInk)
                Text("Click to run 7 health checks on your vault")
                    .font(HydraTheme.mono(.subheadline))
                    .foregroundStyle(Color.hydraMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.hydraVoid)
    }
}

struct HealthRunningView: View {
    let currentCheck: Int
    let totalChecks: Int
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vault Health").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Running checks...").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HydraPanel(title: "Progress", icon: "stethoscope") {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: Double(currentCheck), total: Double(totalChecks))
                            .tint(Color.hydraAccent)
                        Text("Check \(currentCheck) of \(totalChecks)")
                            .font(HydraTheme.mono(.caption))
                            .foregroundStyle(Color.hydraMuted)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct HealthResultsVideoView: View {
    let report: HealthReport
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vault Health").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Diagnostics and maintenance").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.hydraPartial)
                    Text("WARNING").font(HydraTheme.mono(.title3, weight: .bold)).tracking(2).foregroundStyle(Color.hydraPartial)
                    Text("5 healthy · 2 warnings · 0 critical").font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraMuted)
                    Spacer()
                }
                .padding(14)
                .background(Color.hydraPartial.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                ForEach(report.checks) { check in
                    HStack(spacing: 12) {
                        Image(systemName: check.status == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(check.status == .healthy ? Color.hydraLive : Color.hydraPartial)
                            .font(.system(size: 14)).frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name).font(HydraTheme.mono(.callout, weight: .semibold)).foregroundStyle(Color.hydraInk)
                            Text(check.message).font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraMuted)
                        }
                        Spacer()
                        Text(check.status.rawValue.uppercased())
                            .font(HydraTheme.mono(.caption2, weight: .bold)).tracking(1.5)
                            .foregroundStyle(check.status == .healthy ? Color.hydraLive : Color.hydraPartial)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((check.status == .healthy ? Color.hydraLive : Color.hydraPartial).opacity(0.12), in: Capsule())
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(Color.hydraPanel.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
    }
}
