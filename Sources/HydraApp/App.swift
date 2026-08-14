import SwiftUI
import HydraCore
import HydraVault
import HydraHealth

@main
struct HydraAppMain: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 650)
                .background(Color.hydraVoid)
        }
    }
}

enum AppTab: String, CaseIterable {
    case hydrate, vault, oracle, health
}

// MARK: - Root View

struct ContentView: View {
    @State private var selectedTab: AppTab = .hydrate

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                // Logo
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.hydraAccent)
                        .shadow(color: Color.hydraAccent.opacity(0.6), radius: 6)
                    Text("HYDRA")
                        .font(HydraTheme.mono(.title3, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(Color.hydraInk)
                }
                .padding(.vertical, 20)

                Divider()
                    .background(Color.hydraLine)

                // Nav items
                VStack(spacing: 4) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        SidebarItem(
                            icon: tab.icon,
                            label: tab.label,
                            isActive: selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.top, 16)

                Spacer()

                // Footer
                HStack(spacing: 4) {
                    HydraStatusDot(color: .hydraLive, pulsing: true)
                    Text("ONLINE")
                        .font(HydraTheme.mono(.caption2, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.hydraMuted)
                }
                .padding(.bottom, 16)
            }
            .frame(width: 200)
            .background(Color.hydraPanel)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .background(Color.hydraLine),
                alignment: .trailing
            )

            // Content
            Group {
                switch selectedTab {
                case .hydrate: HydrationView()
                case .vault: VaultExplorerView()
                case .oracle: OracleView()
                case .health: HealthView()
                }
            }
            .background(Color.hydraVoid)
        }
    }
}

