import Foundation

/// Maps OTIO timeline state to UI-friendly models for the timeline view.
@MainActor
@Observable
final class TimelineViewModel {
    var clips: [TimelineClipModel] = []
    var totalDurationMs: Double = 0
    var playheadMs: Double = 0
    var pixelsPerSecond: Double = 100.0

    /// Waveform amplitude data keyed by media file ID.
    var waveformData: [Int64: [Float]] = [:]

    /// Index where a dragged clip would be inserted (nil when not dragging).
    var dropIndicatorIndex: Int?

    private let otioEngine = OTIOEngine()
    private let waveformGenerator = WaveformGenerator()

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
            // Generate waveforms for all media files
            await generateWaveforms(for: mediaFiles)
        }
    }

    /// Inserts a media file at a specific clip index in the timeline.
    func insertMediaFile(_ file: MediaFile, at index: Int, allMediaFiles: [MediaFile]) {
        Task {
            // Get the current timeline or build one
            var timeline = await otioEngine.currentTimeline()
            if timeline == nil {
                timeline = await otioEngine.buildTimeline(from: allMediaFiles)
            }
            guard var tl = timeline else { return }

            // Create a new clip for the dropped media
            let clip = OTIOClip(
                name: file.url.lastPathComponent,
                mediaReference: OTIOMediaReference(targetURL: file.url.absoluteString),
                sourceRange: OTIOTimeRange(
                    startTime: OTIOTime(value: 0, rate: file.fps),
                    duration: OTIOTime(
                        value: file.durationMs / 1000.0 * file.fps,
                        rate: file.fps
                    )
                ),
                mediaFileId: file.id
            )

            // Insert into the first video track
            if tl.tracks.isEmpty {
                let track = OTIOTrack(
                    name: file.url.deletingPathExtension().lastPathComponent,
                    kind: .video,
                    children: [.clip(clip)]
                )
                tl.tracks.append(track)
            } else {
                let safeIndex = min(index, tl.tracks[0].children.count)
                tl.tracks[0].children.insert(.clip(clip), at: safeIndex)
            }

            // Update the engine and rebuild UI
            await otioEngine.setTimeline(tl)
            await updateFromTimeline(tl, mediaFiles: allMediaFiles + [file])

            // Generate waveform for the new file
            await generateWaveforms(for: [file])
        }
    }

    /// Computes the insertion index from a drop x-coordinate.
    func insertionIndex(forDropX x: CGFloat) -> Int {
        var accumulated: CGFloat = 0
        for (index, clip) in clips.enumerated() {
            let clipWidth = clip.durationMs / 1000.0 * pixelsPerSecond
            if x < accumulated + clipWidth / 2 {
                return index
            }
            accumulated += clipWidth
        }
        return clips.count
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

    /// Sets the zoom level directly (used by pinch gesture).
    func setZoom(_ pps: Double) {
        pixelsPerSecond = max(20, min(400, pps))
    }

    // MARK: - Waveform

    /// Generates waveform data for the given media files.
    private func generateWaveforms(for mediaFiles: [MediaFile]) async {
        for file in mediaFiles {
            let samples = await waveformGenerator.generateWaveform(for: file)
            waveformData[file.id] = samples
        }
    }

    /// Returns waveform samples for a clip, if available.
    func waveformSamples(for clip: TimelineClipModel) -> [Float]? {
        waveformData[clip.mediaFileId]
    }

    /// Exports the OTIO timeline as JSON.
    func exportOTIOJSON() async throws -> String {
        try await otioEngine.exportOTIOJSON()
    }
}
