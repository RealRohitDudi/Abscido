@preconcurrency import AVFoundation
import Foundation

// MARK: - Transcription Backend

/// Selects the transcription engine.
///
/// | Backend      | Requires                          | Sandboxed | Notes                                        |
/// |-------------|-----------------------------------|-----------|----------------------------------------------|
/// | whisperKit  | Nothing (CoreML model download)   | ✅         | Recommended. No TCC, no Python.              |
/// | appleSpeech | Speech Recognition entitlement    | ✅         | Needs re-signed binary (`run-with-speech-capability.sh`) |
/// | mlxWhisper  | Python 3 + `pip install mlx-whisper` | ❌      | Development only; blocked in hardened sandbox.|
enum TranscriptionBackend: String, CaseIterable, Sendable {
    case whisperKit  = "whisper_kit"
    case appleSpeech = "apple_speech"
    case mlxWhisper  = "mlx_whisper"

    var displayName: String {
        switch self {
        case .whisperKit:  return "WhisperKit (On-device)"
        case .appleSpeech: return "Apple Speech (Built-in)"
        case .mlxWhisper:  return "MLX-Whisper (Python)"
        }
    }
}

// MARK: - Engine

/// Manages local speech-to-text transcription for source media clips.
///
/// **Recommended path** — WhisperKit: pure Swift + CoreML, no TCC entitlements,
/// no Python, word-level timestamps, runs on Apple Neural Engine / GPU.
///
/// **Secondary path** — `SFSpeechRecognizer`: native, sandbox-safe, but requires
/// the binary to carry a `speech-recognition` entitlement (use `run-with-speech-capability.sh`).
///
/// **Development path** — MLX-Whisper via Python subprocess: highest accuracy on
/// Apple Silicon, but needs `pip install mlx-whisper` and a signed build.
actor TranscriptionEngine {

    private let whisperBridge = MLXWhisperBridge()

    // MARK: - Public

    func transcribe(
        mediaFile: MediaFile,
        language: String = "en",
        backend: TranscriptionBackend = .whisperKit,
        modelName: String? = nil,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptWord] {
        // Normalize to 2-letter Whisper/MLX codes (e.g. "hi-IN" -> "hi").
        let normalizedLanguage = LanguageRegistry.normalizedLanguageCode(language) ?? "en"
        switch backend {

        case .whisperKit:
            let requested = modelName.flatMap { WhisperKitModelSize(rawValue: $0) } ?? .base
            let size = WhisperKitModelSize.effectiveForTranscription(
                requested: requested,
                normalizedLanguageCode: normalizedLanguage
            )
            return try await mediaFile.withReadableFileURL { scopedURL in
                try await WhisperKitTranscriber.transcribe(
                    mediaURL: scopedURL,
                    clipId: mediaFile.id,
                    language: normalizedLanguage,
                    modelSize: size,
                    onProgress: onProgress
                )
            }

        case .appleSpeech:
            return try await mediaFile.withReadableFileURL { scopedURL in
                try await AppleSpeechTranscriber.transcribe(
                    mediaURL: scopedURL,
                    clipId: mediaFile.id,
                    languageCode: normalizedLanguage,
                    onProgress: onProgress
                )
            }

        case .mlxWhisper:
            return try await mediaFile.withReadableFileURL { scopedURL in
                try await runMLXWhisper(
                    mediaURL: scopedURL,
                    clipId: mediaFile.id,
                    language: normalizedLanguage,
                    mlxModelName: modelName ?? MLXWhisperBridge.defaultModelName,
                    onProgress: onProgress
                )
            }
        }
    }

    // MARK: - MLX-Whisper Engine (Python subprocess)

    private func runMLXWhisper(
        mediaURL: URL,
        clipId: Int64,
        language: String,
        mlxModelName: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptWord] {
        onProgress(0.05)
        let wavURL = try await extractAudioWAV(from: mediaURL, clipId: clipId)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        onProgress(0.10)
        let json = try await whisperBridge.runTranscription(
            wavPath: wavURL.path,
            language: language,
            modelName: mlxModelName,
            onProgress: { p in onProgress(0.10 + p * 0.80) }
        )

        onProgress(0.90)
        let words = try WhisperOutputParser.parse(jsonString: json, clipId: clipId)
        onProgress(1.00)
        return words
    }

    // MARK: - Audio Utilities

    /// Extracts 16 kHz mono WAV — required by MLX-Whisper. `mediaURL` must already be sandbox-readable.
    private func extractAudioWAV(from mediaURL: URL, clipId: Int64) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Abscido", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Step 1: Export to intermediate M4A
        let m4aURL = tempDir.appendingPathComponent("\(UUID().uuidString).m4a")
        let asset  = AVURLAsset(url: mediaURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Could not create audio export session."
            )
        }
        exportSession.outputURL      = m4aURL
        exportSession.outputFileType = .m4a
        await exportSession.export()

        guard exportSession.status == .completed else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: exportSession.error?.localizedDescription ?? "Audio extraction failed."
            )
        }

        // Step 2: Resample M4A → 16 kHz mono WAV
        let wavURL     = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        let sourceFile = try AVAudioFile(forReading: m4aURL)
        let targetFmt  = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate:   16000,
            channels:     1,
            interleaved:  true
        )!

        let outputFile = try AVAudioFile(
            forWriting: wavURL,
            settings:   targetFmt.settings,
            commonFormat: .pcmFormatInt16,
            interleaved:  true
        )

        guard let converter = AVAudioConverter(
            from: sourceFile.processingFormat,
            to:   targetFmt
        ) else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Cannot create audio converter to 16 kHz mono."
            )
        }

        let srcFrames = AVAudioFrameCount(sourceFile.length)
        guard let srcBuf = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: srcFrames
        ) else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Failed to allocate source audio buffer."
            )
        }
        try sourceFile.read(into: srcBuf)

        let dstFrames = AVAudioFrameCount(
            Double(srcFrames) * targetFmt.sampleRate / sourceFile.processingFormat.sampleRate
        )
        guard let dstBuf = AVAudioPCMBuffer(
            pcmFormat: targetFmt,
            frameCapacity: dstFrames
        ) else {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: "Failed to allocate output audio buffer."
            )
        }

        var inputConsumed = false
        var convError: NSError?
        converter.convert(to: dstBuf, error: &convError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return srcBuf
        }

        if let convError {
            throw AbscidoError.transcriptionFailed(
                clipId: clipId,
                pythonError: convError.localizedDescription
            )
        }

        try outputFile.write(from: dstBuf)
        try? FileManager.default.removeItem(at: m4aURL)
        return wavURL
    }
}