extension AppTab {
    var icon: String {
        switch self {
        case .hydrate: "drop.fill"
        case .vault: "archivebox.fill"
        case .oracle: "brain.head.profile.fill"
        case .health: "heart.text.square.fill"
        }
    }
    var label: String {
        switch self {
        case .hydrate: "Hydrate"
        case .vault: "Vault"
        case .oracle: "Oracle"
        case .health: "Health"
        }
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? Color.hydraAccent : Color.hydraMuted)
                    .frame(width: 20)
                Text(label)
                    .font(HydraTheme.mono(.callout, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.hydraInk : Color.hydraMuted)
                Spacer()
                if isActive {
                    Rectangle()
                        .fill(Color.hydraAccent)
                        .frame(width: 3)
                        .padding(.vertical, -4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isActive ? Color.hydraSelection : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hydration Tab

struct HydrationView: View {
    @State private var vaultPath = "~/Documents/MyVault"
    @State private var sourcePath = "~/.claude/plans"
    @State private var isHydrating = false
    @State private var dryRun = true
    @State private var sourceKind: SourceKind = .claudePlans

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context Hydration")
                            .font(HydraTheme.display(.largeTitle))
                            .foregroundStyle(Color.hydraInk)
                        Text("Sources → enrich → vault → export")
                            .font(HydraTheme.mono(.subheadline))
                            .foregroundStyle(Color.hydraMuted)
                            .tracking(0.5)
                    }
                    Spacer()
                    HydraStatCard(title: "Vault Notes", value: "168", icon: "doc.text.fill")
                        .frame(width: 140)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                // Stats row
                HStack(spacing: 12) {
                    HydraStatCard(title: "Sources", value: "9", icon: "square.stack.3d.up.fill", accentColor: .hydraAccent)
                    HydraStatCard(title: "Tags", value: "685", icon: "tag.fill", accentColor: .hydraLive)
                    HydraStatCard(title: "Pending", value: "0", icon: "tray.fill", accentColor: .hydraPartial)
                    HydraStatCard(title: "Health", value: "98%", icon: "checkmark.shield.fill", accentColor: .hydraLive)
                }
                .padding(.horizontal, 24)

                // Source config
                HydraPanel(title: "Source", icon: "square.and.arrow.down.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        HydraFieldRow(label: "Path", value: $sourcePath)
                        HydraFieldRow(label: "Kind", picker: true, sourceKind: $sourceKind)
                    }
                }
                .padding(.horizontal, 24)

                // Vault config
                HydraPanel(title: "Vault", icon: "archivebox.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        HydraFieldRow(label: "Root", value: $vaultPath)
                        HStack {
                            Toggle("", isOn: $dryRun)
                                .toggleStyle(HydraToggleStyle())
                                .labelsHidden()
                            Text("Dry Run")
                                .font(HydraTheme.mono(.callout))
                                .foregroundStyle(Color.hydraInk)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Export
                HydraPanel(title: "Export Destinations", icon: "arrow.up.forward.app.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        HydraExportRow(icon: "book.fill", label: "Obsidian Vault", enabled: true)
                        HydraExportRow(icon: "link.circle.fill", label: "JSON-LD Graph", enabled: false)
                        HydraExportRow(icon: "network.fill", label: "API Push", enabled: false)
                    }
                }
                .padding(.horizontal, 24)

                // Action
                HStack {
                    Spacer()
                    HydraButton("Hydrate", icon: "drop.fill") {
                        isHydrating = true
                    }
                    .disabled(isHydrating)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .background(Color.hydraVoid)
    }
}

struct HydraFieldRow: View {
    let label: String
    @Binding var value: String
    var picker: Bool = false
    @Binding var sourceKind: SourceKind

    init(label: String, value: Binding<String>) {
        self.label = label
        self._value = value
        self.picker = false
        self._sourceKind = .constant(.claudePlans)
    }

    init(label: String, picker: Bool, sourceKind: Binding<SourceKind>) {
        self.label = label
        self._value = .constant("")
        self.picker = picker
        self._sourceKind = sourceKind
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label.uppercased())
                .font(HydraTheme.mono(.caption, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.hydraMuted)
                .frame(width: 60, alignment: .leading)

            if picker {
                Picker("", selection: $sourceKind) {
                    ForEach(SourceKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.hydraAccent)
            } else {
                TextField("", text: $value)
                    .textFieldStyle(HydraFieldStyle())
            }
        }
    }
}

extension SourceKind {
    var displayName: String {
        switch self {
        case .claudePlans:    "Claude Plans"
        case .claudeSessions: "Claude Sessions"
        case .codexSessions:  "Codex Sessions"
        case .gitRepo:        "Git Repo"
        case .changelog:      "Changelog"
        case .claudeMem:      "Claude-mem"
        case .obsidianVault:  "Obsidian Vault"
        case .adHocFile:      "Ad-hoc File"
        case .apiStream:      "API Stream"
        }
    }
}

struct HydraFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(HydraTheme.mono(.callout))
            .foregroundStyle(Color.hydraInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.hydraVoid)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.hydraLine, lineWidth: 1)
            )
    }
}

struct HydraToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(configuration.isOn ? Color.hydraAccent : Color.hydraMuted.opacity(0.3))
                .frame(width: 36, height: 20)
                .overlay(
                    Circle()
                        .fill(Color.hydraInk)
                        .frame(width: 14, height: 14)
                        .offset(x: configuration.isOn ? 8 : -8)
                )
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

struct HydraExportRow: View {
    let icon: String
    let label: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(enabled ? Color.hydraAccent : Color.hydraMuted)
                .font(.system(size: 12))
                .frame(width: 16)
            Text(label)
                .font(HydraTheme.mono(.callout))
                .foregroundStyle(enabled ? Color.hydraInk : Color.hydraMuted)
            Spacer()
            HydraStatusDot(color: enabled ? .hydraLive : .hydraMuted)
        }
    }
}

// MARK: - Vault Explorer Tab

