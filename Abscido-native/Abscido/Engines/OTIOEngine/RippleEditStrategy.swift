import Foundation

/// Computes keep ranges and edit decisions from transcript word states.
/// This is the bridge between "the user deleted words in the transcript"
/// and "the timeline needs these time ranges kept."
enum RippleEditStrategy {

    /// Computes an EditDecision for a single clip based on which words are not deleted.
    /// Groups consecutive non-deleted words into keep ranges with configurable padding
    /// to avoid hard audio cuts at edit points.
    static func computeEditDecision(
        words: [TranscriptWord],
        clipId: Int64,
        mediaFilePath: String,
        mediaDurationMs: Double,
        paddingMs: Double = 10.0
    ) -> EditDecision {
        let activeWords = words
            .filter { $0.clipId == clipId && !$0.isDeleted }
            .sorted { $0.startMs < $1.startMs }

        // If no words are deleted, keep the entire clip
        let allWords = words.filter { $0.clipId == clipId }
        let deletedCount = allWords.filter(\.isDeleted).count

        if deletedCount == 0 {
            return EditDecision(
                clipId: clipId,
                mediaFilePath: mediaFilePath,
                keepRanges: [TimeRangeMs(startMs: 0, endMs: mediaDurationMs)]
            )
        }

        // If all words are deleted, return empty keep ranges
        if activeWords.isEmpty {
            return EditDecision(
                clipId: clipId,
                mediaFilePath: mediaFilePath,
                keepRanges: []
            )
        }

        var keepRanges: [TimeRangeMs] = []
        var rangeStart = activeWords[0].startMs
        var rangeEnd = activeWords[0].endMs

        for i in 1..<activeWords.count {
            let word = activeWords[i]
            let gap = word.startMs - rangeEnd

            if gap > paddingMs * 2 {
                // Close current range and start a new one
                keepRanges.append(TimeRangeMs(
                    startMs: max(0, rangeStart - paddingMs),
                    endMs: min(mediaDurationMs, rangeEnd + paddingMs)
                ))
                rangeStart = word.startMs
                rangeEnd = word.endMs
            } else {
                // Extend current range
                rangeEnd = word.endMs
            }
        }

        // Close the final range
        keepRanges.append(TimeRangeMs(
            startMs: max(0, rangeStart - paddingMs),
            endMs: min(mediaDurationMs, rangeEnd + paddingMs)
        ))

        return EditDecision(
            clipId: clipId,
            mediaFilePath: mediaFilePath,
            keepRanges: keepRanges
        )
    }

    /// Computes edit decisions for all clips in a project.
    static func computeAllEditDecisions(
        words: [TranscriptWord],
        mediaFiles: [MediaFile]
    ) -> [EditDecision] {
        mediaFiles.map { file in
            let clipWords = words.filter { $0.clipId == file.id }
            return computeEditDecision(
                words: clipWords,
                clipId: file.id,
                mediaFilePath: file.filePath,
                mediaDurationMs: file.durationMs
            )
        }
    }
}
