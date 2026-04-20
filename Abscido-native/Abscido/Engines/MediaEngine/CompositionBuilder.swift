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
