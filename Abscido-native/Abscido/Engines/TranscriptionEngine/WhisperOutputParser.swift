import Foundation

/// Parses MLX-Whisper JSON output into domain TranscriptWord and TranscriptSegment arrays.
enum WhisperOutputParser {

    /// Parses the raw JSON string from MLX-Whisper into TranscriptWord objects.
    static func parse(jsonString: String, clipId: Int64) throws -> [TranscriptWord] {
        guard let data = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            .data(using: .utf8) else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Could not decode output as UTF-8"
            )
        }

        let result: WhisperResult
        do {
            result = try JSONDecoder().decode(WhisperResult.self, from: data)
        } catch {
            // Try parsing as error response
            if let errorData = try? JSONDecoder().decode(WhisperError.self, from: data) {
                throw AbscidoError.transcriptionFailed(
                    clipId: clipId,
                    pythonError: errorData.error
                )
            }
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Failed to parse Whisper output: \(error.localizedDescription)"
            )
        }

        var words: [TranscriptWord] = []

        for segment in result.segments {
            if let segmentWords = segment.words {
                for word in segmentWords {
                    words.append(TranscriptWord(
                        clipId: clipId,
                        word: word.word.trimmingCharacters(in: .whitespaces),
                        startMs: word.start * 1000.0,
                        endMs: word.end * 1000.0,
                        confidence: word.probability ?? 1.0
                    ))
                }
            } else {
                // Fallback: create a single word from the segment text
                let segWords = segment.text.split(separator: " ")
                let segDuration = segment.end - segment.start
                let wordDuration = segDuration / Double(max(1, segWords.count))

                for (i, word) in segWords.enumerated() {
                    let start = segment.start + wordDuration * Double(i)
                    let end = start + wordDuration
                    words.append(TranscriptWord(
                        clipId: clipId,
                        word: String(word),
                        startMs: start * 1000.0,
                        endMs: end * 1000.0,
                        confidence: 1.0
                    ))
                }
            }
        }

        return words
    }

    /// Parses segments from the Whisper output.
    static func parseSegments(jsonString: String, clipId: Int64) throws -> [TranscriptSegment] {
        guard let data = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            .data(using: .utf8) else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Could not decode output as UTF-8"
            )
        }

        let result = try JSONDecoder().decode(WhisperResult.self, from: data)

        return result.segments.map { segment in
            TranscriptSegment(
                clipId: clipId,
                text: segment.text.trimmingCharacters(in: .whitespaces),
                startMs: segment.start * 1000.0,
                endMs: segment.end * 1000.0
            )
        }
    }
}

// MARK: - Whisper JSON Schema

private struct WhisperResult: Decodable {
    let text: String
    let segments: [WhisperSegment]
    let language: String?
}

private struct WhisperSegment: Decodable {
    let id: Int?
    let start: Double
    let end: Double
    let text: String
    let words: [WhisperWord]?
}

private struct WhisperWord: Decodable {
    let word: String
    let start: Double
    let end: Double
    let probability: Double?
}

private struct WhisperError: Decodable {
    let error: String
}
