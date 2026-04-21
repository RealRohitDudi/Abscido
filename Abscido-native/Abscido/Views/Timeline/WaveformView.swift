import SwiftUI

/// Canvas-based waveform visualization rendered inside timeline clips.
/// Draws a mirrored amplitude bar chart from normalized [Float] sample data.
struct WaveformView: View {
    let samples: [Float]
    let accentColor: Color

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let barWidth: CGFloat = max(1, size.width / CGFloat(samples.count))
            let midY = size.height / 2

            for (index, amplitude) in samples.enumerated() {
                let x = CGFloat(index) * barWidth
                let barHeight = CGFloat(amplitude) * size.height * 0.85

                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: max(0.5, barWidth - 0.5),
                    height: max(0.5, barHeight)
                )

                context.fill(
                    Path(rect),
                    with: .color(accentColor.opacity(Double(0.3 + amplitude * 0.5)))
                )
            }
        }
    }
}
