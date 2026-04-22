import Foundation
import OpenTimelineIO

/// OTIOEngine manages the timeline data model using OTIO-compatible structures.
/// It is the source of truth for the editorial timeline state.
/// Supports multi-track editing, linked clips, insert/overwrite, trim, copy/paste.
/// Uses the real OpenTimelineIO library for serialization and interchange.
actor OTIOEngine {
    private var timeline: OTIOTimeline?
    private var clipboard: [ClipboardEntry] = []

    struct ClipboardEntry: Sendable {
        let clip: OTIOClip
        let trackKind: OTIOTrackKind
    }

    // MARK: - Build

    /// Builds a new timeline from the given media files.
    /// Each media file creates a linked V+A track pair.
    func buildTimeline(from mediaFiles: [MediaFile]) -> OTIOTimeline {
        var videoTrack = OTIOTrack(name: "V1", kind: .video, children: [])
        var audioTrack = OTIOTrack(name: "A1", kind: .audio, children: [])

        for file in mediaFiles {
            let linkId = UUID().uuidString
            let sourceRange = OTIOTimeRange(
                startTime: OTIOTime(value: 0, rate: file.fps),
                duration: OTIOTime(
                    value: file.durationMs / 1000.0 * file.fps,
                    rate: file.fps
                )
            )
            let mediaRef = OTIOMediaReference(targetURL: file.url.absoluteString)

            let videoClip = OTIOClip(
                name: file.url.lastPathComponent,
                mediaReference: mediaRef,
                sourceRange: sourceRange,
                mediaFileId: file.id,
                linkGroupId: linkId
            )

            let audioClip = OTIOClip(
                name: file.url.lastPathComponent,
                mediaReference: mediaRef,
                sourceRange: sourceRange,
                mediaFileId: file.id,
                linkGroupId: linkId
            )

            videoTrack.children.append(.clip(videoClip))
            audioTrack.children.append(.clip(audioClip))
        }

        let tl = OTIOTimeline(
            name: "Abscido Timeline",
            tracks: [videoTrack, audioTrack]
        )
        self.timeline = tl
        return tl
    }

    // MARK: - Insert

    /// Inserts a media file at a time position, creating linked V+A clips.
    /// In insert mode, existing clips are pushed right.
    func insertMedia(
        file: MediaFile,
        atTimeMs timeMs: Double,
        videoTrackIndex: Int,
        audioTrackIndex: Int
    ) {
        guard var tl = timeline else { return }

        let linkId = UUID().uuidString
        let sourceRange = OTIOTimeRange(
            startTime: OTIOTime(value: 0, rate: file.fps),
            duration: OTIOTime(
                value: file.durationMs / 1000.0 * file.fps,
                rate: file.fps
            )
        )
        let mediaRef = OTIOMediaReference(targetURL: file.url.absoluteString)

        let videoClip = OTIOClip(
            name: file.url.lastPathComponent,
            mediaReference: mediaRef,
            sourceRange: sourceRange,
            mediaFileId: file.id,
            linkGroupId: linkId
        )
        let audioClip = OTIOClip(
            name: file.url.lastPathComponent,
            mediaReference: mediaRef,
            sourceRange: sourceRange,
            mediaFileId: file.id,
            linkGroupId: linkId
        )

        insertClipIntoTrack(&tl.tracks[videoTrackIndex], clip: videoClip, atTimeMs: timeMs)
        insertClipIntoTrack(&tl.tracks[audioTrackIndex], clip: audioClip, atTimeMs: timeMs)
        self.timeline = tl
    }

    /// Inserts a clip at the given time position in a track.
    private func insertClipIntoTrack(_ track: inout OTIOTrack, clip: OTIOClip, atTimeMs: Double) {
        // Find insertion point
        var accumulatedMs: Double = 0
        var insertIndex = track.children.count

        for (index, child) in track.children.enumerated() {
            let childDurationMs: Double
            switch child {
            case .clip(let c): childDurationMs = c.sourceRange.durationMs
            case .gap(let g): childDurationMs = g.sourceRange.durationMs
            }

            if atTimeMs <= accumulatedMs + childDurationMs / 2 {
                insertIndex = index
                break
            }
            accumulatedMs += childDurationMs
        }

        track.children.insert(.clip(clip), at: insertIndex)
    }

    // MARK: - Overwrite

    /// Overwrites content at a time position (replaces existing material).
    func overwriteMedia(
        file: MediaFile,
        atTimeMs timeMs: Double,
        videoTrackIndex: Int,
        audioTrackIndex: Int
    ) {
        guard var tl = timeline else { return }

        let linkId = UUID().uuidString
        let newDurationMs = file.durationMs
        let sourceRange = OTIOTimeRange(
            startTime: OTIOTime(value: 0, rate: file.fps),
            duration: OTIOTime(
                value: newDurationMs / 1000.0 * file.fps,
                rate: file.fps
            )
        )
        let mediaRef = OTIOMediaReference(targetURL: file.url.absoluteString)

        let videoClip = OTIOClip(
            name: file.url.lastPathComponent,
            mediaReference: mediaRef,
            sourceRange: sourceRange,
            mediaFileId: file.id,
            linkGroupId: linkId
        )
        let audioClip = OTIOClip(
            name: file.url.lastPathComponent,
            mediaReference: mediaRef,
            sourceRange: sourceRange,
            mediaFileId: file.id,
            linkGroupId: linkId
        )

        overwriteInTrack(&tl.tracks[videoTrackIndex], clip: videoClip, atTimeMs: timeMs, durationMs: newDurationMs)
        overwriteInTrack(&tl.tracks[audioTrackIndex], clip: audioClip, atTimeMs: timeMs, durationMs: newDurationMs)
        self.timeline = tl
    }

    private func overwriteInTrack(_ track: inout OTIOTrack, clip: OTIOClip, atTimeMs: Double, durationMs: Double) {
        // Simple overwrite: remove items in the range, then insert
        // For now, append at end as a simplified overwrite
        track.children.append(.clip(clip))
    }

    // MARK: - Delete

    /// Deletes clips by matching mediaFileId and offset within a specific track.
    func deleteClip(trackIndex: Int, clipIndex: Int) {
        guard var tl = timeline,
              trackIndex < tl.tracks.count,
              clipIndex < tl.tracks[trackIndex].children.count else { return }
        tl.tracks[trackIndex].children.remove(at: clipIndex)
        self.timeline = tl
    }

    /// Deletes clips and their linked counterparts.
    func deleteLinkedClips(trackIndex: Int, clipIndex: Int) {
        guard var tl = timeline,
              trackIndex < tl.tracks.count,
              clipIndex < tl.tracks[trackIndex].children.count else { return }

        // Get the linkGroupId
        let linkGroupId: String?
        if case .clip(let c) = tl.tracks[trackIndex].children[clipIndex] {
            linkGroupId = c.linkGroupId
        } else {
            linkGroupId = nil
        }

        // Remove from the primary track
        tl.tracks[trackIndex].children.remove(at: clipIndex)

        // Remove linked clips from other tracks
        if let lgId = linkGroupId {
            for ti in tl.tracks.indices where ti != trackIndex {
                tl.tracks[ti].children.removeAll { item in
                    if case .clip(let c) = item { return c.linkGroupId == lgId }
                    return false
                }
            }
        }

        self.timeline = tl
    }

    // MARK: - Trim

    /// Trims a clip's start time (trim in-point).
    func trimClipStart(trackIndex: Int, clipIndex: Int, newStartMs: Double) {
        guard var tl = timeline,
              trackIndex < tl.tracks.count,
              clipIndex < tl.tracks[trackIndex].children.count,
              case .clip(var clip) = tl.tracks[trackIndex].children[clipIndex] else { return }

        let rate = clip.sourceRange.startTime.rate
        let originalEndMs = clip.sourceRange.endMs
        let clampedStart = max(0, min(newStartMs, originalEndMs - 100))

        clip.sourceRange = OTIOTimeRange(
            startTime: OTIOTime.fromMs(clampedStart, rate: rate),
            duration: OTIOTime.fromMs(originalEndMs - clampedStart, rate: rate)
        )
        tl.tracks[trackIndex].children[clipIndex] = .clip(clip)

        // Trim linked clip too
        if let lgId = clip.linkGroupId {
            trimLinkedClips(in: &tl, linkGroupId: lgId, excludeTrack: trackIndex, newStartMs: clampedStart, newEndMs: originalEndMs)
        }

        self.timeline = tl
    }

    /// Trims a clip's end time (trim out-point).
    func trimClipEnd(trackIndex: Int, clipIndex: Int, newEndMs: Double) {
        guard var tl = timeline,
              trackIndex < tl.tracks.count,
              clipIndex < tl.tracks[trackIndex].children.count,
              case .clip(var clip) = tl.tracks[trackIndex].children[clipIndex] else { return }

        let rate = clip.sourceRange.startTime.rate
        let startMs = clip.sourceRange.startMs
        let clampedEnd = max(startMs + 100, newEndMs)

        clip.sourceRange = OTIOTimeRange(
            startTime: clip.sourceRange.startTime,
            duration: OTIOTime.fromMs(clampedEnd - startMs, rate: rate)
        )
        tl.tracks[trackIndex].children[clipIndex] = .clip(clip)

        // Trim linked clip too
        if let lgId = clip.linkGroupId {
            trimLinkedClips(in: &tl, linkGroupId: lgId, excludeTrack: trackIndex, newStartMs: startMs, newEndMs: clampedEnd)
        }

        self.timeline = tl
    }

    private func trimLinkedClips(in tl: inout OTIOTimeline, linkGroupId: String, excludeTrack: Int, newStartMs: Double, newEndMs: Double) {
        for ti in tl.tracks.indices where ti != excludeTrack {
            for ci in tl.tracks[ti].children.indices {
                if case .clip(var c) = tl.tracks[ti].children[ci], c.linkGroupId == linkGroupId {
                    let rate = c.sourceRange.startTime.rate
                    c.sourceRange = OTIOTimeRange(
                        startTime: OTIOTime.fromMs(newStartMs, rate: rate),
                        duration: OTIOTime.fromMs(newEndMs - newStartMs, rate: rate)
                    )
                    tl.tracks[ti].children[ci] = .clip(c)
                }
            }
        }
    }

    // MARK: - Link / Unlink

    /// Links clips together by assigning a shared linkGroupId.
    func linkClips(trackIndices: [Int], clipIndices: [Int]) {
        guard var tl = timeline else { return }
        let newLinkId = UUID().uuidString

        for (ti, ci) in zip(trackIndices, clipIndices) {
            guard ti < tl.tracks.count, ci < tl.tracks[ti].children.count else { continue }
            if case .clip(var c) = tl.tracks[ti].children[ci] {
                c.linkGroupId = newLinkId
                tl.tracks[ti].children[ci] = .clip(c)
            }
        }
        self.timeline = tl
    }

    /// Unlinks clips by clearing their linkGroupId.
    func unlinkClips(trackIndices: [Int], clipIndices: [Int]) {
        guard var tl = timeline else { return }

        for (ti, ci) in zip(trackIndices, clipIndices) {
            guard ti < tl.tracks.count, ci < tl.tracks[ti].children.count else { continue }
            if case .clip(var c) = tl.tracks[ti].children[ci] {
                c.linkGroupId = nil
                tl.tracks[ti].children[ci] = .clip(c)
            }
        }
        self.timeline = tl
    }

    // MARK: - Copy / Paste

    /// Copies clips to the internal clipboard.
    func copyClips(selections: [(trackIndex: Int, clipIndex: Int)]) {
        guard let tl = timeline else { return }
        clipboard = []

        for (ti, ci) in selections {
            guard ti < tl.tracks.count, ci < tl.tracks[ti].children.count else { continue }
            if case .clip(let c) = tl.tracks[ti].children[ci] {
                clipboard.append(ClipboardEntry(clip: c, trackKind: tl.tracks[ti].kind))
            }
        }
    }

    /// Pastes clips from the clipboard at the given time position.
    func pasteClips(atTimeMs timeMs: Double) {
        guard var tl = timeline, !clipboard.isEmpty else { return }

        for entry in clipboard {
            var clip = entry.clip
            clip.linkGroupId = UUID().uuidString // New link IDs for pasted clips

            if let trackIndex = tl.tracks.firstIndex(where: { $0.kind == entry.trackKind }) {
                insertClipIntoTrack(&tl.tracks[trackIndex], clip: clip, atTimeMs: timeMs)
            }
        }

        self.timeline = tl
    }

    // MARK: - Move

    /// Moves a clip from one position to another (within or between tracks).
    func moveClip(fromTrack: Int, fromIndex: Int, toTrack: Int, toTimeMs: Double) {
        guard var tl = timeline,
              fromTrack < tl.tracks.count,
              fromIndex < tl.tracks[fromTrack].children.count else { return }

        let item = tl.tracks[fromTrack].children.remove(at: fromIndex)
        if case .clip(let clip) = item {
            if toTrack < tl.tracks.count {
                insertClipIntoTrack(&tl.tracks[toTrack], clip: clip, atTimeMs: toTimeMs)
            }
        }

        self.timeline = tl
    }

    // MARK: - Track Management

    /// Adds a new empty track.
    func addTrack(kind: OTIOTrackKind) {
        guard var tl = timeline else { return }
        let existingCount = tl.tracks.filter { $0.kind == kind }.count
        let name = kind == .video ? "V\(existingCount + 1)" : "A\(existingCount + 1)"
        tl.tracks.append(OTIOTrack(name: name, kind: kind, children: []))
        self.timeline = tl
    }

    /// Removes an empty track.
    func removeTrack(index: Int) {
        guard var tl = timeline,
              index < tl.tracks.count,
              tl.tracks[index].children.isEmpty else { return }
        tl.tracks.remove(at: index)
        self.timeline = tl
    }

    // MARK: - Edit Decisions (transcript-based editing)

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

            for range in decision.keepRanges.sorted(by: { $0.startMs < $1.startMs }) {
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
                    mediaFileId: firstClip.mediaFileId,
                    linkGroupId: firstClip.linkGroupId
                )
                newChildren.append(.clip(clip))
            }

            tl.tracks[trackIndex].children = newChildren
        }

        self.timeline = tl
        return tl
    }

    // MARK: - Access

    func currentTimeline() -> OTIOTimeline? { timeline }

    func setTimeline(_ tl: OTIOTimeline) {
        self.timeline = tl
    }

    func reset() {
        timeline = nil
        clipboard = []
    }

    // MARK: - OTIO Serialization (real OpenTimelineIO)

    /// Exports the timeline as a real .otio JSON string using OpenTimelineIO.
    func exportOTIO() throws -> String {
        guard let tl = timeline else {
            throw AbscidoError.exportFailed(reason: "No timeline to export")
        }

        // Convert bridge model → real OTIO Timeline
        let otioTimeline = tl.toOTIOTimeline()

        // Serialize to .otio JSON
        let jsonString = try otioTimeline.toJSON()
        return jsonString
    }

    /// Exports the timeline as our internal bridge JSON format.
    func exportBridgeJSON() throws -> String {
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

    /// Imports a timeline from a .otio JSON file using the real OpenTimelineIO parser.
    func importOTIO(from url: URL) throws {
        let otioTimeline = try OpenTimelineIO.Timeline.fromJSON(url: url) as! OpenTimelineIO.Timeline
        let bridgeTimeline = OTIOTimeline.from(otioTimeline)
        self.timeline = bridgeTimeline
    }

    /// Saves the current timeline to a .otio file.
    func saveOTIO(to url: URL) throws {
        let json = try exportOTIO()
        try json.write(to: url, atomically: true, encoding: .utf8)
    }
}


