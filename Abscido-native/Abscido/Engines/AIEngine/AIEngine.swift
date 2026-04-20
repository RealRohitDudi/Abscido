import Foundation

/// AIEngine orchestrates bad take detection via the Anthropic API.
actor AIEngine {
    private let client = AnthropicClient()
    private let detector = BadTakeDetector()

    /// Detects bad takes in the transcript using Claude.
    func detectBadTakes(
        words: [TranscriptWord]
    ) async throws -> [BadTake] {
        let apiKey = try Keychain.load(key: "anthropic_api_key")

        let activeWords = words.filter { !$0.isDeleted }
        guard !activeWords.isEmpty else { return [] }

        let prompt = detector.buildPrompt(from: activeWords)
        let systemPrompt = detector.systemPrompt

        let responseText = try await client.sendMessage(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userMessage: prompt,
            model: "claude-opus-4-5",
            maxTokens: 4096
        )

        let badTakes = try detector.parseResponse(responseText, validWordIds: Set(activeWords.map(\.id)))
        return badTakes
    }
}
