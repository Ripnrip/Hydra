import Foundation

// MARK: - HydraRetrieval — Graph RAG for the Oracle
// Ported from Ripnrip/obsidian-graph-rag-platform GraphRAGKit.
// Semantic search (on-device, no API keys) + graph BFS expansion + grounded answers.

// MARK: - Graph Traversal

/// Bounded BFS expansion over the vault's wikilink adjacency.
/// From GraphRAGKit GraphTraversal.swift — proven in production.
public enum GraphTraversal {
    /// Expand from seed notes to their neighbors, bounded by hops and result count.
    /// - Parameters:
    ///   - seedIDs: starting note identifiers (typically vector-search hits)
    ///   - links: all note-to-note links in the vault
    ///   - maxHops: BFS depth (2 = seed → neighbor → neighbor-of-neighbor)
    ///   - maxResults: hard cap on returned IDs
    /// - Returns: ordered IDs — seeds first, then nearest neighbors outward
    public static func expand(
        seedIDs: [String],
        links: [NoteLink],
        maxHops: Int = 2,
        maxResults: Int = 24
    ) -> [String] {
        // Build bidirectional adjacency
        let adjacency = Dictionary(
            grouping: links.flatMap { [($0.source, $0.target), ($0.target, $0.source)] },
            by: \.0
        ).mapValues { $0.map(\.1) }

        var visited = Set(seedIDs)
        var ordered = seedIDs
        var frontier = seedIDs

        for _ in 0..<maxHops where !frontier.isEmpty && ordered.count < maxResults {
            var next: [String] = []
            for noteID in frontier {
                for neighbor in adjacency[noteID, default: []] where visited.insert(neighbor).inserted {
                    ordered.append(neighbor)
                    next.append(neighbor)
                    if ordered.count == maxResults { break }
                }
                if ordered.count == maxResults { break }
            }
            frontier = next
        }
        return ordered
    }
}

// MARK: - Note Link

/// A directed link between two notes (wikilink).
public struct NoteLink: Sendable, Equatable, Hashable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

// MARK: - Local Semantic Search

/// On-device semantic search using hashed bag-of-words embeddings.
/// From GraphRAGKit LocalSemanticSearchClient — zero API keys, fully offline.
/// 256 dimensions, FNV-1a token hashing, L2 normalization, cosine ranking.
public actor LocalSemanticIndex {

    /// Embedding dimensions. 256 is enough for vault-scale semantic ranking.
    public static let dimensions = 256

    /// Notes below this cosine similarity are considered irrelevant.
    public static let similarityFloor: Float = 0.18

    private var indexed: [(id: String, title: String, snippet: String, embedding: [Float])] = []
    private var isBuilt = false

    public init() {}

    // MARK: - Indexing

    /// Build the index from vault notes. Call after each vault scan.
    public func build(from notes: [(id: String, title: String, tags: [String], content: String)]) {
        indexed = notes.map { note in
            let text = "\(note.title) \(note.tags.joined(separator: " ")) \(note.content)"
            return (note.id, note.title, String(note.content.prefix(200)), Self.embed(text))
        }
        isBuilt = true
    }

    public var noteCount: Int { indexed.count }
    public var isReady: Bool { isBuilt && !indexed.isEmpty }

    // MARK: - Query

    /// Find the top-K notes most similar to the query text.
    /// - Returns: (noteID, title, snippet, score) sorted by descending similarity.
    public func search(_ query: String, limit: Int = 6) -> [(id: String, title: String, snippet: String, score: Float)] {
        let queryVector = Self.embed(query)

        var scored: [(id: String, title: String, snippet: String, score: Float)] = []
        for item in indexed {
            let score = Self.cosine(queryVector, item.embedding)
            if score >= Self.similarityFloor {
                scored.append((item.id, item.title, item.snippet, score))
            }
        }
        scored.sort { $0.score > $1.score }

        let count = min(limit, scored.count)
        return Array(scored[0..<count])
    }

    // MARK: - Embedding (hashed bag-of-words)

    /// Deterministic 256-dim embedding: tokenize, hash each token to a bucket, count, normalize.
    /// No ML model — pure feature hashing. Fast, offline, surprisingly effective for vault-scale retrieval.
    public static func embed(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }

        for token in tokens {
            // FNV-1a hash → bucket
            let hash = token.utf8.reduce(UInt64(1_469_598_103_934_665_603)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
            let index = Int(hash % UInt64(dimensions))
            vector[index] += 1
        }

        // L2 normalize
        let magnitude = sqrt(vector.reduce(Float.zero) { $0 + $1 * $1 })
        return magnitude > 0 ? vector.map { $0 / magnitude } : vector
    }

    /// Cosine similarity (vectors are pre-normalized, so this is just dot product).
    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        for i in 0..<lhs.count {
            dot += lhs[i] * rhs[i]
        }
        return dot
    }
}

// MARK: - Hybrid RAG Query

/// The full Graph RAG pipeline: semantic seeds → graph expansion → ranked results.
/// Parameters match the proven web implementation (0.18 floor, top-6 seeds, depth-2, 24 nodes).
public struct HybridRAGQuery: Sendable {

    public struct Result: Sendable {
        public let query: String
        public let semanticHits: [(id: String, title: String, snippet: String, score: Float)]
        public let graphHits: [(id: String, title: String)]
        public let allNoteIDs: [String]

        public var answer: String {
            guard !semanticHits.isEmpty else {
                return "No notes matched \"\(query)\". Try a more specific term, tag, or phrase from your vault."
            }

            var lines = ["**Results for \"\(query)\"**", ""]
            lines.append("*Semantic matches:*")
            for hit in semanticHits.prefix(4) {
                let clean = hit.snippet
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("- **\(hit.title)** (\(Int(hit.score * 100))% match) — \(String(clean.prefix(160)))")
            }

            if !graphHits.isEmpty {
                lines.append("")
                lines.append("*Related via graph:*")
                for hit in graphHits.prefix(6) {
                    lines.append("- \(hit.title)")
                }
            }

            lines.append("")
            lines.append("_\(semanticHits.count + graphHits.count) notes found — \(semanticHits.count) semantic, \(graphHits.count) via \(graphHits.isEmpty ? 0 : 1)+ hop graph expansion_")
            return lines.joined(separator: "\n")
        }
    }

    public init() {}

    /// Run the full hybrid retrieval.
    /// - Parameters:
    ///   - query: natural language question
    ///   - index: built semantic index
    ///   - links: vault wikilinks for graph expansion
    ///   - titleFor: closure resolving note ID → display title
    public func run(
        query: String,
        index: LocalSemanticIndex,
        links: [NoteLink],
        titleFor: @Sendable (String) -> String
    ) async -> Result {
        // Step 1: semantic search for seeds
        let semantic = await index.search(query, limit: 6)
        let seedIDs = semantic.map(\.id)

        // Step 2: BFS graph expansion from semantic seeds
        let expanded = GraphTraversal.expand(
            seedIDs: seedIDs,
            links: links,
            maxHops: 2,
            maxResults: 24
        )

        // Step 3: separate semantic hits from graph-only hits
        let seedSet = Set(seedIDs)
        let graphOnly = expanded
            .filter { !seedSet.contains($0) }
            .map { (id: $0, title: titleFor($0)) }

        return Result(
            query: query,
            semanticHits: semantic,
            graphHits: graphOnly,
            allNoteIDs: expanded
        )
    }
}
