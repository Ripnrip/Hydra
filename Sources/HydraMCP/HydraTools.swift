// HydraTools.swift — typed MCP tool catalog: real JSON Schemas and typed
// arguments. Replaces the stringly-typed `[String: String]` schema maps
// (Exhibit 1: the schema existed but lied about its own types).
//
// Wire names are kept EXACTLY as the previous server exposed them
// (hydrate, search, health_check, relationships, gaps, timeline,
// tag_report, projectNote) so existing client registrations keep working.
// The casing inconsistency (snake vs camel) is noted here, not silently
// "fixed" — renaming tools is a client-breaking change and belongs to a
// deliberate version bump, not a rewrite PR.

import Foundation

// MARK: - Tool catalog

struct HydraTool: Encodable, Sendable {
    struct Property: Encodable, Sendable {
        let type: String
        let description: String
    }

    struct InputSchema: Encodable, Sendable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
    }

    let name: String
    let description: String
    let inputSchema: InputSchema
}

extension HydraTool {
    static let search = HydraTool(
        name: "search",
        description: "Search vault notes by title text or tag.",
        inputSchema: InputSchema(
            properties: [
                "query": Property(type: "string", description: "Text to match against note titles (case-insensitive)"),
                "tag": Property(type: "string", description: "When set, restrict results to notes carrying this tag"),
                "limit": Property(type: "integer", description: "Maximum results to return (default 20)"),
            ],
            required: ["query"]
        )
    )

    static let healthCheck = HydraTool(
        name: "health_check",
        description: "Run vault health checks and return the report.",
        inputSchema: InputSchema(
            properties: [
                "vault_path": Property(
                    type: "string",
                    description: "Reserved — currently scans the configured vault root; accepted for schema compatibility."
                ),
            ],
            required: []
        )
    )

    static let hydrate = HydraTool(
        name: "hydrate",
        description: "Trigger a context hydration pass from configured sources.",
        inputSchema: InputSchema(
            properties: [
                "mode": Property(type: "string", description: "backfill | watch | adHoc"),
                "sources": Property(type: "array", description: "Source selectors"),
                "dry_run": Property(type: "boolean", description: "Preview without writing"),
            ],
            required: []
        )
    )

    static let relationships = HydraTool(
        name: "relationships",
        description: "Query the relationship graph for an artifact.",
        inputSchema: InputSchema(
            properties: [
                "artifact_id": Property(type: "string", description: "Artifact to center the query on"),
                "depth": Property(type: "integer", description: "Graph traversal depth"),
            ],
            required: []
        )
    )

    static let gaps = HydraTool(
        name: "gaps",
        description: "Analyze gaps in the vault (missing plans, unlinked sessions).",
        inputSchema: InputSchema(
            properties: [
                "severity": Property(type: "string", description: "Filter by severity"),
            ],
            required: []
        )
    )

    static let timeline = HydraTool(
        name: "timeline",
        description: "Get a chronological timeline of vault entries.",
        inputSchema: InputSchema(
            properties: [
                "from": Property(type: "string", description: "ISO8601 lower bound"),
                "to": Property(type: "string", description: "ISO8601 upper bound"),
                "limit": Property(type: "integer", description: "Maximum entries"),
            ],
            required: []
        )
    )

    static let tagReport = HydraTool(
        name: "tag_report",
        description: "Report on tag usage, variants, and dedup suggestions.",
        inputSchema: InputSchema(
            properties: [
                "include_variants": Property(type: "boolean", description: "Include variant groupings"),
            ],
            required: []
        )
    )

    static let projectNote = HydraTool(
        name: "projectNote",
        description: "Project a single artifact into the vault.",
        inputSchema: InputSchema(
            properties: [
                "source_path": Property(type: "string", description: "Path of the artifact to project"),
                "dry_run": Property(type: "boolean", description: "Preview without writing"),
            ],
            required: ["source_path"]
        )
    )

    static let all: [HydraTool] = [
        .search, .healthCheck, .hydrate, .relationships, .gaps, .timeline, .tagReport, .projectNote,
    ]
}

// MARK: - Typed arguments

struct SearchArguments: Decodable, Sendable {
    let query: String
    let tag: String?
    let limit: Int?
}

struct HealthCheckArguments: Decodable, Sendable {
    let vaultPath: String?

    private enum CodingKeys: String, CodingKey {
        case vaultPath = "vault_path"
    }
}

// MARK: - Typed results
// Result payloads are Encodable models — JSONEncoder (`.sortedKeys`,
// `.iso8601` dates) owns formatting; no hand-built dictionaries.

struct SearchHit: Encodable, Sendable {
    let title: String
    let path: String
    let tags: [String]
    let modified: Date
}

struct SearchResult: Encodable, Sendable {
    let count: Int
    let results: [SearchHit]
}

struct HealthCheckLine: Encodable, Sendable {
    let name: String
    let status: String
    let message: String
    let count: Int
}

struct HealthCheckSummary: Encodable, Sendable {
    let status: String
    let summary: String
    let checks: [HealthCheckLine]
}
