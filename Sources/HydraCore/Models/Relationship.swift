import Foundation

// MARK: - Relationship

/// A typed, potentially bidirectional connection between artifacts.
/// Not just wikilinks — these carry semantic meaning.
public struct Relationship: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var type: RelationshipType
    public var target: String        // artifact ID or vault path
    public var label: String?        // optional human-readable label
    public var bidirectional: Bool

    public init(
        id: UUID = UUID(),
        type: RelationshipType,
        target: String,
        label: String? = nil,
        bidirectional: Bool = false
    ) {
        self.id = id
        self.type = type
        self.target = target
        self.label = label
        self.bidirectional = bidirectional
    }
}

// MARK: - Relationship Type

public enum RelationshipType: String, Sendable, Equatable, CaseIterable {
    case implements       // this artifact implements another (plan → PR)
    case dependsOn = "depends-on"       // this artifact requires another to be useful
    case supersedes       // this artifact replaces an older one
    case references       // this artifact mentions another
    case childOf = "child-of"           // hierarchical containment
    case derivedFrom = "derived-from"   // this artifact was generated/extracted from another
    case relatesTo = "relates-to"       // generic association
    case blocks           // this artifact is blocked by another

    public var inverse: RelationshipType {
        switch self {
        case .implements:    return .references
        case .dependsOn:     return .blocks
        case .supersedes:    return .relatesTo  // inverse handled by caller (no .superseded case)
        case .references:    return .relatesTo
        case .childOf:       return .relatesTo
        case .derivedFrom:   return .references
        case .relatesTo:     return .relatesTo
        case .blocks:        return .dependsOn
        }
    }
}
