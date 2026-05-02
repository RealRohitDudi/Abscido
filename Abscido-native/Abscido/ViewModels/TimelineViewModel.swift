import Foundation

/// Maps OTIO timeline state to UI-friendly multi-track models.
/// Manages clip selection, clipboard, and all NLE operations.
@MainActor
@Observable
final class TimelineViewModel {
    // MARK: - Track & Clip Models

    struct TrackModel: Identifiable, Equatable {
        let id: String
        let name: String
        let kind: OTIOTrackKind
        let trackIndex: Int
        var clips: [TimelineClipModel]
    }

    struct TimelineClipModel: Identifiable, Equatable {
        let id: String
        let name: String
        let startMs: Double
        let durationMs: Double
        let sourceStartMs: Double
        let sourceDurationMs: Double
        let mediaFileId: Int64
        let trackIndex: Int
        let clipIndex: Int
        let color: ClipColor
        let linkGroupId: String?
        var isSelected: Bool

        enum ClipColor: Sendable {
            case video, audio, gap
        }
    }

    // MARK: - State

    var tracks: [TrackModel] = []
    var totalDurationMs: Double = 0
    var playheadMs: Double = 0
    var pixelsPerSecond: Double = 100.0

    /// Selected clip identifiers.
    var selectedClipIds: Set<String> = []

    /// Individual track heights (keyed by trackIndex). Default is 52.
    var trackHeights: [Int: CGFloat] = [:]

    /// Waveform amplitude data keyed by media file ID.
    var waveformData: [Int64: [Float]] = [:]

    /// Monotonically increasing token used by AppKit timeline renderer to know
    /// when async waveform generation finished (so it can rebuild layers).
    var waveformRevision: Int = 0

    /// Callback to notify parent when timeline changes require composition rebuild.
    var onTimelineChanged: (() -> Void)?

    let otioEngine = OTIOEngine()
    private let waveformGenerator = WaveformGenerator()

    // MARK: - Flat accessor (for backward compat)

    var clips: [TimelineClipModel] {
        tracks.flatMap(\.clips)
    }

    // MARK: - Build

    func buildInitial(mediaFiles: [MediaFile]) {
        Task {
            let timeline = await otioEngine.buildTimeline(from: mediaFiles)
            await refreshFromEngine()
            await generateWaveforms(for: mediaFiles)
        }
    }

    func rebuild(editDecisions: [EditDecision], mediaFiles: [MediaFile]) {
        Task {
            _ = await otioEngine.applyEditDecisions(editDecisions, mediaFiles: mediaFiles)
            await refreshFromEngine()
        }
    }

    // MARK: - Insert / Overwrite

    func insertMedia(_ file: MediaFile, atTimeMs timeMs: Double, allMediaFiles: [MediaFile]) {
        Task {
            if await otioEngine.currentTimeline() == nil {
                _ = await otioEngine.buildTimeline(from: allMediaFiles)
            }

            guard let tl = await otioEngine.currentTimeline() else { return }

            let vIndex = tl.tracks.firstIndex(where: { $0.kind == .video }) ?? 0
            let aIndex = tl.tracks.firstIndex(where: { $0.kind == .audio }) ?? 1

            insertMediaOnTracks(file, atTimeMs: timeMs, allMediaFiles: allMediaFiles, videoTrackIndex: vIndex, audioTrackIndex: aIndex)
        }
    }

    func insertMediaOnTracks(
        _ file: MediaFile,
        atTimeMs timeMs: Double,
        allMediaFiles: [MediaFile],
        videoTrackIndex: Int,
        audioTrackIndex: Int
    ) {
        Task {
            // Ensure timeline exists
            if await otioEngine.currentTimeline() == nil {
                _ = await otioEngine.buildTimeline(from: allMediaFiles)
            }

            await otioEngine.insertMedia(
                file: file,
                atTimeMs: timeMs,
                videoTrackIndex: videoTrackIndex,
                audioTrackIndex: audioTrackIndex
            )
            await refreshFromEngine()
            await generateWaveforms(for: [file])
        }
    }

