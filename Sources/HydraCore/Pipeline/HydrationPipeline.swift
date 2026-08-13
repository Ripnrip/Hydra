import Foundation

// MARK: - Hydration Mode

/// How context enters the system. Backfill is one mode, not the identity.
public enum HydrationMode: Sendable, Equatable {
    case backfill         // historical batch — scan all sources for a time window
    case watch            // real-time — FS events trigger immediate hydration
    case adHoc            // interactive — human drags/pastes a file
    case query            // oracle — read-only traversal of the hydrated graph
}

// MARK: - Hydration Request

/// A request to hydrate context from sources into the vault.
public struct HydrationRequest: Sendable {
    public var mode: HydrationMode
    public var sources: [SourceConfig]
    public var window: DateInterval?       // nil = all time (backfill mode)
    public var targetVault: String         // path to Obsidian vault root
    public var targetOutbox: String?       // nil = own DB, path = external control plane
    public var exportDestinations: [ExportDestination]
    public var dryRun: Bool

    public init(
        mode: HydrationMode,
        sources: [SourceConfig],
        window: DateInterval? = nil,
        targetVault: String,
        targetOutbox: String? = nil,
        exportDestinations: [ExportDestination] = [],
        dryRun: Bool = false
    ) {
        self.mode = mode
        self.sources = sources
        self.window = window
        self.targetVault = targetVault
        self.targetOutbox = targetOutbox
        self.exportDestinations = exportDestinations
        self.dryRun = dryRun
    }
}

// MARK: - Source Config

/// Configuration for a source scanner.
public struct SourceConfig: Sendable, Equatable {
    public var kind: SourceKind
    public var path: String               // directory or file to scan
    public var recursive: Bool
    public var filePattern: String        // glob, e.g. "*.md"
    public var authority: Authority       // trust level for this source

    public init(kind: SourceKind, path: String, recursive: Bool = true, filePattern: String = "*.md", authority: Authority = .observation) {
        self.kind = kind
        self.path = path
        self.recursive = recursive
        self.filePattern = filePattern
        self.authority = authority
    }
}

// MARK: - Source Kind

public enum SourceKind: Sendable, Equatable, CaseIterable {
    case claudePlans      // ~/.claude/plans/*.md
    case claudeSessions   // ~/.claude/projects/*/sessions
    case codexSessions    // ~/.codex/
    case gitRepo          // docs/plans/, CHANGELOG, commits, PRs
    case changelog        // CHANGELOG.md, SETUP-LOG.md
    case claudeMem        // observations DB
    case obsidianVault    // existing vault notes
    case adHocFile        // drag-and-drop, paste
    case apiStream        // webhook/event stream
}

// MARK: - Export Destination

/// Pluggable output destination. Same core pipeline, different targets.
public struct ExportDestination: Sendable, Equatable {
    public var kind: ExportKind
    public var path: String?              // file/directory path for file-based exports
    public var endpoint: String?          // URL for API-based exports
    public var options: [String: String]

    public init(kind: ExportKind, path: String? = nil, endpoint: String? = nil, options: [String: String] = [:]) {
        self.kind = kind
        self.path = path
        self.endpoint = endpoint
        self.options = options
    }
}

public enum ExportKind: Sendable, Equatable, CaseIterable {
    case obsidian         // write to vault (primary)
    case jsonLD           // JSON-LD graph export
    case markdownPath     // markdown to custom directory
    case apiPush          // POST to configurable endpoint
    case stdout           // print to stdout (CLI)
}

// MARK: - Hydration Result

/// The outcome of a hydration pass — what was found, classified, projected, and exported.
public struct HydrationResult: Sendable {
    public var scanned: Int
    public var classified: Int
    public var projected: Int
    public var exported: Int
    public var conflicts: [Conflict]
    public var gaps: [Gap]
    public var artifacts: [SourceArtifact]
    public var duration: Duration

    public init(
        scanned: Int = 0,
        classified: Int = 0,
        projected: Int = 0,
        exported: Int = 0,
        conflicts: [Conflict] = [],
        gaps: [Gap] = [],
        artifacts: [SourceArtifact] = [],
        duration: Duration = .zero
    ) {
        self.scanned = scanned
        self.classified = classified
        self.projected = projected
        self.exported = exported
        self.conflicts = conflicts
        self.gaps = gaps
        self.artifacts = artifacts
        self.duration = duration
    }
}

// MARK: - Gap

/// Something missing from the vault that should be there.
public struct Gap: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var description: String
    public var severity: GapSeverity
    public var suggestedArtifact: SourceArtifact?

    public init(id: UUID = UUID(), description: String, severity: GapSeverity = .info, suggestedArtifact: SourceArtifact? = nil) {
        self.id = id
        self.description = description
        self.severity = severity
        self.suggestedArtifact = suggestedArtifact
    }
}

public enum GapSeverity: String, Sendable, Equatable, CaseIterable {
    case info       // nice to have
    case warning    // should address
    case critical   // blocking integrity issue
}
