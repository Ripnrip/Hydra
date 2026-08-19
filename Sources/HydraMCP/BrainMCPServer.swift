// BrainMCPServer.swift — typed MCP stdio server for Hydra.
//
// Rewrite of the dynamic-JSON server (swift-canon Exhibit 1: JSONSerialization
// dictionaries, `try?` casting at the trust boundary, `Any` ids echoed via
// NSNull). Shapes ported from Ripnrip/Andromeda AndromedaMCP @ 1d8920b:
// typed envelopes (RPC.swift), notification law (`id` omitted = never reply;
// explicit `"id": null` = -32600), real initialize handshake, ping, real
// JSON Schemas, typed tool arguments, and line-framed stdin — the old loop
// read arbitrary chunks, so two requests arriving together parsed as one
// garbage message and a split request silently died.
//
// Pure core / effect shell: `handle(line:)` is the testable typed core;
// `run()` is the only effect (stdin/stdout).

import Foundation
import HydraCore
import HydraVault
import HydraHealth

/// Minimal id-only probe for salvaging a well-formed id out of an
/// otherwise-invalid envelope (JSON-RPC 2.0: reply with the request's id
/// when detectable, null only when it is not).
private struct IDSalvage: Decodable {
    let id: RPCID?
}

// MARK: - MCP Server

