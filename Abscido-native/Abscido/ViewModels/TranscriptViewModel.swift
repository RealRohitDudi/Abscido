import Combine
import Dispatch
import Foundation
import Security
import Speech

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
            undoStack = []
            redoStack = []
        } catch {
            words = []
            segments = []
        }
    }

    // MARK: - Transcription

    func transcribe(mediaFile: MediaFile) {
        transcriptionTask?.cancel()

        isTranscribing = true
        transcriptionProgress = 0
        transcriptionError = nil

        let language = selectedLanguage
        let backend  = selectedBackend
        let modelName: String? = backend == .whisperKit ? whisperKitModelSize.rawValue
                               : backend == .mlxWhisper  ? MLXWhisperBridge.defaultModelName
                               : nil
        let engine  = transcriptionEngine
        let clipId  = mediaFile.id

        let progressRelay = TranscriptionProgressRelay()
        progressRelay.viewModel = self

        // Inherit MainActor so Speech / TCC calls happen on the app's principal thread.
        transcriptionTask = Task { @MainActor [weak self, engine, progressRelay] in
            guard let self else { return }

            // Apple Speech pre-flight: check for the required TCC entitlement BEFORE calling any
            // Speech API. On unsigned `swift run` builds the entitlement is absent and macOS will
            // deliberately crash the process (__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__) the moment
            // SFSpeechRecognizer tries to contact the TCC daemon. Detecting this here lets us show
            // a helpful error instead of a hard crash.
            if backend == .appleSpeech {
                guard Self.hasSpeechRecognitionEntitlement() else {
                    transcriptionError = """
                        Apple Speech requires a re-signed binary. \
                        Run the app with:  ./scripts/run-with-speech-capability.sh
                        Or switch the engine to WhisperKit (recommended — no signing needed).
                        """
                    isTranscribing = false
                    return
                }
                do {
                    try await prepareAppleSpeechAuthorization()
                } catch {
                    transcriptionError = Self.coherentTranscriptionError(error)
                    isTranscribing = false
                    transcriptionProgress = 0
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

    // MARK: - Apple Speech helpers

    /// Returns `true` when the binary's codesign contains the speech-recognition entitlement.
    /// A `false` result means `swift run` was used without the re-signing script; attempting to
    /// call `SFSpeechRecognizer.requestAuthorization` would crash the process via TCC.
    private static func hasSpeechRecognitionEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let key = "com.apple.security.personal-information.speech-recognition" as CFString
        let value = SecTaskCopyValueForEntitlement(task, key, nil)
        return value != nil
    }

    /// Presents macOS Speech permission on the main actor before Speech touches media files.
    private func prepareAppleSpeechAuthorization() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .denied:
            throw AbscidoError.transcriptionFailed(
                clipId: 0,
                pythonError: "Speech recognition is off. Enable Abscido in System Settings → Privacy & Security → Speech Recognition."
            )
        case .restricted:
            throw AbscidoError.transcriptionFailed(
                clipId: 0,
                pythonError: "Speech recognition is restricted on this Mac (Screen Time or device policy)."
            )
        case .notDetermined:
            let newStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            guard newStatus == .authorized else {
                throw AbscidoError.transcriptionFailed(
                    clipId: 0,
                    pythonError: "Speech recognition was not allowed. Enable it in System Settings → Privacy & Security → Speech Recognition."
                )
            }
        @unknown default:
            throw AbscidoError.transcriptionFailed(clipId: 0, pythonError: "Unknown speech authorization state.")
        }
    }

    /// Produces clearer copy than opaque NSError descriptions for Speech / export failures.
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
