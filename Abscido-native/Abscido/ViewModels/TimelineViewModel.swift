import Foundation

/// Maps OTIO timeline state to UI-friendly models for the timeline view.
@MainActor
@Observable
final class TimelineViewModel {
    var clips: [TimelineClipModel] = []
    var totalDurationMs: Double = 0
    var playheadMs: Double = 0
    var pixelsPerSecond: Double = 100.0

    private let otioEngine = OTIOEngine()

    struct TimelineClipModel: Identifiable, Equatable {
        let id: String
        let name: String
        let startMs: Double
        let durationMs: Double
        let mediaFileId: Int64
        let color: ClipColor

        enum ClipColor: Sendable {
            case video
            case audio
            case gap
        }
    }

    /// Rebuilds timeline UI model from edit decisions and media files.
    func rebuild(editDecisions: [EditDecision], mediaFiles: [MediaFile]) {
        Task {
            let timeline = await otioEngine.applyEditDecisions(editDecisions, mediaFiles: mediaFiles)
            await updateFromTimeline(timeline, mediaFiles: mediaFiles)
        }
    }

    /// Builds an initial timeline from unedited media files.
    func buildInitial(mediaFiles: [MediaFile]) {
        Task {
            let timeline = await otioEngine.buildTimeline(from: mediaFiles)
            await updateFromTimeline(timeline, mediaFiles: mediaFiles)
        }
    }

    private func updateFromTimeline(_ timeline: OTIOTimeline, mediaFiles: [MediaFile]) async {
        var newClips: [TimelineClipModel] = []
        var offset: Double = 0

        for track in timeline.tracks {
            for child in track.children {
                switch child {
                case .clip(let clip):
                    let durationMs = clip.sourceRange.durationMs
                    newClips.append(TimelineClipModel(
                        id: "\(clip.mediaFileId)_\(offset)",
                        name: clip.name,
                        startMs: offset,
                        durationMs: durationMs,
                        mediaFileId: clip.mediaFileId,
                        color: track.kind == .video ? .video : .audio
                    ))
                    offset += durationMs

                case .gap(let gap):
                    let durationMs = gap.sourceRange.durationMs
                    newClips.append(TimelineClipModel(
                        id: "gap_\(offset)",
                        name: "Gap",
                        startMs: offset,
                        durationMs: durationMs,
                        mediaFileId: 0,
                        color: .gap
                    ))
                    offset += durationMs
                }
            }
        }

        self.clips = newClips
        self.totalDurationMs = offset
    }

    /// Updates the playhead position.
    func updatePlayhead(ms: Double) {
        playheadMs = ms
    }

    // MARK: - Zoom

    func zoomIn() {
        pixelsPerSecond = min(400, pixelsPerSecond * 1.5)
    }

    func zoomOut() {
        pixelsPerSecond = max(20, pixelsPerSecond / 1.5)
    }

    /// Exports the OTIO timeline as JSON.
    func exportOTIOJSON() async throws -> String {
        try await otioEngine.exportOTIOJSON()
    }
}
