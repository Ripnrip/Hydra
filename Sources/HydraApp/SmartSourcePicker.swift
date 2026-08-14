import SwiftUI
import HydraCore
import HydraVault

// MARK: - Smart Source Detection

/// Detects what kind of content lives in a picked folder and suggests
/// source + destination configuration automatically.
/// Pick a folder → we figure out what's there → present options.

enum DetectedSource: String, CaseIterable, Identifiable {
    case claudePlans = "Claude Plans"
    case claudeSessions = "Claude Sessions"
    case codexSessions = "Codex Sessions"
    case obsidianVault = "Obsidian Vault"
    case gitRepo = "Git Repository"
    case changelog = "Changelog / Logs"
    case markdown = "Markdown Files"
    case unknown = "Unknown Content"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .claudePlans: "doc.text.fill"
        case .claudeSessions: "bubble.left.fill"
        case .codexSessions: "terminal.fill"
        case .obsidianVault: "book.fill"
        case .gitRepo: "arrow.triangle.branch"
        case .changelog: "list.bullet.rectangle.fill"
        case .markdown: "doc.plaintext"
        case .unknown: "questionmark.folder"
        }
    }
    var description: String {
        switch self {
        case .claudePlans: "Claude Code planning artifacts"
        case .claudeSessions: "Claude Code session transcripts"
        case .codexSessions: "Codex CLI session files"
        case .obsidianVault: "Obsidian vault with .obsidian config"
        case .gitRepo: "Git repository with commits"
        case .changelog: "Changelog, setup logs, or release notes"
        case .markdown: "Generic markdown documents"
        case .unknown: "No recognizable pattern"
        }
    }
    var suggestedVaultSubpath: String {
        switch self {
        case .claudePlans, .markdown: "wiki/plans"
        case .claudeSessions: "wiki/recaps/sessions"
        case .codexSessions: "wiki/recaps/sessions"
        case .obsidianVault: "" // already a vault
        case .gitRepo: "wiki/projects"
        case .changelog: "wiki/changelogs"
        case .unknown: "wiki/notes"
        }
    }
}

// MARK: - Folder Detector

struct FolderDetector {
    /// Analyzes a folder and detects what it contains.
    func detect(path: String) -> DetectedSource {
        let fm = FileManager.default
        let expanded = path.hasPrefix("~")
            ? fm.homeDirectoryForCurrentUser.path + path.dropFirst()
            : path

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            return .unknown
        }

        let contents = (try? fm.contentsOfDirectory(atPath: expanded)) ?? []

        // Obsidian vault: has .obsidian directory
        if contents.contains(".obsidian") { return .obsidianVault }

        // Git repo: has .git
        if contents.contains(".git") { return .gitRepo }

        // Check file patterns
        let mdFiles = contents.filter { $0.hasSuffix(".md") }
        let jsonFiles = contents.filter { $0.hasSuffix(".json") }

        // Claude plans: markdown files with kebab-case names (Claude's naming)
        if !mdFiles.isEmpty {
            let kebabCount = mdFiles.filter { $0.contains("-") && !$0.contains(" ") }.count
            if path.contains(".claude/plans") || (kebabCount >= mdFiles.count / 2 && mdFiles.count <= 20) {
                return .claudePlans
            }
        }

        // Claude sessions: path check
        if path.contains(".claude/projects") { return .claudeSessions }
        if path.contains(".codex") { return .codexSessions }

        // Changelog: CHANGELOG.md, SETUP-LOG.md present
        if contents.contains(where: { $0.lowercased().contains("changelog") || $0.lowercased().contains("setup-log") }) {
            return .changelog
        }

        // Generic markdown
        if !mdFiles.isEmpty { return .markdown }

