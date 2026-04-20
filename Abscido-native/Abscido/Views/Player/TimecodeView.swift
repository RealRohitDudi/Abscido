import SwiftUI

/// Displays timecode in HH:MM:SS:FF monospaced format.
struct TimecodeView: View {
    let ms: Double
    var fps: Double = 30.0

    var body: some View {
        Text(TimecodeFormatter.format(ms: ms, fps: fps))
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .monospacedDigit()
    }
}
