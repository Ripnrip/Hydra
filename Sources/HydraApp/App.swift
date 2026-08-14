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
    @State private var selectedTab: AppTab = {
        // Demo mode: --demo-oracle launches into the Oracle tab
        CommandLine.arguments.contains("--demo-oracle") ? .oracle : .hydrate
    }()

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
    @State private var sourcePath = "~/.claude/plans"
    @State private var vaultPath = "~/Documents/MyVault"
    @State private var isHydrating = false
    @State private var dryRun = true
    @State private var smartConfig: SmartVaultConfig?
    @State private var isDetecting = false
    @State private var showFolderPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context Hydration")
                            .font(HydraTheme.display(.largeTitle))
                            .foregroundStyle(Color.hydraInk)
                        Text("Pick a folder — we detect the rest")
                            .font(HydraTheme.mono(.subheadline))
                            .foregroundStyle(Color.hydraMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                // Smart folder picker — detect sources from a single chosen folder
                HydraPanel(title: "Vault Folder", icon: "folder.badge.gearshape") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Folder display + browse button
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.hydraAccent)
                            Text(smartConfig?.detectedVault ?? vaultPath)
                                .font(HydraTheme.mono(.callout))
                                .foregroundStyle(Color.hydraInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Choose...") { showFolderPicker = true }
                                .buttonStyle(.bordered)
                                .tint(Color.hydraAccent)
                        }

                        // Detection results
                        if isDetecting {
                            HStack(spacing: 8) {
                                HydraStaticSpinner()
                                Text("Detecting sources...")
                                    .font(HydraTheme.mono(.caption))
                                    .foregroundStyle(Color.hydraMuted)
                            }
                        } else if let config = smartConfig {
                            // What we found
                            VStack(alignment: .leading, spacing: 6) {
                                Label(config.summary, systemImage: "checkmark.shield.fill")
                                    .font(HydraTheme.mono(.caption))
                                    .foregroundStyle(Color.hydraLive)

                                if !config.detectedSources.isEmpty {
                                    Text("SOURCES FOUND")
                                        .font(.system(size: 8, design: .monospaced).weight(.semibold))
                                        .tracking(1.5)
                                        .foregroundStyle(Color.hydraMuted)
                                        .padding(.top, 4)

                                    ForEach(config.detectedSources) { source in
                                        HStack(spacing: 8) {
                                            Image(systemName: iconName(for: source.kind))
                                                .foregroundStyle(Color.hydraAccent)
                                                .font(.system(size: 10))
                                            Text(source.label)
                                                .font(HydraTheme.mono(.caption))
                                                .foregroundStyle(Color.hydraInk)
                                            Spacer()
                                            Text(source.path)
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundStyle(Color.hydraMuted)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }

                        // Dry run toggle
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

                // Export (simplified — Obsidian is default when vault detected)
                HydraPanel(title: "Export", icon: "arrow.up.forward.app.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        HydraExportRow(icon: "book.fill", label: "Obsidian Vault", enabled: smartConfig?.isObsidianVault == true)
                        HydraExportRow(icon: "link.circle.fill", label: "JSON-LD Graph", enabled: false)
                    }
                }
                .padding(.horizontal, 24)

                // Action
                HStack {
                    Spacer()
                    HydraButton("Hydrate", icon: "drop.fill") {
                        isHydrating = true
                    }
                    .disabled(isHydrating || smartConfig == nil)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .background(Color.hydraVoid)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await detectFolder(url.path) }
            }
        }
        .task {
            if smartConfig == nil {
                await detectFolder(vaultPath)
            }
        }
    }

    private func detectFolder(_ path: String) async {
        isDetecting = true
        let detector = VaultDetector()
        smartConfig = await detector.detect(at: path)
        if let vault = smartConfig?.detectedVault {
            vaultPath = vault
        }
        isDetecting = false
    }

    private func iconName(for kind: SourceKind) -> String {
        switch kind {
        case .claudePlans: "doc.text.magnifyingglass"
        case .claudeSessions: "bubble.left.and.bubble.right"
        case .codexSessions: "terminal"
        case .gitRepo: "square.stack.3d.up"
        case .changelog: "list.bullet.rectangle"
        case .claudeMem: "brain"
        case .obsidianVault: "book"
        case .adHocFile: "doc"
        case .apiStream: "antenna.radiowaves.left.and.right"
        }
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

// OracleView, HealthView, and String.expandingTildeInPath are in OracleAndHealthViews.swift
