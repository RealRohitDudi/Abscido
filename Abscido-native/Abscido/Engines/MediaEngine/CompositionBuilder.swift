import AVFoundation
import Foundation

/// Builds AVMutableComposition objects from edit decision lists.
/// Separated from MediaEngine for testability.
enum CompositionBuilder {

    /// Builds an AVMutableComposition from edit decisions.
    /// Each keep range from an EditDecision is inserted contiguously into the composition,
    /// effectively ripple-deleting the gaps between them.
    static func build(
        from editDecisions: [EditDecision],
        mediaFiles: [MediaFile]
    ) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })

        for decision in editDecisions {
            guard let file = fileMap[decision.clipId] else { continue }
            guard !decision.keepRanges.isEmpty else { continue }

            let asset = AVURLAsset(url: file.url)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )

            var insertionTime = CMTime.zero

            for range in decision.keepRanges.sorted(by: { $0.startMs < $1.startMs }) {
                let cmRange = CMTimeRange.fromMs(start: range.startMs, end: range.endMs)

                if let srcVideo = videoTracks.first, let dstVideo = compVideoTrack {
                    try dstVideo.insertTimeRange(cmRange, of: srcVideo, at: insertionTime)
                }
                if let srcAudio = audioTracks.first, let dstAudio = compAudioTrack {
                    try dstAudio.insertTimeRange(cmRange, of: srcAudio, at: insertionTime)
                }

                insertionTime = CMTimeAdd(insertionTime, cmRange.duration)
            }
        }

        return composition
    }

    /// Builds an AVMutableComposition that mirrors the OTIO timeline state — every clip's
    /// `sourceRange` (in/out points after Q/E/razor/manual trim) and gap layout are preserved.
    ///
    /// This is what keeps the player honest after timeline-side edits. Without it, the player
    /// stays loaded with the raw asset (or a stale transcript-derived composition), so a Q at
    /// playhead 3 s on a 10 s clip *appears* on the timeline as a 7 s clip but the player still
    /// plays source [0, 10 s] — the user perceives the trim as if the clip's tail was removed.
    static func build(
        from timeline: OTIOTimeline,
        mediaFiles: [MediaFile]
    ) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })

        // One AVURLAsset per file (loaded once, reused across all clips on every track that
        // references the same media — a typical V/A linked import has at least two clips per file).
        var assetCache: [Int64: AVURLAsset] = [:]
        var videoTrackCache: [Int64: AVAssetTrack] = [:]
        var audioTrackCache: [Int64: AVAssetTrack] = [:]

        func asset(for file: MediaFile) -> AVURLAsset {
            if let cached = assetCache[file.id] { return cached }
            let a = AVURLAsset(url: file.url)
            assetCache[file.id] = a
            return a
        }

        for track in timeline.tracks {
            let mediaType: AVMediaType = (track.kind == .video) ? .video : .audio
            guard let compTrack = composition.addMutableTrack(
                withMediaType: mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            var insertionTime = CMTime.zero

            for child in track.children {
                switch child {
                case .clip(let clip):
                    let durationMs = clip.sourceRange.durationMs
                    guard durationMs > 0.0,
                          let file = fileMap[clip.mediaFileId] else {
                        // Unknown media or zero-length clip — leave a gap so downstream cumulative
                        // offsets still match the OTIO model.
                        insertionTime = CMTimeAdd(insertionTime, CMTime.fromMs(max(0, durationMs)))
                        continue
                    }

                    let srcAsset = asset(for: file)
                    let srcTrack: AVAssetTrack?
                    if mediaType == .video {
                        if let cached = videoTrackCache[file.id] {
                            srcTrack = cached
                        } else {
                            srcTrack = try await srcAsset.loadTracks(withMediaType: .video).first
                            if let t = srcTrack { videoTrackCache[file.id] = t }
                        }
                    } else {
                        if let cached = audioTrackCache[file.id] {
                            srcTrack = cached
                        } else {
                            srcTrack = try await srcAsset.loadTracks(withMediaType: .audio).first
                            if let t = srcTrack { audioTrackCache[file.id] = t }
                        }
                    }

                    guard let sourceTrack = srcTrack else {
                        // Asset has no track of this kind (e.g. silent video on an audio lane);
                        // advance the cursor so cumulative offsets stay aligned.
                        insertionTime = CMTimeAdd(insertionTime, CMTime.fromMs(durationMs))
                        continue
                    }

                    let sourceRange = CMTimeRange.fromMs(
                        start: clip.sourceRange.startMs,
                        end: clip.sourceRange.startMs + durationMs
                    )

                    do {
                        try compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertionTime)
                    } catch {
                        // Insertion can fail if the requested range is outside the source asset's
                        // duration (rounding near the tail). Fall back to a gap of the same length
                        // so the rest of the timeline stays aligned.
                    }
                    insertionTime = CMTimeAdd(insertionTime, sourceRange.duration)

                case .gap(let gap):
                    insertionTime = CMTimeAdd(insertionTime, CMTime.fromMs(gap.sourceRange.durationMs))
                }
            }
        }

        return composition
    }

    /// Builds a composition for a single clip with the full duration (no edits).
    static func buildFull(for mediaFile: MediaFile) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let asset = AVURLAsset(url: mediaFile.url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)

        let fullRange = CMTimeRange(start: .zero, duration: duration)

        if let srcVideo = videoTracks.first {
            let compTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try compTrack?.insertTimeRange(fullRange, of: srcVideo, at: .zero)
        }
        if let srcAudio = audioTracks.first {
            let compTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try compTrack?.insertTimeRange(fullRange, of: srcAudio, at: .zero)
        }

        return composition
    }
}