struct VaultExplorerView: View {
    @State private var inventory: VaultInventory?
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var vaultPath = "~/Documents/MyVault"

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.hydraMuted)
                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(HydraTheme.mono(.callout))
                    .foregroundStyle(Color.hydraInk)
            }
            .padding(10)
            .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 10))
            .padding()

            if isLoading {
                Spacer()
                ProgressView("Scanning vault...")
                    .tint(Color.hydraAccent)
                Spacer()
            } else if let inventory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Stats header
                        HStack(spacing: 12) {
                            statBadge("\(inventory.noteCount)", "Notes")
                            statBadge("\(inventory.tagFrequency.count)", "Tags")
                            statBadge("\(inventory.orphanedNotes.count)", "Orphaned")
                            statBadge("\(inventory.brokenWikilinks.count)", "Broken Links")
                        }

                        // Top tags
                        if !inventory.tagFrequency.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TOP TAGS")
                                    .font(HydraTheme.mono(.caption, weight: .semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(Color.hydraMuted)
                                ForEach(inventory.tagFrequency.prefix(15), id: \.tag) { item in
                                    HStack {
                                        Circle().fill(Color.hydraAccent.opacity(0.6)).frame(width: 5, height: 5)
                                        Text(item.tag)
                                            .font(HydraTheme.mono(.caption))
                                            .foregroundStyle(Color.hydraInk)
                                        Spacer()
                                        Text("\(item.count)")
                                            .font(HydraTheme.mono(.caption, weight: .semibold))
                                            .foregroundStyle(Color.hydraAccent)
                                    }
                                }
                            }
                        }

                        // Recent notes
                        if !filteredNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("RECENT NOTES")
                                    .font(HydraTheme.mono(.caption, weight: .semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(Color.hydraMuted)
                                ForEach(filteredNotes.prefix(20), id: \.id) { note in
                                    HStack {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundStyle(Color.hydraAccent.opacity(0.6))
                                            .font(.system(size: 11))
                                        VStack(alignment: .leading) {
                                            Text(note.title)
                                                .font(HydraTheme.mono(.caption, weight: .medium))
                                                .foregroundStyle(Color.hydraInk)
                                            Text(note.relativePath)
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundStyle(Color.hydraMuted)
                                        }
                                        Spacer()
                                        if note.orphaned {
                                            Image(systemName: "ant.fill")
                                                .foregroundStyle(Color.hydraPartial)
                                                .font(.system(size: 9))
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Button {
                        Task { await scanVault() }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.hydraAccent.opacity(0.6))
                            Text("Scan Your Vault")
                                .font(HydraTheme.display(.title))
                                .foregroundStyle(Color.hydraInk)
                            Text("Click to browse notes, tags, and relationships")
                                .font(HydraTheme.mono(.subheadline))
                                .foregroundStyle(Color.hydraMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .background(Color.hydraVoid)
    }

    private var filteredNotes: [VaultNote] {
        guard let inventory else { return [] }
        if searchText.isEmpty {
            return inventory.notes.sorted { $0.modifiedDate > $1.modifiedDate }
        }
        return inventory.notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    private func statBadge(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(HydraTheme.mono(.title3, weight: .bold)).foregroundStyle(Color.hydraAccent)
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.hydraMuted).tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func scanVault() async {
        isLoading = true
        let scanner = VaultScanner(vaultRoot: vaultPath.expandingTildeInPath)
        do {
            inventory = try await scanner.scan()
        } catch {
            // If real vault doesn't exist, show sample data
            inventory = sampleInventory
        }
        isLoading = false
    }

    // Fallback sample data if no vault is configured
    private var sampleInventory: VaultInventory {
        var notes: [VaultNote] = []
        let sampleTitles = ["System Architecture", "Package Dependencies", "Session Notes", "Anima Memory Stack",
                           "Multibrain Pipeline", "Tailscale Fleet", "Tag Optimization", "Vault Health Report"]
        for (i, title) in sampleTitles.enumerated() {
            notes.append(VaultNote(
                relativePath: "0\(i+1)-Permanent/Systems/\(title).md",
                title: title,
                tags: ["system", "architecture"],
                wikilinks: i > 0 ? ["System Architecture"] : [],
                paraCategory: .system,
                modifiedDate: Date().addingTimeInterval(TimeInterval(-i * 86400)),
                orphaned: i == 0
            ))
        }
        return VaultInventory(vaultRoot: vaultPath, notes: notes, scannedAt: Date())
    }
}

// MARK: - Path helper
extension String {
    var expandingTildeInPath: String {
        guard hasPrefix("~") else { return self }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + dropFirst()
    }
}

// MARK: - Oracle Tab

struct OracleView: View {
    @State private var inventory: VaultInventory?
    @State private var isLoading = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Color.hydraAccent)
                TextField("Ask the oracle...", text: $query)
                    .textFieldStyle(.plain)
                    .font(HydraTheme.mono(.callout))
                    .foregroundStyle(Color.hydraInk)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button("Search") { Task { await search() } }
                        .buttonStyle(.bordered)
                        .tint(Color.hydraAccent)
                }
            }
            .padding(10)
            .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 10))
            .padding()

            if isLoading {
                Spacer()
                HStack(spacing: 8) {
                    HydraScanSweep()
                    Text("Querying the graph...")
                        .font(HydraTheme.mono(.callout))
                        .foregroundStyle(Color.hydraMuted)
                }
                Spacer()
            } else if let inventory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Graph stats
                        HStack(spacing: 16) {
                            oracleStat("Nodes", "\(inventory.noteCount)")
                            oracleStat("Edges", "\(inventory.notes.reduce(0) { $0 + $1.wikilinks.count })")
                            oracleStat("Orphans", "\(inventory.orphanedNotes.count)")
                            oracleStat("Broken", "\(inventory.brokenWikilinks.count)")
                        }

                        // Adjacency preview
                        if !inventory.adjacencyList.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("CONNECTIONS")
                                    .font(HydraTheme.mono(.caption, weight: .semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(Color.hydraMuted)
                                ForEach(Array(inventory.adjacencyList.sorted { $0.value.count > $1.value.count }.prefix(10)), id: \.key) { node, links in
                                    HStack(spacing: 6) {
                                        Image(systemName: "circle.fill")
                                            .foregroundStyle(Color.hydraAccent)
                                            .font(.system(size: 6))
                                        Text(node)
                                            .font(HydraTheme.mono(.caption))
                                            .foregroundStyle(Color.hydraInk)
                                        Spacer()
                                        Text("\(links.count) links")
                                            .font(HydraTheme.mono(.caption2))
                                            .foregroundStyle(Color.hydraAccent)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.hydraCard, in: RoundedRectangle(cornerRadius: 10))
                        }

                        // Broken wikilinks (gaps)
                        if !inventory.brokenWikilinks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("BROKEN WIKILINKS (GAPS)")
                                    .font(HydraTheme.mono(.caption, weight: .semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(Color.hydraMuted)
                                ForEach(inventory.brokenWikilinks.prefix(15), id: \.self) { link in
                                    HStack(spacing: 4) {
                                        Image(systemName: "link.badge.plus")
                                            .foregroundStyle(Color.hydraPartial)
                                            .font(.system(size: 9))
                                        Text("[[\(link)]]")
                                            .font(HydraTheme.mono(.caption2))
                                            .foregroundStyle(Color.hydraInk.opacity(0.7))
                                    }
                                }
                                if inventory.brokenWikilinks.count > 15 {
                                    Text("+ \(inventory.brokenWikilinks.count - 15) more")
                                        .font(HydraTheme.mono(.caption2))
                                        .foregroundStyle(Color.hydraMuted)
                                }
                            }
                            .padding()
                            .background(Color.hydraCard, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                }
            } else {
                Spacer()
                Button { Task { await loadDefault() } } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.hydraAccent.opacity(0.6))
                        Text("Oracle")
                            .font(HydraTheme.display(.title))
                            .foregroundStyle(Color.hydraInk)
                        Text("Scan vault to see the relationship graph,\ngaps, and connection map.")
                            .font(HydraTheme.mono(.subheadline))
                            .foregroundStyle(Color.hydraMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .background(Color.hydraVoid)
    }

    private func oracleStat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(HydraTheme.mono(.title3, weight: .bold)).foregroundStyle(Color.hydraAccent)
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.hydraMuted).tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.hydraPanel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func search() async {
        isLoading = true
        // For now, just show the full inventory filtered by query
        if inventory == nil {
            await loadDefault()
        }
        isLoading = false
    }

    private func loadDefault() async {
        let path = "~/Documents/MyVault".expandingTildeInPath
        let scanner = VaultScanner(vaultRoot: path)
        do {
            inventory = try await scanner.scan()
        } catch {
            // Sample data fallback
            inventory = VaultInventory(vaultRoot: path, notes: [
                VaultNote(relativePath: "test.md", title: "Sample Note", wikilinks: ["Missing Link"], paraCategory: .system)
            ], scannedAt: Date())
        }
    }
}

// MARK: - Health Tab

struct HealthView: View {
    @State private var report: HealthReport?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    HStack(spacing: 8) {
                        HydraScanSweep()
                        Text("Running health checks...")
                            .foregroundStyle(Color.hydraMuted)
                    }
                    .padding()
                } else if let report {
                    // Overall status banner
                    HStack(spacing: 10) {
                        Image(systemName: statusIcon(report.overallStatus))
                            .foregroundStyle(statusColor(report.overallStatus))
                            .font(.title3)
                        VStack(alignment: .leading) {
                            Text(report.overallStatus.rawValue.uppercased())
                                .font(HydraTheme.mono(.title3, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(statusColor(report.overallStatus))
                            Text(report.summary)
                                .font(HydraTheme.mono(.caption))
                                .foregroundStyle(Color.hydraMuted)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(statusColor(report.overallStatus).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                    // Individual checks
                    ForEach(report.checks) { check in
                        HStack(spacing: 12) {
                            Image(systemName: healthStatusIcon(check.status))
                                .foregroundStyle(healthStatusColor(check.status))
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

                            Text(check.status.rawValue.uppercased())
                                .font(HydraTheme.mono(.caption2, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(healthStatusColor(check.status))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(healthStatusColor(check.status).opacity(0.12), in: Capsule())
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.hydraPanel.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    // Empty state with scan button
                    Button {
                        Task { await runHealth() }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.hydraAccent.opacity(0.6))
                            Text("Vault Health")
                                .font(HydraTheme.display(.title))
                                .foregroundStyle(Color.hydraInk)
                            Text("Click to run 7 health checks on your vault")
                                .font(HydraTheme.mono(.subheadline))
                                .foregroundStyle(Color.hydraMuted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(Color.hydraVoid)
    }

    private func statusIcon(_ s: HealthStatus) -> String {
        switch s { case .healthy: "checkmark.shield.fill"; case .warning: "exclamationmark.triangle.fill"; case .critical: "xmark.octagon.fill" }
    }
    private func statusColor(_ s: HealthStatus) -> Color {
        switch s { case .healthy: Color.hydraLive; case .warning: Color.hydraPartial; case .critical: Color.hydraAlert ?? .red }
    }
    private func healthStatusIcon(_ s: HealthStatus) -> String {
        switch s { case .healthy: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .critical: "xmark.octagon.fill" }
    }
    private func healthStatusColor(_ s: HealthStatus) -> Color {
        switch s { case .healthy: Color.hydraLive; case .warning: Color.hydraPartial; case .critical: .red }
    }

    private func runHealth() async {
        isLoading = true
        let path = "~/Documents/MyVault".expandingTildeInPath
        let scanner = VaultScanner(vaultRoot: path)
        do {
            let inventory = try await scanner.scan()
            let checker = HealthChecker()
            report = checker.checkAll(inventory)
        } catch {
            // Sample report
            report = HealthReport(vaultRoot: path, checks: [
                HealthCheck(name: "Demo", status: .healthy, message: "Configure your vault path to see real results"),
            ])
        }
        isLoading = false
    }
}
