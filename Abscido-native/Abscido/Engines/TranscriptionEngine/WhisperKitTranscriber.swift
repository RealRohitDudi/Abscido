@preconcurrency import AVFoundation
import Foundation
import WhisperKit

// MARK: - WhisperKit Model Sizes

/// Available on-device Whisper model sizes. All are CoreML-compiled and run locally via
/// Apple's Neural Engine + GPU — no network after the one-time download, no TCC entitlements.
enum WhisperKitModelSize: String, CaseIterable, Sendable {
    case tiny  = "openai_whisper-tiny"
    case base  = "openai_whisper-base"
    case small = "openai_whisper-small"

    var displayName: String {
        switch self {
        case .tiny:  return "Tiny  (75 MB · fastest)"
        case .base:  return "Base (150 MB · balanced)"
        case .small: return "Small (480 MB · accurate)"
        }
    }

    /// Model size string shown beside the picker.
    var shortLabel: String {
        switch self {
        case .tiny:  return "Tiny"
        case .base:  return "Base"
        case .small: return "Small"
        }
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
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "WhisperKit failed to load model '\(modelSize.shortLabel)': \(error.localizedDescription). Check your internet connection for first-time model download."
            )
        }

        onProgress(0.12)

        // MARK: Estimate total windows for progress (Whisper uses 30-second windows)
        let duration = (try? await AVURLAsset(url: audioURL).load(.duration).seconds) ?? 60.0
        let totalWindows = max(1, Int(ceil(duration / 30.0)))
        let windowTracker = WindowProgressTracker(total: totalWindows)

        // MARK: Decode options
        // Force the selected language when provided; otherwise allow auto-detection.
        let normalizedLanguage = (language == "auto" || language.isEmpty) ? nil : language
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: normalizedLanguage,
            temperature: 0.0,
            usePrefillPrompt: true,
            detectLanguage: normalizedLanguage == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true
        )

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
