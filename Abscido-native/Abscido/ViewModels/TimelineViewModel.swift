import Foundation
import OpenTimelineIO

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
    /// Mirrors the playback edit line (kept in sync from `TimelineCoordinator` + `PlayerViewModel`).
    /// Used for razor, ripple trim, paste-at-playhead, etc.
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

    /// Bumps on every `refreshFromEngine` so the AppKit timeline can rebuild even when
    /// `totalDurationMs` is unchanged (e.g. deleting all audio while video still sets max duration).
    var timelineStructureRevision: Int = 0

    /// Callback to notify parent when timeline changes require composition rebuild.
    var onTimelineChanged: (() -> Void)?
    /// Callback for transcript sync after destructive timeline edits. The dictionary contains
    /// currently kept source ranges keyed by media file id; the set limits work to changed media.
    var onSourceRangesChanged: (([Int64: [TimeRangeMs]], Set<Int64>) -> Void)?

    let otioEngine = OTIOEngine()
    private let waveformGenerator = WaveformGenerator()

    // MARK: - Flat accessor (for backward compat)

    var clips: [TimelineClipModel] {
        tracks.flatMap(\.clips)
    }

    /// Current visible source ranges per media file, independent of timeline/program placement.
    /// Video/audio linked partners may contribute duplicate ranges; consumers should treat these
    /// as a union of kept source intervals.
    func keptSourceRangesByMediaFile() -> [Int64: [TimeRangeMs]] {
        var rangesByMediaFile: [Int64: [TimeRangeMs]] = [:]
        for clip in clips where clip.mediaFileId != 0 && clip.color != .gap && clip.sourceDurationMs > 0 {
            rangesByMediaFile[clip.mediaFileId, default: []].append(
                TimeRangeMs(
                    startMs: clip.sourceStartMs,
                    endMs: clip.sourceStartMs + clip.sourceDurationMs
                )
            )
        }
        return rangesByMediaFile.mapValues { ranges in
            ranges.sorted { $0.startMs < $1.startMs }
        }
    }

    private func sourceRangeChangedMediaIds(
        from previous: [Int64: [TimeRangeMs]],
        to current: [Int64: [TimeRangeMs]]
    ) -> Set<Int64> {
        let mediaIds = Set(previous.keys).union(current.keys)
        return Set(mediaIds.filter { previous[$0, default: []] != current[$0, default: []] })
    }

    private func notifySourceRangesChanged(from previous: [Int64: [TimeRangeMs]]) {
        let current = keptSourceRangesByMediaFile()
        let changedMediaIds = sourceRangeChangedMediaIds(from: previous, to: current)
        guard !changedMediaIds.isEmpty else { return }
        onSourceRangesChanged?(current, changedMediaIds)
    }

    /// Converts an edit-program time into the source time for a concrete media file.
    /// Transcript words are stored in source-clip time, while timeline playback reports program
    /// time. Returning nil means the playhead is on a gap or on some other clip.
    func sourceTimeMs(forProgramTimeMs programMs: Double, mediaFileId: Int64) -> Double? {
        guard mediaFileId != 0 else { return nil }
        let epsilon = 0.5
        guard let clip = clips.first(where: { clip in
            clip.mediaFileId == mediaFileId &&
            clip.color != .gap &&
            programMs >= clip.startMs - epsilon &&
            programMs < clip.startMs + clip.durationMs + epsilon
        }) else {
            return nil
        }

        let offsetIntoTimelineClip = max(0, programMs - clip.startMs)
        return clip.sourceStartMs + offsetIntoTimelineClip
    }

    /// Converts a source transcript timestamp back to program time for word-click seeking.
    /// If the source range appears multiple times, prefer the earliest visible occurrence.
    func programTimeMs(forSourceTimeMs sourceMs: Double, mediaFileId: Int64) -> Double? {
        guard mediaFileId != 0 else { return nil }
        let epsilon = 0.5
        return clips
            .filter { $0.mediaFileId == mediaFileId && $0.color != .gap }
            .sorted { $0.startMs < $1.startMs }
            .first { clip in
                sourceMs >= clip.sourceStartMs - epsilon &&
                sourceMs < clip.sourceStartMs + clip.sourceDurationMs + epsilon
            }
            .map { clip in
                clip.startMs + max(0, sourceMs - clip.sourceStartMs)
            }
    }

    // MARK: - Build / Hydrate / Persist

    /// Loads OTIO from `Project.otioJSON` or creates an empty V1/A1 shell. Does **not** mirror media-bin selection.
    func hydrateFromProject(otioJSON: String?, mediaFiles: [MediaFile]) async {
        waveformData = [:]
        waveformRevision &+= 1
        selectedClipIds = []
        await otioEngine.reset()
        if let json = otioJSON, !json.isEmpty {
            do {
                try await otioEngine.importBridgeJSON(json)
                let loadedAfterImport = await otioEngine.currentTimeline()
                if loadedAfterImport == nil || loadedAfterImport?.tracks.isEmpty != false {
                    await otioEngine.reset()
                    _ = await otioEngine.ensureEmptyTimeline()
                }
            } catch {
                _ = await otioEngine.ensureEmptyTimeline()
            }
        } else {
            _ = await otioEngine.ensureEmptyTimeline()
        }
        await refreshFromEngine()
        let touched = Set(clips.map(\.mediaFileId)).filter { $0 != 0 }
        let files = mediaFiles.filter { touched.contains($0.id) }
        if !files.isEmpty {
            await generateWaveforms(for: files)
        }
    }

    /// Encodes the current timeline for `projects.otio_json`.
    func exportBridgeJSONForPersistence() async throws -> String {
        try await otioEngine.exportBridgeJSON()
    }

    /// Canonical OpenTimelineIO graph for interchange export (``.otio``, FCP XML derived writers).
    func openTimelineForInterchangeExport(sequenceDisplayName: String) async throws -> Timeline {
        guard let bridge = await otioEngine.currentTimeline() else {
            throw AbscidoError.exportFailed(reason: "No timeline loaded.")
        }
        let tl = try bridge.toOTIOTimeline()
        tl.name = sequenceDisplayName
        // Timeline() defaults global_start to 24 fps; align with actual clip rate for interchange.
        if let stack = tl.tracks {
            outer: for composable in stack.children {
                guard let track = composable as? Track else { continue }
                for i in 0..<track.children.count {
                    if let clip = track.children[i] as? Clip,
                       let sr = clip.sourceRange,
                       sr.duration.rate > 0 {
                        tl.globalStartTime = RationalTime(value: 0, rate: sr.duration.rate)
                        break outer
                    }
                }
            }
        }
        return tl
    }

    func rebuild(editDecisions: [EditDecision], mediaFiles: [MediaFile]) {
        Task {
            _ = await otioEngine.applyEditDecisions(editDecisions, mediaFiles: mediaFiles)
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    // MARK: - Insert / Overwrite

    func insertMedia(_ file: MediaFile, atTimeMs timeMs: Double, allMediaFiles: [MediaFile]) {
        Task {
            if await otioEngine.currentTimeline() == nil {
                _ = await otioEngine.ensureEmptyTimeline()
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
                _ = await otioEngine.ensureEmptyTimeline()
            }

            await otioEngine.insertMedia(
                file: file,
                atTimeMs: timeMs,
                videoTrackIndex: videoTrackIndex,
                audioTrackIndex: audioTrackIndex
            )
            await refreshFromEngine()
            await generateWaveforms(for: [file])
            onTimelineChanged?()
        }
    }

    func overwriteMedia(_ file: MediaFile, atTimeMs timeMs: Double, allMediaFiles: [MediaFile]) {
        Task {
            if await otioEngine.currentTimeline() == nil {
                _ = await otioEngine.ensureEmptyTimeline()
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
        let previousSourceRanges = keptSourceRangesByMediaFile()
        Task {
            if await otioEngine.currentTimeline() == nil {
                _ = await otioEngine.ensureEmptyTimeline()
            }

            await otioEngine.overwriteMedia(
                file: file,
                atTimeMs: timeMs,
                videoTrackIndex: videoTrackIndex,
                audioTrackIndex: audioTrackIndex
            )
            await refreshFromEngine()
            notifySourceRangesChanged(from: previousSourceRanges)
            await generateWaveforms(for: [file])
            onTimelineChanged?()
        }
    }

    // MARK: - Selection

    /// Expand any clip IDs to include all timeline clips sharing their `linkGroupId`.
    ///
    /// A linked group represents *one logical clip occupying the same timeline position across
    /// different tracks* (e.g. V1+A1 from a single import). Two clips on the SAME track at
    /// different positions can never be linked partners — so the expansion only crosses to OTHER
    /// tracks. Without this guard, a leaked duplicate `linkGroupId` (e.g. from a split clip) would
    /// pull a same-track sibling into the selection and cause "delete the next clip too" bugs.
    private func expandedSelectionIncludingLinkedPartners(_ ids: Set<String>) -> Set<String> {
        var result = ids
        for clip in clips {
            guard ids.contains(clip.id), let lg = clip.linkGroupId else { continue }
            for c in clips where c.linkGroupId == lg && c.trackIndex != clip.trackIndex {
                result.insert(c.id)
            }
        }
        return result
    }

    /// Clip IDs forming one linked partition (whole link group when linked, otherwise just that clip).
    /// Same-track partners are excluded for the same reason as `expandedSelectionIncludingLinkedPartners`.
    private func idsToRemoveWhenDeselecting(clipId: String) -> Set<String> {
        guard let clip = clips.first(where: { $0.id == clipId }) else { return [clipId] }
        guard let lg = clip.linkGroupId else { return [clipId] }
        let partners = clips.filter { $0.linkGroupId == lg && $0.trackIndex != clip.trackIndex }.map(\.id)
        return Set([clipId] + partners)
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

    /// Slot keys for `OTIOEngine.applyLiftRippleRemoval` — selected **media clips** plus **cross-track**
    /// linked partners only (lift mode). Never adds same-track neighbors, so a leaked duplicate
    /// `linkGroupId` on one track cannot wipe the whole row.
    private func explicitLiftSlots(forClips deletableClips: [TimelineClipModel]) -> Set<String> {
        var slots = Set(deletableClips.map { "\($0.trackIndex)_\($0.clipIndex)" })
        for clip in deletableClips {
            guard let lg = clip.linkGroupId else { continue }
            for other in clips where other.linkGroupId == lg && other.trackIndex != clip.trackIndex {
                slots.insert("\(other.trackIndex)_\(other.clipIndex)")
            }
        }
        return slots
    }

    // MARK: - Delete

    func deleteSelected() {
        // Resolve the selection → slot keys synchronously on the main actor, then clear the
        // selection BEFORE kicking off the async engine call.
        //
        // The Delete shortcut is dispatched twice on every press: once by the SwiftUI
        // `CommandGroup` `.keyboardShortcut(.delete)` in `AbscidoApp` and once by
        // `ShortcutEventHandler`'s `NSEvent.addLocalMonitorForEvents`. Without this synchronous
        // clear, both dispatches start a `Task`, both see the same `selectedClipIds`, both
        // compute the same slot key (e.g. `"1_0"` for the first audio clip), and both call
        // `applyDeletion`. The second pass runs after the first has already shrunk the track
        // and ends up deleting whatever clip slid into slot index 0 — exactly the "deleting
        // one audio clip also kills the next one" symptom.
        //
        // Capturing + clearing inside the @MainActor synchronous prologue means the duplicate
        // dispatch lands on an empty `selectedClipIds`, exits via the `isEmpty` guard, and only
        // one engine deletion runs.
        let selected = selectedClips()
        guard !selected.isEmpty else { return }

        let clipItems = selected.filter { $0.color != .gap }
        let gapItems = selected.filter { $0.color == .gap }

        guard !clipItems.isEmpty || !gapItems.isEmpty else {
            selectedClipIds.removeAll()
            updateSelectionState()
            return
        }

        let liftSlots: Set<String> = clipItems.isEmpty ? Set() : explicitLiftSlots(forClips: clipItems)
        let rippleSlots = Set(gapItems.map { "\($0.trackIndex)_\($0.clipIndex)" })

        selectedClipIds.removeAll()
        updateSelectionState()

        let previousSourceRanges = keptSourceRangesByMediaFile()
        Task {
            await otioEngine.applyLiftRippleRemoval(liftClipSlotKeys: liftSlots, rippleRemoveSlotKeys: rippleSlots)
            await refreshFromEngine()
            notifySourceRangesChanged(from: previousSourceRanges)
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
        let previousSourceRanges = keptSourceRangesByMediaFile()
        Task {
            await otioEngine.trimClipStart(trackIndex: trackIndex, clipIndex: clipIndex, newStartMs: newStartMs)
            await refreshFromEngine()
            notifySourceRangesChanged(from: previousSourceRanges)
            onTimelineChanged?()
        }
    }

    func trimClipEnd(trackIndex: Int, clipIndex: Int, newEndMs: Double) {
        let previousSourceRanges = keptSourceRangesByMediaFile()
        Task {
            await otioEngine.trimClipEnd(trackIndex: trackIndex, clipIndex: clipIndex, newEndMs: newEndMs)
            await refreshFromEngine()
            notifySourceRangesChanged(from: previousSourceRanges)
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
            onTimelineChanged?()
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
            onTimelineChanged?()
        }
    }

    // MARK: - Track Management

    func addTrack(kind: OTIOTrackKind) {
        Task {
            await otioEngine.addTrack(kind: kind)
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    // MARK: - Move

    func moveClip(fromTrack: Int, fromIndex: Int, toTrack: Int, toTimeMs: Double, rippleInsert: Bool = false) {
        Task {
            await otioEngine.moveClip(
                fromTrack: fromTrack,
                fromIndex: fromIndex,
                toTrack: toTrack,
                toTimeMs: toTimeMs,
                rippleInsert: rippleInsert
            )
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    /// Razor (W): split every track at the current edit/playback time (`playheadMs`).
    func razorAtPlayhead() {
        let ms = playheadMs
        Task {
            await otioEngine.razorSplit(atTimelineMs: ms)
            await refreshFromEngine()
            onTimelineChanged?()
        }
    }

    func rippleTrimStartToPlayhead() {
        let ms = playheadMs
        let previousSourceRanges = keptSourceRangesByMediaFile()
        Task { @MainActor in
            let clipHeadProgramMs = await otioEngine.rippleTrimStartToPlayhead(playheadMs: ms)
            await refreshFromEngine()
            notifySourceRangesChanged(from: previousSourceRanges)
            // Park the CTI at the **clip head** (`segmentStart`): that is the timeline position of the first
            // frame left after Q — staying at raw program time `ms` would leave the needle mid-clip relative
            // to the new trim (looks like trimming the wrong edge). E already leaves the needle at clip tail.
            if let h = clipHeadProgramMs {
                updatePlayhead(ms: h)
            }
            onTimelineChanged?()
        }
    }

    func rippleTrimEndToPlayhead() {
        let ms = playheadMs
        let previousSourceRanges = keptSourceRangesByMediaFile()
        Task {
            await otioEngine.rippleTrimEndToPlayhead(playheadMs: ms)
            await refreshFromEngine()
            notifySourceRangesChanged(from: previousSourceRanges)
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
                        isSelected: selectedClipIds.contains(gapId)
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
        timelineStructureRevision &+= 1
    }
}
