@preconcurrency import AVFoundation
import Foundation
import Speech

/// Runs the full Apple Speech pipeline on **`@MainActor` only**.
///
/// `SFSpeechRecognizer`, `recognitionTask`, and recognition callbacks must execute on the main
/// thread; creating a recogniser from `TranscriptionEngine`’s background actor triggers
/// **`__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`** on macOS 26 despite an embedded plist.
@MainActor
enum AppleSpeechTranscriber {

    private static let chunkSeconds: Double = 55.0

    /// High-level entry: resolves locale, verifies recogniser, transcribes every chunk on the main actor.
    static func transcribe(
        mediaURL: URL,
        clipId: Int64,
        languageCode: String,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> [TranscriptWord] {

        onProgress(0.05)

        let locale = localeForAbscidoCode(languageCode)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Speech recognition is not available for language '\(languageCode)'."
            )
        }
        guard recognizer.isAvailable else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Speech recognizer is unavailable for this locale. Try English (en) or check System Settings → Siri & Spotlight."
            )
        }

        onProgress(0.08)
        let asset = AVURLAsset(url: mediaURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = duration.seconds
        guard totalSeconds > 0 else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Media file has no playable audio or zero duration."
            )
        }

        onProgress(0.10)
        return try await transcribeChunked(
            mediaURL: mediaURL,
            clipId: clipId,
            totalSeconds: totalSeconds,
            recognizer: recognizer,
            onProgress: { p in onProgress(0.10 + p * 0.90) }
        )
    }

    // MARK: - Chunking + recognition

    private static func transcribeChunked(
        mediaURL: URL,
        clipId: Int64,
        totalSeconds: Double,
        recognizer: SFSpeechRecognizer,
        onProgress: @escaping (Double) -> Void
    ) async throws -> [TranscriptWord] {

        let chunkSize = chunkSeconds
        let chunkCount = max(1, Int(ceil(totalSeconds / chunkSize)))
        var allWords: [TranscriptWord] = []

        for i in 0 ..< chunkCount {
            try Task.checkCancellation()

            let chunkStart = Double(i) * chunkSize
            let chunkEnd = min(chunkStart + chunkSize, totalSeconds)

            let chunkURL: URL
            let needsCleanup: Bool

            if chunkCount == 1 {
                chunkURL = mediaURL
                needsCleanup = false
            } else {
                chunkURL = try await exportAudioChunk(from: mediaURL, start: chunkStart, end: chunkEnd)
                needsCleanup = true
            }

            let holder = RecognitionTaskHolder()
            let chunkWords = try await withTaskCancellationHandler {
                try await recognizeURL(
                    url: chunkURL,
                    clipId: clipId,
                    timeOffset: chunkStart,
                    recognizer: recognizer,
                    holder: holder
                )
            } onCancel: {
                holder.task?.cancel()
            }

            allWords.append(contentsOf: chunkWords)

            if needsCleanup {
                try? FileManager.default.removeItem(at: chunkURL)
            }

            onProgress(Double(i + 1) / Double(chunkCount))
        }

        return allWords
    }

    private static func recognizeURL(
        url: URL,
        clipId: Int64,
        timeOffset: Double,
        recognizer: SFSpeechRecognizer,
        holder: RecognitionTaskHolder
    ) async throws -> [TranscriptWord] {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[TranscriptWord], Error>) in

            func fail(_ message: String) {
                continuation.resume(
                    throwing: AbscidoError.transcriptionFailed(clipId: clipId, pythonError: message)
                )
            }

            guard recognizer.isAvailable else {
                fail("Speech recognizer became unavailable.")
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.addsPunctuation = false

            var resumed = false

            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }

                if let error {
                    let ns = error as NSError

                    let isURLCancelled = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
                    let isCocoaCancelled = ns.domain == NSCocoaErrorDomain &&
                        ns.code == NSUserCancelledError

                    if isURLCancelled || isCocoaCancelled {
                        resumed = true
                        continuation.resume(returning: [])
                        return
                    }

                    if ns.domain == "kAFAssistantErrorDomain", ns.code == 203 {
                        resumed = true
                        continuation.resume(returning: [])
                        return
                    }

                    resumed = true
                    let detail = SpeechTranscriptionDiagnostics.userFacingMessage(for: ns)
                    continuation.resume(
                        throwing: AbscidoError.transcriptionFailed(clipId: clipId, pythonError: detail)
                    )
                    return
                }

                guard let result, result.isFinal else { return }

                resumed = true
                let words = extractWords(from: result, clipId: clipId, timeOffset: timeOffset)
                continuation.resume(returning: words)
            }
            holder.task = task
            if holder.task == nil {
                fail("Could not create a speech recognition task for this audio file.")
            }
        }
    }

    private static func extractWords(
        from result: SFSpeechRecognitionResult,
        clipId: Int64,
        timeOffset: Double
    ) -> [TranscriptWord] {
        result.bestTranscription.segments.compactMap { seg in
            let text = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptWord(
                clipId: clipId,
                word: text,
                startMs: (timeOffset + seg.timestamp) * 1000.0,
                endMs: (timeOffset + seg.timestamp + max(seg.duration, 0.05)) * 1000.0,
                confidence: Double(seg.confidence)
            )
        }
    }

    // MARK: - Export

    private static func exportAudioChunk(from url: URL, start: Double, end: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("abscido_chunk_\(UUID().uuidString).m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AbscidoError.transcriptionFailed(
                clipId: 0,
                pythonError: "Cannot create audio export session for a chunk."
            )
        }

        session.outputURL = output
        session.outputFileType = .m4a
        let startTime = CMTime(seconds: start, preferredTimescale: 60_000)
        let duration = CMTime(seconds: max(end - start, 0.1), preferredTimescale: 60_000)
        session.timeRange = CMTimeRange(start: startTime, duration: duration)

        await session.export()

        guard session.status == .completed else {
            throw AbscidoError.transcriptionFailed(
                clipId: 0,
                pythonError: session.error?.localizedDescription ?? "Audio chunk export failed."
            )
        }
        return output
    }

    // MARK: - Locale

    private static func localeForAbscidoCode(_ code: String) -> Locale {
        let map: [String: String] = [
            "en": "en-US", "es": "es-ES", "fr": "fr-FR", "de": "de-DE",
            "hi": "hi-IN", "ja": "ja-JP", "pt": "pt-BR", "ar": "ar-SA",
            "zh": "zh-Hans", "ko": "ko-KR", "it": "it-IT", "nl": "nl-NL",
            "ru": "ru-RU", "pl": "pl-PL", "tr": "tr-TR", "sv": "sv-SE",
            "da": "da-DK", "no": "nb-NO", "fi": "fi-FI", "uk": "uk-UA",
        ]
        return Locale(identifier: map[code] ?? "en-US")
    }
}

// MARK: - Diagnostics

private enum SpeechTranscriptionDiagnostics {
    static func userFacingMessage(for ns: NSError) -> String {

        if ns.domain == "kAFAssistantErrorDomain" {
            switch ns.code {
            case 1700:
                return "Speech privacy metadata was rejected by the system. Rebuild from a clean folder; if developing with swift run, ensure Info.plist is linked (Package.swift -sectcreate)."
            case 1101:
                return "The speech recognition service failed to transcribe this file. Try a shorter clip or M4A/WAV."
            default:
                break
            }
        }

        if ns.domain == NSURLErrorDomain {
            return """
                Network-required speech recognition failed: \(ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)).
                Enable Wi‑Fi or use Apple’s on-device recognition where available.
                """
        }

        let detail = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detail.isEmpty == false else {
            return "Speech recognition failed (domain: \(ns.domain), code: \(ns.code))."
        }
        return detail
    }
}

/// Holds the active recognition task so `withTaskCancellationHandler` can cancel it on the MainActor.
private final class RecognitionTaskHolder: @unchecked Sendable {
    var task: SFSpeechRecognitionTask?
}