    func overwriteMedia(_ file: MediaFile, atTimeMs timeMs: Double, allMediaFiles: [MediaFile]) {
        Task {
            if await otioEngine.currentTimeline() == nil {
                _ = await otioEngine.buildTimeline(from: allMediaFiles)
            }

            guard let tl = await otioEngine.currentTimeline() else { return }

            let vIndex = tl.tracks.firstIndex(where: { $0.kind == .video }) ?? 0
            let aIndex = tl.tracks.firstIndex(where: { $0.kind == .audio }) ?? 1

            overwriteMediaOnTracks(file, atTimeMs: timeMs, allMediaFiles: allMediaFiles, videoTrackIndex: vIndex, audioTrackIndex: aIndex)
        }
    }

    func overwriteMediaOnTracks(
        _ file: MediaFile,
        atTimeMs timeMs: Double,
        allMediaFiles: [MediaFile],
        videoTrackIndex: Int,
        audioTrackIndex: Int
    ) {
        Task {
            if await otioEngine.currentTimeline() == nil {
                _ = await otioEngine.buildTimeline(from: allMediaFiles)
            }

            await otioEngine.overwriteMedia(
                file: file,
                atTimeMs: timeMs,
                videoTrackIndex: videoTrackIndex,
                audioTrackIndex: audioTrackIndex
            )
            await refreshFromEngine()
            await generateWaveforms(for: [file])
        }
    }

    // MARK: - Selection

    /// Expand any clip IDs to include all timeline clips sharing their `linkGroupId`.
    private func expandedSelectionIncludingLinkedPartners(_ ids: Set<String>) -> Set<String> {
        var result = ids
        for clip in clips {
            guard ids.contains(clip.id), let lg = clip.linkGroupId else { continue }
            for c in clips where c.linkGroupId == lg {
                result.insert(c.id)
            }
        }
        return result
    }

    /// Clip IDs forming one linked partition (whole link group when linked, otherwise just that clip).
    private func idsToRemoveWhenDeselecting(clipId: String) -> Set<String> {
        guard let clip = clips.first(where: { $0.id == clipId }) else { return [clipId] }
        guard let lg = clip.linkGroupId else { return [clipId] }
        return Set(clips.filter { $0.linkGroupId == lg }.map(\.id))
    }

    func selectClip(_ clipId: String, exclusive: Bool = true) {
        if exclusive {
            selectedClipIds = expandedSelectionIncludingLinkedPartners([clipId])
        } else {
            selectedClipIds = expandedSelectionIncludingLinkedPartners(selectedClipIds.union([clipId]))
        }
        updateSelectionState()
    }

    func toggleClipSelection(_ clipId: String) {
        if selectedClipIds.contains(clipId) {
            selectedClipIds.subtract(idsToRemoveWhenDeselecting(clipId: clipId))
        } else {
            selectedClipIds = expandedSelectionIncludingLinkedPartners(selectedClipIds.union([clipId]))
        }
        updateSelectionState()
    }

    func clearSelection() {
        selectedClipIds.removeAll()
        updateSelectionState()
    }

    func setSelection(_ ids: Set<String>) {
        selectedClipIds = expandedSelectionIncludingLinkedPartners(ids)
        updateSelectionState()
    }

    // MARK: - Link / Unlink commands (selection rules)

    /// Link is available only with ≥2 clips that are **not** already one shared linked group.
    var canLinkSelectedClips: Bool {
        let selected = selectedClips()
        // One clip (or one logical ID after expansion failure) → no link/unlink ops.
        guard selected.count >= 2, selectedClipIds.count >= 2 else { return false }
        let firstGroup = selected[0].linkGroupId
        let allShareSameLinkedGroup =
            selected.allSatisfy { $0.linkGroupId == firstGroup } && firstGroup != nil
        return !allShareSameLinkedGroup
    }

