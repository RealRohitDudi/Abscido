import AVFoundation
import Accelerate

/// Extracts audio waveform amplitude data from media files for timeline visualization.
/// Uses AVAssetReader to read raw PCM samples, then downsamples via Accelerate
/// for efficient rendering at any zoom level.
actor WaveformGenerator {
    /// Cache of generated waveform data keyed by file path.
    private var cache: [String: [Float]] = [:]

    /// Target samples per second of audio for visualization.
    private let samplesPerSecond: Int = 200

    /// Generates waveform amplitude data for a media file.
    /// Returns normalized [Float] in 0...1 range.
    /// Results are cached per file path.
    func generateWaveform(for file: MediaFile) async -> [Float] {
        if let cached = cache[file.filePath] {
            return cached
        }

        let samples = await extractSamples(url: file.url, durationMs: file.durationMs)
        cache[file.filePath] = samples
        return samples
    }

    /// Extracts and downsamples audio amplitude data from the given URL.
    private func extractSamples(url: URL, durationMs: Double) async -> [Float] {
        let asset = AVURLAsset(url: url)

        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            // No audio track — return empty
            return []
        }

        let totalSamples = max(1, Int(durationMs / 1000.0 * Double(samplesPerSecond)))

        do {
            let reader = try AVAssetReader(asset: asset)

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1
            ]

            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)

            guard reader.startReading() else {
                return Array(repeating: 0.3, count: totalSamples)
            }

            // Read all audio samples into a single buffer
            var allSamples: [Int16] = []
            allSamples.reserveCapacity(44100 * Int(durationMs / 1000.0))

            while let sampleBuffer = output.copyNextSampleBuffer() {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return }
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
                }

                // Convert bytes to Int16 samples
                let int16Count = length / MemoryLayout<Int16>.size
                data.withUnsafeBytes { rawBuffer in
                    guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
                    let buffer = UnsafeBufferPointer(start: ptr, count: int16Count)
                    allSamples.append(contentsOf: buffer)
                }
            }

            reader.cancelReading()

            guard !allSamples.isEmpty else {
                return Array(repeating: 0.3, count: totalSamples)
            }

            // Downsample: divide all samples into `totalSamples` buckets,
            // take the max absolute value in each bucket
            return downsample(allSamples, to: totalSamples)

        } catch {
            // On failure, return a flat placeholder
            return Array(repeating: 0.3, count: totalSamples)
        }
    }

    /// Downsamples raw Int16 audio into `targetCount` normalized peak amplitudes.
    private func downsample(_ samples: [Int16], to targetCount: Int) -> [Float] {
        let bucketSize = max(1, samples.count / targetCount)
        var result: [Float] = []
        result.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let start = i * bucketSize
            let end = min(start + bucketSize, samples.count)
            guard start < end else {
                result.append(0)
                continue
            }

            var maxVal: Int32 = 0
            for j in start..<end {
                let absVal = abs(Int32(samples[j]))
                if absVal > maxVal { maxVal = absVal }
            }

            // Normalize to 0...1
            result.append(Float(maxVal) / Float(Int16.max))
        }

        return result
    }

    /// Clears the cache for a specific file.
    func clearCache(for filePath: String) {
        cache.removeValue(forKey: filePath)
    }

    /// Clears the entire waveform cache.
    func clearAllCache() {
        cache.removeAll()
    }
}
