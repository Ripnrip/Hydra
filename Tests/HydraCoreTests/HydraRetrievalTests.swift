import Testing
import Foundation
@testable import HydraCore

// MARK: - HydraRetrieval Tests

@Suite("GraphTraversal")
struct GraphTraversalTests {

    @Test("Expands one hop from single seed")
    func oneHop() {
        let links = [
            NoteLink(source: "a", target: "b"),
            NoteLink(source: "b", target: "c"),
        ]
        let result = GraphTraversal.expand(seedIDs: ["a"], links: links, maxHops: 1, maxResults: 10)
        #expect(result.contains("a"))
        #expect(result.contains("b"))
        #expect(!result.contains("c"))  // 2 hops away, maxHops=1
    }

    @Test("Expands two hops")
    func twoHops() {
        let links = [
            NoteLink(source: "a", target: "b"),
            NoteLink(source: "b", target: "c"),
        ]
        let result = GraphTraversal.expand(seedIDs: ["a"], links: links, maxHops: 2, maxResults: 10)
        #expect(result.contains("a"))
        #expect(result.contains("b"))
        #expect(result.contains("c"))
    }

    @Test("Respects maxResults cap")
    func maxResultsCap() {
        // Star graph: center connected to 10 leaves
        let links = (1...10).map { NoteLink(source: "center", target: "leaf\($0)") }
        let result = GraphTraversal.expand(seedIDs: ["center"], links: links, maxHops: 2, maxResults: 5)
        #expect(result.count <= 5)
    }

    @Test("Bidirectional traversal")
    func bidirectional() {
        // Link is a→b, but BFS should find b from a AND a from b
        let links = [NoteLink(source: "a", target: "b")]
        let fromB = GraphTraversal.expand(seedIDs: ["b"], links: links, maxHops: 1, maxResults: 10)
        #expect(fromB.contains("a"))
    }

    @Test("No links returns seeds only")
    func noLinks() {
        let result = GraphTraversal.expand(seedIDs: ["x"], links: [], maxHops: 3, maxResults: 10)
        #expect(result == ["x"])
    }
}

@Suite("LocalSemanticIndex")
struct LocalSemanticIndexTests {

    @Test("Embedding is deterministic")
    func deterministicEmbedding() {
        let a = LocalSemanticIndex.embed("hello world vault notes")
        let b = LocalSemanticIndex.embed("hello world vault notes")
        #expect(a == b)
    }

    @Test("Embedding has correct dimensions")
    func dimensions() {
        let v = LocalSemanticIndex.embed("test")
        #expect(v.count == LocalSemanticIndex.dimensions)
    }

    @Test("Embedding is normalized")
    func normalized() {
        let v = LocalSemanticIndex.embed("some longer text with multiple tokens for normalization testing")
        let magnitude = sqrt(v.reduce(Float.zero) { $0 + $1 * $1 })
        #expect(abs(magnitude - 1.0) < 0.01)
    }

    @Test("Identical text has similarity 1.0")
    func identicalSimilarity() {
        let v = LocalSemanticIndex.embed("swift package manager")
        let score = LocalSemanticIndex.cosine(v, v)
        #expect(abs(score - 1.0) < 0.01)
    }

    @Test("Different text has lower similarity than similar text")
    func ranking() async {
        let index = LocalSemanticIndex()
        await index.build(from: [
            (id: "swift", title: "Swift Packages", tags: ["swift"], content: "swift package manager dependencies spm"),
            (id: "python", title: "Python Scripts", tags: ["python"], content: "python automation scripts requests"),
            (id: "network", title: "Network Config", tags: ["network"], content: "tailscale vpn mesh network configuration"),
        ])

        let results = await index.search("swift package dependencies", limit: 2)
        #expect(!results.isEmpty)
        #expect(results[0].id == "swift")
    }

    @Test("Empty index returns no results")
    func emptyIndex() async {
        let index = LocalSemanticIndex()
        let results = await index.search("anything", limit: 5)
        #expect(results.isEmpty)
    }
}

@Suite("HybridRAGQuery")
struct HybridRAGTests {

    @Test("Full pipeline: semantic + graph expansion")
    func fullPipeline() async {
        let index = LocalSemanticIndex()
        await index.build(from: [
            (id: "arch", title: "System Architecture", tags: ["architecture"], content: "system architecture design patterns components"),
            (id: "deps", title: "Package Dependencies", tags: ["dependencies"], content: "package dependencies swift modules"),
            (id: "net", title: "Network Setup", tags: ["network"], content: "tailscale network mesh vpn"),
            (id: "unrelated", title: "Recipes", tags: ["cooking"], content: "pasta sauce garlic tomatoes dinner"),
        ])

        let links = [
            NoteLink(source: "arch", target: "deps"),   // arch ↔ deps connected
            NoteLink(source: "deps", target: "net"),     // deps ↔ net connected
        ]

        let query = HybridRAGQuery()
        let result = await query.run(
            query: "architecture design",
            index: index,
            links: links,
            titleFor: { id in
                switch id {
                case "arch": "System Architecture"
                case "deps": "Package Dependencies"
                case "net": "Network Setup"
                default: id
                }
            }
        )

        // Architecture should be the top semantic hit
        #expect(result.semanticHits.first?.id == "arch")

        // deps and net should be found via graph expansion
        let graphIDs = result.graphHits.map(\.id)
        #expect(graphIDs.contains("deps"))
        #expect(graphIDs.contains("net"))

        // Answer should mention the query
        #expect(result.answer.contains("architecture design"))

        // Recipes should not appear
        #expect(!result.allNoteIDs.contains("unrelated"))
    }

    @Test("No match returns graceful answer")
    func noMatch() async {
        let index = LocalSemanticIndex()
        await index.build(from: [
            (id: "a", title: "Alpha", tags: [], content: "alpha beta gamma"),
        ])

        let query = HybridRAGQuery()
        let result = await query.run(
            query: "completely unrelated quantum physics zebra",
            index: index,
            links: [],
            titleFor: { $0 }
        )

        #expect(result.semanticHits.isEmpty)
        #expect(result.answer.contains("No notes matched"))
    }
}
