@preconcurrency import AVFoundation
import Foundation

/// Manages the MLX-Whisper Python subprocess for local transcription on Apple Silicon.
actor TranscriptionEngine {
    private var pythonProcess: Process?
    private let whisperBridge = MLXWhisperBridge()

    /// Transcribes a media file to word-level timestamps using MLX-Whisper.
    func transcribe(
        mediaFile: MediaFile,
        language: String = "en",
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptWord] {
        // Step 1: Extract audio to WAV
        onProgress(0.05)
        let wavURL = try await extractAudio(from: mediaFile)

        // Step 2: Run MLX-Whisper via Python subprocess
        onProgress(0.1)
        let jsonOutput = try await whisperBridge.runTranscription(
            wavPath: wavURL.path,
            language: language,
            onProgress: { progress in
                // Scale whisper progress to 10%-90% of total
                onProgress(0.1 + progress * 0.8)
            }
        )

        // Step 3: Parse output
        onProgress(0.9)
        let words = try WhisperOutputParser.parse(
            jsonString: jsonOutput,
            clipId: mediaFile.id
        )

        // Cleanup temp WAV
        try? FileManager.default.removeItem(at: wavURL)

        onProgress(1.0)
        return words
    }

    /// Extracts audio from a media file to a 16kHz mono WAV file.
    private func extractAudio(from mediaFile: MediaFile) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Abscido", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let wavURL = tempDir.appendingPathComponent("\(UUID().uuidString).wav")

        let asset = AVURLAsset(url: mediaFile.url)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AbscidoError.transcriptionFailed(
                clipId: mediaFile.id,
                pythonError: "Could not create audio export session"
            )
        }

        let m4aURL = tempDir.appendingPathComponent("\(UUID().uuidString).m4a")
        exportSession.outputURL = m4aURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status != .completed {
            throw AbscidoError.transcriptionFailed(
                clipId: mediaFile.id,
                pythonError: exportSession.error?.localizedDescription ?? "Audio extraction failed"
            )
        }

        // Convert M4A to 16kHz mono WAV using AVAudioFile
        let audioFile = try AVAudioFile(forReading: m4aURL)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let outputFile = try AVAudioFile(
            forWriting: wavURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)

        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw AbscidoError.transcriptionFailed(
                clipId: mediaFile.id,
                pythonError: "Failed to create audio buffer"
            )
        }
        try audioFile.read(into: buffer)

        // Resample by writing to output format
        let converter = AVAudioConverter(from: audioFile.processingFormat, to: format)!
        let outputFrameCount = AVAudioFrameCount(
            Double(frameCount) * 16000.0 / audioFile.processingFormat.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: outputFrameCount
        ) else {
            throw AbscidoError.transcriptionFailed(
                clipId: mediaFile.id,
                pythonError: "Failed to create output buffer"
            )
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            throw AbscidoError.transcriptionFailed(
                clipId: mediaFile.id,
                pythonError: error.localizedDescription
            )
        }

        try outputFile.write(from: outputBuffer)

        // Cleanup intermediate M4A
        try? FileManager.default.removeItem(at: m4aURL)

        return wavURL
    }

    /// Cancels any running transcription.
    func cancel() {
        pythonProcess?.terminate()
        pythonProcess = nil
    }
}
