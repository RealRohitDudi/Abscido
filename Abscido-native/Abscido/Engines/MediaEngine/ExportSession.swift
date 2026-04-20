import AVFoundation
import Foundation

/// Wraps AVAssetExportSession for rendering the final composition to a file.
enum ExportSession {

    /// Export preset configuration.
    struct ExportConfig: Sendable {
        let presetName: String
        let outputFileType: AVFileType
        let fileExtension: String

        static let proresLT = ExportConfig(
            presetName: AVAssetExportPresetAppleProRes422LPCM,
            outputFileType: .mov,
            fileExtension: "mov"
        )

        static let highestQuality = ExportConfig(
            presetName: AVAssetExportPresetHighestQuality,
            outputFileType: .mov,
            fileExtension: "mov"
        )

        static let h264 = ExportConfig(
            presetName: AVAssetExportPresetHighestQuality,
            outputFileType: .mp4,
            fileExtension: "mp4"
        )
    }

    /// Exports the given composition to the output URL with progress reporting.
    static func export(
        composition: AVComposition,
        to outputURL: URL,
        config: ExportConfig = .highestQuality,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Ensure output directory exists
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: config.presetName
        ) else {
            throw AbscidoError.exportFailed(reason: "Could not create export session with preset: \(config.presetName)")
        }

        session.outputURL = outputURL
        session.outputFileType = config.outputFileType
        session.shouldOptimizeForNetworkUse = false

        // Progress polling task
        let progressTask = Task {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 250_000_000) // 250ms
                let progress = Double(session.progress)
                onProgress(progress)
                if session.status == .completed || session.status == .failed || session.status == .cancelled {
                    break
                }
            }
        }

        await session.export()
        progressTask.cancel()

        switch session.status {
        case .completed:
            onProgress(1.0)
        case .failed:
            throw AbscidoError.exportFailed(
                reason: session.error?.localizedDescription ?? "Unknown export error"
            )
        case .cancelled:
            throw AbscidoError.exportFailed(reason: "Export was cancelled")
        default:
            throw AbscidoError.exportFailed(reason: "Unexpected export status: \(session.status.rawValue)")
        }
    }
}
