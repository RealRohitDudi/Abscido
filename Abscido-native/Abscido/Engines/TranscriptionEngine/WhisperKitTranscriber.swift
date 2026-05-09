@preconcurrency import AVFoundation
import Foundation
import WhisperKit

// MARK: - WhisperKit Model Sizes

/// Available on-device Whisper model sizes. All are CoreML-compiled and run locally via
/// Apple's Neural Engine + GPU — no network after the one-time download, no TCC entitlements.
///
/// **Choosing a model for non-English audio:** Whisper's `tiny` and `base` checkpoints are
/// trained almost entirely on English. With languages like Hindi, Arabic, Chinese or Japanese
/// they routinely emit the *wrong* script (e.g. Urdu/Arabic glyphs for Hindi audio) even when
/// the language token is forced. `small` is the practical minimum for non-English; for
/// production-grade quality use `largeV3Turbo`.
enum WhisperKitModelSize: String, CaseIterable, Sendable {
    case tiny         = "openai_whisper-tiny"
    case base         = "openai_whisper-base"
    case small        = "openai_whisper-small"
    /// ANE-optimised compressed Whisper large-v3 (Sept 2024 release). Recommended for any
    /// non-English language and the highest-quality option that still fits in a one-time
    /// download under a gigabyte.
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"

    var displayName: String {
        switch self {
        case .tiny:         return "Tiny  (75 MB · English only)"
        case .base:         return "Base (150 MB · English only)"
        case .small:        return "Small (480 MB · multilingual)"
        case .largeV3Turbo: return "Large v3 Turbo (632 MB · best quality)"
        }
    }

    /// Model size string shown beside the picker.
    var shortLabel: String {
        switch self {
        case .tiny:         return "Tiny"
        case .base:         return "Base"
        case .small:        return "Small"
        case .largeV3Turbo: return "Large·v3·Turbo"
        }
    }

    /// Whether this checkpoint is large enough to be reliable for non-English audio.
    /// Hindi/Urdu, Arabic, CJK, Cyrillic and similar non-Latin languages need at least
    /// `small` to consistently produce the correct script.
    var isReliableForNonEnglish: Bool {
        switch self {
        case .tiny, .base:      return false
        case .small, .largeV3Turbo: return true
        }
    }

    /// Checkpoint WhisperKit will actually load. `tiny` / `base` cannot reliably honour a forced
    /// non-English language (they still drift into Urdu/Arabic script for Hindi, etc.); upgrading
    /// to `small` is the smallest model that multilingual Whisper was trained for.
    static func effectiveForTranscription(
        requested: WhisperKitModelSize,
        normalizedLanguageCode: String
    ) -> WhisperKitModelSize {
        guard normalizedLanguageCode != "en" else { return requested }
        guard !requested.isReliableForNonEnglish else { return requested }
        return .small
    }
}

// MARK: - Transcriber

/// On-device speech-to-text via WhisperKit (CoreML + Metal).
///
/// **Why WhisperKit instead of SFSpeechRecognizer or Python Whisper?**
/// - No `com.apple.security.personal-information.speech-recognition` entitlement required
///   → works with plain `swift run`, no re-signing script needed.
/// - No Python runtime or `mlx-whisper` pip dependency.
/// - Uses Apple Neural Engine / GPU via CoreML → fast on Apple Silicon.
/// - Word-level timestamps out-of-the-box.
/// - Models download once to `~/Library/Caches/huggingface/` and are reused.
enum WhisperKitTranscriber {

