import AVFoundation
import CoreMedia

extension CMTime {
    /// Creates a CMTime from milliseconds with 1000 timescale for frame-exact precision.
    static func fromMs(_ ms: Double) -> CMTime {
        CMTime(value: CMTimeValue(ms), timescale: 1000)
    }

    /// Converts this CMTime to milliseconds.
    var toMs: Double {
        CMTimeGetSeconds(self) * 1000.0
    }

    /// Creates a CMTime from milliseconds and fps, using the fps as timescale
    /// for frame-exact alignment.
    static func fromMs(_ ms: Double, fps: Double) -> CMTime {
        let timescale = Int32(fps * 1000)
        let value = CMTimeValue(ms / 1000.0 * Double(timescale))
        return CMTime(value: value, timescale: timescale)
    }

    /// Converts this CMTime to a frame number at the given fps.
    func toFrames(fps: Double) -> Int64 {
        let seconds = CMTimeGetSeconds(self)
        return Int64(round(seconds * fps))
    }

    /// Creates a CMTime representing a specific frame at the given fps.
    static func fromFrames(_ frame: Int64, fps: Double) -> CMTime {
        let timescale = Int32(round(fps) * 1000)
        let value = CMTimeValue(Double(frame) / fps * Double(timescale))
        return CMTime(value: value, timescale: timescale)
    }

    /// Returns a reduced rational fraction string like "1001/30000s" for FCPXML.
    var rationalString: String {
        let g = gcd(abs(Int(value)), Int(timescale))
        let num = Int(value) / g
        let den = Int(timescale) / g
        return "\(num)/\(den)s"
    }
}

extension CMTimeRange {
    /// Creates a CMTimeRange from start and end in milliseconds.
    static func fromMs(start: Double, end: Double) -> CMTimeRange {
        let startTime = CMTime.fromMs(start)
        let duration = CMTime.fromMs(end - start)
        return CMTimeRange(start: startTime, duration: duration)
    }

    /// The duration of this range in milliseconds.
    var durationMs: Double {
        duration.toMs
    }

    /// The start time of this range in milliseconds.
    var startMs: Double {
        start.toMs
    }
}

/// Converts milliseconds to a frame count at the given fps.
func msToFrames(_ ms: Double, fps: Double) -> Int64 {
    Int64(round(ms / 1000.0 * fps))
}

/// Converts a frame count to milliseconds at the given fps.
func framesToMs(_ frames: Int64, fps: Double) -> Double {
    Double(frames) / fps * 1000.0
}
