import Combine
import Dispatch
import Foundation
import Security

/// Weak bridge — progress hops to main without capturing `Task.detached`'s `self`. Throttled to avoid flooding the event loop.
private final class TranscriptionProgressRelay: @unchecked Sendable {
    weak var viewModel: TranscriptViewModel?
    private var lastEmit: CFAbsoluteTime = 0

    func report(_ value: Double) {
        let now = CFAbsoluteTimeGetCurrent()
        let isBoundary = value <= 0.02 || value >= 0.99
        // Setup steps (WhisperKitTranscriber) often fire 0.02 → 0.06 within the same millisecond.
        // The generic throttle would drop 0.06, so the UI stays at 2% for the entire model
        // download / CoreML compile (minutes on first Small run).
        let setupMilestones: [Double] = [0.06, 0.12, 0.91]
        let nearSetupMilestone = setupMilestones.contains { abs($0 - value) < 0.001 }
        guard isBoundary || nearSetupMilestone || now - lastEmit >= 0.08 else { return }
        lastEmit = now
        DispatchQueue.main.async { [weak viewModel] in
            viewModel?.transcriptionProgress = value
        }
    }
}

/// Manages transcript word states, selection, undo/redo, and the delete→ripple flow.
@MainActor
@Observable
final class TranscriptViewModel {
    var words: [TranscriptWord] = []
    var segments: [TranscriptSegment] = []
    var selectedWordIds: Set<Int64> = []
    /// Last "focus" word for Shift+click range extension (stable unlike `Set.first`).
    var selectionAnchorWordId: Int64?
    var currentPlayingWordId: Int64?
    var isTranscribing = false
    var transcriptionProgress: Double = 0
    var transcriptionError: String?
    var selectedLanguage: String = "en"
    var selectedBackend: TranscriptionBackend = .whisperKit
    /// Default to `.small` rather than `.base`. `base` is English-only quality and produces
    /// wrong-script transcripts for Hindi, Arabic, CJK audio (e.g. Hindi audio decoded into
    /// Urdu/Arabic glyphs) — `.small` is the smallest checkpoint that's reliable across the
    /// language picker. Users who only need English can downshift to `.base` / `.tiny`.
    var whisperKitModelSize: WhisperKitModelSize = .small

    private var undoStack: [[TranscriptWord]] = []
    private var redoStack: [[TranscriptWord]] = []
    private let maxUndoDepth = 100

