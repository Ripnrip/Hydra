import Testing
import SnapshotTesting
import SwiftUI
import AppKit
import HydraCore
import HydraVault
import HydraHealth
@testable import HydraApp

/// Wraps a SwiftUI view in NSHostingController for snapshot testing.
@MainActor
func snapView<V: View>(_ view: V, named: String, width: CGFloat = 800, height: CGFloat = 600) {
    let controller = NSHostingController(rootView: view)
    controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    controller.view.needsLayout = true
    controller.view.layoutSubtreeIfNeeded()
    assertSnapshot(of: controller, as: .image(size: .init(width: width, height: height)), named: named, timeout: 30)
}

/// Captures both light and dark mode snapshots.
@MainActor
func snapViewBoth<V: View>(_ view: V, named: String, width: CGFloat = 800, height: CGFloat = 600) {
    // Dark
    let darkController = NSHostingController(rootView: view)
    darkController.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    darkController.view.needsLayout = true
    darkController.view.layoutSubtreeIfNeeded()
    darkController.view.appearance = NSAppearance(named: .darkAqua)
    assertSnapshot(of: darkController, as: .image(size: .init(width: width, height: height)), named: "\(named)_dark", timeout: 30)

    // Light
    let lightController = NSHostingController(rootView: view)
    lightController.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    lightController.view.needsLayout = true
    lightController.view.layoutSubtreeIfNeeded()
    lightController.view.appearance = NSAppearance(named: .aqua)
    assertSnapshot(of: lightController, as: .image(size: .init(width: width, height: height)), named: "\(named)_light", timeout: 30)
}

// MARK: - Component Snapshots

@Suite("Tag Chip")
@MainActor
struct TagChipSnapshots {
    @Test("All color axes")
    func tagChipAllAxes() {
        for axis in ColorAxis.allCases {
            let tag = ColorTag(axis: axis, value: "test", color: defaultColor(for: axis))
            snapViewBoth(TagChip(colorTag: tag), named: "\(axis.rawValue)", width: 200, height: 40)
        }
    }
    @Test("Selected state")
    func tagChipSelected() {
        let tag = ColorTag(axis: .project, value: "ai-config", color: .projectWarm)
        snapViewBoth(TagChip(colorTag: tag, isSelected: true), named: "selected", width: 200, height: 40)
    }
}

@Suite("Confidence Meter")
@MainActor
struct ConfidenceMeterSnapshots {
    @Test("All levels", arguments: [0.0, 0.25, 0.5, 0.75, 0.92, 1.0])
    func confidenceMeter(value: Double) {
        snapViewBoth(ConfidenceMeter(value: value), named: "confidence_\(Int(value * 100))", width: 200, height: 30)
    }
}

@Suite("Provenance Badge")
@MainActor
struct ProvenanceBadgeSnapshots {
    @Test("All authority levels")
    func provenanceBadges() {
        for authority in [Authority.gitReceipt, .controlPlaneLedger, .changelog, .observation, .wikiNote] {
            snapViewBoth(ProvenanceBadge(authority: authority), named: authority.rawValue, width: 200, height: 30)
        }
    }
}

@Suite("Lifecycle Badge")
@MainActor
struct LifecycleBadgeSnapshots {
    @Test("All states")
    func lifecycleBadges() {
        for state in LifecycleState.allCases {
            snapViewBoth(LifecycleBadge(state: state), named: state.rawValue, width: 200, height: 30)
        }
    }
}

@Suite("Delivery State Pill")
@MainActor
struct DeliveryStatePillSnapshots {
    @Test("All delivery states")
    func deliveryPills() {
        for state in DeliveryState.allCases {
            snapViewBoth(DeliveryStatePill(state: state), named: state.rawValue, width: 250, height: 30)
        }
    }
}

// MARK: - Panel Snapshots

@Suite("Hydration Panel")
@MainActor
struct HydrationPanelSnapshots {
    @Test("Light + dark")
    func hydrationPanel() {
        snapViewBoth(HydrationView(), named: "hydration", width: 900, height: 600)
    }
}

@Suite("Vault Explorer")
@MainActor
struct VaultExplorerSnapshots {
    @Test("Empty state")
    func vaultEmpty() {
        snapViewBoth(VaultExplorerView(), named: "vault_empty", width: 900, height: 600)
    }
}

