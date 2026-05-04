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

    /// Places linked V+A at `atTimeMs` on the timeline (splits/overlaps gaps and clips, pads with gap
    /// if the drop is past track end). Does not ripple-shift the rest of the track.
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

        // Place at exact timeline time (split gaps/clips, pad with gap after track end) — no ripple insert.
        // One shared remap so V's right-half and A's right-half of any split clip wind up linked
        // to each other (same fresh id) instead of to their LEFT halves on the same track.
        var splitLinkRemap: [String: String] = [:]
        overwriteInTrack(&tl.tracks[videoTrackIndex], clip: videoClip, atTimeMs: timeMs, durationMs: sourceRange.durationMs, splitLinkRemap: &splitLinkRemap)
        overwriteInTrack(&tl.tracks[audioTrackIndex], clip: audioClip, atTimeMs: timeMs, durationMs: sourceRange.durationMs, splitLinkRemap: &splitLinkRemap)
        self.timeline = tl
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

        var splitLinkRemap: [String: String] = [:]
        overwriteInTrack(&tl.tracks[videoTrackIndex], clip: videoClip, atTimeMs: timeMs, durationMs: newDurationMs, splitLinkRemap: &splitLinkRemap)
        overwriteInTrack(&tl.tracks[audioTrackIndex], clip: audioClip, atTimeMs: timeMs, durationMs: newDurationMs, splitLinkRemap: &splitLinkRemap)
        self.timeline = tl
    }

    private func itemDurationMs(_ item: OTIOItem) -> Double {
        switch item {
        case .clip(let c): return c.sourceRange.durationMs
        case .gap(let g): return g.sourceRange.durationMs
        }
    }

    private func gapItem(rate: Double, durationMs: Double) -> OTIOItem {
        .gap(OTIOGap(sourceRange: OTIOTimeRange(
            startTime: OTIOTime(value: 0, rate: rate),
            duration: OTIOTime.fromMs(durationMs, rate: rate)
        )))
    }

    /// Timeline [start,end) where `clipIndex` appears on one track prior to edits.
    private func timelineBoundsOfClip(track ti: Int, clipIndex ci: Int, in tl: OTIOTimeline) -> (start: Double, duration: Double)? {
        guard ti < tl.tracks.count, ci < tl.tracks[ti].children.count else { return nil }
        var cursor = 0.0
        for (j, child) in tl.tracks[ti].children.enumerated() {
            let d = itemDurationMs(child)
            if j == ci { return (cursor, d) }
            cursor += d
        }
        return nil
    }

    /// After linking, all clips in the group share the same timeline start/duration (reference = first selected clip).
    private func syncLinkedGroupTimelinePositions(
        linkGroupId: String,
        referenceStartMs: Double,
        referenceDurationMs: Double,
        timeline: inout OTIOTimeline
    ) {
        var extracted: [(Int, OTIOClip)] = []
        for ti in timeline.tracks.indices {
            for ci in (0..<timeline.tracks[ti].children.count).reversed() {
                if case .clip(let c) = timeline.tracks[ti].children[ci], c.linkGroupId == linkGroupId {
                    timeline.tracks[ti].children.remove(at: ci)
                    extracted.append((ti, c))
                }
            }
        }
        var splitLinkRemap: [String: String] = [:]
        for (ti, var clip) in extracted {
            let rate = clip.sourceRange.startTime.rate
            let clampedDur = min(clip.sourceRange.durationMs, referenceDurationMs)
            guard clampedDur > 0.5 else { continue }
            clip.sourceRange = OTIOTimeRange(
                startTime: clip.sourceRange.startTime,
                duration: OTIOTime.fromMs(clampedDur, rate: rate)
            )
            overwriteInTrack(&timeline.tracks[ti], clip: clip, atTimeMs: referenceStartMs, durationMs: referenceDurationMs, splitLinkRemap: &splitLinkRemap)
        }
    }

    /// Non-destructive placement: clip starts at `atTimeMs`, splits gaps/clips, pads with leading gap if past track end.
    ///
    /// `splitLinkRemap` maps an existing `linkGroupId → freshly minted linkGroupId` for the
    /// **right half** of any clip that gets split by the overwrite window. Threading the same
    /// map across the V/A calls of one operation keeps V's right-half linked to A's right-half
    /// (they get the same new id) while still breaking the (incorrect) link to the LEFT halves
    /// that remain on the same track. Without this, both halves of a split clip kept the same
    /// `linkGroupId`, so deleting one half also deleted its same-track sibling — the reported
    /// "deleting one audio clip also deletes the next one" bug.
    private func overwriteInTrack(
        _ track: inout OTIOTrack,
        clip: OTIOClip,
        atTimeMs: Double,
        durationMs: Double,
        splitLinkRemap: inout [String: String]
    ) {
        let startMs = max(0, atTimeMs)
        let endMs = startMs + max(0, durationMs)
        let original = track.children

        var newChildren: [OTIOItem] = []
        newChildren.reserveCapacity(original.count + 1)

        var inserted = false
        var cursorMs: Double = 0
        let rate = clip.sourceRange.startTime.rate

        for item in original {
            let itemDurMs = itemDurationMs(item)

            let itemStart = cursorMs
            let itemEnd = cursorMs + itemDurMs

            // Entirely before overwrite window
            if itemEnd <= startMs {
                newChildren.append(item)
                cursorMs = itemEnd
                continue
            }

            // Entirely after overwrite window
            if itemStart >= endMs {
                if !inserted {
                    newChildren.append(.clip(clip))
                    inserted = true
                }
                newChildren.append(item)
                cursorMs = itemEnd
                continue
            }

            // Overlaps overwrite window — left half keeps original linkGroupId
            if itemStart < startMs {
                let leftDur = startMs - itemStart
                if let leftItem = trimmedItem(item, keepStartOffsetMs: 0, keepDurationMs: leftDur, overrideLinkGroupId: nil) {
                    newChildren.append(leftItem)
                }
            }

            if !inserted {
                newChildren.append(.clip(clip))
                inserted = true
            }

            // Right half gets a remapped linkGroupId (shared across tracks via splitLinkRemap)
            if itemEnd > endMs {
                let rightStartOffset = endMs - itemStart
                let rightDur = itemEnd - endMs
                let remapped = remappedLinkIdForRightHalf(of: item, remap: &splitLinkRemap)
                if let rightItem = trimmedItem(item, keepStartOffsetMs: rightStartOffset, keepDurationMs: rightDur, overrideLinkGroupId: remapped) {
                    newChildren.append(rightItem)
                }
            }

            cursorMs = itemEnd
        }

        if !inserted {
            if startMs > cursorMs + 0.5 {
                newChildren.append(gapItem(rate: rate, durationMs: startMs - cursorMs))
            }
            newChildren.append(.clip(clip))
        }

        track.children = newChildren
    }

    /// Looks up (or mints) a fresh `linkGroupId` for the right half of a clip that's about to be
    /// split. `remap` is shared between the V/A passes of a single operation so that, when the
    /// same source clip is split symmetrically on both tracks, the two right halves wind up with
    /// the same new id and remain linked across tracks. Returns `nil` for gaps and for clips
    /// that didn't have a `linkGroupId` to begin with — nothing to remap.
    private func remappedLinkIdForRightHalf(of item: OTIOItem, remap: inout [String: String]) -> String? {
        guard case .clip(let c) = item, let oldLg = c.linkGroupId else { return nil }
        if let cached = remap[oldLg] { return cached }
        let fresh = UUID().uuidString
        remap[oldLg] = fresh
        return fresh
    }

    /// Inserts a clip at `atTimeMs` by splitting whatever segment occupies that timeline position and
    /// pushing the trailing material right (ripple insert). Mirrors `overwriteInTrack` link remapping so
    /// split V/A partners stay paired.
    private func rippleInsertInTrack(
        _ track: inout OTIOTrack,
        clip: OTIOClip,
        atTimeMs: Double,
        splitLinkRemap: inout [String: String]
    ) {
        let startMs = max(0, atTimeMs)
        let L = clip.sourceRange.durationMs
        guard L > 0.5 else { return }

        let original = track.children
        var newChildren: [OTIOItem] = []
        var inserted = false
        var cursorMs: Double = 0
        let rate = clip.sourceRange.startTime.rate
        let epsilon = 0.5

        for item in original {
            let itemDurMs = itemDurationMs(item)
            let itemStart = cursorMs
            let itemEnd = cursorMs + itemDurMs

            // Whole segment finishes strictly before insertion anchor (allow tiny FP slack)
            if itemEnd < startMs - epsilon {
                newChildren.append(item)
                cursorMs = itemEnd
                continue
            }

            // Junction / leading edge — insert clip before this segment instead of slicing it apart
            if !inserted, startMs <= itemStart + epsilon {
                newChildren.append(.clip(clip))
                inserted = true
                newChildren.append(item)
                cursorMs = itemEnd
                continue
            }

            // Anchor inside this segment interior
            if !inserted {
                let cutMs = max(0, startMs - itemStart)
                if cutMs > 0.5 {
                    if let left = trimmedItem(item, keepStartOffsetMs: 0, keepDurationMs: cutMs, overrideLinkGroupId: nil) {
                        newChildren.append(left)
                    }
                }

                newChildren.append(.clip(clip))
                inserted = true

                let rightDur = itemEnd - startMs
                if rightDur > 0.5 {
                    let remapped = remappedLinkIdForRightHalf(of: item, remap: &splitLinkRemap)
                    if let right = trimmedItem(item, keepStartOffsetMs: cutMs, keepDurationMs: rightDur, overrideLinkGroupId: remapped) {
                        newChildren.append(right)
                    }
                }
                cursorMs = itemEnd
                continue
            }

            newChildren.append(item)
            cursorMs = itemEnd
        }

        if !inserted {
            if startMs > cursorMs + 0.5 {
                newChildren.append(gapItem(rate: rate, durationMs: startMs - cursorMs))
            }
            newChildren.append(.clip(clip))
        }

        track.children = newChildren
    }

    /// Razor: split clips and gaps whose timeline spans contain `splitMs` (all tracks). One shared remap
    /// keeps right halves linked across paired V/A edits.
    private func splitTrackAtTimelineTime(_ track: inout OTIOTrack, at splitMs: Double, splitLinkRemap: inout [String: String]) {
        let epsilon = 0.5
        let split = max(0, splitMs)
        let original = track.children
        var newChildren: [OTIOItem] = []
        var cursorMs = 0.0

        for item in original {
            let d = itemDurationMs(item)
            let s = cursorMs
            let e = cursorMs + d
            cursorMs = e

            if split <= s + epsilon || split >= e - epsilon {
                newChildren.append(item)
                continue
            }

            let leftDur = split - s
            let rightDur = e - split
            guard leftDur > epsilon, rightDur > epsilon else {
                newChildren.append(item)
                continue
            }

            if let left = trimmedItem(item, keepStartOffsetMs: 0, keepDurationMs: leftDur, overrideLinkGroupId: nil) {
                newChildren.append(left)
            }
            let remapped = remappedLinkIdForRightHalf(of: item, remap: &splitLinkRemap)
            if let right = trimmedItem(item, keepStartOffsetMs: leftDur, keepDurationMs: rightDur, overrideLinkGroupId: remapped) {
                newChildren.append(right)
            }
        }

        track.children = newChildren
    }

    /// Finds the next segment strictly containing `playheadMs` across tracks top-to-bottom.
    private func findSegmentInterior(playheadMs: Double) -> (ti: Int, ci: Int, s: Double, e: Double, item: OTIOItem)? {
        guard let tl = timeline else { return nil }
        let epsilon = 0.5
        let P = playheadMs

        for ti in tl.tracks.indices {
            var cursor = 0.0
            for ci in tl.tracks[ti].children.indices {
                let item = tl.tracks[ti].children[ci]
                let d = itemDurationMs(item)
                let s = cursor
                let e = cursor + d
                cursor = e
                if P > s + epsilon && P < e - epsilon {
                    return (ti, ci, s, e, item)
                }
            }
        }
        return nil
    }

    private func applyRippleGapTrim(
        trackIndex ti: Int,
        childIndex ci: Int,
        segmentStart s: Double,
        segmentEnd e: Double,
        playheadMs P: Double,
        trimTail: Bool
    ) {
        guard var tl = timeline,
              ti < tl.tracks.count,
              ci < tl.tracks[ti].children.count,
              case .gap(let g) = tl.tracks[ti].children[ci] else { return }

        let rate = g.sourceRange.startTime.rate

        if trimTail {
            let newDur = P - s
            if newDur <= 0.5 {
                tl.tracks[ti].children.remove(at: ci)
            } else {
                tl.tracks[ti].children[ci] = .gap(OTIOGap(sourceRange: OTIOTimeRange(
                    startTime: g.sourceRange.startTime,
                    duration: OTIOTime.fromMs(newDur, rate: rate)
                )))
            }
        } else {
            let newDur = e - P
            if newDur <= 0.5 {
                tl.tracks[ti].children.remove(at: ci)
            } else {
                tl.tracks[ti].children[ci] = .gap(OTIOGap(sourceRange: OTIOTimeRange(
                    startTime: g.sourceRange.startTime,
                    duration: OTIOTime.fromMs(newDur, rate: rate)
                )))
            }
        }

        coalesceAdjacentGaps(in: &tl.tracks[ti])
        self.timeline = tl
    }

    /// Trims an item to a sub-range. When `overrideLinkGroupId` is non-nil and the item is a clip,
    /// the returned clip's `linkGroupId` is replaced with that value — used to give the right half
    /// of a split a fresh shared id so it doesn't stay linked to its left-half sibling on the same
    /// track. Passing `nil` keeps whatever `linkGroupId` the source already had.
    private func trimmedItem(
        _ item: OTIOItem,
        keepStartOffsetMs: Double,
        keepDurationMs: Double,
        overrideLinkGroupId: String?
    ) -> OTIOItem? {
        guard keepDurationMs > 0.5 else { return nil }

        switch item {
        case .clip(let c):
            let rate = c.sourceRange.startTime.rate
            let newStartMs = c.sourceRange.startMs + keepStartOffsetMs
            let newStartTime = OTIOTime.fromMs(newStartMs, rate: rate)
            let newDuration = OTIOTime.fromMs(keepDurationMs, rate: rate)
            var newClip = c
            newClip.sourceRange = OTIOTimeRange(startTime: newStartTime, duration: newDuration)
            if let override = overrideLinkGroupId {
                newClip.linkGroupId = override
            }
            return .clip(newClip)

        case .gap(let g):
            let rate = g.sourceRange.startTime.rate
            let newStartTime = g.sourceRange.startTime
            let newDuration = OTIOTime.fromMs(keepDurationMs, rate: rate)
            let newGap = OTIOGap(sourceRange: OTIOTimeRange(startTime: newStartTime, duration: newDuration))
            return .gap(newGap)
        }
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

    /// Applies two removal modes in **one index space** (`"\(trackIndex)_\(clipIndex)"` referring to the
    /// timeline rows **before** this call):
    ///
    /// - **`liftClipSlotKeys`**: remove each **clip**, replacing its timeline span with an empty Gap
    ///   of identical duration (`lift` semantics from an NLE) so later clips retain their timeline
    ///   offsets.
    /// - **`rippleRemoveSlotKeys`**: remove each referenced **item** outright (clips or gaps): used
    ///   for gap deletion (`ripple`/close empty space).
    ///
    /// After removals, consecutive gaps on each track are coalesced to keep OTIO stacks tidy.
    func applyLiftRippleRemoval(liftClipSlotKeys: Set<String>, rippleRemoveSlotKeys: Set<String>) {
        guard var tl = timeline else { return }

        for ti in tl.tracks.indices {
            var newChildren: [OTIOItem] = []

            for (ci, item) in tl.tracks[ti].children.enumerated() {
                let key = "\(ti)_\(ci)"
                if liftClipSlotKeys.contains(key) {
                    if case .clip(let c) = item {
                        newChildren.append(
                            gapItem(rate: c.sourceRange.startTime.rate, durationMs: c.sourceRange.durationMs)
                        )
                    } else if case .gap = item {
                        // Shouldn't combine lift on a gap, but tolerate by keeping the gap.
                        newChildren.append(item)
                    }
                    continue
                }
                if rippleRemoveSlotKeys.contains(key) {
                    continue
                }
                newChildren.append(item)
            }

            tl.tracks[ti].children = newChildren
            coalesceAdjacentGaps(in: &tl.tracks[ti])
        }

        self.timeline = tl
    }

    private func coalesceAdjacentGaps(in track: inout OTIOTrack) {
        guard track.children.count > 1 else { return }

        var out: [OTIOItem] = []
        out.reserveCapacity(track.children.count)

        for item in track.children {
            guard case .gap(let gAdded) = item else {
                out.append(item)
                continue
            }
            guard let last = out.last else {
                out.append(item)
                continue
            }
            if case .gap(let gPrev) = last {
                let rate = gPrev.sourceRange.duration.rate
                let combinedMs = gPrev.sourceRange.durationMs + gAdded.sourceRange.durationMs
                let mergedGap = OTIOGap(sourceRange: OTIOTimeRange(
                    startTime: gPrev.sourceRange.startTime,
                    duration: OTIOTime.fromMs(combinedMs, rate: rate)
                ))
                out[out.count - 1] = .gap(mergedGap)
            } else {
                out.append(item)
            }
        }
        track.children = out
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
        guard var tl = timeline,
              trackIndices.count == clipIndices.count,
              let firstT = trackIndices.first,
              let firstC = clipIndices.first,
              let anchor = timelineBoundsOfClip(track: firstT, clipIndex: firstC, in: tl) else { return }

        let newLinkId = UUID().uuidString

        for (ti, ci) in zip(trackIndices, clipIndices) {
            guard ti < tl.tracks.count, ci < tl.tracks[ti].children.count else { continue }
            if case .clip(var c) = tl.tracks[ti].children[ci] {
                c.linkGroupId = newLinkId
                tl.tracks[ti].children[ci] = .clip(c)
            }
        }

        syncLinkedGroupTimelinePositions(
            linkGroupId: newLinkId,
            referenceStartMs: anchor.start,
            referenceDurationMs: anchor.duration,
            timeline: &tl
        )
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

        var splitLinkRemap: [String: String] = [:]
        for entry in clipboard {
            var clip = entry.clip
            clip.linkGroupId = UUID().uuidString // New link IDs for pasted clips

            if let trackIndex = tl.tracks.firstIndex(where: { $0.kind == entry.trackKind }) {
                let d = clip.sourceRange.durationMs
                overwriteInTrack(&tl.tracks[trackIndex], clip: clip, atTimeMs: timeMs, durationMs: d, splitLinkRemap: &splitLinkRemap)
            }
        }

        self.timeline = tl
    }

    // MARK: - Razor & Ripple Trim

    /// Razor tool: splits every timeline item intersected by `timelineMs` interior (clips and gaps).
    func razorSplit(atTimelineMs timelineMs: Double) {
        guard var tl = timeline else { return }
        var splitLinkRemap: [String: String] = [:]
        for ti in tl.tracks.indices {
            splitTrackAtTimelineTime(&tl.tracks[ti], at: timelineMs, splitLinkRemap: &splitLinkRemap)
        }
        self.timeline = tl
    }

    /// Ripple trim in-point(s) so each segment spanning the playhead starts at `playheadMs` on the timeline.
    func rippleTrimStartToPlayhead(playheadMs: Double) {
        rippleTrim(playheadMs: playheadMs, trimTail: false)
    }

    /// Ripple trim out-point(s): each segment spanning the playhead ends at `playheadMs`.
    func rippleTrimEndToPlayhead(playheadMs: Double) {
        rippleTrim(playheadMs: playheadMs, trimTail: true)
    }

    private func rippleTrim(playheadMs P: Double, trimTail: Bool) {
        while let hit = findSegmentInterior(playheadMs: P) {
            switch hit.item {
            case .clip(let c):
                if trimTail {
                    let trimAmt = hit.e - P
                    let newEndMs = c.sourceRange.endMs - trimAmt
                    trimClipEnd(trackIndex: hit.ti, clipIndex: hit.ci, newEndMs: newEndMs)
                } else {
                    let timelineDelta = P - hit.s
                    let newStartMs = c.sourceRange.startMs + timelineDelta
                    trimClipStart(trackIndex: hit.ti, clipIndex: hit.ci, newStartMs: newStartMs)
                }
            case .gap:
                applyRippleGapTrim(
                    trackIndex: hit.ti,
                    childIndex: hit.ci,
                    segmentStart: hit.s,
                    segmentEnd: hit.e,
                    playheadMs: P,
                    trimTail: trimTail
                )
            }

            guard timeline != nil else { return }
        }
    }

    // MARK: - Move

    /// Moves clip(s) to `toTimeMs`. Default overwrites overlapping material on the destination track(s).
    /// With `rippleInsert`: splits at the drop frame and pushes the rest of the timeline right without
    /// removing underlying clips except by the splice.
    func moveClip(fromTrack: Int, fromIndex: Int, toTrack: Int, toTimeMs: Double, rippleInsert: Bool = false) {
        guard var tl = timeline,
              fromTrack < tl.tracks.count,
              fromIndex < tl.tracks[fromTrack].children.count else { return }

        guard case .clip(let moved) = tl.tracks[fromTrack].children[fromIndex] else { return }

        var splitLinkRemap: [String: String] = [:]
        func place(track: Int, clip: OTIOClip) {
            guard track < tl.tracks.count else { return }
            let d = clip.sourceRange.durationMs
            if rippleInsert {
                rippleInsertInTrack(&tl.tracks[track], clip: clip, atTimeMs: toTimeMs, splitLinkRemap: &splitLinkRemap)
            } else {
                overwriteInTrack(&tl.tracks[track], clip: clip, atTimeMs: toTimeMs, durationMs: d, splitLinkRemap: &splitLinkRemap)
            }
        }

        if let lg = moved.linkGroupId {
            var extracted: [(Int, OTIOClip)] = []
            for ti in tl.tracks.indices {
                for ci in (0..<tl.tracks[ti].children.count).reversed() {
                    if case .clip(let c) = tl.tracks[ti].children[ci], c.linkGroupId == lg {
                        tl.tracks[ti].children.remove(at: ci)
                        extracted.append((ti, c))
                    }
                }
            }
            for (ti, clip) in extracted.sorted(by: { $0.0 < $1.0 }) {
                place(track: ti, clip: clip)
            }
        } else {
            let item = tl.tracks[fromTrack].children.remove(at: fromIndex)
            if case .clip(let clip) = item {
                place(track: toTrack, clip: clip)
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

        /// One fresh `linkGroupId` per kept **segment** (ripple range), shared by every track that
        /// processes the same `mediaFileId` so V1↔A1 stay paired. Reusing `firstClip.linkGroupId` for
        /// every segment made all adjacent timeline clips look like one linked block and mass-delete
        /// removed the whole row.
        var segmentLinkGroupsByMediaId: [Int64: [String]] = [:]

        for (trackIndex, track) in tl.tracks.enumerated() {
            guard let firstClip = track.children.compactMap({ item -> OTIOClip? in
                if case .clip(let c) = item { return c } else { return nil }
            }).first,
            let decision = decisions.first(where: { $0.clipId == firstClip.mediaFileId }),
            let file = fileMap[firstClip.mediaFileId] else {
                continue
            }

            let sortedRanges = decision.keepRanges.sorted(by: { $0.startMs < $1.startMs })
            let mid = firstClip.mediaFileId

            let segmentLinks: [String]
            if let cached = segmentLinkGroupsByMediaId[mid], cached.count == sortedRanges.count {
                segmentLinks = cached
            } else {
                let fresh = sortedRanges.map { _ in UUID().uuidString }
                segmentLinkGroupsByMediaId[mid] = fresh
                segmentLinks = fresh
            }

            var newChildren: [OTIOItem] = []
            newChildren.reserveCapacity(sortedRanges.count)

            for (segIdx, range) in sortedRanges.enumerated() {
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
                    mediaFileId: mid,
                    linkGroupId: segmentLinks[segIdx]
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