    /// Transcribes audio from `mediaURL` (any AVFoundation-readable format: MP4, MOV, M4A, WAV …).
    ///
    /// Progress reports map as follows:
    /// - 0 %–12 %  initialising / loading model
    /// - 12 %–91 % transcription windows
    /// - 91 %–100 % result assembly
    static func transcribe(
        mediaURL: URL,
        clipId: Int64,
        language: String,
        modelSize: WhisperKitModelSize = .base,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> [TranscriptWord] {

        onProgress(0.02)

        // MARK: Extract audio
        // WhisperKit's AudioProcessor reads audio via AVFoundation. Passing a video container
        // directly works on macOS, but an explicit M4A export is more reliable across formats.
        let audioURL = try await extractAudioM4A(from: mediaURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        onProgress(0.06)

        // MARK: Initialise WhisperKit (downloads model on first use, loads from cache thereafter)
        // WhisperKit does not report download progress; first-time Small/Large fetches can take
        // several minutes. Creep 6%→11% on a timer so the UI is not frozen at 2%.
        let loadHeartbeat = Task { @Sendable in
            var p = 0.06
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { break }
                p = min(0.11, p + 0.006)
                onProgress(p)
            }
        }

        let whisperKit: WhisperKit
        do {
            whisperKit = try await WhisperKit(
                model: modelSize.rawValue,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: true
            )
        } catch {
            loadHeartbeat.cancel()
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "WhisperKit failed to load model '\(modelSize.shortLabel)': \(error.localizedDescription). Check your internet connection for first-time model download."
            )
        }
        loadHeartbeat.cancel()

        onProgress(0.12)

        // MARK: Estimate total windows for progress (Whisper uses 30-second windows)
        let duration = (try? await AVURLAsset(url: audioURL).load(.duration).seconds) ?? 60.0
        let totalWindows = max(1, Int(ceil(duration / 30.0)))
        let windowTracker = WindowProgressTracker(total: totalWindows)

        // MARK: Decode options
        // Force the selected language when provided; otherwise allow auto-detection.
        let normalizedLanguage = LanguageRegistry.normalizedLanguageCode(language)
        let isForcedLanguage = normalizedLanguage != nil
        let isForcedNonEnglish = isForcedLanguage && normalizedLanguage != "en"

        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: normalizedLanguage,
            // Allow temperature to climb on fallback so a hallucinated low-confidence window
            // (e.g. wrong-script garbage for Hindi) gets retried instead of frozen at temp 0.
            temperature: 0.0,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            // When we attach `promptTokens` for script priming WhisperKit already bypasses the
            // KV prefill cache (see TextDecoder.prefillDecoderInputs — the cache branch checks
            // `promptTokens == nil`). Disable it explicitly for forced non-English so the intent
            // is obvious in code and we never silently fall back to a cached English-prefilled
            // KV state on a future WhisperKit version.
            usePrefillCache: !isForcedNonEnglish,
            detectLanguage: !isForcedLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            // Suppress the empty / blank-padding tokens; helps prevent "thank you for watching"
            // / "..." style hallucinations when the audio is sparse.
            suppressBlank: true,
            // Slightly stricter than WhisperKit's defaults — rejects the repetitive-script
            // hallucination loops the small models fall into on Indic / Arabic audio.
            compressionRatioThreshold: 2.2,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6
        )

        // If the user explicitly picked a non-English language, prime the decoder with a real
        // multi-sentence seed in the target script. The `<|xx|>` language token alone is a SOFT
        // bias — for languages whose audio overlaps with another script (Hindi/Urdu being the
        // canonical case) only a script-specific prefill prompt reliably keeps Whisper on the
        // intended writing system.
        if let code = normalizedLanguage,
           code != "en",
           let seed = LanguageRegistry.promptSeedText(forNormalizedCode: code),
           let tokenizer = whisperKit.tokenizer
        {
            options.promptTokens = tokenizer.encode(text: seed)
        }

        // MARK: Run transcription
        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options,
                callback: { progress in
                    let mapped = windowTracker.advance(to: progress.windowId)
                    onProgress(mapped)
                    return true
                }
            )
        } catch {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "WhisperKit transcription failed: \(error.localizedDescription)"
            )
        }

        onProgress(0.91)

        // MARK: Build word list from word-level timestamps
        var words: [TranscriptWord] = []
        for result in results {
            for timing in result.allWords {
                let text = timing.word
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Drop empty strings and Whisper special tokens such as <|0.00|>, [BLANK_AUDIO], etc.
                guard !text.isEmpty,
                      !text.hasPrefix("<"),
                      !text.hasPrefix("[") else { continue }

                words.append(TranscriptWord(
                    clipId: clipId,
                    word: text,
                    startMs: Double(timing.start) * 1000.0,
                    endMs: Double(timing.end) * 1000.0,
                    confidence: Double(timing.probability)
                ))
            }
        }

        onProgress(1.0)
        return words
    }

    // MARK: - Audio Extraction

    /// Exports just the audio track to a temporary M4A file so WhisperKit receives a clean
    /// audio-only input regardless of the source container (MP4, MOV, MXF, etc.).
    private static func extractAudioM4A(from url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Abscido", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let output = tempDir.appendingPathComponent("wk_\(UUID().uuidString).m4a")

        let asset = AVURLAsset(url: url)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            // Pure audio files (WAV, AIFF) may not be exportable to M4A — pass original URL.
            return url
        }
        session.outputURL      = output
        session.outputFileType = .m4a

        await session.export()

        guard session.status == .completed else {
            // If export fails (e.g. already an M4A or no audio track), pass original.
            try? FileManager.default.removeItem(at: output)
            return url
        }
        return output
    }
}

// MARK: - Progress Tracking

/// Maps WhisperKit's integer windowId to a 0.12 → 0.91 progress value.
/// Thread-safe via `NSLock`; WhisperKit calls the callback from a concurrent context.
private final class WindowProgressTracker: @unchecked Sendable {

    private let total: Int
    private var maxWindow = 0
    private let lock = NSLock()

    init(total: Int) { self.total = total }

    /// Returns the mapped progress value (0.12 to 0.91).
    func advance(to windowId: Int) -> Double {
        lock.withLock {
            if windowId > maxWindow { maxWindow = windowId }
            let ratio = Double(maxWindow + 1) / Double(total)
            return min(0.91, 0.12 + ratio * 0.79)
        }
    }
}
