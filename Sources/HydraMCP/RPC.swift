// RPC.swift — typed JSON-RPC 2.0 envelope models.
//
// Ported from Ripnrip/Andromeda `Packages/AndromedaMCP/Sources/AndromedaMCP/RPC.swift`
// at merge 1d8920b (2026-08-16) — the shapes the swift-canon anti-patterns
// Exhibits 1 and 5 mandate: typed envelopes over dynamic JSON, explicit-null
// `id` via `@EncodeNull`, and notification-vs-invalid-request distinction
// via `idOmitted`. Keep in sync with the Andromeda source of truth when the
// canon evolves; resync note lives in `.claude/skills/swift-canon/MIRROR.md`.
//
// The wire protocol is closed: this server defines every method, tool, and
// argument, so every message gets Codable models instead of a dynamic JSON
// enum. Method routing decodes in two typed passes over the same bytes
// (header first, then the full per-method request).

import Foundation

// MARK: - Request id

/// JSON-RPC ids are numbers or strings; `null` is a reply target but never
/// a request id, so decoding rejects it. Numbers cover the full JSON-number
/// shape: exact integers stay integers, while fractional values and integers
/// outside the platform `Int` range (discouraged and huge, but both legal
/// per JSON-RPC 2.0) decode as `Double` and are echoed verbatim.
enum RPCID: Hashable, Sendable {
    case integer(Int)
    case double(Double)
    case string(String)
}

extension RPCID: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Union probing: each attempt is a legitimate case of the id shape,
        // and failure of the last is a real decode error, not a silent nil.
        // Int-first so `1` round-trips as an integer, not `1.0`.
        if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected number or string request id"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let integer): try container.encode(integer)
        case .double(let double): try container.encode(double)
        case .string(let string): try container.encode(string)
        }
    }
}

// MARK: - Optional-wire-key encoding

/// Encodes the wrapped optional as a present key — `null` when nil —
/// instead of letting synthesized conformance drop the key entirely.
///
/// JSON-RPC 2.0: the `id` member is REQUIRED on responses and MUST be
/// null — not absent — when the request id could not be determined
/// (parse errors, invalid requests). Synthesized conformance would
/// `encodeIfPresent` and silently omit the key.
@propertyWrapper
struct EncodeNull<Value: Encodable & Sendable>: Encodable, Sendable {
    var wrappedValue: Value?

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Envelopes

/// First decode pass: enough of any message to route it. `idOmitted`
/// distinguishes a notification (id key absent — no reply, ever) from a
/// malformed request carrying an explicit `"id": null` (discouraged by
/// JSON-RPC 2.0, but NOT a notification — it must get an error reply).
struct RPCRequestHeader: Decodable, Sendable {
    let jsonrpc: String?
    let id: RPCID?
    let idOmitted: Bool
    let method: String

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, method }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idOmitted = !container.contains(.id)
        jsonrpc = try container.decodeIfPresent(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(RPCID.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
    }
}

/// Second decode pass: a full request with typed params.
struct RPCRequest<Params: Decodable>: Decodable {
    let id: RPCID?
    let params: Params?
}

/// A `tools/call` request; `Arguments` is the tool-specific payload.
struct ToolCallRequest<Arguments: Decodable>: Decodable {
    struct Params: Decodable {
        let name: String
        let arguments: Arguments?
    }

    let id: RPCID?
    let params: Params
}

struct RPCResult<Response: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RPCID?
    let result: Response
}

struct RPCErrorResponse: Encodable, Sendable {
    enum Code: Int, Sendable {
        case parseError = -32700
        case invalidRequest = -32600
        case methodNotFound = -32601
        case invalidParams = -32602
        case internalError = -32603
    }

    struct Error: Encodable, Sendable {
        let code: Int
        let message: String
    }

    let jsonrpc = "2.0"

    @EncodeNull var id: RPCID?

    let error: Error

    init(id: RPCID?, code: Code, message: String) {
        self._id = EncodeNull(wrappedValue: id)
        self.error = Error(code: code.rawValue, message: message)
    }
}

// MARK: - Method payloads

struct InitializeResult: Encodable, Sendable {
    struct ServerInfo: Encodable, Sendable {
        let name: String
        let version: String
    }

    struct ToolsCapabilities: Encodable, Sendable {}

    struct Capabilities: Encodable, Sendable {
        let tools: ToolsCapabilities
    }

    let protocolVersion = "2025-06-18"
    let capabilities = Capabilities(tools: ToolsCapabilities())
    let serverInfo = ServerInfo(name: "hydra", version: "0.1.0")
}

struct ToolsListResult: Encodable, Sendable {
    let tools: [HydraTool]
}

struct CallToolResult: Encodable, Sendable {
    struct TextContent: Encodable, Sendable {
        let type = "text"
        let text: String
    }

    let content: [TextContent]
    var isError = false

    static func text(_ message: String, isError: Bool = false) -> CallToolResult {
        CallToolResult(content: [TextContent(text: message)], isError: isError)
    }
}

/// Arguments payload for `tools/call` requests whose tool is not recognized;
/// only the id is needed to reply.
///
/// Decode gate: the wrapped member must be a JSON **object** when present.
/// Synthesized empty `Decodable` structs accept every JSON value, so
/// `"params": 7` and `"params": []` used to decode as success (Codex review
/// round 2). Decoding a dictionary over a single-value container rejects
/// scalars and arrays with `typeMismatch` on every platform — that contract
/// is the gate. Absent keys stay `nil` (optional member).
struct StrictJSONObject: Decodable, Sendable {
    private struct AnyValue: Decodable {}

    init(from decoder: Decoder) throws {
        _ = try decoder.singleValueContainer().decode([String: AnyValue].self)
    }
}

/// Empty `{}` result payload — the reply shape for `ping`.
struct EmptyResult: Encodable, Sendable {}

// MARK: - Decode evidence

extension DecodingError {
    /// Compact, caller-facing description that keeps the coding path — the
    /// evidence a client needs to fix the message — instead of collapsing
    /// to an opaque string.
    var brief: String {
        func path(_ context: Context) -> String {
            let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "root" : joined
        }
        switch self {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .valueNotFound(_, let context):
            return "unexpected null at \(path(context))"
        case .typeMismatch(_, let context), .dataCorrupted(let context):
            return "\(localizedDescription) at \(path(context))"
        @unknown default:
            return localizedDescription
        }
    }
}
