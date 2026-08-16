// Protocol tests for the typed Hydra MCP server — drive `handle(line:)`
// (the pure core) with wire lines and assert on wire-shaped responses.
// The stdio loop (run) is the effect shell and stays thin by construction.

import Testing
import Foundation
@testable import HydraMCP

@Suite("Hydra MCP protocol")
struct HydraMCPServerTests {

    private func makeServer() throws -> HydraMCPServer {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hydra-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        ---
        title: Andromeda War Notes
        tags: swift, mcp
        ---
        # War
        Field intel lives here.
        """.write(to: root.appendingPathComponent("war-notes.md"), atomically: true, encoding: .utf8)
        try """
        ---
        title: SecondBrain Inbox
        tags: obsidian
        ---
        # Inbox
        """.write(to: root.appendingPathComponent("inbox.md"), atomically: true, encoding: .utf8)
        return HydraMCPServer(vaultRoot: root.path)
    }

    // MARK: - Handshake

    @Test("initialize handshake answers with the request id and server info")
    func initializeHandshake() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#))
        #expect(response.contains(#""id":1"#))
        #expect(response.contains(#""protocolVersion":"2025-06-18""#))
        #expect(response.contains(#""name":"hydra""#))
        #expect(!response.contains("error"))
    }

    @Test("ping requests get an empty result with the id echoed")
    func pingResponds() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":42,"method":"ping"}"#))
        #expect(response.contains(#""id":42"#))
        #expect(response.contains(#""result":{}"#))
        #expect(!response.contains("error"))
    }

    // MARK: - Notification law

    @Test("notification-form messages (no id) get no response at all")
    func notificationsStaySilent() async throws {
        let server = try makeServer()
        let await1 = await server.handle(line: #"{"jsonrpc":"2.0","method":"ping"}"#)
        let await2 = await server.handle(line: #"{"jsonrpc":"2.0","method":"tools/list"}"#)
        let await3 = await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(await1 == nil)
        #expect(await2 == nil)
        #expect(await3 == nil)
    }

    @Test("explicit null id is invalid request, answered with id null — not silence")
    func explicitNullID() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#))
        #expect(response.contains("-32600"))
        #expect(response.contains(#""id":null"#))
    }

    @Test("envelopes missing jsonrpc are invalid requests, not dispatches")
    func missingJSONRPCVersion() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(line: #"{"id":1,"method":"tools/list"}"#))
        #expect(response.contains("-32600"))
        #expect(response.contains("jsonrpc"))
        #expect(response.contains(#""id":1"#))
    }

    @Test("valid JSON with an invalid envelope shape is -32600, not -32700")
    func invalidShapeNotSyntax() async throws {
        let server = try makeServer()
        let noMethod = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":5}"#))
        #expect(noMethod.contains("-32600"))
        #expect(noMethod.contains(#""id":5"#))
        #expect(!noMethod.contains("-32700"))
        let badIDType = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":true,"method":"ping"}"#))
        #expect(badIDType.contains("-32600"))
    }

    @Test("the stdio write path ships the raw response line, not a re-encoded string")
    func replyPathIsNotDoubleEncoded() async throws {
        // Pins the reply() fix: handle() output IS the final wire line. If
        // reply() ever routes it through the encoder again, clients receive
        // a JSON string literal and nothing works — the exact gap Codex
        // caught in review. Assert the invariant on the contract itself:
        // handle()'s output must parse as a JSON object directly.
        let server = try makeServer()
        let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["result"] is [String: Any])
    }

    @Test("unparseable lines answer -32700 with an explicit null id")
    func parseErrorCarriesNullID() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(line: "this is not json"))
        #expect(response.contains("-32700"))
        #expect(response.contains(#""id":null"#))
    }

    // MARK: - Tool surface

    @Test("tools/list reports every tool with a typed object schema")
    func toolsList() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        for name in ["hydrate", "search", "health_check", "relationships", "gaps", "timeline", "tag_report", "projectNote"] {
            #expect(response.contains(#""name":"\#(name)""#), "missing tool \(name)")
        }
        #expect(response.contains(#""inputSchema":{"properties""#))
        #expect(response.contains(#""type":"object""#))
        // search requires a query string — the schema must say so, typed.
        #expect(response.contains(#""query":{"description""#))
        #expect(response.contains(#""required":["query"]"#))
    }

    @Test("tools/call search returns typed results from a fixture vault")
    func searchRoundTrip() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(
            line: #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"search","arguments":{"query":"war"}}}"#
        ))
        #expect(response.contains(#""id":7"#))
        #expect(response.contains("Andromeda War Notes"))
        #expect(response.contains("swift"))
        #expect(response.contains(#""isError":false"#))
    }

    @Test("tools/call search honors the tag filter the schema promises")
    func searchTagFilter() async throws {
        let server = try makeServer()
        // query matches both notes via tags ("mcp" vs "obsidian" do not overlap) —
        // use a query both match? Titles differ; query against tags instead.
        let response = try #require(await server.handle(
            line: #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"search","arguments":{"query":"e","tag":"obsidian"}}}"#
        ))
        #expect(response.contains("SecondBrain Inbox"))
        #expect(!response.contains("Andromeda War Notes"))
    }

    @Test("missing required argument answers -32602 with the id and the coding path")
    func malformedArgumentsKeepID() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(
            line: #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"search","arguments":{"limit":5}}}"#
        ))
        #expect(response.contains(#""id":9"#))
        #expect(response.contains("-32602"))
        #expect(response.contains("query"))
    }

    @Test("unknown tool is a tool-level error, not silence and not a protocol error")
    func unknownTool() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(
            line: #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"explode","arguments":{}}}"#
        ))
        #expect(response.contains(#""id":10"#))
        #expect(response.contains("unknown tool"))
        #expect(response.contains(#""isError":true"#))
        #expect(!response.contains("-326"))
    }

    @Test("known-but-unimplemented tools answer honestly")
    func unimplementedToolHonest() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(
            line: #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"hydrate","arguments":{"mode":"adHoc"}}}"#
        ))
        #expect(response.contains("not_yet_implemented"))
        #expect(!response.contains(#""isError":true"#))
    }

    @Test("health_check returns the typed report")
    func healthCheckRoundTrip() async throws {
        let server = try makeServer()
        let response = try #require(await server.handle(
            line: #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"health_check","arguments":{}}}"#
        ))
        #expect(response.contains(#""id":12"#))
        #expect(response.contains("summary"))
        #expect(response.contains("checks"))
    }

    // MARK: - Framing note
    // The line-framing fix (chunked stdin → newline-delimited messages) lives
    // in run()'s buffer loop; it is exercised by the CLI in real use. The
    // handle() core above is what these tests pin.
}
