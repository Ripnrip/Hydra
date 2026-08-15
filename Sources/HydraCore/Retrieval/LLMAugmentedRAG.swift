import Foundation
import Logging

// MARK: - LLM Configuration

/// Optional OpenAI-compatible LLM configuration for reasoning-augmented RAG.
/// Works with OpenAI, Ollama, LM Studio, Cerebras, Groq, or any server
/// speaking the /v1/chat/completions protocol.
public struct LLMConfig: Sendable, Codable, Equatable {
    public var baseURL: String      // e.g. "http://localhost:11434/v1" (Ollama)
    public var apiKey: String       // optional for local servers
    public var model: String        // e.g. "llama3.1", "gpt-4o-mini"
    public var temperature: Double

    public init(
        baseURL: String = "",
        apiKey: String = "",
        model: String = "",
        temperature: Double = 0.3
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
    }

    public var isEnabled: Bool {
        !baseURL.isEmpty && !model.isEmpty
    }
}

// MARK: - LLM Client

/// Minimal OpenAI-compatible chat client. Pure URLSession — no dependencies.
public actor LLMClient {
    private let config: LLMConfig
    private let session: URLSession

    public init(config: LLMConfig) {
        self.config = config
        self.session = URLSession(configuration: .ephemeral)
    }

    /// Send a chat completion request. Returns the assistant message content.
    public func complete(system: String, user: String) async throws -> String {
        guard config.isEnabled else {
            throw LLMError.notConfigured
        }

        var request = URLRequest(url: URL(string: "\(config.baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": config.model,
            "temperature": config.temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.requestFailed
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }
        return content
    }

    /// Quick connectivity + model check.
    public func healthCheck() async -> Bool {
        guard config.isEnabled else { return false }
        do {
            _ = try await complete(
                system: "You are a health check.",
                user: "Reply with the word: ok"
            )
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Augmented RAG

/// Combines hybrid retrieval with optional LLM reasoning.
/// - No LLM configured → grounded offline summary (current behavior)
/// - LLM configured → reasoning answer synthesized from retrieved notes
public struct LLMAugmentedRAG: Sendable {
    public let retrieval: HybridRAGQuery
    public let llm: LLMClient?
    public let config: LLMConfig

    public init(config: LLMConfig = LLMConfig()) {
        self.retrieval = HybridRAGQuery()
        self.config = config
        self.llm = config.isEnabled ? LLMClient(config: config) : nil
    }

    public struct AugmentedResult: Sendable {
        public let retrievalResult: HybridRAGQuery.Result
        public let reasoning: String?       // LLM answer when configured
        public let usedLLM: Bool
        public let seedNoteIDs: Set<String>       // for graph highlighting (bright)
        public let graphNoteIDs: Set<String>      // for graph highlighting (soft)
    }

    public func ask(
        _ question: String,
        index: LocalSemanticIndex,
        links: [HydraCore.NoteLink],
        titleFor: @Sendable (String) -> String,
        contentFor: @Sendable (String) -> String
    ) async -> AugmentedResult {
        // Step 1: hybrid retrieval (always)
        let result = await retrieval.run(query: question, index: index, links: links, titleFor: titleFor)

        let seeds = Set(result.semanticHits.map(\.id))
        let graphOnly = Set(result.allNoteIDs).subtracting(seeds)

        // Step 2: optional LLM reasoning over the retrieved context
        var reasoning: String?
        if let llm, !result.semanticHits.isEmpty {
            var context = "Retrieved notes:\n\n"
            for (i, hit) in result.semanticHits.prefix(6).enumerated() {
                let content = String(contentFor(hit.id).prefix(2000))
                context += "[\(i + 1)] \(hit.title)\n\(content)\n\n"
            }
            if !result.graphHits.isEmpty {
                context += "Related notes (graph neighbors): \(result.graphHits.prefix(8).map(\.title).joined(separator: ", "))\n"
            }

            reasoning = try? await llm.complete(
                system: """
                You answer questions using ONLY the provided notes from the user's knowledge vault. \
                Cite note titles in your answer like [Note Title]. If the notes don't contain \
                the answer, say so. Be concise and grounded.
                """,
                user: "\(context)\nQuestion: \(question)"
            )
        }

        return AugmentedResult(
            retrievalResult: result,
            reasoning: reasoning,
            usedLLM: reasoning != nil,
            seedNoteIDs: seeds,
            graphNoteIDs: graphOnly
        )
    }
}

// MARK: - Wire types

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

public enum LLMError: LocalizedError, Sendable {
    case notConfigured
    case requestFailed
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "LLM not configured"
        case .requestFailed: "LLM request failed"
        case .emptyResponse: "LLM returned empty response"
        }
    }
}
