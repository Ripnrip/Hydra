import SwiftUI
import HydraCore
import HydraVault
import HydraHealth

// MARK: - E2E Demo Views

/// Deterministic sample data from real SecondBrain vault scan (2026-08-13).
/// These mirror the CLI output so snapshots show the actual e2e flow results.
enum E2ESampleData {
    static let vaultPath = "~/Developer/SecondBrain"

    static let scanResult = VaultScanResult(
        noteCount: 331,
        tagCount: 685,
        paraBreakdown: [
            (.session, 204), (.other, 61), (.journal, 29),
            (.concept, 9), (.system, 9), (.project, 8),
            (.template, 7), (.area, 1), (.resource, 1),
            (.daily, 1), (.moc, 1),
        ],
        orphanedCount: 304,
        brokenWikilinks: 927,
        missingFrontmatter: 52
    )

    static let healthChecks: [E2EHealthCheck] = [
        .init(name: "Vault Staleness", status: .healthy, message: "Latest entry was 1 days ago", icon: "clock.fill"),
        .init(name: "Missing Frontmatter", status: .warning, message: "52 notes missing frontmatter", icon: "doc.badge.gearshape.fill"),
        .init(name: "Orphaned Notes", status: .warning, message: "304 of 331 notes are orphaned (no incoming links)", icon: "ant.fill"),
        .init(name: "Broken Wikilinks", status: .warning, message: "927 broken wikilinks: .env, .env.local, .eslintrc.json…", icon: "link.badge.plus"),
        .init(name: "Tag Consistency", status: .healthy, message: "No duplicate tag variants detected", icon: "tag.fill"),
        .init(name: "Inbox Backlog", status: .healthy, message: "0 notes in inbox", icon: "tray.fill"),
        .init(name: "Digest Integrity", status: .healthy, message: "All digests present", icon: "checkmark.seal.fill"),
    ]

    static let searchResults: [E2ESearchResult] = [
        .init(title: "Andromeda Control Plane", path: "01-Permanent/Systems/Andromeda Control Plane.md", tags: ["andromeda", "anima", "control-plane"]),
        .init(title: "Session — Swift package hierarchy", path: "07-Sessions/2026-07-21--swift-package-hierarchy--cursor.md", tags: []),
        .init(title: "Oura IPA lab: ipatool → extract", path: "07-Sessions/2026-07-23--research-sec-oura-ipatool--grok.md", tags: ["andromeda-adjacent", "ios", "ipa"]),
        .init(title: "Visible Alpha Residual Wave Closeout", path: "07-Sessions/2026-07-17--anima-residual-wave-closeout--cursor.md", tags: ["closeout", "visible-alpha"]),
        .init(title: "Visible Alpha — Capability Curtain", path: "07-Sessions/2026-07-15--anima-visible-alpha--cursor.md", tags: ["andromeda", "anima", "mcp"]),
    ]
}

// MARK: - Data Types

struct VaultScanResult: Identifiable {
    let id = UUID()
    let noteCount: Int
    let tagCount: Int
    let paraBreakdown: [(PARACategory, Int)]
    let orphanedCount: Int
    let brokenWikilinks: Int
    let missingFrontmatter: Int
}

struct E2EHealthCheck: Identifiable {
    let id = UUID()
    let name: String
    let status: E2EHealthStatus
    let message: String
    let icon: String
}

enum E2EHealthStatus {
    case healthy, warning, critical

    var color: Color {
        switch self {
        case .healthy: Color.hydraLive
        case .warning: Color.hydraPartial
        case .critical: Color.red
        }
    }

    var icon: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .healthy: "HEALTHY"
        case .warning: "WARNING"
        case .critical: "CRITICAL"
        }
    }
}

struct E2ESearchResult: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    let tags: [String]
}

// MARK: - Vault Scan Results View

