import Foundation
import Combine

/// Manages transcript word states, selection, undo/redo, and the delete→ripple flow.
@MainActor
@Observable
final class TranscriptViewModel {
    var words: [TranscriptWord] = []
    var segments: [TranscriptSegment] = []
    var selectedWordIds: Set<Int64> = []
    var currentPlayingWordId: Int64?
    var isTranscribing = false
    var transcriptionProgress: Double = 0
    var selectedLanguage: String = "en"

    private var undoStack: [[TranscriptWord]] = []
    private var redoStack: [[TranscriptWord]] = []
    private let maxUndoDepth = 100

    private let transcriptRepo = TranscriptRepository()
    private let transcriptionEngine = TranscriptionEngine()

    // MARK: - Computed

    var activeWords: [TranscriptWord] {
        words.filter { !$0.isDeleted }
    }

    var hasTranscript: Bool {
        !words.isEmpty
    }

    var deletedCount: Int {
        words.filter(\.isDeleted).count
    }

    // MARK: - Load / Store

    func loadTranscript(clipId: Int64) {
        do {
            words = try transcriptRepo.fetchWords(clipId: clipId)
            segments = try transcriptRepo.fetchSegments(clipId: clipId)
            selectedWordIds = []
            undoStack = []
            redoStack = []
        } catch {
            words = []
            segments = []
        }
    }

    // MARK: - Transcription

    func transcribe(mediaFile: MediaFile) {
        isTranscribing = true
        transcriptionProgress = 0

        Task {
            do {
                // Clear existing transcript
                try transcriptRepo.deleteWords(clipId: mediaFile.id)
                try transcriptRepo.deleteSegments(clipId: mediaFile.id)

                let newWords = try await transcriptionEngine.transcribe(
                    mediaFile: mediaFile,
                    language: selectedLanguage,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.transcriptionProgress = progress
                        }
                    }
                )

                // Assign IDs by persisting
                try transcriptRepo.insertWords(newWords)
                words = try transcriptRepo.fetchWords(clipId: mediaFile.id)

                // Build segments from words
                let newSegments = buildSegments(from: words, clipId: mediaFile.id)
                try transcriptRepo.insertSegments(newSegments)
                segments = try transcriptRepo.fetchSegments(clipId: mediaFile.id)

                isTranscribing = false
                transcriptionProgress = 1.0
            } catch {
                isTranscribing = false
                transcriptionProgress = 0
            }
        }
    }

    // MARK: - Selection

    func selectWord(_ wordId: Int64) {
        selectedWordIds = [wordId]
    }

    func toggleWordSelection(_ wordId: Int64) {
        if selectedWordIds.contains(wordId) {
            selectedWordIds.remove(wordId)
        } else {
            selectedWordIds.insert(wordId)
        }
    }

    func selectRange(from startId: Int64, to endId: Int64) {
        guard let startIdx = words.firstIndex(where: { $0.id == startId }),
              let endIdx = words.firstIndex(where: { $0.id == endId }) else { return }

        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        selectedWordIds = Set(words[range].filter { !$0.isDeleted }.map(\.id))
    }

    func selectAll() {
        selectedWordIds = Set(words.filter { !$0.isDeleted }.map(\.id))
    }

    func clearSelection() {
        selectedWordIds = []
    }

    // MARK: - Delete Flow (core product loop)

    /// Deletes selected words, triggers ripple edit computation.
    /// Returns the new EditDecision for the affected clip.
    func deleteSelectedWords(mediaFile: MediaFile) -> EditDecision? {
        guard !selectedWordIds.isEmpty else { return nil }

        // Save undo state
        pushUndo()

        let command = DeleteWordsCommand(
            wordIds: selectedWordIds,
            clipId: mediaFile.id
        )
        _ = command.execute(on: &words)

        // Persist deletion states
        persistWordStates()

        // Clear selection
        selectedWordIds = []

        // Compute new edit decision
        return RippleEditStrategy.computeEditDecision(
            words: words,
            clipId: mediaFile.id,
            mediaFilePath: mediaFile.filePath,
            mediaDurationMs: mediaFile.durationMs
        )
    }

    /// Restores words from a previous state.
    func restoreWords(_ previousWords: [TranscriptWord]) {
        words = previousWords
        persistWordStates()
    }

    // MARK: - Undo / Redo

    func undo() -> Bool {
        guard let previousState = undoStack.popLast() else { return false }
        redoStack.append(words)
        words = previousState
        persistWordStates()
        selectedWordIds = []
        return true
    }

    func redo() -> Bool {
        guard let nextState = redoStack.popLast() else { return false }
        undoStack.append(words)
        words = nextState
        persistWordStates()
        selectedWordIds = []
        return true
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func pushUndo() {
        undoStack.append(words)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        redoStack = []
    }

    // MARK: - Playback Sync

    /// Updates the currently playing word based on playback time.
    /// Uses binary search for O(log n) performance.
    func updatePlayingWord(timeMs: Double) {
        let sortedWords = words.filter { !$0.isDeleted }.sorted { $0.startMs < $1.startMs }
        guard !sortedWords.isEmpty else {
            currentPlayingWordId = nil
            return
        }

        // Binary search for the word containing timeMs
        var low = 0
        var high = sortedWords.count - 1
        var result: Int?

        while low <= high {
            let mid = (low + high) / 2
            let word = sortedWords[mid]

            if timeMs >= word.startMs && timeMs < word.endMs {
                result = mid
                break
            } else if timeMs < word.startMs {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }

        if let idx = result {
            currentPlayingWordId = sortedWords[idx].id
        } else {
            currentPlayingWordId = nil
        }
    }

    // MARK: - Edit Decision Computation

    func computeEditDecision(mediaFile: MediaFile) -> EditDecision {
        RippleEditStrategy.computeEditDecision(
            words: words,
            clipId: mediaFile.id,
            mediaFilePath: mediaFile.filePath,
            mediaDurationMs: mediaFile.durationMs
        )
    }

    func computeAllEditDecisions(mediaFiles: [MediaFile]) -> [EditDecision] {
        RippleEditStrategy.computeAllEditDecisions(
            words: words,
            mediaFiles: mediaFiles
        )
    }

    // MARK: - Helpers

    private func persistWordStates() {
        Task.detached { [words, transcriptRepo] in
            try? transcriptRepo.updateWordsBatch(words: words)
        }
    }

    private func buildSegments(from words: [TranscriptWord], clipId: Int64) -> [TranscriptSegment] {
        guard !words.isEmpty else { return [] }

        var segments: [TranscriptSegment] = []
        var currentWords: [TranscriptWord] = []
        let maxSegmentGapMs: Double = 2000

        for word in words {
            if let last = currentWords.last, word.startMs - last.endMs > maxSegmentGapMs {
                // Close current segment
                let text = currentWords.map(\.word).joined(separator: " ")
                segments.append(TranscriptSegment(
                    clipId: clipId,
                    text: text,
                    startMs: currentWords.first!.startMs,
                    endMs: currentWords.last!.endMs
                ))
                currentWords = [word]
            } else {
                currentWords.append(word)
            }
        }

        if !currentWords.isEmpty {
            let text = currentWords.map(\.word).joined(separator: " ")
            segments.append(TranscriptSegment(
                clipId: clipId,
                text: text,
                startMs: currentWords.first!.startMs,
                endMs: currentWords.last!.endMs
            ))
        }

        return segments
    }
}
