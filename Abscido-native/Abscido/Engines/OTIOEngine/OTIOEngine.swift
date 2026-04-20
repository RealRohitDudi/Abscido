import Foundation

/// OTIOEngine manages the timeline data model using OTIO-compatible structures.
/// It is the source of truth for the editorial timeline state.
/// All edit operations (word deletions → ripple) mutate this timeline.
actor OTIOEngine {
    private var timeline: OTIOTimeline?

    /// Builds a new timeline from the given media files.
    /// Each media file becomes a track with a single full-duration clip.
    func buildTimeline(from mediaFiles: [MediaFile]) -> OTIOTimeline {
        var tracks: [OTIOTrack] = []

        for file in mediaFiles {
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

            let track = OTIOTrack(
                name: file.url.deletingPathExtension().lastPathComponent,
                kind: .video,
                children: [.clip(clip)]
            )
            tracks.append(track)
        }

        let tl = OTIOTimeline(
            name: "Abscido Timeline",
            tracks: tracks
        )
        self.timeline = tl
        return tl
    }

    /// Applies edit decisions to the timeline, replacing full clips with
    /// sequences of kept clips and gaps (ripple delete).
    func applyEditDecisions(
        _ decisions: [EditDecision],
        mediaFiles: [MediaFile]
    ) -> OTIOTimeline {
        guard var tl = timeline else {
            return buildTimeline(from: mediaFiles)
        }

        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })

        for (trackIndex, track) in tl.tracks.enumerated() {
            guard let firstClip = track.children.compactMap({ item -> OTIOClip? in
                if case .clip(let c) = item { return c } else { return nil }
            }).first,
            let decision = decisions.first(where: { $0.clipId == firstClip.mediaFileId }),
            let file = fileMap[firstClip.mediaFileId] else {
                continue
            }

            var newChildren: [OTIOItem] = []
            var lastEndMs: Double = 0

            for range in decision.keepRanges.sorted(by: { $0.startMs < $1.startMs }) {
                // Insert gap if there's a deleted region before this keep range
                if range.startMs > lastEndMs {
                    // Gap represents deleted content — not inserted into output.
                    // OTIO ripple: gaps are simply omitted, clips pack together.
                }

                let clip = OTIOClip(
                    name: firstClip.name,
                    mediaReference: firstClip.mediaReference,
                    sourceRange: OTIOTimeRange(
                        startTime: OTIOTime(
                            value: range.startMs / 1000.0 * file.fps,
                            rate: file.fps
                        ),
                        duration: OTIOTime(
                            value: range.durationMs / 1000.0 * file.fps,
                            rate: file.fps
                        )
                    ),
                    mediaFileId: firstClip.mediaFileId
                )
                newChildren.append(.clip(clip))
                lastEndMs = range.endMs
            }

            tl.tracks[trackIndex].children = newChildren
        }

        self.timeline = tl
        return tl
    }

    /// Returns the current timeline.
    func currentTimeline() -> OTIOTimeline? {
        timeline
    }

    /// Exports the timeline as OTIO-compatible JSON.
    func exportOTIOJSON() throws -> String {
        guard let tl = timeline else {
            throw AbscidoError.exportFailed(reason: "No timeline to export")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tl)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AbscidoError.exportFailed(reason: "Failed to encode timeline JSON")
        }
        return json
    }

    /// Resets the timeline state.
    func reset() {
        timeline = nil
    }
}
