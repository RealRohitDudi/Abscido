import AVFoundation
import AppKit
import Foundation

/// Generates thumbnail images from video assets using AVAssetImageGenerator.
enum ThumbnailService {

    /// Generates a thumbnail at the specified time and saves it to disk.
    /// Returns the file path of the saved thumbnail.
    static func generateThumbnail(
        for asset: AVAsset,
        at timeMs: Double,
        outputDir: URL,
        maxSize: CGSize = CGSize(width: 320, height: 180)
    ) async throws -> String {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let time = CMTime.fromMs(timeMs)
        let cgImage: CGImage

        if #available(macOS 15, *) {
            let (image, _) = try await generator.image(at: time)
            cgImage = image
        } else {
            cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        }

        let filename = UUID().uuidString + ".jpg"
        let outputURL = outputDir.appendingPathComponent(filename)

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.8]
        ) else {
            throw AbscidoError.mediaImportFailed(
                url: outputURL,
                underlying: "Failed to create JPEG data"
            )
        }

        try jpegData.write(to: outputURL)
        return outputURL.path
    }

    /// Generates multiple thumbnails at evenly spaced intervals for a waveform/strip preview.
    static func generateThumbnailStrip(
        for asset: AVAsset,
        count: Int,
        outputDir: URL,
        maxSize: CGSize = CGSize(width: 160, height: 90)
    ) async throws -> [String] {
        let duration = try await asset.load(.duration)
        let durationMs = duration.toMs
        let interval = durationMs / Double(count + 1)

        var paths: [String] = []
        for i in 1...count {
            let timeMs = interval * Double(i)
            let path = try await generateThumbnail(
                for: asset,
                at: timeMs,
                outputDir: outputDir,
                maxSize: maxSize
            )
            paths.append(path)
        }
        return paths
    }
}
