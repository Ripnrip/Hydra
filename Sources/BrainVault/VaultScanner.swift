import Foundation
import BrainCore
import CryptoKit

// MARK: - Vault Scanner

/// Scans an Obsidian vault directory and produces a typed inventory.
/// This is the foundation for: vault writer (knows what exists), health (tag consistency,
/// orphans, staleness), and oracle (relationship graph, gap analysis).
public actor VaultScanner {
    private let vaultRoot: String
    private let fileManager: FileManager

    public init(vaultRoot: String, fileManager: FileManager = .default) {
        self.vaultRoot = vaultRoot
        self.fileManager = fileManager
    }

    /// Scan the entire vault and return a typed inventory.
    public func scan() async throws -> VaultInventory {
        var notes: [VaultNote] = []
        let baseURL = URL(fileURLWithPath: vaultRoot)

        let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Skip non-markdown files
            guard fileURL.pathExtension == "md" else { continue }

            // Skip .obsidian, .git, .smart-env, .claude directories
            let path = fileURL.path
            if path.contains("/.obsidian/") ||
               path.contains("/.git/") ||
               path.contains("/.smart-env/") ||
               path.contains("/.claude/") {
                continue
            }

            let note = try await parseNote(at: fileURL, vaultRootPath: vaultRoot)
            notes.append(note)
        }

        // Resolve orphaned status (no incoming wikilinks)
        let wikilinkTargets = Set(notes.flatMap { $0.wikilinks.map { $0.lowercased() } })
        for i in notes.indices {
            let titleLower = notes[i].title.lowercased()
            notes[i].orphaned = !wikilinkTargets.contains(titleLower)
        }

        return VaultInventory(
            vaultRoot: vaultRoot,
            notes: notes,
            scannedAt: Date()
        )
    }

    /// Parse a single markdown file into a VaultNote.
    public func parseNote(at fileURL: URL, vaultRootPath: String) async throws -> VaultNote {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let absolutePath = fileURL.path
        let relativePath = String(absolutePath.dropFirst(vaultRootPath.count + 1)) // strip vault root + "/"
        let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        let (frontmatter, body) = Self.parseFrontmatter(content)
        let title = Self.extractTitle(from: content, filename: fileURL.deletingPathExtension().lastPathComponent)
        let tags = Self.extractTags(from: frontmatter, body: body)
        let wikilinks = Self.extractWikilinks(from: body)
        let paraCategory = PARACategory.resolve(from: relativePath)
        let digest = Self.sha256(content)

        return VaultNote(
            relativePath: relativePath,
            title: title,
            frontmatter: frontmatter,
            tags: tags,
            wikilinks: wikilinks,
            paraCategory: paraCategory,
            modifiedDate: resourceValues.contentModificationDate ?? .distantPast,
            size: resourceValues.fileSize ?? 0,
            digest: digest,
            hasFrontmatter: !frontmatter.isEmpty
        )
    }

    // MARK: - Parsing helpers (static — pure functions)

    /// Split content into frontmatter dictionary and body.
    public static func parseFrontmatter(_ content: String) -> (frontmatter: [String: String], body: String) {
        guard content.hasPrefix("---") else {
            return ([:], content)
        }

        // Find the closing --- after the opening one
        let afterOpening = content.index(content.startIndex, offsetBy: 3)
        // Skip newline after opening ---
        var searchStart = afterOpening
        if searchStart < content.endIndex && content[searchStart] == "\n" {
            searchStart = content.index(after: searchStart)
        } else if searchStart < content.endIndex && content[searchStart] == "\r" {
            searchStart = content.index(after: searchStart)
            if searchStart < content.endIndex && content[searchStart] == "\n" {
                searchStart = content.index(after: searchStart)
            }
        }

        guard let closeRange = content.range(of: "\n---", range: searchStart..<content.endIndex) else {
            return ([:], content)
        }

        let yamlBlock = String(content[searchStart..<closeRange.lowerBound])
        var body = String(content[closeRange.upperBound...])
        // Strip leading newline from body
        if body.hasPrefix("\n") { body.removeFirst() }
        else if body.hasPrefix("\r\n") { body.removeFirst(2) }

        var frontmatter: [String: String] = [:]
        for line in yamlBlock.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces))
            // Strip quotes
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty {
                frontmatter[String(key)] = value
            }
        }

        return (frontmatter, body)
    }

    /// Extract the title from frontmatter `title:` field or first H1, fallback to filename.
    public static func extractTitle(from content: String, filename: String) -> String {
        // Try frontmatter title
        let (frontmatter, _) = parseFrontmatter(content)
        if let title = frontmatter["title"], !title.isEmpty {
            return title
        }

        // Try first H1
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }

        return filename
    }

    /// Extract tags from frontmatter `tags:` field and inline #tags in body.
    public static func extractTags(from frontmatter: [String: String], body: String) -> [String] {
        var tags = Set<String>()

        // Frontmatter tags (can be comma-separated)
        if let tagString = frontmatter["tags"] ?? frontmatter["tag"] {
            for tag in tagString.split(whereSeparator: { $0 == "," || $0 == " " }) {
                let cleaned = String(tag).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]"))
                if !cleaned.isEmpty {
                    tags.insert(cleaned.lowercased())
                }
            }
        }

        // Inline #tags in body (but not #headings, #hex-colors, or channel mentions)
        // Simple scanner: find '#' followed by letters
        var inTag = false
        var currentTag = ""
        for char in body {
            if char == "#" && !inTag {
                inTag = true
                currentTag = ""
            } else if inTag && (char.isLetter || char.isNumber || char == "/" || char == "_" || char == "-") {
                currentTag.append(char)
            } else if inTag {
                if !currentTag.isEmpty {
                    tags.insert(currentTag.lowercased())
                }
                inTag = false
                currentTag = ""
            }
        }
        if !currentTag.isEmpty {
            tags.insert(currentTag.lowercased())
        }

        return Array(tags).sorted()
    }

    /// Extract [[wikilink]] targets from body.
    public static func extractWikilinks(from body: String) -> [String] {
        var links: [String] = []
        var seen = Set<String>()

        // Scan for [[Target]] or [[Target|Display]]
        var i = body.startIndex
        while i < body.endIndex {
            // Look for "[["
            if body[i] == "[" && body.index(after: i) < body.endIndex && body[body.index(after: i)] == "[" {
                let contentStart = body.index(i, offsetBy: 2, limitedBy: body.endIndex) ?? body.endIndex
                // Find closing "]]"
                if let closeRange = body.range(of: "]]", range: contentStart..<body.endIndex) {
                    let linkContent = String(body[contentStart..<closeRange.lowerBound])
                    // Handle "|Display Text"
                    let target = linkContent.split(separator: "|").first.map {
                        String($0).trimmingCharacters(in: .whitespaces)
                    } ?? linkContent

                    if !target.isEmpty && !seen.contains(target) {
                        seen.insert(target)
                        links.append(target)
                    }
                    i = closeRange.upperBound
                } else {
                    i = body.index(after: i)
                }
            } else {
                i = body.index(after: i)
            }
        }

        return links
    }

    /// SHA-256 hex digest of content.
    public static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