struct VaultScanResultsView: View {
    let result: VaultScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header stats
            HStack(spacing: 12) {
                HydraStatCard(title: "Notes", value: "\(result.noteCount)", icon: "doc.text.fill", accentColor: .hydraAccent)
                HydraStatCard(title: "Tags", value: "\(result.tagCount)", icon: "tag.fill", accentColor: .hydraLive)
                HydraStatCard(title: "Orphaned", value: "\(result.orphanedCount)", icon: "ant.fill", accentColor: .hydraPartial)
                HydraStatCard(title: "Broken Links", value: "\(result.brokenWikilinks)", icon: "link.badge.plus", accentColor: .hydraPartial)
            }

            // PARA breakdown
            HydraPanel(title: "PARA Breakdown", icon: "square.grid.2x2.fill") {
                VStack(spacing: 4) {
                    ForEach(result.paraBreakdown, id: \.0) { category, count in
                        HStack {
                            Circle()
                                .fill(Color.hydraAccent.opacity(0.6))
                                .frame(width: 6, height: 6)
                            Text(category.paraLabel)
                                .font(HydraTheme.mono(.caption))
                                .foregroundStyle(Color.hydraInk)
                            Spacer()
                            Text("\(count)")
                                .font(HydraTheme.mono(.caption, weight: .semibold))
                                .foregroundStyle(Color.hydraAccent)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .padding(24)
    }
}

extension PARACategory {
    var paraLabel: String {
        switch self {
        case .session: "07-Sessions"
        case .project: "Projects"
        case .area: "Areas"
        case .resource: "Resources"
        case .archive: "Archives"
        case .concept: "Concepts"
        case .system: "Systems"
        case .journal: "06-Journal"
        case .daily: "02-Daily"
        case .template: "Templates"
        case .moc: "Maps of Content"
        case .inbox: "Inbox"
        case .other: "Other"
        case .asset: "Assets"
        }
    }
}

// MARK: - Health Results View

struct HealthResultsView: View {
    let checks: [E2EHealthCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Overall status banner
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.hydraPartial)
                Text("WARNING")
                    .font(HydraTheme.mono(.title3, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.hydraPartial)
                Text("4 healthy · 3 warnings · 0 critical")
                    .font(HydraTheme.mono(.caption))
                    .foregroundStyle(Color.hydraMuted)
                Spacer()
            }
            .padding(12)
            .background(Color.hydraPartial.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            // Check list
            ForEach(checks) { check in
                HealthCheckRow(check: check)
            }
        }
        .padding(24)
    }
}

struct HealthCheckRow: View {
    let check: E2EHealthCheck

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: check.status.icon)
                .foregroundStyle(check.status.color)
                .font(.system(size: 14))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(HydraTheme.mono(.callout, weight: .semibold))
                    .foregroundStyle(Color.hydraInk)
                Text(check.message)
                    .font(HydraTheme.mono(.caption))
                    .foregroundStyle(Color.hydraMuted)
            }

            Spacer()

            Text(check.status.label)
                .font(HydraTheme.mono(.caption2, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(check.status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(check.status.color.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.hydraPanel.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Search Results View

struct SearchResultsView: View {
    let query: String
    let results: [E2ESearchResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.hydraAccent)
                Text("\"\(query)\"")
                    .font(HydraTheme.mono(.headline))
                    .foregroundStyle(Color.hydraInk)
                Text("\(results.count) results")
                    .font(HydraTheme.mono(.caption))
                    .foregroundStyle(Color.hydraMuted)
                Spacer()
            }

            // Results list
            ForEach(results) { result in
                SearchResultRow(result: result)
            }
        }
        .padding(24)
    }
}

struct SearchResultRow: View {
    let result: E2ESearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.hydraAccent.opacity(0.7))
                    .font(.system(size: 11))
                Text(result.title)
                    .font(HydraTheme.mono(.callout, weight: .medium))
                    .foregroundStyle(Color.hydraInk)
                Spacer()
            }
            Text(result.path)
                .font(HydraTheme.mono(.caption2))
                .foregroundStyle(Color.hydraMuted)

            if !result.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(result.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 8, design: .monospaced).weight(.medium))
                            .foregroundStyle(Color.hydraAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.hydraAccent.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .padding(10)
        .background(Color.hydraPanel.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
