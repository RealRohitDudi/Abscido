import AVFoundation
import Foundation
import OpenTimelineIO

/// Coordinates render export and editorial interchange (OpenTimelineIO + derived XML).
actor ExportEngine {

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

    // MARK: - OpenTimelineIO interchange

    /// Native ``.otio`` JSON via OpenTimelineIO’s canonical serializer (same graph Resolve/Premiere adapters consume).
    func exportOTIOJSON(timeline: Timeline, outputURL: URL) throws {
        do {
            try OTIOInterchangeExporter.writeOTIOJSON(timeline: timeline, to: outputURL)
        } catch let err as OTIOError {
            throw AbscidoError.exportFailed(reason: "\(err.description) (OpenTimelineIO code \(err.status.rawValue))")
        }
    }

    /// FCP 7 XML from the bridge timeline (same layout as playback).
    func exportFcp7XML(
        bridgeTimeline: OTIOTimeline,
        mediaFiles: [MediaFile],
        projectName: String,
        outputURL: URL
    ) throws {
        let xml = try OTIOInterchangeExporter.buildFCP7XML(
            bridgeTimeline: bridgeTimeline,
            mediaFiles: mediaFiles,
            projectName: projectName
        )
        try xml.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// FCPXML 1.10 — primary storyline from the first video track.
    func exportFCPXML(
        bridgeTimeline: OTIOTimeline,
        mediaFiles: [MediaFile],
        projectName: String,
        outputURL: URL
    ) throws {
        let xml = try OTIOInterchangeExporter.buildFCPXML(
            bridgeTimeline: bridgeTimeline,
            mediaFiles: mediaFiles,
            projectName: projectName
        )
        try xml.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// CMX 3600-style EDL (first video track).
    func exportEDL(
        bridgeTimeline: OTIOTimeline,
        mediaFiles: [MediaFile],
        projectName: String,
        outputURL: URL
    ) throws {
        let text = try OTIOInterchangeExporter.buildCMX3600EDL(
            bridgeTimeline: bridgeTimeline,
            mediaFiles: mediaFiles,
            projectName: projectName
        )
        try text.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
