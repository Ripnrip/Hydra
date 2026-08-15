import Foundation
import HydraCore

// MARK: - Vault Inventory

/// A complete snapshot of an Obsidian vault at a point in time.
/// All derived data is EAGERLY precomputed at init (one-time cost, then free reads).
/// This is the performance contract: tagFrequency, adjacencyList, rankedNotes etc.
/// are stored properties — zero per-access cost. Critical for SwiftUI views that
/// read these per-frame.
public struct VaultInventory: Sendable {

    public let vaultRoot: String
    public let notes: [VaultNote]
    public let scannedAt: Date

    // MARK: - Precomputed derived data (stored, not computed)

    /// All unique tags with frequency, sorted by count desc.
    public let tagFrequency: [(tag: String, count: Int)]

    /// Wikilink targets that resolve to no note.
    public let brokenWikilinks: [String]

    /// Notes with no incoming links.
    public let orphanedNotes: [VaultNote]

    /// Lowercased title → index in notes. O(1) lookup.
    public let titleIndex: [String: Int]

    /// Bidirectional adjacency (wikilinks + backlinks).
    public let adjacencyList: [String: [String]]

    /// Connection count per lowercased title.
    public let connectionCounts: [String: Int]

    /// Notes sorted by connectivity desc, then recency desc.
    public let rankedNotes: [VaultNote]

    // MARK: - Init (precomputes everything)

    public init(vaultRoot: String, notes: [VaultNote], scannedAt: Date = Date()) {
        self.vaultRoot = vaultRoot
        self.notes = notes
        self.scannedAt = scannedAt

        // Precompute ALL derived data once — the one-time cost of a scan
        var tagCounts: [String: Int] = [:]
        var adj: [String: [String]] = [:]
        var titleIdx: [String: Int] = [:]

        for (i, note) in notes.enumerated() {
            let key = note.title.lowercased()
            if titleIdx[key] == nil { titleIdx[key] = i }
            for tag in note.tags {
                tagCounts[tag, default: 0] += 1
            }
            adj[key, default: []].append(contentsOf: note.wikilinks.map { $0.lowercased() })
            for link in note.wikilinks {
                adj[link.lowercased(), default: []].append(key)
            }
        }

        self.tagFrequency = tagCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (tag: $0.key, count: $0.value) }

        let titleSet = Set(titleIdx.keys)
        let allLinks = Set(adj.keys)
        self.brokenWikilinks = Array(allLinks.subtracting(titleSet)).sorted()

        self.orphanedNotes = notes.filter { $0.orphaned }
        self.titleIndex = titleIdx
        self.adjacencyList = adj

        var counts: [String: Int] = [:]
        for (key, links) in adj { counts[key] = links.count }
        self.connectionCounts = counts

        self.rankedNotes = notes.sorted { a, b in
            let ac = counts[a.title.lowercased()] ?? 0
            let bc = counts[b.title.lowercased()] ?? 0
            if ac != bc { return ac > bc }
            return a.modifiedDate > b.modifiedDate
        }
    }

    // MARK: - Convenience (all O(1) or O(n) simple filters)

    public var noteCount: Int { notes.count }

    public func notes(in category: PARACategory) -> [VaultNote] {
        notes.filter { $0.paraCategory == category }
    }

    public func notes(modifiedSince date: Date) -> [VaultNote] {
        notes.filter { $0.modifiedDate >= date }
    }

    public var notesMissingFrontmatter: [VaultNote] {
        notes.filter { !$0.hasFrontmatter }
    }

    /// O(1) title lookup.
    public func note(titled title: String) -> VaultNote? {
        guard let idx = titleIndex[title.lowercased()], idx < notes.count else { return nil }
        return notes[idx]
    }
}
