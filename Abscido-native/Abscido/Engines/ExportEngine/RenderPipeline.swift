import AVFoundation
import Foundation

/// Manages the render pipeline for exporting compositions to video files.
/// Uses AVAssetExportSession with hardware-accelerated VideoToolbox encoding.
enum RenderPipeline {

    /// Available export presets for the user.
    enum Preset: String, CaseIterable, Identifiable, Sendable {
        case proresLT = "ProRes 422 LT"
        case highQuality = "High Quality (H.264)"
        case medium = "Medium Quality"

        var id: String { rawValue }

        var exportConfig: ExportSession.ExportConfig {
            switch self {
            case .proresLT:
                return .proresLT
            case .highQuality:
                return .highestQuality
            case .medium:
                return .h264
            }
        }

        var fileExtension: String {
            switch self {
            case .proresLT:
                return "mov"
            case .highQuality:
                return "mov"
            case .medium:
                return "mp4"
            }
        }
    }

    /// Renders the composition to a file using the specified preset.
    static func render(
        editDecisions: [EditDecision],
        mediaFiles: [MediaFile],
        outputURL: URL,
        preset: Preset = .highQuality,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let composition = try await CompositionBuilder.build(
            from: editDecisions,
            mediaFiles: mediaFiles
        )

        try await ExportSession.export(
            composition: composition,
            to: outputURL,
            config: preset.exportConfig,
            onProgress: onProgress
        )
    }

    /// Generates the default output URL for a project export.
    static func defaultOutputURL(
        projectName: String,
        preset: Preset
    ) -> URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let exportDir = moviesDir.appendingPathComponent("Abscido Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .short,
            timeStyle: .short
        ).replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")

        let filename = "\(projectName)_\(timestamp).\(preset.fileExtension)"
        return exportDir.appendingPathComponent(filename)
    }
}