@Suite("Oracle Panel")
@MainActor
struct OraclePanelSnapshots {
    @Test("Empty state")
    func oracleEmpty() {
        snapViewBoth(OracleView(), named: "oracle_empty", width: 900, height: 600)
    }
}

@Suite("Health Panel")
@MainActor
struct HealthPanelSnapshots {
    @Test("Empty state")
    func healthEmpty() {
        snapViewBoth(HealthView(), named: "health_empty", width: 900, height: 600)
    }
}

// MARK: - GPU Graph Renderer

@Suite("Relationship Graph")
@MainActor
struct GraphSnapshots {
    @Test("Initial layout")
    func graphInitial() {
        snapView(RelationshipGraphView(), named: "graph_initial", width: 900, height: 600)
    }
}

// MARK: - E2E Flow (snapshot-driven UI test)

@Suite("E2E Hydration Flow")
@MainActor
struct E2EFlowSnapshots {

    @Test("Step 1: Idle")
    func flowIdle() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .idle), named: "e2e_idle", width: 900, height: 600)
    }

    @Test("Step 2: Scanning")
    func flowScanning() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .scanning), named: "e2e_scanning", width: 900, height: 600)
    }

    @Test("Step 3: Scanned (source files discovered)")
    func flowScanned() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .scanned), named: "e2e_scanned", width: 900, height: 600)
    }

    @Test("Step 4: Classifying")
    func flowClassifying() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .classifying), named: "e2e_classifying", width: 900, height: 600)
    }

    @Test("Step 5: Classified (results with tags)")
    func flowClassified() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .classified), named: "e2e_classified", width: 900, height: 600)
    }

    @Test("Step 6: Review complete")
    func flowReviewing() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .reviewing), named: "e2e_reviewing", width: 900, height: 600)
    }

    @Test("Step 7: Writing to vault")
    func flowWriting() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .writing), named: "e2e_writing", width: 900, height: 600)
    }

    @Test("Step 8: Complete (success summary)")
    func flowComplete() {
        snapViewBoth(E2EHydrationFlowView(fixedStep: .complete), named: "e2e_complete", width: 900, height: 600)
    }
}

// MARK: - Functional Tab Snapshots (with real data)

@Suite("Functional — Oracle with Data")
@MainActor
struct OracleDataSnapshots {
    @Test("Oracle populated")
    func oracleWithData() {
        // Create sample inventory with real-looking data
        var notes: [VaultNote] = []
        let sampleData: [(String, String, [String], [String], PARACategory)] = [
            ("System Architecture", "01-Permanent/Systems/System Architecture.md", ["system", "architecture", "design"], ["Package Dependencies", "Memory Stack"], .system),
            ("Package Dependencies", "01-Permanent/Systems/Package Dependencies.md", ["swift", "dependencies", "spm"], ["System Architecture"], .system),
            ("Session — Hydra Pipeline", "07-Sessions/2026-08-13--hydra-pipeline.md", ["hydra", "session", "pipeline"], ["System Architecture", "Multibrain"], .session),
            ("Multibrain Pipeline", "01-Permanent/Systems/Multibrain.md", ["multibrain", "pipeline", "nightly"], ["Memory Stack"], .system),
            ("Memory Stack", "01-Permanent/Systems/Memory Stack.md", ["memory", "anima", "claude-mem"], [], .system),
            ("Tailscale Fleet", "01-Permanent/Systems/Tailscale Fleet.md", ["tailscale", "network", "fleet"], [], .system),
            ("Vault Health Report", "01-Permanent/Resources/Vault Health.md", ["health", "report", "obsidian"], [], .resource),
        ]
        for (title, path, tags, links, cat) in sampleData {
            notes.append(VaultNote(
                relativePath: path, title: title, tags: tags, wikilinks: links,
                paraCategory: cat, modifiedDate: Date(timeIntervalSince1970: 1755100000),
                orphaned: links.isEmpty
            ))
        }
        let inv = VaultInventory(vaultRoot: "~/Documents/MyVault", notes: notes, scannedAt: Date(timeIntervalSince1970: 1755100000))
        snapViewBoth(
            OracleViewWithData(inventory: inv),
            named: "oracle_data", width: 900, height: 600
        )
    }
}

