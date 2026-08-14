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
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.hydraAccent.opacity(0.6))
                Text("Vault Explorer")
                    .font(HydraTheme.display(.title))
                    .foregroundStyle(Color.hydraInk)
                Text("Browse, filter, and explore vault notes with tags and relationships.")
                    .font(HydraTheme.mono(.subheadline))
                    .foregroundStyle(Color.hydraMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hydraVoid)
    }
}

// OracleView and HealthView are in OracleAndHealthViews.swift
