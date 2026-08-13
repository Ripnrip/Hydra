import Foundation
import BrainCore

// MARK: - Source Adapter Protocol

/// Scans a source directory and produces raw SourceArtifacts.
/// Each source type has its own adapter. The pipeline feeds these into the classifier.
public protocol SourceAdapter: Sendable {
    func scan() async throws -> [SourceArtifact]
    var sourceKind: SourceKind { get }
}

// MARK: - Claude Plans Adapter

/// Reads ~/.claude/plans/*.md files and converts them to SourceArtifacts.
/// This is the first real hydration use-case: Claude session plans → vault.
public actor ClaudePlansAdapter: SourceAdapter {
    public let sourceKind: SourceKind = .claudePlans

    private let plansDirectory: String
    private let fileManager: FileManager

    public init(plansDirectory: String? = nil, fileManager: FileManager = .default) {
        self.plansDirectory = plansDirectory ?? Self.defaultPlansDirectory
        self.fileManager = fileManager
    }

    public static var defaultPlansDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/plans"
    }

    public func scan() async throws -> [SourceArtifact] {
        guard fileManager.fileExists(atPath: plansDirectory) else {
            return []
        }

        var artifacts: [SourceArtifact] = []
        let url = URL(fileURLWithPath: plansDirectory)

        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "md" else { continue }

            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let digest = VaultScanner.sha256(content)

            // Parse frontmatter
            let (frontmatter, body) = VaultScanner.parseFrontmatter(content)
            let tags = VaultScanner.extractTags(from: frontmatter, body: body)
            let wikilinks = VaultScanner.extractWikilinks(from: body)

            // Infer artifact kind from content
            let kind = inferKind(from: filename, content: content, frontmatter: frontmatter)

            // Extract title
            let title = VaultScanner.extractTitle(from: content, filename: filename)

            let artifact = SourceArtifact(
                sourcePath: fileURL.path,
                kind: kind,
                title: title,
                content: body,
                frontmatter: frontmatter,
                tags: tags,
                wikilinks: wikilinks,
                provenance: Provenance(
                    authority: .observation,
                    source: fileURL.path,
                    digest: digest,
                    timestamp: modDate,
                    actor: "claude-code"
                ),
                lifecycleState: inferLifecycle(from: frontmatter, content: content),
                deliveryState: .submitted,
                confidence: 0.6  // base confidence — classifier will adjust
            )

            artifacts.append(artifact)
        }

        return artifacts.sorted { $0.provenance.timestamp > $1.provenance.timestamp }
    }

    // MARK: - Inference helpers

    private func inferKind(from filename: String, content: String, frontmatter: [String: String]) -> ArtifactKind {
        let lowerFilename = filename.lowercased()
        let lowerContent = content.lowercased()

        if lowerFilename.contains("plan") || lowerContent.contains("# plan") {
            return .plan
        }
        if lowerFilename.contains("session") || lowerContent.contains("session") {
            return .session
        }
        if lowerFilename.contains("decision") || lowerContent.contains("## decision") {
            return .decision
        }
        if lowerFilename.contains("handoff") || lowerContent.contains("handoff") {
            return .handoff
        }
        if lowerFilename.contains("audit") || lowerContent.contains("audit") {
            return .audit
        }
        return .note
    }

    private func inferLifecycle(from frontmatter: [String: String], content: String) -> LifecycleState {
        let status = (frontmatter["status"] ?? frontmatter["lifecycle"] ?? "").lowercased()
        let lowerContent = content.lowercased()

        if status.contains("complet") || status == "done" { return .completed }
        if status.contains("active") || status == "in-progress" { return .active }
        if status.contains("accept") { return .accepted }
        if status.contains("supers") { return .superseded }
        if status.contains("abandon") { return .abandoned }
        if status.contains("archiv") { return .archived }

        // Heuristic: if content mentions "merged" or "shipped", likely completed
        if lowerContent.contains("merged") || lowerContent.contains("shipped") {
            return .completed
        }

        return .draft
    }
}

// MARK: - Changelog Adapter

/// Reads CHANGELOG.md or SETUP-LOG.md and splits into entries.
public actor ChangelogAdapter: SourceAdapter {
    public let sourceKind: SourceKind = .changelog

    private let filePath: String

    public init(filePath: String) {
        self.filePath = filePath
    }

    public func scan() async throws -> [SourceArtifact] {
        guard FileManager.default.fileExists(atPath: filePath) else { return [] }

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let filename = (filePath as NSString).lastPathComponent
        let digest = VaultScanner.sha256(content)

        // Split by ## headers (changelog convention)
        var artifacts: [SourceArtifact] = []
        let sections = splitChangelog(content)

        for section in sections {
            let artifact = SourceArtifact(
                sourcePath: filePath,
                kind: .changelog,
                title: section.title,
                content: section.body,
                frontmatter: ["source-file": filename],
                tags: ["changelog"],
                provenance: Provenance(
                    authority: .changelog,
                    source: filePath,
                    digest: digest,
                    timestamp: section.date ?? Date(),
                    actor: nil
                ),
                lifecycleState: .completed,
                deliveryState: .submitted,
                confidence: 0.9
            )
            artifacts.append(artifact)
        }

        return artifacts
    }

    private struct ChangelogSection {
        let title: String
        let body: String
        let date: Date?
    }

    private func splitChangelog(_ content: String) -> [ChangelogSection] {
        var sections: [ChangelogSection] = []
        var currentTitle = ""
        var currentBody = ""
        var currentDate: Date?

        let lines = content.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("## ") {
                if !currentTitle.isEmpty {
                    sections.append(ChangelogSection(title: currentTitle, body: currentBody, date: currentDate))
                }
                currentTitle = String(line.dropFirst(3))
                currentBody = ""
                currentDate = parseDate(from: currentTitle)
            } else {
                currentBody += line + "\n"
            }
        }
        if !currentTitle.isEmpty {
            sections.append(ChangelogSection(title: currentTitle, body: currentBody, date: currentDate))
        }

        return sections
    }

    private func parseDate(from title: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Try to extract a date from the title
        let pattern = /\d{4}-\d{2}-\d{2}/
        if let match = title.firstMatch(of: pattern) {
            return formatter.date(from: String(match.output))
        }
        return nil
    }
}
