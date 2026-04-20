import AVFoundation
import Foundation

/// MediaEngine is the AVFoundation orchestrator — handles import, composition building,
/// playback loading, and export rendering.
actor MediaEngine {
    private var player: AVPlayer
    private var currentComposition: AVMutableComposition?

    init() {
        self.player = AVPlayer()
    }

    /// Returns the managed AVPlayer instance for use by PlayerViewModel.
    func getPlayer() -> AVPlayer {
        player
    }

    // MARK: - Import

    /// Imports a media file, extracting metadata via AVURLAsset.
    func importFile(_ url: URL, projectId: Int64) async throws -> MediaFile {
        let asset = AVURLAsset(url: url)

        let duration: CMTime
        let videoTrack: AVAssetTrack?
        let audioTrack: AVAssetTrack?

        if #available(macOS 15, *) {
            duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            videoTrack = videoTracks.first
            audioTrack = audioTracks.first
        } else {
            duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            videoTrack = videoTracks.first
            audioTrack = audioTracks.first
        }

        let durationMs = duration.toMs

        var width = 0
        var height = 0
        var fps: Double = 30.0
        var codec = "unknown"

        if let vTrack = videoTrack {
            let size = try await vTrack.load(.naturalSize)
            let frameRate = try await vTrack.load(.nominalFrameRate)
            let formatDescriptions = try await vTrack.load(.formatDescriptions)
            width = Int(size.width)
            height = Int(size.height)
            fps = Double(frameRate)
            if fps <= 0 { fps = 30.0 }

            if let desc = formatDescriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                codec = fourCharCodeToString(mediaSubType)
            }
        }

        // Generate security-scoped bookmark
        let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Generate thumbnail
        let thumbnailPath = try? await ThumbnailService.generateThumbnail(
            for: asset,
            at: durationMs * 0.1,
            outputDir: thumbnailDirectory()
        )

        return MediaFile(
            projectId: projectId,
            filePath: url.path,
            bookmarkData: bookmarkData,
            durationMs: durationMs,
            fps: fps,
            width: width,
            height: height,
            codec: codec,
            thumbnailPath: thumbnailPath
        )
    }

    // MARK: - Composition Building

    /// Builds an AVMutableComposition from edit decisions — this is the heart of text-based editing.
    /// Each keep range becomes a time insertion in the composition. Deleted regions are simply not included,
    /// achieving ripple-delete behavior through AVComposition's contiguous insertion model.
    func buildComposition(
        from editDecisions: [EditDecision],
        mediaFiles: [MediaFile]
    ) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })

        for decision in editDecisions {
            guard let file = fileMap[decision.clipId] else { continue }

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

            for range in decision.keepRanges {
                let timeRange = CMTimeRange.fromMs(start: range.startMs, end: range.endMs)

                if let sourceVideoTrack = videoTracks.first, let compVTrack = compVideoTrack {
                    try compVTrack.insertTimeRange(
                        timeRange,
                        of: sourceVideoTrack,
                        at: insertionTime
                    )
                }

                if let sourceAudioTrack = audioTracks.first, let compATrack = compAudioTrack {
                    try compATrack.insertTimeRange(
                        timeRange,
                        of: sourceAudioTrack,
                        at: insertionTime
                    )
                }

                insertionTime = CMTimeAdd(insertionTime, timeRange.duration)
            }
        }

        self.currentComposition = composition
        return composition
    }

    // MARK: - Playback

    /// Loads a composition for instant playback — no render step needed.
    func loadForPlayback(_ composition: AVComposition) {
        let playerItem = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: playerItem)
    }

    /// Loads a raw media file for playback (before any edits).
    func loadFileForPlayback(_ url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
    }

    /// Frame-exact seek with zero tolerance.
    func seek(to ms: Double) async {
        let time = CMTime.fromMs(ms)
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Returns current playback time in milliseconds.
    func currentTimeMs() -> Double {
        player.currentTime().toMs
    }

    // MARK: - Helpers

    private func thumbnailDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Abscido/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar(truncatingIfNeeded: (code >> 24) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 16) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 8) & 0xFF),
            CChar(truncatingIfNeeded: code & 0xFF),
            0,
        ]
        return String(cString: bytes)
    }
}
