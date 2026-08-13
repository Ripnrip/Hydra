import Foundation

/// A discrete unit of context discovered from a source (plan, session, changelog, git commit, ad-hoc file).
/// Flows through the hydration pipeline: scan → classify → enrich → outbox → project.
public struct SourceArtifact: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var sourcePath: String
    public var kind: ArtifactKind
    public var title: String
    public var content: String
    public var frontmatter: [String: String]
    public var tags: [String]
    public var wikilinks: [String]
    public var provenance: Provenance
    public var lifecycleState: LifecycleState
    public var deliveryState: DeliveryState
    public var confidence: Double
    public var relationships: [Relationship]
    public var colorTag: ColorTag?

    public init(
        id: UUID = UUID(),
        sourcePath: String,
        kind: ArtifactKind = .other(""),
        title: String = "",
        content: String = "",
        frontmatter: [String: String] = [:],
        tags: [String] = [],
        wikilinks: [String] = [],
        provenance: Provenance = .unknown,
        lifecycleState: LifecycleState = .draft,
        deliveryState: DeliveryState = .submitted,
        confidence: Double = 0.0,
        relationships: [Relationship] = [],
        colorTag: ColorTag? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.kind = kind
        self.title = title
        self.content = content
        self.frontmatter = frontmatter
        self.tags = tags
        self.wikilinks = wikilinks
        self.provenance = provenance
        self.lifecycleState = lifecycleState
        self.deliveryState = deliveryState
        self.confidence = confidence
        self.relationships = relationships
        self.colorTag = colorTag
    }
}
