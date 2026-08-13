import SwiftUI
import HydraCore

// MARK: - Backfill Configuration

/// All the knobs a human tunes before a backfill run.
/// Date range, sources, exclusions, classification thresholds, destination.
@MainActor
final class BackfillConfig: ObservableObject {
    // Date range
    @Published var dateFrom: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @Published var dateTo: Date = Date()
    @Published var useDateRange: Bool = true

    // Sources
    @Published var sources: [SourceToggle]
    @Published var customSourcePath: String = ""

    // Exclusions
    @Published var excludeTags: [String] = ["secret", "credential", "api-key"]
    @Published var excludePaths: [String] = []
    @Published var excludeDrafts: Bool = false
    @Published var excludeArchived: Bool = false
    @Published var excludePathsInput: String = ""

    // Classification
    @Published var autoClassifyThreshold: Double = 0.7
    @Published var requireHumanReview: Bool = true
    @Published var proposeNewTags: Bool = true

    // Relationships
    @Published var inferRelationships: Bool = true
    @Published var rescueOrphans: Bool = true
    @Published var fixBrokenLinks: Bool = true

    // Destination
    @Published var writeMode: WriteMode = .dryRun
    @Published var exportObsidian: Bool = true
    @Published var exportJSON: Bool = false

    init() {
        sources = SourceToggle.defaults
    }

    var activeSourceCount: Int { sources.filter { $0.enabled }.count }
    var excludedCount: Int { excludeTags.count + excludePaths.count + (excludeDrafts ? 1 : 0) + (excludeArchived ? 1 : 0) }
}

enum WriteMode: String, CaseIterable {
    case dryRun = "Dry Run"
    case write = "Write to Vault"
}

struct SourceToggle: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let path: String
    var enabled: Bool
    let count: Int?

    static let defaults: [SourceToggle] = [
        .init(name: "Claude Plans", icon: "doc.text.fill", path: "~/.claude/plans", enabled: true, count: 2),
        .init(name: "Claude Sessions", icon: "bubble.left.fill", path: "~/.claude/projects", enabled: true, count: nil),
        .init(name: "Codex Sessions", icon: "terminal.fill", path: "~/.codex", enabled: false, count: nil),
        .init(name: "Git History", icon: "arrow.triangle.branch", path: "git log --since", enabled: true, count: 47),
        .init(name: "Changelog", icon: "list.bullet.rectangle.fill", path: "CHANGELOG.md", enabled: true, count: nil),
        .init(name: "claude-mem", icon: "cylinder.split.3x1.fill", path: "~/.claude-mem", enabled: false, count: nil),
        .init(name: "Obsidian Vault", icon: "book.fill", path: "~/Developer/SecondBrain", enabled: false, count: 155),
    ]
}

// MARK: - Backfill Config View

/// The full configuration panel for a backfill run.
/// Answers: what date range? which sources? what to exclude? how confident? where to write?
struct BackfillConfigView: View {
    @StateObject private var config = BackfillConfig()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection
                statsRow

                // Date Range
                HydraPanel(title: "Date Range", icon: "calendar.badge.clock") {
                    dateRangeContent
                }

                // Sources
                HydraPanel(title: "Sources (\(config.activeSourceCount) active)", icon: "square.stack.3d.up.fill") {
                    sourcesContent
                }

                // Exclusions
                HydraPanel(title: "Exclusions (\(config.excludedCount) rules)", icon: "hand.raised.fill") {
                    exclusionsContent
                }

                // Classification
                HydraPanel(title: "Classification", icon: "wand.and.stars") {
                    classificationContent
                }

                // Relationships
                HydraPanel(title: "Relationships", icon: "link.circle.fill") {
                    relationshipsContent
                }

                // Write Mode
                HydraPanel(title: "Output", icon: "internaldrive.fill") {
                    outputContent
                }

                // Action
                HStack {
                    Spacer()
                    HydraButton(
                        config.writeMode == .dryRun ? "Preview Dry Run" : "Run Backfill",
                        icon: config.writeMode == .dryRun ? "eye.fill" : "drop.fill"
                    ) {}
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .background(Color.hydraVoid)
    }

