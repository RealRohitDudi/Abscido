import Foundation

struct DeleteWordsCommand: Sendable {
    let wordIds: Set<Int64>
    let clipId: Int64

    /// Executes the deletion by marking words as deleted. Returns the previous state for undo.
    func execute(on words: inout [TranscriptWord]) -> [TranscriptWord] {
        let previousState = words
        for index in words.indices {
            if wordIds.contains(words[index].id) {
                words[index].isDeleted = true
            }
        }
        return previousState
    }

    /// Computes the EditDecision from the current word states for this clip.
    /// Groups consecutive non-deleted words into keep ranges with 10ms padding.
    func computeEditDecision(
        from words: [TranscriptWord],
        mediaFilePath: String
    ) -> EditDecision {
        let activeWords = words
            .filter { $0.clipId == clipId && !$0.isDeleted }
            .sorted { $0.startMs < $1.startMs }

        let padding: Double = 10.0
        var keepRanges: [TimeRangeMs] = []
        var rangeStart: Double?
        var rangeEnd: Double?

        for word in activeWords {
            if let currentEnd = rangeEnd {
                if word.startMs - currentEnd > padding * 2 {
                    keepRanges.append(TimeRangeMs(
                        startMs: max(0, (rangeStart ?? 0) - padding),
                        endMs: currentEnd + padding
                    ))
                    rangeStart = word.startMs
                    rangeEnd = word.endMs
                } else {
                    rangeEnd = word.endMs
                }
            } else {
                rangeStart = word.startMs
                rangeEnd = word.endMs
            }
        }

        if let start = rangeStart, let end = rangeEnd {
            keepRanges.append(TimeRangeMs(
                startMs: max(0, start - padding),
                endMs: end + padding
            ))
        }

        return EditDecision(
            clipId: clipId,
            mediaFilePath: mediaFilePath,
            keepRanges: keepRanges
        )
    }
}