    /// Unlink is available only with ≥2 clips that **all** share the same non-nil `linkGroupId`.
    var canUnlinkSelectedClips: Bool {
        let selected = selectedClips()
        guard selected.count >= 2, selectedClipIds.count >= 2 else { return false }
        guard let g = selected[0].linkGroupId else { return false }
        return selected.allSatisfy { $0.linkGroupId == g }
    }

    private func updateSelectionState() {
        for ti in tracks.indices {
            for ci in tracks[ti].clips.indices {
                tracks[ti].clips[ci].isSelected = selectedClipIds.contains(tracks[ti].clips[ci].id)
            }
        }
    }

    // MARK: - Delete

    func deleteSelected() {
        Task {
            let selected = selectedClips()
            guard !selected.isEmpty else { return }

            // One atomic pass avoids stale `(trackIndex, clipIndex)` when both halves of a linked
            // clip pair are selected: calling `deleteLinkedClips` twice used to remove index 0 twice
            // on the video track — deleting the wrong (next) clip after the linked pair vanished.
            let removeLinkGroups = Set(selected.compactMap(\.linkGroupId))
            let explicitSlots = Set(
                selected
                    .filter { $0.linkGroupId == nil }
                    .map { "\($0.trackIndex)_\($0.clipIndex)" }
            )

            await otioEngine.applyDeletion(
                removeLinkGroupIds: removeLinkGroups,
                explicitRemoveSlotKeys: explicitSlots
            )

            selectedClipIds.removeAll()
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    // MARK: - Copy / Paste

    func copySelected() {
        Task {
            let selected = selectedClips()
            let selections = selected.map { (trackIndex: $0.trackIndex, clipIndex: $0.clipIndex) }
            await otioEngine.copyClips(selections: selections)
        }
    }

    func cutSelected() {
        copySelected()
        deleteSelected()
    }

    func pasteAtPlayhead() {
        Task {
            await otioEngine.pasteClips(atTimeMs: playheadMs)
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    // MARK: - Trim

    func trimClipStart(trackIndex: Int, clipIndex: Int, newStartMs: Double) {
        Task {
            await otioEngine.trimClipStart(trackIndex: trackIndex, clipIndex: clipIndex, newStartMs: newStartMs)
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    func trimClipEnd(trackIndex: Int, clipIndex: Int, newEndMs: Double) {
        Task {
            await otioEngine.trimClipEnd(trackIndex: trackIndex, clipIndex: clipIndex, newEndMs: newEndMs)
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    // MARK: - Link / Unlink

    func linkSelected() {
        Task {
            guard canLinkSelectedClips else { return }
            let selected = selectedClips()
            let trackIndices = selected.map(\.trackIndex)
            let clipIndices = selected.map(\.clipIndex)
            await otioEngine.linkClips(trackIndices: trackIndices, clipIndices: clipIndices)
            await refreshFromEngine()
        }
    }

    func unlinkSelected() {
        Task {
            guard canUnlinkSelectedClips else { return }
            let selected = selectedClips()
            let trackIndices = selected.map(\.trackIndex)
            let clipIndices = selected.map(\.clipIndex)
            await otioEngine.unlinkClips(trackIndices: trackIndices, clipIndices: clipIndices)
            await refreshFromEngine()
        }
    }

    // MARK: - Track Management

    func addTrack(kind: OTIOTrackKind) {
        Task {
            await otioEngine.addTrack(kind: kind)
            await refreshFromEngine()
        }
    }

    // MARK: - Move

    func moveClip(fromTrack: Int, fromIndex: Int, toTrack: Int, toTimeMs: Double) {
        Task {
            await otioEngine.moveClip(fromTrack: fromTrack, fromIndex: fromIndex, toTrack: toTrack, toTimeMs: toTimeMs)
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        pixelsPerSecond = min(500, pixelsPerSecond * 1.3)
    }

    func zoomOut() {
        pixelsPerSecond = max(10, pixelsPerSecond / 1.3)
    }

    func setZoom(_ pps: Double) {
        pixelsPerSecond = max(10, min(500, pps))
    }

    // MARK: - Playhead

    func updatePlayhead(ms: Double) {
        playheadMs = ms
    }

    // MARK: - Waveform

    func waveformSamples(for clip: TimelineClipModel) -> [Float]? {
        waveformData[clip.mediaFileId]
    }

    private func generateWaveforms(for mediaFiles: [MediaFile]) async {
        for file in mediaFiles {
            let samples = await waveformGenerator.generateWaveform(for: file)
            waveformData[file.id] = samples
            waveformRevision &+= 1
        }
    }

    // MARK: - Helpers

    func selectedClips() -> [TimelineClipModel] {
        clips.filter { selectedClipIds.contains($0.id) }
    }

    /// Converts x-coordinate to time in milliseconds.
    func xToMs(_ x: CGFloat) -> Double {
        max(0, Double(x) / pixelsPerSecond * 1000.0)
    }

    /// Converts time in milliseconds to x-coordinate.
    func msToX(_ ms: Double) -> CGFloat {
        CGFloat(ms / 1000.0 * pixelsPerSecond)
    }

    /// Finds the clip at a given track index and x-coordinate.
    func clipAt(trackIndex: Int, x: CGFloat) -> TimelineClipModel? {
        guard trackIndex < tracks.count else { return nil }
        let timeMs = xToMs(x)
        return tracks[trackIndex].clips.first { clip in
            timeMs >= clip.startMs && timeMs < clip.startMs + clip.durationMs
        }
    }

    /// Exports the OTIO timeline as JSON.
    func exportOTIOJSON() async throws -> String {
        try await otioEngine.exportOTIO()
    }

    // MARK: - Refresh

    private func refreshFromEngine() async {
        guard let tl = await otioEngine.currentTimeline() else { return }

        var newTracks: [TrackModel] = []
        var maxDuration: Double = 0

        for (trackIndex, track) in tl.tracks.enumerated() {
            var trackClips: [TimelineClipModel] = []
            var offset: Double = 0

            for (clipIndex, child) in track.children.enumerated() {
                switch child {
                case .clip(let clip):
                    let durationMs = clip.sourceRange.durationMs
                    let clipId = "\(trackIndex)_\(clipIndex)_\(clip.mediaFileId)"
                    trackClips.append(TimelineClipModel(
                        id: clipId,
                        name: clip.name,
                        startMs: offset,
                        durationMs: durationMs,
                        sourceStartMs: clip.sourceRange.startMs,
                        sourceDurationMs: durationMs,
                        mediaFileId: clip.mediaFileId,
                        trackIndex: trackIndex,
                        clipIndex: clipIndex,
                        color: track.kind == .video ? .video : .audio,
                        linkGroupId: clip.linkGroupId,
                        isSelected: selectedClipIds.contains(clipId)
                    ))
                    offset += durationMs

                case .gap(let gap):
                    let durationMs = gap.sourceRange.durationMs
                    let gapId = "gap_\(trackIndex)_\(offset)"
                    trackClips.append(TimelineClipModel(
                        id: gapId,
                        name: "Gap",
                        startMs: offset,
                        durationMs: durationMs,
                        sourceStartMs: 0,
                        sourceDurationMs: durationMs,
                        mediaFileId: 0,
                        trackIndex: trackIndex,
                        clipIndex: clipIndex,
                        color: .gap,
                        linkGroupId: nil,
                        isSelected: false
                    ))
                    offset += durationMs
                }
            }

            maxDuration = max(maxDuration, offset)
            newTracks.append(TrackModel(
                id: "\(track.kind.rawValue)_\(trackIndex)",
                name: track.name,
                kind: track.kind,
                trackIndex: trackIndex,
                clips: trackClips
            ))
        }

        self.tracks = newTracks
        self.totalDurationMs = maxDuration
    }
}
