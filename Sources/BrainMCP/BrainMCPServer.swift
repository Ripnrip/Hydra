import Foundation
import BrainCore
import BrainVault
import BrainHealth

// MARK: - MCP Tool Definitions

/// MCP tools exposed to Claude Code and other agents.
/// Focused on Claude stdio transport for now.
public enum MCPTool: String, Sendable, CaseIterable {
    case hydrate       // trigger a hydration pass
    case search        // search the vault
    case healthCheck   = "health_check"
    case relationships // query relationship graph
    case gaps          // gap analysis
    case timeline      // chronological view
    case tagReport     = "tag_report"
    case projectNote   // project a single artifact into the vault

    public var description: String {
        switch self {
        case .hydrate:       return "Trigger a context hydration pass from configured sources"
        case .search:        return "Search vault notes by text, tag, or relationship"
        case .healthCheck:   return "Run vault health checks and return the report"
        case .relationships: return "Query the relationship graph for an artifact"
        case .gaps:          return "Analyze gaps in the vault (missing plans, unlinked sessions)"
        case .timeline:      return "Get a chronological timeline of vault entries"
        case .tagReport:     return "Report on tag usage, variants, and dedup suggestions"
        case .projectNote:   return "Project a single artifact into the vault"
        }
    }

    public var inputSchema: [String: String] {
        switch self {
        case .hydrate:
            return ["mode": "string (backfill|watch|adHoc)", "sources": "array", "dry_run": "boolean"]
        case .search:
            return ["query": "string", "tag": "string?", "limit": "int?"]
        case .healthCheck:
            return ["vault_path": "string"]
        case .relationships:
            return ["artifact_id": "string?", "depth": "int?"]
        case .gaps:
            return ["severity": "string?"]
        case .timeline:
            return ["from": "string?", "to": "string?", "limit": "int?"]
        case .tagReport:
            return ["include_variants": "boolean"]
        case .projectNote:
            return ["source_path": "string", "dry_run": "boolean"]
        }
    }
}

// MARK: - MCP Server

/// Minimal JSON-RPC 2.0 server for Claude stdio transport.
/// Reads requests from stdin, writes responses to stdout.
public actor BrainMCPServer {
    private let vaultRoot: String

    public init(vaultRoot: String) {
        self.vaultRoot = vaultRoot
    }

    /// Run the server — reads JSON-RPC from stdin, writes to stdout.
    public func run() async {
        let stdin = FileHandle.standardInput

        // Announce available tools
        let initResponse = initializeResponse()
        print(initResponse)
        fflush(stdout)

        // Read loop
        let bufferSize = 65536
        while true {
            let data = stdin.availableData
            if data.isEmpty { break }

            guard let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                continue
            }

            let response = await handle(line)
            print(response)
            fflush(stdout)
        }
    }

    // MARK: - Request handling

    private func handle(_ json: String) async -> String {
        // Parse JSON-RPC request
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = parsed["method"] as? String else {
            return errorResponse(id: 0, code: -32700, message: "Parse error")
        }

        let request = parsed
        let id = request["id"] ?? NSNull()

        switch method {
        case "tools/list":
            return toolsListResponse(id: id)

        case "tools/call":
            let params = request["params"] as? [String: Any] ?? [:]
            guard let toolName = params["name"] as? String else {
                return errorResponse(id: id, code: -32602, message: "Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = await handleToolCall(name: toolName, arguments: arguments)
            return resultResponse(id: id, result: result)

        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func handleToolCall(name: String, arguments: [String: Any]) async -> [String: Any] {
        guard let tool = MCPTool(rawValue: name) else {
            return ["error": "Unknown tool: \(name)"]
        }

        switch tool {
        case .healthCheck:
            let scanner = VaultScanner(vaultRoot: vaultRoot)
            do {
                let inventory = try await scanner.scan()
                let checker = HealthChecker()
                let report = checker.checkAll(inventory)
                return [
                    "status": report.overallStatus.rawValue,
                    "summary": report.summary,
                    "checks": report.checks.map { check -> [String: Any] in
                        [
                            "name": check.name,
                            "status": check.status.rawValue,
                            "message": check.message,
                            "count": check.affectedCount
                        ]
                    }
                ]
            } catch {
                return ["error": "Scan failed: \(error.localizedDescription)"]
            }

        case .search:
            let query = arguments["query"] as? String ?? ""
            let scanner = VaultScanner(vaultRoot: vaultRoot)
            do {
                let inventory = try await scanner.scan()
                let results = inventory.notes.filter { note in
                    note.title.localizedCaseInsensitiveContains(query)
                    || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                }
                return [
                    "count": results.count,
                    "results": results.prefix(20).map { note -> [String: Any] in
                        [
                            "title": note.title,
                            "path": note.relativePath,
                            "tags": note.tags,
                            "modified": ISO8601DateFormatter().string(from: note.modifiedDate)
                        ]
                    }
                ]
            } catch {
                return ["error": "Scan failed: \(error.localizedDescription)"]
            }

        default:
            return ["status": "not_yet_implemented", "tool": name]
        }
    }

    // MARK: - JSON-RPC responses

    private func initializeResponse() -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": [
                "protocolVersion": "2024-11-05",
                "serverInfo": [
                    "name": "brain-oracle",
                    "version": "0.1.0"
                ]
            ]
        ]
        return jsonString(response)
    }

    private func toolsListResponse(id: Any) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": [
                "tools": MCPTool.allCases.map { tool -> [String: Any] in
                    [
                        "name": tool.rawValue,
                        "description": tool.description,
                        "inputSchema": ["type": "object", "properties": tool.inputSchema]
                    ]
                }
            ]
        ]
        return jsonString(response)
    }

    private func resultResponse(id: Any, result: [String: Any]) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": [
                "content": [
                    ["type": "text", "text": jsonString(result)]
                ]
            ]
        ]
        return jsonString(response)
    }

    private func errorResponse(id: Any, code: Int, message: String) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message]
        ]
        return jsonString(response)
    }

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
