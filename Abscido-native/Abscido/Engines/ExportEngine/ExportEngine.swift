import AVFoundation
import Foundation

/// Coordinates all export operations — render to file and XML export.
actor ExportEngine {
    private let xmlService = XmlExportService()

    // MARK: - Render Export

    /// Compiles the current edit to a ProRes 422 file.
    func compileEdit(
        editDecisions: [EditDecision],
        mediaFiles: [MediaFile],
        outputURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let composition = try await CompositionBuilder.build(
            from: editDecisions,
            mediaFiles: mediaFiles
        )

        try await ExportSession.export(
            composition: composition,
            to: outputURL,
            config: .highestQuality,
            onProgress: onProgress
        )
    }

    /// Renders with a specific export config.
    func render(
        editDecisions: [EditDecision],
        mediaFiles: [MediaFile],
        outputURL: URL,
        config: ExportSession.ExportConfig,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let composition = try await CompositionBuilder.build(
            from: editDecisions,
            mediaFiles: mediaFiles
        )

        try await ExportSession.export(
            composition: composition,
            to: outputURL,
            config: config,
            onProgress: onProgress
        )
    }

    // MARK: - XML Export

    /// Exports the edit as FCP7 XML.
    func exportFcp7XML(
        editDecisions: [EditDecision],
        mediaFiles: [MediaFile],
        projectName: String,
        outputURL: URL
    ) throws {
        let xml = xmlService.buildFcp7XML(
            edl: editDecisions,
            mediaFiles: mediaFiles,
            projectName: projectName
        )
        try xml.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// Exports the edit as FCPXML 1.10.
    func exportFCPXML(
        editDecisions: [EditDecision],
        mediaFiles: [MediaFile],
        projectName: String,
        outputURL: URL
    ) throws {
        let xml = xmlService.buildFCPXML(
            edl: editDecisions,
            mediaFiles: mediaFiles,
            projectName: projectName
        )
        try xml.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