/// Typed JSON-RPC 2.0 server for the Claude stdio transport.
/// Reads newline-delimited requests from stdin, writes responses to stdout.
public actor HydraMCPServer {
    private let vaultRoot: String

    public init(vaultRoot: String) {
        self.vaultRoot = vaultRoot
    }

    /// Run the server: line-framed stdin loop, responses to stdout.
    /// Never volunteers messages — the old server printed an unrequested
    /// initialize result at startup and then answered the client's actual
    /// `initialize` with `-32601`.
    public func run() async {
        let stdin = FileHandle.standardInput
        var buffer = Data()

        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                // EOF — flush any trailing line that lacked a newline.
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                    await reply(to: line)
                }
                return
            }
            buffer.append(chunk)
            // Frame on newlines: a chunk may carry several requests, and a
            // request may span several chunks. Both are now correct.
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                if let line = String(data: lineData, encoding: .utf8) {
                    await reply(to: line)
                }
            }
        }
    }

    private func reply(to line: String) async {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // handle() returns the COMPLETE encoded response line — write it as
        // bytes directly. (Passing it through the encoder again would ship a
        // JSON string literal instead of a JSON-RPC object.)
        guard let response = await handle(line: trimmed) else { return }
        FileHandle.standardOutput.write(Data(response.utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    // MARK: - Request handling (pure core)

    /// Handle one JSON-RPC line. Returns the response line, or `nil` for
    /// messages that must not be answered (notifications) and lines that
    /// cannot produce honest output (empty/non-UTF8/impossible encodes).
    public func handle(line: String) async -> String? {
        guard let data = line.data(using: .utf8) else { return nil }

        // Stage 1 — syntax only: -32700 is reserved for bytes that are not
        // JSON at all. (JSONSerialization is a syntax gate here, not a
        // typing layer — everything typed stays Codable.)
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return Self.encoded(RPCErrorResponse(id: nil, code: .parseError, message: "Parse error"))
        }

        let header: RPCRequestHeader
        switch Self.decode(RPCRequestHeader.self, from: data, id: nil) {
        case .ok(let decoded): header = decoded
        case .reply(let line): return line.isEmpty ? nil : line
        }

        // JSON-RPC 2.0: a message whose `id` key is OMITTED is a
        // notification — the server MUST NOT reply, whatever the method.
        // An explicit `"id": null` is not a notification (and not a valid
        // id either) — it gets an invalid-request error so the caller is
        // never left waiting.
        if header.id == nil {
            if header.idOmitted { return nil }
            return Self.encoded(RPCErrorResponse(
                id: nil,
                code: .invalidRequest,
                message: "Invalid request: id must be a number or string when present, not null"
            ))
        }

        // A valid JSON-RPC 2.0 envelope names its version; anything else is
        // an invalid request (id preserved), never a method dispatch.
        guard header.jsonrpc == "2.0" else {
            return Self.encoded(RPCErrorResponse(
                id: header.id,
                code: .invalidRequest,
                message: "Invalid request: jsonrpc must be \"2.0\""
            ))
        }

        switch header.method {
        case "initialize":
            switch Self.decode(RPCRequest<StrictJSONObject>.self, from: data, id: header.id) {
            case .ok(let request):
                return Self.encoded(RPCResult(id: request.id, result: InitializeResult()))
            case .reply(let line): return line.isEmpty ? nil : line
            }

        case "ping":
            // MCP 2025-06-18: the receiver MUST respond to a ping request
            // promptly with an (empty) result.
            switch Self.decode(RPCRequest<StrictJSONObject>.self, from: data, id: header.id) {
            case .ok(let request):
                return Self.encoded(RPCResult(id: request.id, result: EmptyResult()))
            case .reply(let line): return line.isEmpty ? nil : line
            }

        case "tools/list":
            switch Self.decode(RPCRequest<StrictJSONObject>.self, from: data, id: header.id) {
            case .ok(let request):
                return Self.encoded(RPCResult(id: request.id, result: ToolsListResult(tools: HydraTool.all)))
            case .reply(let line): return line.isEmpty ? nil : line
            }

        case "tools/call":
            return await toolCall(data, requestID: header.id)

        default:
            return Self.encoded(RPCErrorResponse(
                id: header.id,
                code: .methodNotFound,
                message: "Method not found: \(header.method)"
            ))
        }
    }

    // MARK: - Tool dispatch

    /// First decode pass inside `tools/call`: just the tool name, so the
    /// second pass can decode tool-specific arguments.
    private struct ToolNameProbe: Decodable {
        struct Params: Decodable { let name: String }
        let params: Params
    }

    private func toolCall(_ data: Data, requestID: RPCID?) async -> String? {
        let probe: ToolNameProbe
        switch Self.decode(ToolNameProbe.self, from: data, id: requestID) {
        case .ok(let decoded): probe = decoded
        case .reply(let line): return line.isEmpty ? nil : line
        }

        switch probe.params.name {
        case HydraTool.search.name:
            switch Self.decode(ToolCallRequest<SearchArguments>.self, from: data, id: requestID) {
            case .ok(let request): return await runSearch(request)
            case .reply(let line): return line.isEmpty ? nil : line
            }

        case HydraTool.healthCheck.name:
            switch Self.decode(ToolCallRequest<HealthCheckArguments>.self, from: data, id: requestID) {
            case .ok(let request): return await runHealthCheck(request)
            case .reply(let line): return line.isEmpty ? nil : line
            }

        default:
            switch Self.decode(ToolCallRequest<StrictJSONObject>.self, from: data, id: requestID) {
            case .ok(let request):
                // Known-but-unimplemented tools answer honestly as tool-level
                // errors — the call did not do anything, and MCP clients key
                // automation off `isError`; unknown tools are the same class.
                if HydraTool.all.contains(where: { $0.name == probe.params.name }) {
                    return Self.encoded(RPCResult(
                        id: request.id,
                        result: CallToolResult.text("not_yet_implemented: \(probe.params.name)", isError: true)
                    ))
                }
                return Self.encoded(RPCResult(
                    id: request.id,
                    result: CallToolResult.text("Error: unknown tool '\(probe.params.name)'", isError: true)
                ))
            case .reply(let line): return line.isEmpty ? nil : line
            }
        }
    }

    private func runSearch(_ request: ToolCallRequest<SearchArguments>) async -> String? {
        guard let arguments = request.params.arguments else {
            return Self.encoded(RPCErrorResponse(
                id: request.id,
                code: .invalidParams,
                message: "Invalid request: missing key 'arguments' at root"
            ))
        }
        do {
            let scanner = VaultScanner(vaultRoot: vaultRoot)
            let inventory = try await scanner.scan()
            let matched = inventory.notes.filter { note in
                let matchesQuery = note.title.localizedCaseInsensitiveContains(arguments.query)
                    || note.tags.contains { $0.localizedCaseInsensitiveContains(arguments.query) }
                guard matchesQuery else { return false }
                if let tag = arguments.tag, !tag.isEmpty {
                    return note.tags.contains { $0.localizedCaseInsensitiveContains(tag) }
                }
                return true
            }
            let limit = max(0, arguments.limit ?? 20)
            let hits = matched.prefix(limit).map { note in
                SearchHit(
                    title: note.title,
                    path: note.relativePath,
                    tags: note.tags,
                    modified: note.modifiedDate
                )
            }
            return Self.encoded(RPCResult(
                id: request.id,
                result: Self.resultText(SearchResult(count: matched.count, results: Array(hits)))
            ))
        } catch {
            return Self.encoded(RPCResult(
                id: request.id,
                result: CallToolResult.text("Error: Scan failed: \(error.localizedDescription)", isError: true)
            ))
        }
    }

    private func runHealthCheck(_ request: ToolCallRequest<HealthCheckArguments>) async -> String? {
        do {
            let scanner = VaultScanner(vaultRoot: vaultRoot)
            let inventory = try await scanner.scan()
            let report = HealthChecker().checkAll(inventory)
            let summary = HealthCheckSummary(
                status: report.overallStatus.rawValue,
                summary: report.summary,
                checks: report.checks.map { check in
                    HealthCheckLine(
                        name: check.name,
                        status: check.status.rawValue,
                        message: check.message,
                        count: check.affectedCount
                    )
                }
            )
            return Self.encoded(RPCResult(
                id: request.id,
                result: Self.resultText(summary)
            ))
        } catch {
            return Self.encoded(RPCResult(
                id: request.id,
                result: CallToolResult.text("Error: Scan failed: \(error.localizedDescription)", isError: true)
            ))
        }
    }

    // MARK: - Encode / decode with evidence

    /// Decode outcome: a value, or the response line that must be sent back
    /// in its place (`RPCErrorResponse` is a wire payload, not an `Error`).
    private enum Decoded<T> {
        case ok(T)
        case reply(String)
    }

    /// Decode with evidence: failures produce the error response carrying
    /// the coding path instead of collapsing to a silent nil.
    private static func decode<T: Decodable>(
        _ type: T.Type, from data: Data, id: RPCID?
    ) -> Decoded<T> {
        do {
            return .ok(try JSONDecoder().decode(type, from: data))
        } catch let error as DecodingError {
            // Syntax was validated before decoding, so a header DecodingError
            // means valid JSON with an invalid envelope shape (-32600), never
            // -32700. Tool probes fail on params shape (-32602).
            let isHeader = type == RPCRequestHeader.self
            // Salvage a well-formed id from invalid envelopes — JSON-RPC 2.0:
            // reply with the request's id when it is detectable, null only
            // when it is not.
            let salvagedID = (try? JSONDecoder().decode(IDSalvage.self, from: data))?.id
            let response = RPCErrorResponse(
                id: salvagedID ?? id,
                code: isHeader ? .invalidRequest : .invalidParams,
                message: "Invalid request: \(error.brief)"
            )
            return .reply(Self.encoded(response) ?? "")
        } catch {
            let response = RPCErrorResponse(id: id, code: .parseError, message: "Parse error")
            return .reply(Self.encoded(response) ?? "")
        }
    }

    /// Encode an envelope deterministically. Returns nil only if encoding a
    /// member of our own closed envelope set fails — unreachable by
    /// construction; staying silent beats emitting corrupt JSON.
    private static func encoded<Response: Encodable>(_ response: Response) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(response) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Wrap a typed result payload as CallToolResult text — JSONEncoder owns
    /// formatting (`.sortedKeys`, `.iso8601` dates); the old server hand-built
    /// `[String: Any]` dictionaries per call site.
    private static func resultText(_ payload: some Encodable) -> CallToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return CallToolResult.text("Error: failed to encode result payload", isError: true)
        }
        return CallToolResult.text(text)
    }
}
