import Foundation

// MARK: - LLM Answer Client (OpenAI-compatible, optional)

/// Optional LLM reasoning layer for the Oracle. OpenAI-compatible chat completions
/// endpoint — works with OpenAI, Ollama, LM Studio, vLLM, LiteLLM, any compatible server.
/// When unset, the Oracle falls back to the offline grounded summary.
public struct LLMAnswerClient: Sendable {

    public struct Config: Sendable, Equatable, Codable {
        /// Base URL — e.g. "https://api.openai.com/v1" or "http://localhost:11434/v1" (Ollama)
        public var baseURL: String
        /// API key (empty for local servers like Ollama)
        public var apiKey: String
        /// Chat model — e.g. "gpt-4o-mini", "llama3.2", whatever the server serves
        public var model: String

        public init(baseURL: String, apiKey: String = "", model: String = "gpt-4o-mini") {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.model = model
        }

        public var isConfigured: Bool { !baseURL.isEmpty && !model.isEmpty }
    }

    public enum LLMError: Error, Sendable, Equatable {
        case notConfigured
        case badResponse(String)
        case http(Int, String)
    }

    private let config: Config
    private let session: URLSession

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public var isConfigured: Bool { config.isConfigured }

    // MARK: - Answer with retrieved context (RAG)

    /// Generate a reasoned answer from retrieved vault context.
    /// The context comes from the hybrid RAG pipeline (semantic + graph hits).
    public func answer(
        question: String,
        context: [ContextNote]
    ) async throws -> String {
        guard config.isConfigured else { throw LLMError.notConfigured }

        let systemPrompt = """
        You are a knowledgeable assistant answering questions about the user's personal knowledge vault. \
        You receive notes retrieved by semantic search and graph traversal. \
        Answer accurately based ONLY on the provided context. \
        Cite which notes your information comes from using their titles. \
        If the context doesn't contain the answer, say so honestly.
        """

        var contextBlock = ""
        for (i, note) in context.enumerated() {
            let kind = note.source == .semantic ? "semantic match" : "graph connection"
            contextBlock += "--- Note \(i + 1): \(note.title) (\(kind), relevance \(Int(note.relevance * 100))%) ---\n"
            contextBlock += String(note.snippet.prefix(1200))
            contextBlock += "\n\n"
        }

        let userMessage = """
        Retrieved vault context:

        \(contextBlock)

        Question: \(question)
        """

        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ],
            "temperature": 0.3,
            "max_tokens": 800,
        ]

        return try await chat(requestBody)
    }

    // MARK: - Raw chat

    private func chat(_ body: [String: Any]) async throws -> String {
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw LLMError.badResponse("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 60

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.badResponse("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, String(body.prefix(300)))
        }

        // Parse OpenAI-compatible response: choices[0].message.content
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.badResponse("Unexpected response shape")
        }

        return content
    }
}

// MARK: - Context Note (for LLM)

/// A retrieved note passed to the LLM as context.
public struct ContextNote: Sendable, Equatable {
    public enum Source: String, Sendable {
        case semantic
        case graph
    }

    public let title: String
    public let snippet: String
    public let source: Source
    public let relevance: Float

    public init(title: String, snippet: String, source: Source, relevance: Float) {
        self.title = title
        self.snippet = snippet
        self.source = source
        self.relevance = relevance
    }
}

// MARK: - Hybrid RAG + LLM integration

extension HybridRAGQuery.Result {
    /// Convert retrieval results into LLM context notes.
    public var contextNotes: [ContextNote] {
        let semantic = semanticHits.map { hit in
            ContextNote(title: hit.title, snippet: hit.snippet, source: .semantic, relevance: hit.score)
        }
        let graph = graphHits.map { hit in
            ContextNote(title: hit.title, snippet: "", source: .graph, relevance: 0.3)
        }
        return semantic + graph
    }
}
