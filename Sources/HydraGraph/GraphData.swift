import Foundation
import SwiftUI
import HydraCore

// MARK: - Graph Node

/// A node in the knowledge graph — represents a vault note, artifact, tag, or entity.
public struct GraphNode: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let category: NodeCategory
    public var size: CGFloat       // proportional to connection count
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    public var isFixed: Bool       // pinned by user

    public init(id: String, label: String, category: NodeCategory, size: CGFloat = 8) {
        self.id = id
        self.label = label
        self.category = category
        self.size = size
        self.position = SIMD2<Float>(Float.random(in: -200...200), Float.random(in: -200...200))
        self.velocity = .zero
        self.isFixed = false
    }
}

// MARK: - Node Category

public enum NodeCategory: String, Sendable, CaseIterable, Equatable {
    case session
    case project
    case plan
    case system
    case concept
    case journal
    case other

    public var color: Color {
        switch self {
        case .session:  Color(red: 0.70, green: 0.53, blue: 1.0)    // light purple
        case .project:  Color(red: 0.88, green: 0.53, blue: 0.28)   // warm orange
        case .plan:     Color(red: 0.49, green: 0.87, blue: 0.47)   // signal green
        case .system:   Color(red: 0.49, green: 0.30, blue: 1.0)    // deep purple
        case .concept:  Color(red: 0.90, green: 0.75, blue: 0.34)   // amber
        case .journal:  Color(red: 0.47, green: 0.47, blue: 0.56)   // slate
        case .other:    Color(red: 0.55, green: 0.51, blue: 0.63)   // muted purple-gray
        }
    }

    public var radius: CGFloat {
        switch self {
        case .session:  6
        case .project:  10
        case .plan:     8
        case .system:   9
        case .concept:  7
        case .journal:  5
        case .other:    5
        }
    }
}

// MARK: - Graph Edge

/// An edge between two nodes — wikilink, relationship, or tag co-occurrence.
public struct GraphEdge: Identifiable, Sendable, Equatable {
    public let id: String
    public let source: String    // node id
    public let target: String    // node id
    public let weight: Float     // connection strength
    public let kind: EdgeKind

    public init(source: String, target: String, weight: Float = 1.0, kind: EdgeKind = .wikilink) {
        self.id = "\(source)→\(target)"
        self.source = source
        self.target = target
        self.weight = weight
        self.kind = kind
    }
}

public enum EdgeKind: String, Sendable, Equatable {
    case wikilink
    case relationship
    case tagCooccurrence
    case crossReference
}

// MARK: - Knowledge Graph

/// The full graph model — nodes, edges, and adjacency.
public struct KnowledgeGraph: Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]
    public var adjacency: [String: [String]]  // nodeID → connected nodeIDs

    public init(nodes: [GraphNode] = [], edges: [GraphEdge] = []) {
        self.nodes = nodes
        self.edges = edges
        self.adjacency = KnowledgeGraph.buildAdjacency(nodes: nodes, edges: edges)
    }

    public var nodeCount: Int { nodes.count }
    public var edgeCount: Int { edges.count }

    public func node(id: String) -> GraphNode? {
        nodes.first { $0.id == id }
    }

    public func neighbors(of id: String) -> [GraphNode] {
        guard let neighbors = adjacency[id] else { return [] }
        return neighbors.compactMap { id in nodes.first { $0.id == id } }
    }

    /// Build a graph from a VaultInventory.
    public static func from(vaultNotes: [any VaultNoteProtocol]) -> KnowledgeGraph {
        var nodes: [GraphNode] = []
        var edges: [GraphEdge] = []
        var nodeIndex: [String: Int] = [:]

        for note in vaultNotes {
            let id = note.noteTitle.lowercased()
            guard nodeIndex[id] == nil else { continue }
            nodeIndex[id] = nodes.count

            let category = resolveCategory(from: note.paraPath)
            let connections = note.linkTargets.count
            nodes.append(GraphNode(
                id: id,
                label: note.noteTitle,
                category: category,
                size: CGFloat(5 + min(connections, 20))
            ))
        }

        // Build edges from wikilinks
        for note in vaultNotes {
            let sourceId = note.noteTitle.lowercased()
            for target in note.linkTargets {
                let targetId = target.lowercased()
                if nodeIndex[targetId] != nil {
                    edges.append(GraphEdge(source: sourceId, target: targetId))
                }
            }
        }

        return KnowledgeGraph(nodes: nodes, edges: edges)
    }

    private static func resolveCategory(from path: String) -> NodeCategory {
        if path.contains("07-Sessions") { .session }
        else if path.contains("Projects") { .project }
        else if path.contains("Systems") { .system }
        else if path.contains("Concepts") { .concept }
        else if path.contains("Journal") || path.contains("Daily") { .journal }
        else { .other }
    }

    private static func buildAdjacency(nodes: [GraphNode], edges: [GraphEdge]) -> [String: [String]] {
        var adj: [String: [String]] = [:]
        for edge in edges {
            adj[edge.source, default: []].append(edge.target)
            adj[edge.target, default: []].append(edge.source)
        }
        return adj
    }
}

// MARK: - Vault Note Protocol (for graph construction without coupling to HydraVault)

public protocol VaultNoteProtocol: Sendable {
    var noteTitle: String { get }
    var paraPath: String { get }
    var linkTargets: [String] { get }
}
