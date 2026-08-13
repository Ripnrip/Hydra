import Foundation
import BrainCore

// MARK: - Vault Inventory

/// A complete snapshot of an Obsidian vault at a point in time.
/// Used by the health system, oracle queries, and the writer to avoid duplicates.
public struct VaultInventory: Sendable {
    public var vaultRoot: String
    public var notes: [VaultNote]
    public var scannedAt: Date

    public init(vaultRoot: String, notes: [VaultNote], scannedAt: Date) {
        self.vaultRoot = vaultRoot
        self.notes = notes
        self.scannedAt = scannedAt
    }

    // MARK: - Derived data

    public var noteCount: Int { notes.count }

    /// All unique tags across the vault, with frequency.
    public var tagFrequency: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for note in notes {
            for tag in note.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (tag: $0.key, count: $0.value) }
    }

    /// All unique wikilink targets that don't resolve to any note title (broken links).
    public var brokenWikilinks: [String] {
        let titles = Set(notes.map { $0.title.lowercased() })
        let allLinks = Set(notes.flatMap { $0.wikilinks.map { $0.lowercased() } })
        return Array(allLinks.subtracting(titles)).sorted()
    }

    /// Notes with no incoming wikilinks (orphans in the graph).
    public var orphanedNotes: [VaultNote] {
        notes.filter { $0.orphaned }
    }

    /// Notes by PARA category.
    public func notes(in category: PARACategory) -> [VaultNote] {
        notes.filter { $0.paraCategory == category }
    }

    /// Notes modified within the given time interval.
    public func notes(modifiedSince date: Date) -> [VaultNote] {
        notes.filter { $0.modifiedDate >= date }
    }

    /// Notes missing frontmatter entirely.
    public var notesMissingFrontmatter: [VaultNote] {
        notes.filter { !$0.hasFrontmatter }
    }

    /// Find a note by title (case-insensitive).
    public func note(titled title: String) -> VaultNote? {
        notes.first { $0.title.lowercased() == title.lowercased() }
    }

    /// Build a simple adjacency list from wikilinks for graph traversal.
    public var adjacencyList: [String: [String]] {
        var graph: [String: [String]] = [:]
        for note in notes {
            graph[note.title.lowercased()] = note.wikilinks.map { $0.lowercased() }
        }
        return graph
    }
}
