import Foundation

enum TimecodeFormatter {
    /// Formats milliseconds into HH:MM:SS:FF timecode string.
    /// - Parameters:
    ///   - ms: Time in milliseconds
    ///   - fps: Frames per second for frame count calculation
    /// - Returns: Formatted string like "01:23:45:12"
    static func format(ms: Double, fps: Double) -> String {
        let totalSeconds = ms / 1000.0
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let fractionalSeconds = totalSeconds - Double(Int(totalSeconds))
        let frames = Int(fractionalSeconds * fps)

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// Formats milliseconds into a short MM:SS display (no frames).
    static func formatShort(ms: Double) -> String {
        let totalSeconds = ms / 1000.0
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formats milliseconds into HH:MM:SS (no frames).
    static func formatHMS(ms: Double) -> String {
        let totalSeconds = ms / 1000.0
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Parses a timecode string "HH:MM:SS:FF" back to milliseconds.
    static func parse(timecode: String, fps: Double) -> Double? {
        let parts = timecode.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        let hours = parts[0]
        let minutes = parts[1]
        let seconds = parts[2]
        let frames = parts[3]
        let totalSeconds = Double(hours * 3600 + minutes * 60 + seconds) + Double(frames) / fps
        return totalSeconds * 1000.0
    }
}
