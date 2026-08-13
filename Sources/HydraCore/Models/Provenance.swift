import Foundation

// MARK: - Authority

/// Authority hierarchy for resolving conflicts between sources.
/// From the vault ingestion contract: Git receipts > control-plane ledger > CHANGELOG > observations > wiki notes.
/// Mirror is never authoritative.
public enum Authority: String, Sendable, Equatable, Comparable {
    case gitReceipt = "git"
    case controlPlaneLedger = "ledger"
    case changelog = "changelog"
    case observation = "observation"
    case wikiNote = "wiki"

    public static func < (lhs: Authority, rhs: Authority) -> Bool {
        Self.order(lhs) < Self.order(rhs)
    }

    /// Lower = higher authority.
    private static func order(_ a: Authority) -> Int {
        switch a {
        case .gitReceipt:         0
        case .controlPlaneLedger: 1
        case .changelog:          2
        case .observation:        3
        case .wikiNote:           4
        }
    }
}

// MARK: - Provenance

/// Where this artifact came from and how trustworthy its metadata is.
public struct Provenance: Sendable, Equatable {
    public var authority: Authority
    public var source: String          // repo path, file path, session ID
    public var digest: String          // content hash for integrity
    public var timestamp: Date
    public var actor: String?          // who/what produced this

    public static let unknown = Provenance(
        authority: .wikiNote,
        source: "unknown",
        digest: "",
        timestamp: .distantPast,
        actor: nil
    )

    public init(authority: Authority, source: String, digest: String, timestamp: Date, actor: String? = nil) {
        self.authority = authority
        self.source = source
        self.digest = digest
        self.timestamp = timestamp
        self.actor = actor
    }
}

// MARK: - Conflict

/// A single witness in a conflict — the authority level and the value it claims.
public struct ConflictWitness: Sendable, Equatable {
    public var authority: Authority
    public var value: String

    public init(authority: Authority, value: String) {
        self.authority = authority
        self.value = value
    }
}

/// When two sources disagree on a field value. Both witnesses are preserved — never silently flatten.
public struct Conflict: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var field: String               // e.g. "status", "lifecycle"
    public var witnessA: ConflictWitness
    public var witnessB: ConflictWitness
    public var resolvedValue: String       // higher authority wins
    public var resolvedAt: Date

    public init(
        id: UUID = UUID(),
        field: String,
        witnessA: ConflictWitness,
        witnessB: ConflictWitness,
        resolvedAt: Date = Date()
    ) {
        self.id = id
        self.field = field
        self.witnessA = witnessA
        self.witnessB = witnessB
        self.resolvedValue = witnessA.authority < witnessB.authority ? witnessA.value : witnessB.value
        self.resolvedAt = resolvedAt
    }
}
