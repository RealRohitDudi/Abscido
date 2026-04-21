import SwiftUI

/// Visual clip representation in the timeline.
struct TimelineClipView: View {
    let clip: TimelineViewModel.TimelineClipModel
    let pixelsPerSecond: Double
    let waveformSamples: [Float]?

    private var width: CGFloat {
        max(4, clip.durationMs / 1000.0 * pixelsPerSecond)
    }

    private var clipColor: Color {
        switch clip.color {
        case .video:
            return Color(red: 0.486, green: 0.424, blue: 0.980) // accent purple
        case .audio:
            return Color(red: 0.3, green: 0.7, blue: 0.5)
        case .gap:
            return Color(red: 0.2, green: 0.2, blue: 0.2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clip bar
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [clipColor.opacity(0.35), clipColor.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    // Waveform layer
                    if let samples = waveformSamples, !samples.isEmpty {
                        WaveformView(
                            samples: visibleSamples(from: samples),
                            accentColor: clipColor
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .overlay(alignment: .leading) {
                    if width > 60 {
                        Text(clip.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(clipColor.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                    }
                }
                .frame(width: width, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(clipColor.opacity(0.6), lineWidth: 0.5)
                )

            // Duration label
            if width > 40 {
                Text(TimecodeFormatter.formatShort(ms: clip.durationMs))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.leading, 4)
                    .padding(.top, 2)
            }
        }
    }

    /// Extracts the subset of waveform samples visible for this clip's source range.
    private func visibleSamples(from allSamples: [Float]) -> [Float] {
        // allSamples covers the entire media file duration.
        // The clip may only represent a sub-range after editing.
        // For now, use all samples (initial clips cover full duration).
        // When source range clipping is needed, slice here based on clip.startMs.
        return allSamples
    }
}