@Suite("Functional — Health with Data")
@MainActor
struct HealthDataSnapshots {
    @Test("Health populated")
    func healthWithData() {
        let report = HealthReport(
            vaultRoot: "~/Documents/MyVault",
            checks: [
                HealthCheck(name: "Vault Staleness", status: .healthy, message: "Latest entry was 1 day ago", affectedCount: 0),
                HealthCheck(name: "Missing Frontmatter", status: .warning, message: "12 notes missing frontmatter", affectedCount: 12),
                HealthCheck(name: "Orphaned Notes", status: .warning, message: "3 of 7 notes are orphaned", affectedCount: 3),
                HealthCheck(name: "Broken Wikilinks", status: .healthy, message: "All wikilinks resolve", affectedCount: 0),
                HealthCheck(name: "Tag Consistency", status: .healthy, message: "No duplicate variants", affectedCount: 0),
                HealthCheck(name: "Inbox Backlog", status: .healthy, message: "0 notes in inbox", affectedCount: 0),
                HealthCheck(name: "Digest Integrity", status: .healthy, message: "All digests present", affectedCount: 0),
            ]
        )
        snapViewBoth(
            HealthViewWithData(report: report),
            named: "health_data", width: 900, height: 600
        )
    }
}

// MARK: - Data-injected view wrappers (for snapshot testing)

