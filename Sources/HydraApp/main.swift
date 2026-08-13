import SwiftUI
import HydraCore
import HydraVault
import HydraHealth

// MARK: - App Entry Point

@main
struct BrainOracleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @State private var selectedTab: AppTab = .hydrate

    var body: some View {
        TabView(selection: $selectedTab) {
            HydrationView()
                .tabItem { Label("Hydrate", systemImage: "drop.fill") }
                .tag(AppTab.hydrate)

            VaultExplorerView()
                .tabItem { Label("Vault", systemImage: "archivebox.fill") }
                .tag(AppTab.vault)

            OracleView()
                .tabItem { Label("Oracle", systemImage: "brain.head.profile.fill") }
                .tag(AppTab.oracle)

            HealthView()
                .tabItem { Label("Health", systemImage: "heart.text.square.fill") }
                .tag(AppTab.health)
        }
    }
}

enum AppTab: String, CaseIterable {
    case hydrate, vault, oracle, health
}

// MARK: - Hydration Tab

struct HydrationView: View {
    @State private var vaultPath = "~/Developer/SecondBrain"
    @State private var sourcePath = "~/.claude/plans"
    @State private var isHydrating = false
    @State private var result: HydrationResult?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Context Hydration")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Sources → enrich → vault → export")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)

            // Source + Vault config
            Form {
                Section("Source") {
                    TextField("Source path", text: $sourcePath)
                    SourceKindPicker()
                }

                Section("Vault") {
                    TextField("Vault root", text: $vaultPath)
                    OutboxConfigRow()
                }

                Section("Options") {
                    Toggle("Dry run", isOn: .constant(true))
                    ExportDestinationsRow()
                }
            }
            .formStyle(.grouped)

            // Action
            HStack {
                Spacer()
                Button("Hydrate") {
                    isHydrating = true
                    // TODO: Wire to HydrationPipeline
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isHydrating)
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

struct SourceKindPicker: View {
    @State private var selected: SourceKind = .claudePlans

    var body: some View {
        Picker("Kind", selection: $selected) {
            ForEach(SourceKind.allCases, id: \.self) { kind in
                Text(kindLabel(kind)).tag(kind)
            }
        }
    }

    private func kindLabel(_ kind: SourceKind) -> String {
        switch kind {
        case .claudePlans:    return "Claude Plans"
        case .claudeSessions: return "Claude Sessions"
        case .codexSessions:  return "Codex Sessions"
        case .gitRepo:        return "Git Repo"
        case .changelog:      return "Changelog"
        case .claudeMem:      return "Claude-mem"
        case .obsidianVault:  return "Obsidian Vault"
        case .adHocFile:      return "Ad-hoc File"
        case .apiStream:      return "API Stream"
        }
    }
}

struct OutboxConfigRow: View {
    @State private var useOwnDB = true

    var body: some View {
        Toggle("Use own outbox DB", isOn: $useOwnDB)
        if !useOwnDB {
            TextField("External outbox path", text: .constant(""))
        }
    }
}

struct ExportDestinationsRow: View {
    @State private var exportToObsidian = true
    @State private var exportToJSON = false
    @State private var exportToAPI = false

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Obsidian vault", isOn: $exportToObsidian)
            Toggle("JSON-LD graph", isOn: $exportToJSON)
            Toggle("API push", isOn: $exportToAPI)
        }
    }
}

// MARK: - Vault Explorer Tab (placeholder)

struct VaultExplorerView: View {
    var body: some View {
        ContentUnavailableView(
            "Vault Explorer",
            systemImage: "archivebox.fill",
            description: Text("Browse, filter, and explore vault notes with tags and relationships.")
        )
    }
}

// MARK: - Oracle Tab (placeholder)

struct OracleView: View {
    var body: some View {
        ContentUnavailableView(
            "Oracle",
            systemImage: "brain.head.profile.fill",
            description: Text("Query the hydrated context graph — gaps, timeline, relationships.")
        )
    }
}

// MARK: - Health Tab (placeholder)

struct HealthView: View {
    var body: some View {
        ContentUnavailableView(
            "Vault Health",
            systemImage: "heart.text.square.fill",
            description: Text("Staleness, tag consistency, orphaned notes, broken links, and more.")
        )
    }
}
