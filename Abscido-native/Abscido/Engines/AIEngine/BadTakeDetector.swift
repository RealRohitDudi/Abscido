import Foundation

/// Builds the prompt for bad take detection and parses the AI response.
struct BadTakeDetector: Sendable {

    let systemPrompt = """
    You are a professional video editor assistant. You are given a \
    word-level transcript of a video recording. Identify every "bad take": \
    false starts, repeated sentences, stutter restarts, filler-word \
    spirals (um um um), and botched delivery where the speaker clearly \
    restarts the same thought.

    Return ONLY a valid JSON array. No prose, no markdown fences.
    Schema: [{ "word_ids": [Int], "reason": String }]
    Each object = one bad take. word_ids = every word belonging to it.
    reason = short label, e.g. "Repeated sentence", "False start", \
    "Stutter restart", "Incomplete thought".
    If no bad takes are found, return [].
    """

    /// Builds the user message containing the transcript as JSON.
    func buildPrompt(from words: [TranscriptWord]) -> String {
        let wordData = words.map { word in
            [
                "id": AnyCodable.int(Int(word.id)),
                "word": AnyCodable.string(word.word),
                "start_ms": AnyCodable.double(word.startMs),
                "end_ms": AnyCodable.double(word.endMs),
            ]
        }

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: wordData.map { dict in
                dict.mapValues { $0.jsonValue }
            },
            options: [.sortedKeys]
        ),
        let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "[]"
        }

        return jsonString
    }

    /// Parses the AI response into BadTake objects, validating word IDs.
    func parseResponse(_ response: String, validWordIds: Set<Int64>) throws -> [BadTake] {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AbscidoError.aiResponseMalformed(raw: response)
        }

        let decoded: [BadTakeRaw]
        do {
            decoded = try JSONDecoder().decode([BadTakeRaw].self, from: data)
        } catch {
            throw AbscidoError.aiResponseMalformed(raw: String(response.prefix(500)))
        }

        return decoded.compactMap { raw in
            let validIds = raw.word_ids.map { Int64($0) }.filter { validWordIds.contains($0) }
            guard !validIds.isEmpty else { return nil }
            return BadTake(wordIds: validIds, reason: raw.reason)
        }
    }
}

// MARK: - Internal Types

private struct BadTakeRaw: Decodable {
    let word_ids: [Int]
    let reason: String
}

private enum AnyCodable {
    case int(Int)
    case string(String)
    case double(Double)

    var jsonValue: Any {
        switch self {
        case .int(let v): return v
        case .string(let v): return v
        case .double(let v): return v
        }
    }
}