        return .unknown
    }

    /// Counts items in the folder for display
    func itemCount(path: String) -> Int {
        let fm = FileManager.default
        let expanded = path.hasPrefix("~")
            ? fm.homeDirectoryForCurrentUser.path + path.dropFirst()
            : path
        return (try? fm.contentsOfDirectory(atPath: expanded))?.count ?? 0
    }

    /// Auto-detects the user's Obsidian vault
    func detectDefaultVault() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Common vault locations
        var candidates = [
            "\(home)/Documents/MyVault",
            "\(home)/Developer/MyVault",
            "\(home)/Documents/Obsidian",
        ]

        // iCloud Obsidian vaults
        let iCloudBase = "\(home)/Library/Mobile Documents/iCloud~md~obsidian/Documents"
        if let iCloudVaults = try? fm.contentsOfDirectory(atPath: iCloudBase) {
            for vault in iCloudVaults where vault != ".obsidian" {
                candidates.append("\(iCloudBase)/\(vault)")
            }
        }

        for candidate in candidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir),
               isDir.boolValue,
               let contents = try? fm.contentsOfDirectory(atPath: candidate),
               contents.contains(".obsidian") {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - Smart Source Picker View

/// One-click source + destination setup.
/// User picks ONE folder → we detect what's in it → suggest the destination.
struct SmartSourcePicker: View {
    @Binding var sourcePath: String
    @Binding var vaultPath: String
    @Binding var detectedKind: DetectedSource?

    @State private var detected: DetectedSource = .unknown
    @State private var itemCount: Int = 0
    @State private var suggestedVault: String = ""
    @State private var isAnalyzing = false

    private let detector = FolderDetector()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pick a folder
            HydraPanel(title: "Pick a Folder", icon: "folder.badge.plus") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        TextField("or paste a path...", text: $sourcePath)
                            .textFieldStyle(HydraFieldStyle())
                            .onSubmit { analyze() }

                        Button {
                            pickFolder()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text("Browse")
                            }
                            .font(HydraTheme.mono(.callout, weight: .semibold))
                            .foregroundStyle(Color.hydraAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.hydraCard)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hydraLine, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    // Quick picks
                    HStack(spacing: 6) {
                        Text("QUICK PICKS")
                            .font(HydraTheme.mono(.caption2, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Color.hydraMuted)
                        quickPick("~/.claude/plans", label: "Claude Plans")
                        quickPick("~/Documents/MyVault", label: "My Vault")
                        if let vault = detector.detectDefaultVault() {
                            quickPick(vault, label: "Auto-detected Vault")
                        }
                    }
                }
            }

            // Detection result
            if detected != .unknown || isAnalyzing {
                HydraPanel(title: "Detected", icon: detected.icon) {
                    if isAnalyzing {
                        HStack(spacing: 10) {
                            HydraStaticSpinner()
                            Text("Analyzing folder...")
                                .font(HydraTheme.mono(.callout))
                                .foregroundStyle(Color.hydraMuted)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: detected.icon)
                                    .foregroundStyle(Color.hydraAccent)
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(detected.rawValue)
                                        .font(HydraTheme.mono(.headline))
                                        .foregroundStyle(Color.hydraInk)
                                    Text(detected.description)
                                        .font(HydraTheme.mono(.caption))
                                        .foregroundStyle(Color.hydraMuted)
                                }
                                Spacer()
                                HydraTagChip(label: "\(itemCount) items", color: .hydraLive)
                            }

                            // Auto-suggested destination
                            if !suggestedVault.isEmpty {
                                Divider().background(Color.hydraLine)
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundStyle(Color.hydraLive)
                                    Text("Suggested destination:")
                                        .font(HydraTheme.mono(.caption))
                                        .foregroundStyle(Color.hydraMuted)
                                    Text(suggestedVault)
                                        .font(HydraTheme.mono(.caption, weight: .semibold))
                                        .foregroundStyle(Color.hydraLive)
                                }
                                Button("Use Suggested Destination") {
                                    vaultPath = suggestedVault
                                }
                                .font(HydraTheme.mono(.caption, weight: .semibold))
                                .foregroundStyle(Color.hydraAccent)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { analyze() }
        .onChange(of: sourcePath) { _ in analyze() }
    }

    private func quickPick(_ path: String, label: String) -> some View {
        Button(label) {
            sourcePath = path
        }
        .font(HydraTheme.mono(.caption2, weight: .medium))
        .foregroundStyle(Color.hydraAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.hydraAccent.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.hydraAccent.opacity(0.2), lineWidth: 1))
        .buttonStyle(.plain)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Pick a folder to hydrate from"
        if panel.runModal() == .OK, let url = panel.url {
            sourcePath = url.path
        }
    }

    private func analyze() {
        isAnalyzing = true
        detected = detector.detect(path: sourcePath)
        itemCount = detector.itemCount(path: sourcePath)

        // Suggest vault destination
        if detected == .obsidianVault {
            // Source IS a vault — hydrate within it
            suggestedVault = sourcePath
        } else if let vault = detector.detectDefaultVault() {
            suggestedVault = vault
        } else {
            suggestedVault = ""
        }

        detectedKind = detected
        isAnalyzing = false
    }
}
