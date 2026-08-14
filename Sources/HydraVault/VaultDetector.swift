import Foundation
import HydraCore

// MARK: - Smart Vault Detection

/// Auto-detects what a user picked and infers everything else.
/// One folder pick → smart defaults for source + destination.
/// This is the "don't make me think" layer.
public actor VaultDetector {

    public init() {}

    /// Analyze a folder and return smart configuration.
    /// Detects: Obsidian vaults, git repos, Claude/Codex sources, changelogs.
    public func detect(at path: String) async -> SmartVaultConfig {
        let fm = FileManager.default
        let expanded = path.hasPrefix("~")
            ? fm.homeDirectoryForCurrentUser.path + path.dropFirst()
            : path

        var config = SmartVaultConfig(pickedPath: expanded)
        config.isObsidianVault = fm.fileExists(atPath: expanded + "/.obsidian")
        config.isGitRepo = fm.fileExists(atPath: expanded + "/.git")

        // Detect content type from directory structure
        let entries = (try? fm.contentsOfDirectory(atPath: expanded)) ?? []
        let lowerEntries = entries.map { $0.lowercased() }

        // PARA structure detection (Obsidian vault convention)
        let paraMarkers = ["00-inbox", "01-permanent", "02-daily", "03-templates", "07-sessions", "attachments"]
        let paraMatches = lowerEntries.filter { e in paraMarkers.contains { e.contains($0) } }
        if paraMatches.count >= 2 {
            config.vaultStructure = .para
        } else if entries.contains(where: { $0.hasSuffix(".md") }) {
            config.vaultStructure = .flat
        }

        // Source detection — look inside the picked folder AND sibling paths
        config = detectSources(in: expanded, config: config)

        // If this is an Obsidian vault, it's the destination
        if config.isObsidianVault {
            config.detectedVault = expanded
            config.confidence = 0.95
        }

        // If no vault detected but there are .md files, suggest as vault
        if config.detectedVault == nil && entries.contains(where: { $0.hasSuffix(".md") }) {
            config.detectedVault = expanded
            config.confidence = 0.6
        }

        // Auto-suggest Claude/Codex sources from home directory
        config = detectHomeSources(config: config)

        return config
    }

    private func detectSources(in path: String, config: SmartVaultConfig) -> SmartVaultConfig {
        var config = config
        let fm = FileManager.default

        // CHANGELOG / SETUP-LOG detection
        for marker in ["CHANGELOG.md", "CHANGELOG", "setup-log.md", "SETUP-LOG.md"] {
            if fm.fileExists(atPath: path + "/" + marker) {
                config.detectedSources.append(DetectedSource(
                    kind: .changelog,
                    path: path + "/" + marker,
                    label: "Changelog",
                    fileCount: 1
                ))
                break
            }
        }

        // docs/plans detection
        let docsPlans = path + "/docs/plans"
        if fm.fileExists(atPath: docsPlans) {
            let count = countMarkdown(in: docsPlans)
            if count > 0 {
                config.detectedSources.append(DetectedSource(
                    kind: .gitRepo,
                    path: docsPlans,
                    label: "Plans (\(count) files)",
                    fileCount: count
                ))
            }
        }

        // Session-like folders (dated .md files)
        for entry in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where entry.lowercased().contains("session") {
            let fullPath = path + "/" + entry
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue {
                let count = countMarkdown(in: fullPath)
                if count > 0 {
                    config.detectedSources.append(DetectedSource(
                        kind: .claudeSessions,
                        path: fullPath,
                        label: "Sessions (\(count) files)",
                        fileCount: count
                    ))
                }
            }
        }
        return config
    }

    private func detectHomeSources(config: SmartVaultConfig) -> SmartVaultConfig {
        var config = config
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // ~/.claude/plans
        let claudePlans = home + "/.claude/plans"
        if fm.fileExists(atPath: claudePlans) {
            let count = countMarkdown(in: claudePlans)
            if count > 0 {
                config.detectedSources.append(DetectedSource(
                    kind: .claudePlans,
                    path: claudePlans,
                    label: "Claude Plans (\(count) files)",
                    fileCount: count
                ))
            }
        }

        // ~/.claude/projects (sessions)
        let claudeProjects = home + "/.claude/projects"
        if fm.fileExists(atPath: claudeProjects) {
            config.detectedSources.append(DetectedSource(
                kind: .claudeSessions,
                path: claudeProjects,
                label: "Claude Sessions",
                fileCount: -1  // unknown count, expensive to scan
            ))
        }

        // ~/.codex
        let codex = home + "/.codex"
        if fm.fileExists(atPath: codex) {
            config.detectedSources.append(DetectedSource(
                kind: .codexSessions,
                path: codex,
                label: "Codex Sessions",
                fileCount: -1
            ))
        }
        return config
    }

    private func countMarkdown(in dir: String) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
        return entries.filter { $0.hasSuffix(".md") }.count
    }
}

// MARK: - Smart Config

public struct SmartVaultConfig: Sendable {
    public let pickedPath: String

    public var isObsidianVault = false
    public var isGitRepo = false
    public var vaultStructure: VaultStructure = .unknown
    public var detectedVault: String?
    public var detectedSources: [DetectedSource] = []
    public var confidence: Double = 0.0

    public init(pickedPath: String) {
        self.pickedPath = pickedPath
    }

    /// Human-readable summary of what was detected.
    public var summary: String {
        var parts: [String] = []
        if isObsidianVault { parts.append("Obsidian vault") }
        if isGitRepo { parts.append("git repo") }
        if vaultStructure == .para { parts.append("PARA structure") }
        parts.append("\(detectedSources.count) sources found")
        return parts.joined(separator: " · ")
    }
}

public enum VaultStructure: String, Sendable {
    case para        // 00-Inbox, 01-Permanent, etc.
    case flat        // just .md files
    case unknown
}

public struct DetectedSource: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let kind: SourceKind
    public let path: String
    public let label: String
    public let fileCount: Int  // -1 = unknown

    public init(kind: SourceKind, path: String, label: String, fileCount: Int) {
        self.kind = kind
        self.path = path
        self.label = label
        self.fileCount = fileCount
    }
}
