import Foundation
import HydraCore

// MARK: - Vault Writer

/// Projects enriched SourceArtifacts into the Obsidian vault as properly formatted notes.
/// Writes frontmatter (8-field contract), wikilinks, colored tags, and body content.
public actor VaultWriter {
    private let vaultRoot: String
    private let fileManager: FileManager

    public init(vaultRoot: String, fileManager: FileManager = .default) {
        self.vaultRoot = vaultRoot
        self.fileManager = fileManager
    }

    /// Project a single artifact into the vault.
    /// - Returns: The relative path of the written note.
    @discardableResult
    public func project(_ artifact: SourceArtifact) async throws -> String {
        let markdown = renderMarkdown(from: artifact)
        let relativePath = resolvePath(for: artifact)
        let absolutePath = vaultRoot + "/" + relativePath

        // Ensure parent directory exists
        let parentDir = (absolutePath as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Write atomically
        try markdown.write(toFile: absolutePath, atomically: true, encoding: .utf8)

        return relativePath
    }

    /// Project multiple artifacts. Returns the paths written.
    @discardableResult
    public func project(_ artifacts: [SourceArtifact]) async throws -> [String] {
        var paths: [String] = []
        for artifact in artifacts {
            let path = try await project(artifact)
            paths.append(path)
        }
        return paths
    }

    // MARK: - Rendering

    /// Render an artifact as Obsidian-flavored markdown with frontmatter.
    public func renderMarkdown(from artifact: SourceArtifact) -> String {
        var output = ""

        // Frontmatter (8-field contract)
        output += "---\n"
        output += "date: \(ISO8601DateFormatter().string(from: artifact.provenance.timestamp))\n"
        output += "type: \(artifact.kind.vaultSubpath.components(separatedBy: "/").last ?? "note")\n"
        output += "status: \(artifact.lifecycleState.rawValue)\n"
        output += "tags:\n"
        for tag in artifact.tags.sorted() {
            output += "  - \(tag)\n"
        }
        if let colorTag = artifact.colorTag {
            output += "color-axis: \(colorTag.axis.rawValue)\n"
            output += "color-value: \(colorTag.value)\n"
            output += "color-hex: \(colorTag.color.hex)\n"
        }
        output += "artifact-id: \(artifact.id.uuidString)\n"
        output += "source-path: \"\(artifact.sourcePath)\"\n"
        output += "source-digest: \(artifact.provenance.digest)\n"
        output += "authority: \(artifact.provenance.authority.rawValue)\n"
        output += "confidence: \(String(format: "%.2f", artifact.confidence))\n"
        output += "delivery-state: \(artifact.deliveryState.rawValue)\n"
        output += "ingested-at: \(ISO8601DateFormatter().string(from: Date()))\n"
        output += "---\n\n"

        // Title
        output += "# \(artifact.title)\n\n"

        // Body content
        output += artifact.content

        // Relationships as wikilinks
        if !artifact.relationships.isEmpty {
            output += "\n\n## Related\n\n"
            for rel in artifact.relationships {
                let linkTarget = rel.target
                    .replacingOccurrences(of: ".md", with: "")
                    .replacingOccurrences(of: " ", with: "%20")
                let label = rel.label ?? rel.type.rawValue
                output += "- [\(label)](\(linkTarget))\n"
            }
        }

        return output
    }

    // MARK: - Path resolution

    /// Resolve the vault-relative path for an artifact based on its kind and PARA category.
    private func resolvePath(for artifact: SourceArtifact) -> String {
        let subpath = artifact.kind.vaultSubpath
        let safeTitle = artifact.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(subpath)/\(safeTitle).md"
    }
}