    // MARK: Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Backfill Configuration")
                    .font(HydraTheme.display(.largeTitle))
                    .foregroundStyle(Color.hydraInk)
                Text("Tune exactly what gets hydrated — dates, sources, exclusions, thresholds")
                    .font(HydraTheme.mono(.subheadline))
                    .foregroundStyle(Color.hydraMuted)
            }
            Spacer()
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            HydraStatCard(title: "Sources", value: "\(config.activeSourceCount)", icon: "square.stack.3d.up.fill")
            HydraStatCard(title: "Window", value: windowLabel, icon: "calendar", accentColor: .hydraPartial)
            HydraStatCard(title: "Excluded", value: "\(config.excludedCount)", icon: "hand.raised.fill", accentColor: .hydraAlert)
            HydraStatCard(title: "Threshold", value: "\(Int(config.autoClassifyThreshold * 100))%", icon: "chart.bar.fill", accentColor: .hydraLive)
        }
    }

    private var windowLabel: String {
        guard config.useDateRange else { return "ALL" }
        let days = Calendar.current.dateComponents([.day], from: config.dateFrom, to: config.dateTo).day ?? 0
        return "\(days)d"
    }

    // MARK: Date Range

    private var dateRangeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HydraToggle(label: "Limit to date range", isOn: $config.useDateRange)
                Spacer()
            }

            if config.useDateRange {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FROM")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Color.hydraMuted)
                        DatePicker("", selection: $config.dateFrom, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                            .tint(Color.hydraAccent)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.hydraMuted)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TO")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(Color.hydraMuted)
                        DatePicker("", selection: $config.dateTo, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                            .tint(Color.hydraAccent)
                    }

                    Spacer()

                    // Quick presets
                    HStack(spacing: 6) {
                        presetButton("7d", days: 7)
                        presetButton("30d", days: 30)
                        presetButton("90d", days: 90)
                        presetButton("ALL", days: nil)
                    }
                }
            }
        }
    }

    private func presetButton(_ label: String, days: Int?) -> some View {
        Button(label) {
            if let days {
                config.dateFrom = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                config.useDateRange = true
            } else {
                config.useDateRange = false
            }
        }
        .font(HydraTheme.mono(.caption2, weight: .semibold))
        .foregroundStyle(Color.hydraAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.hydraAccent.opacity(0.1)))
        .overlay(Capsule().strokeBorder(Color.hydraAccent.opacity(0.3), lineWidth: 1))
        .buttonStyle(.plain)
    }

    // MARK: Sources

    private var sourcesContent: some View {
        VStack(spacing: 6) {
            ForEach($config.sources) { $source in
                HStack(spacing: 12) {
                    HydraToggle(isOn: $source.enabled)
                    Image(systemName: source.icon)
                        .foregroundStyle(source.enabled ? Color.hydraAccent : Color.hydraMuted)
                        .font(.system(size: 13))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(HydraTheme.mono(.callout))
                            .foregroundStyle(source.enabled ? Color.hydraInk : Color.hydraMuted)
                        Text(source.path)
                            .font(HydraTheme.mono(.caption2))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                    if let count = source.count {
                        Text("\(count)")
                            .font(HydraTheme.mono(.caption2, weight: .bold))
                            .foregroundStyle(Color.hydraMuted)
                    }
                }
                .padding(.vertical, 4)
            }

            // Custom source
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.hydraAccent)
                    .font(.system(size: 13))
                TextField("custom path or glob...", text: $config.customSourcePath)
                    .textFieldStyle(HydraFieldStyle())
            }
            .padding(.top, 8)
        }
    }

    // MARK: Exclusions

    private var exclusionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HydraToggle(label: "Exclude drafts", isOn: $config.excludeDrafts)
            HydraToggle(label: "Exclude archived", isOn: $config.excludeArchived)

            Divider().background(Color.hydraLine)

            // Tag exclusions
            VStack(alignment: .leading, spacing: 6) {
                Text("EXCLUDE TAGS")
                    .font(HydraTheme.mono(.caption2, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.hydraMuted)
                FlowLayout(spacing: 6) {
                    ForEach(config.excludeTags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                            Text(tag)
                                .font(HydraTheme.mono(.caption2, weight: .medium))
                        }
                        .foregroundStyle(Color.hydraAlert)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.hydraAlert.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(Color.hydraAlert.opacity(0.3), lineWidth: 1))
                        .onTapGesture {
                            config.excludeTags.removeAll { $0 == tag }
                        }
                    }
                }
            }

            // Path exclusions
            VStack(alignment: .leading, spacing: 6) {
                Text("EXCLUDE PATHS")
                    .font(HydraTheme.mono(.caption2, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.hydraMuted)
                HStack(spacing: 8) {
                    TextField("path or glob pattern...", text: $config.excludePathsInput)
                        .textFieldStyle(HydraFieldStyle())
                    Button("Add") {
                        let trimmed = config.excludePathsInput.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            config.excludePaths.append(trimmed)
                            config.excludePathsInput = ""
                        }
                    }
                    .font(HydraTheme.mono(.caption, weight: .semibold))
                    .foregroundStyle(Color.hydraAccent)
                    .buttonStyle(.plain)
                }
                ForEach(config.excludePaths, id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.minus")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hydraAlert)
                        Text(path)
                            .font(HydraTheme.mono(.caption))
                            .foregroundStyle(Color.hydraMuted)
                        Spacer()
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.hydraMuted)
                            .onTapGesture { config.excludePaths.removeAll { $0 == path } }
                    }
                }
            }
        }
    }

    // MARK: Classification

    private var classificationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HydraToggle(label: "Require human review below threshold", isOn: $config.requireHumanReview)
            HydraToggle(label: "Propose new tags (vs. existing-only)", isOn: $config.proposeNewTags)

            Divider().background(Color.hydraLine)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AUTO-CLASSIFY THRESHOLD")
                        .font(HydraTheme.mono(.caption2, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.hydraMuted)
                    Spacer()
                    Text("\(Int(config.autoClassifyThreshold * 100))%")
                        .font(HydraTheme.mono(.callout, weight: .bold))
                        .foregroundStyle(thresholdColor)
                }
                Slider(value: $config.autoClassifyThreshold, in: 0.3...0.95)
                    .tint(thresholdColor)
                Text("Items above this confidence auto-classify. Below → human review queue.")
                    .font(HydraTheme.mono(.caption2))
                    .foregroundStyle(Color.hydraMuted)
            }
        }
    }

    private var thresholdColor: Color {
        if config.autoClassifyThreshold >= 0.8 { .hydraLive }
        else if config.autoClassifyThreshold >= 0.5 { .hydraPartial }
        else { .hydraAlert }
    }

    // MARK: Relationships

    private var relationshipsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HydraToggle(label: "Infer typed relationships", isOn: $config.inferRelationships)
            HydraToggle(label: "Rescue orphaned notes (add links to disconnected notes)", isOn: $config.rescueOrphans)
            HydraToggle(label: "Fix broken wikilinks", isOn: $config.fixBrokenLinks)
        }
    }

    // MARK: Output

    private var outputContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(WriteMode.allCases, id: \.self) { mode in
                    Button {
                        config.writeMode = mode
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .dryRun ? "eye.fill" : "internaldrive.fill")
                                .font(.system(size: 12))
                            Text(mode.rawValue)
                                .font(HydraTheme.mono(.callout, weight: .semibold))
                        }
                        .foregroundStyle(config.writeMode == mode ? Color.hydraVoid : Color.hydraMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            config.writeMode == mode
                                ? AnyShapeStyle(Color.hydraAccent)
                                : AnyShapeStyle(Color.hydraCard)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Color.hydraLine)

            HydraToggle(label: "Export to Obsidian vault", isOn: $config.exportObsidian)
            HydraToggle(label: "Export JSON-LD graph", isOn: $config.exportJSON)
        }
    }
}

// MARK: - Hydra Toggle

struct HydraToggle: View {
    var label: String?
    @Binding var isOn: Bool

    init(label: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? Color.hydraAccent : Color.hydraMuted.opacity(0.2))
                .frame(width: 38, height: 22)
                .overlay(
                    Circle()
                        .fill(isOn ? Color.hydraVoid : Color.hydraMuted)
                        .frame(width: 16, height: 16)
                        .offset(x: isOn ? 8 : -8)
                )
                .onTapGesture { isOn.toggle() }

            if let label {
                Text(label)
                    .font(HydraTheme.mono(.callout))
                    .foregroundStyle(Color.hydraInk)
                    .onTapGesture { isOn.toggle() }
            }
        }
    }
}