    private let transcriptRepo = TranscriptRepository()
    private let transcriptionEngine = TranscriptionEngine()
    private var transcriptionTask: Task<Void, Never>?

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
            selectionAnchorWordId = nil
            undoStack = []
            redoStack = []
        } catch {
            words = []
            segments = []
        }
    }

    // MARK: - WhisperKit + language

    /// Tiny/Base are unreliable for forced non\u{2011}English transcription; coerce to at least `.small`.
    func ensureWhisperKitModelMatchesLanguage() {
        guard selectedBackend == .whisperKit else { return }
        let code = LanguageRegistry.normalizedLanguageCode(selectedLanguage) ?? "en"
        let fitted = WhisperKitModelSize.effectiveForTranscription(
            requested: whisperKitModelSize,
            normalizedLanguageCode: code
        )
        if fitted != whisperKitModelSize {
            whisperKitModelSize = fitted
        }
    }

    // MARK: - Transcription

    func transcribe(mediaFile: MediaFile) {
        transcriptionTask?.cancel()

        isTranscribing = true
        transcriptionProgress = 0
        transcriptionError = nil

        ensureWhisperKitModelMatchesLanguage()

        let language = selectedLanguage
        let backend  = selectedBackend
        let modelName: String? = backend == .whisperKit ? whisperKitModelSize.rawValue
                               : backend == .mlxWhisper  ? MLXWhisperBridge.defaultModelName
                               : nil
        let engine  = transcriptionEngine
        let clipId  = mediaFile.id

        let progressRelay = TranscriptionProgressRelay()
        progressRelay.viewModel = self

        transcriptionTask = Task { @MainActor [weak self, engine, progressRelay] in
            guard let self else { return }

            // Apple Speech pre-flight: the binary must be inside a signed .app bundle with
            // Info.plist for tccd to find NSSpeechRecognitionUsageDescription on macOS 26+.
            // SpeechEntitlementBootstrap.ensureEntitlement() handles this at launch via execv;
            // if we're still not inside a bundle here, Speech WILL crash the process.
            if backend == .appleSpeech {
                guard SpeechEntitlementBootstrap.hasEntitlement,
                      Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
                else {
                    isTranscribing = false
                    transcriptionError = """
                        Apple Speech is unavailable in this build. The app tried to create \
                        an .app bundle at launch but could not. \
                        Run from Abscido-native/:  ./scripts/run-with-speech-capability.sh \
                        or switch the engine to WhisperKit (no signing needed).
                        """
                    return
                }
            }

            do {
                try transcriptRepo.deleteWords(clipId: clipId)
                try transcriptRepo.deleteSegments(clipId: clipId)

                let newWords = try await engine.transcribe(
                    mediaFile: mediaFile,
                    language: language,
                    backend: backend,
                    modelName: modelName,
                    onProgress: { progressRelay.report($0) }
                )

                try Task.checkCancellation()

                try transcriptRepo.insertWords(newWords)
                words = try transcriptRepo.fetchWords(clipId: clipId)
                let newSegments = buildSegments(from: words, clipId: clipId)
                try transcriptRepo.insertSegments(newSegments)
                segments = try transcriptRepo.fetchSegments(clipId: clipId)
                isTranscribing = false
                transcriptionProgress = 1.0

            } catch is CancellationError {
                isTranscribing = false
                transcriptionProgress = 0

            } catch {
                transcriptionError = Self.coherentTranscriptionError(error)
                isTranscribing = false
                transcriptionProgress = 0
            }
        }
    }

    // MARK: - Helpers (error formatting)

    private static func coherentTranscriptionError(_ error: Error) -> String {
        if let abscido = error as? AbscidoError {
            return abscido.errorDescription ?? String(describing: abscido)
        }
        let ns = error as NSError
        let description = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return "Transcription failed (domain \(ns.domain), code \(ns.code))."
        }
        return description
    }

    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = false
        transcriptionProgress = 0
    }

    func clearTranscriptionError() {
        transcriptionError = nil
    }

    // MARK: - Selection

    func selectWord(_ wordId: Int64) {
        selectedWordIds = [wordId]
        selectionAnchorWordId = wordId
    }

    func toggleWordSelection(_ wordId: Int64) {
        if selectedWordIds.contains(wordId) {
            selectedWordIds.remove(wordId)
            if selectionAnchorWordId == wordId {
                let remaining = words.filter { selectedWordIds.contains($0.id) && !$0.isDeleted }
                    .sorted { $0.startMs < $1.startMs }
                selectionAnchorWordId = remaining.first?.id
            }
        } else {
            selectedWordIds.insert(wordId)
        }
        selectionAnchorWordId = wordId
    }

    /// Includes every non-deleted word between `startId` and `endId` in **source time order** (not DB row order).
    /// Does not change `selectionAnchorWordId` — used for Shift+extend from the existing pivot.
    func selectRange(from startId: Int64, to endId: Int64) {
        let active = words.filter { !$0.isDeleted }.sorted { $0.startMs < $1.startMs }
        guard let startIdx = active.firstIndex(where: { $0.id == startId }),
              let endIdx = active.firstIndex(where: { $0.id == endId }) else { return }

        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        selectedWordIds = Set(active[range].map(\.id))
    }

    /// Drag-to-select: sets selection and moves the Shift+click pivot to the chronologically first word in the range.
    func applyDragSelection(startWordId: Int64, endWordId: Int64) {
        let active = words.filter { !$0.isDeleted }.sorted { $0.startMs < $1.startMs }
        guard let startIdx = active.firstIndex(where: { $0.id == startWordId }),
              let endIdx = active.firstIndex(where: { $0.id == endWordId }) else { return }

        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        selectedWordIds = Set(active[range].map(\.id))
        selectionAnchorWordId = active[min(startIdx, endIdx)].id
    }

    func selectAll() {
        let active = words.filter { !$0.isDeleted }.sorted { $0.startMs < $1.startMs }
        selectedWordIds = Set(active.map(\.id))
        selectionAnchorWordId = active.first?.id
    }

    func clearSelection() {
        selectedWordIds = []
        selectionAnchorWordId = nil
    }

    // MARK: - Delete Flow (core product loop)

    /// Deletes selected words, triggers ripple edit computation.
    func deleteSelectedWords(mediaFile: MediaFile) -> EditDecision? {
        guard !selectedWordIds.isEmpty else { return nil }

        pushUndo()

        let command = DeleteWordsCommand(
            wordIds: selectedWordIds,
            clipId: mediaFile.id
        )
        _ = command.execute(on: &words)

        persistWordStates()
        selectedWordIds = []
        selectionAnchorWordId = nil

        return RippleEditStrategy.computeEditDecision(
            words: words,
            clipId: mediaFile.id,
            mediaFilePath: mediaFile.filePath,
            mediaDurationMs: mediaFile.durationMs
        )
    }

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
        selectionAnchorWordId = nil
        return true
    }

    func redo() -> Bool {
        guard let nextState = redoStack.popLast() else { return false }
        undoStack.append(words)
        words = nextState
        persistWordStates()
        selectedWordIds = []
        selectionAnchorWordId = nil
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

    /// Updates the currently highlighted word based on playback position.
    /// Binary search for O(log n) performance at 60 fps.
    func updatePlayingWord(timeMs: Double) {
        let sortedWords = words.filter { !$0.isDeleted }.sorted { $0.startMs < $1.startMs }
        guard !sortedWords.isEmpty else {
            currentPlayingWordId = nil
            return
        }

        var low = 0, high = sortedWords.count - 1
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

        currentPlayingWordId = result.map { sortedWords[$0].id }
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

    // MARK: - Timeline Sync

    /// Marks transcript words as deleted when their source time range is no longer present on the
    /// timeline. This is the reverse of transcript-driven ripple edits: timeline trims/deletes
    /// become visible in the text editor without physically deleting transcription rows.
    func markWordsDeletedByTimeline(
        keptRangesByClipId: [Int64: [TimeRangeMs]],
        affectedClipIds: Set<Int64>
    ) {
        guard let clipId = words.first?.clipId, affectedClipIds.contains(clipId) else { return }

        let keptRanges = keptRangesByClipId[clipId, default: []]
        var changed = false

        for index in words.indices where words[index].clipId == clipId && !words[index].isDeleted {
            if !Self.word(words[index], overlapsAny: keptRanges) {
                words[index].isDeleted = true
                changed = true
            }
        }

        guard changed else { return }
        selectedWordIds = selectedWordIds.filter { id in
            words.contains { $0.id == id && !$0.isDeleted }
        }
        if let anchor = selectionAnchorWordId, !selectedWordIds.contains(anchor) {
            selectionAnchorWordId = nil
        }
        if let playingId = currentPlayingWordId,
           words.first(where: { $0.id == playingId })?.isDeleted == true {
            currentPlayingWordId = nil
        }
        persistWordStates()
    }

    // MARK: - Helpers

    private static func word(_ word: TranscriptWord, overlapsAny ranges: [TimeRangeMs]) -> Bool {
        ranges.contains { range in
            word.endMs > range.startMs && word.startMs < range.endMs
        }
    }

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