struct OracleViewWithData: View {
    let inventory: VaultInventory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oracle").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Explore connections, gaps, and relationships").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 12) {
                    HydraStatCard(title: "Notes", value: "\(inventory.noteCount)", icon: "doc.text.fill")
                    HydraStatCard(title: "Tags", value: "\(inventory.tagFrequency.count)", icon: "tag.fill", accentColor: .hydraLive)
                    HydraStatCard(title: "Orphans", value: "\(inventory.orphanedNotes.count)", icon: "questionmark.circle.fill", accentColor: .hydraAlert ?? .red)
                    HydraStatCard(title: "Broken Links", value: "\(inventory.brokenWikilinks.count)", icon: "link.badge.plus", accentColor: .hydraPartial)
                }
                .padding(.horizontal, 24)

                HydraPanel(title: "Top Tags", icon: "tag.fill") {
                    VStack(spacing: 6) {
                        ForEach(inventory.tagFrequency.prefix(10), id: \.tag) { item in
                            HStack(spacing: 10) {
                                Text("#\(item.tag)").font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraAccent)
                                Spacer()
                                Text("\(item.count)").font(HydraTheme.mono(.caption2, weight: .bold)).foregroundStyle(Color.hydraMuted)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                if !inventory.orphanedNotes.isEmpty {
                    HydraPanel(title: "Orphaned Notes (\(inventory.orphanedNotes.count))", icon: "questionmark.circle.fill") {
                        VStack(spacing: 6) {
                            ForEach(inventory.orphanedNotes.prefix(5)) { note in
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text").foregroundStyle(.red.opacity(0.7)).font(.system(size: 11))
                                    Text(note.title.isEmpty ? note.relativePath : note.title).font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraInk).lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
    }
}

struct HealthViewWithData: View {
    let report: HealthReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vault Health").font(HydraTheme.display(.largeTitle)).foregroundStyle(Color.hydraInk)
                        Text("Diagnostics and maintenance").font(HydraTheme.mono(.subheadline)).foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 24)

                HStack(spacing: 12) {
                    HydraStatCard(title: "Healthy", value: "\(report.checks.filter { $0.status == HydraHealth.HealthStatus.healthy }.count)", icon: "checkmark.circle.fill", accentColor: .hydraLive)
                    HydraStatCard(title: "Warnings", value: "\(report.checks.filter { $0.status == HydraHealth.HealthStatus.warning }.count)", icon: "exclamationmark.triangle.fill", accentColor: .hydraPartial)
                    HydraStatCard(title: "Critical", value: "\(report.checks.filter { $0.status == HydraHealth.HealthStatus.critical }.count)", icon: "xmark.octagon.fill", accentColor: .red)
                }
                .padding(.horizontal, 24)

                HydraPanel(title: "Checks", icon: "stethoscope") {
                    VStack(spacing: 12) {
                        ForEach(report.checks) { check in
                            HStack(spacing: 12) {
                                Image(systemName: check.status == HydraHealth.HealthStatus.healthy ? "checkmark.circle.fill" : check.status == HydraHealth.HealthStatus.warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(check.status == HydraHealth.HealthStatus.healthy ? Color.hydraLive : check.status == HydraHealth.HealthStatus.warning ? Color.hydraPartial : .red)
                                    .font(.system(size: 14))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.name).font(HydraTheme.mono(.callout, weight: .semibold)).foregroundStyle(Color.hydraInk)
                                    Text(check.message).font(HydraTheme.mono(.caption)).foregroundStyle(Color.hydraMuted)
                                }
                                Spacer()
                                if check.affectedCount > 0 {
                                    Text("\(check.affectedCount)")
                                        .font(HydraTheme.mono(.callout, weight: .bold))
                                        .foregroundStyle(check.status == HydraHealth.HealthStatus.warning ? Color.hydraPartial : .red)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill((check.status == HydraHealth.HealthStatus.warning ? Color.hydraPartial : Color.red).opacity(0.1)))
                                } else {
                                    Image(systemName: "checkmark").foregroundStyle(Color.hydraLive).font(.system(size: 14))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .background(Color.hydraVoid)
    }
}

// MARK: - Dry Run Preview (what WILL be created)

@Suite("Dry Run Preview")
@MainActor
struct DryRunPreviewSnapshots {

    @Test("Artifact previews")
    func dryRunPreview() {
        snapView(
            ScrollView { DryRunPreviewView(artifacts: DryRunSampleData.artifacts, vaultPath: DryRunSampleData.vaultPath) }
                .background(Color.hydraVoid),
            named: "dryrun_preview", width: 900, height: 600
        )
    }
}

// MARK: - Before/After Graph Comparison

@Suite("Before/After Graph")
@MainActor
struct BeforeAfterGraphSnapshots {

    @Test("Before hydration (scattered, disconnected)")
    func graphBefore() {
        let nodes: [GraphNode] = [
            GraphNode(id: "a", label: "AI-IDE Setup", position: SIMD2<Float>(200, 150), velocity: .zero, radius: 10, color: GraphNodeKind.session.baseColor, kind: .session),
            GraphNode(id: "b", label: "Agent Workflow", position: SIMD2<Float>(500, 200), velocity: .zero, radius: 9, color: GraphNodeKind.session.baseColor, kind: .session),
            GraphNode(id: "c", label: "Brain Cluster", position: SIMD2<Float>(350, 400), velocity: .zero, radius: 8, color: GraphNodeKind.session.baseColor, kind: .session),
            GraphNode(id: "d", label: "Copilot Setup", position: SIMD2<Float>(700, 350), velocity: .zero, radius: 9, color: GraphNodeKind.session.baseColor, kind: .session),
            GraphNode(id: "e", label: "Fork Repo", position: SIMD2<Float>(150, 350), velocity: .zero, radius: 7, color: GraphNodeKind.session.baseColor, kind: .session),
        ]
        // Before: only 1 weak link — mostly orphans
        let edges: [GraphEdge] = [
            GraphEdge(id: "e1", source: "a", target: "b", strength: 0.2, type: .relatesTo),
        ]
        snapView(BeforeAfterGraphView(state: .before, nodes: nodes, edges: edges), named: "graph_before", width: 900, height: 600)
    }

    @Test("After hydration (connected, tagged, linked)")
    func graphAfter() {
        let nodes: [GraphNode] = [
            GraphNode(id: "a", label: "AI-IDE Setup", position: SIMD2<Float>(300, 250), velocity: .zero, radius: 14, color: GraphNodeKind.plan.baseColor, kind: .plan),
            GraphNode(id: "b", label: "Agent Workflow", position: SIMD2<Float>(500, 300), velocity: .zero, radius: 12, color: GraphNodeKind.plan.baseColor, kind: .plan),
            GraphNode(id: "c", label: "Hydra Architecture", position: SIMD2<Float>(450, 200), velocity: .zero, radius: 16, color: GraphNodeKind.plan.baseColor, kind: .plan),
            GraphNode(id: "d", label: "Copilot Setup", position: SIMD2<Float>(600, 180), velocity: .zero, radius: 10, color: GraphNodeKind.decision.baseColor, kind: .decision),
            GraphNode(id: "e", label: "Fork Repo", position: SIMD2<Float>(200, 350), velocity: .zero, radius: 8, color: GraphNodeKind.session.baseColor, kind: .session),
            GraphNode(id: "f", label: "Brain Cluster", position: SIMD2<Float>(350, 400), velocity: .zero, radius: 9, color: GraphNodeKind.session.baseColor, kind: .session),
        ]
        // After: rich typed connections
        let edges: [GraphEdge] = [
            GraphEdge(id: "e1", source: "a", target: "c", strength: 0.9, type: .derivedFrom),
            GraphEdge(id: "e2", source: "b", target: "a", strength: 0.7, type: .relatesTo),
            GraphEdge(id: "e3", source: "c", target: "d", strength: 0.6, type: .references),
            GraphEdge(id: "e4", source: "c", target: "b", strength: 0.8, type: .implements),
            GraphEdge(id: "e5", source: "e", target: "a", strength: 0.5, type: .references),
            GraphEdge(id: "e6", source: "f", target: "c", strength: 0.4, type: .relatesTo),
        ]
        snapView(BeforeAfterGraphView(state: .after, nodes: nodes, edges: edges), named: "graph_after", width: 900, height: 600)
    }
}

// MARK: - Full App

@Suite("E2E — Vault Scan")
@MainActor
struct E2EScanSnapshots {
    @Test("Scan results")
    func scanResults() {
        snapView(
            ScrollView { VaultScanResultsView(result: E2ESampleData.scanResult) }
                                .background(Color.hydraVoid),
            named: "e2e_scan", width: 800, height: 500
        )
    }
}

@Suite("E2E — Health Check")
@MainActor
struct E2EHealthSnapshots {
    @Test("Health results")
    func healthResults() {
        snapView(
            ScrollView { HealthResultsView(checks: E2ESampleData.healthChecks) }
                                .background(Color.hydraVoid),
            named: "e2e_health", width: 800, height: 500
        )
    }
}

@Suite("E2E — Search")
@MainActor
struct E2ESearchSnapshots {
    @Test("Search results")
    func searchResults() {
        snapView(
            ScrollView { SearchResultsView(query: "andromeda", results: E2ESampleData.searchResults) }
                                .background(Color.hydraVoid),
            named: "e2e_search", width: 800, height: 500
        )
    }
}

@Suite("Full App Window")
@MainActor
struct FullAppSnapshots {
    @Test("Light + dark")
    func fullApp() {
        snapViewBoth(ContentView(), named: "fullapp", width: 1000, height: 650)
    }
}

// MARK: - Dry Run Preview

@Suite("Dry Run Preview")
@MainActor
struct DryRunSnapshots {
    @Test("Full dry run — all artifacts")
    func dryRunFull() {
        snapView(
            ScrollView { DryRunPreviewView(artifacts: DryRunSampleData.artifacts, vaultPath: DryRunSampleData.vaultPath) }
                                .background(Color.hydraVoid),
            named: "dry_run_preview", width: 800, height: 600
        )
    }
}

// MARK: - Animation Gallery

@Suite("Hydra Animations")
@MainActor
struct AnimationGallerySnapshots {
    @Test("Core animation stack")
    func animationCore() {
        snapView(
            VStack(spacing: 24) {
                HydraHUDCore()
                HStack(spacing: 20) {
                    HydraLivePulse()
                    HydraBreathingRing()
                    HydraScanSweep()
                }
                HydraRecallWaveform()
                HydraShimmerSkeleton()
            }
            .frame(width: 400, height: 300)
            .background(Color.hydraVoid),
            named: "animation_core", width: 400, height: 300
        )
    }
}

// MARK: - Helpers

func defaultColor(for axis: ColorAxis) -> VaultColor {
    switch axis {
    case .project: .projectWarm
    case .type: .typeCool
    case .status: .statusGreen
    case .integration: .integrationPurple
    case .severity: .severityInfo
    }
}
