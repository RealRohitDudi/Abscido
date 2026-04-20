import Foundation

/// URLSession-based Anthropic API client with retry logic.
struct AnthropicClient: Sendable {
    private let session: URLSession
    private let maxRetries = 3

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    /// Sends a message to the Anthropic Messages API and returns the text response.
    func sendMessage(
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        model: String = "claude-opus-4-5",
        maxTokens: Int = 4096
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = jsonData

        var lastError: Error?

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
            }

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AbscidoError.aiRequestFailed(statusCode: 0, body: "Not an HTTP response")
                }

                if httpResponse.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
                    if let textBlock = decoded.content.first(where: { $0.type == "text" }) {
                        return textBlock.text
                    }
                    throw AbscidoError.aiResponseMalformed(raw: "No text content in response")
                }

                // Retry on 429 (rate limit) and 5xx (server errors)
                if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    lastError = AbscidoError.aiRequestFailed(
                        statusCode: httpResponse.statusCode,
                        body: body
                    )
                    continue
                }

                // Non-retryable error
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AbscidoError.aiRequestFailed(
                    statusCode: httpResponse.statusCode,
                    body: body
                )
            } catch let error as AbscidoError {
                lastError = error
                if case .aiRequestFailed = error {
                    continue
                }
                throw error
            } catch {
                lastError = error
            }
        }

        throw lastError ?? AbscidoError.aiRequestFailed(statusCode: 0, body: "Max retries exceeded")
    }
}

// MARK: - Response Types

private struct AnthropicResponse: Decodable {
    let id: String
    let content: [ContentBlock]
    let model: String
    let role: String
}

private struct ContentBlock: Decodable {
    let type: String
    let text: String
}
