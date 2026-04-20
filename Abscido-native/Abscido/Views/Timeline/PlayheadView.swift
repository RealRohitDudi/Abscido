import SwiftUI

/// Vertical playhead indicator on the timeline.
struct PlayheadView: View {
    let timeMs: Double
    let pixelsPerSecond: Double
    let height: CGFloat

    private var xPosition: CGFloat {
        timeMs / 1000.0 * pixelsPerSecond
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Playhead line
            Rectangle()
                .fill(Color.white)
                .frame(width: 1, height: height)

            // Playhead handle
            Path { path in
                path.move(to: CGPoint(x: -5, y: 0))
                path.addLine(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: 2, y: 8))
                path.addLine(to: CGPoint(x: -2, y: 8))
                path.closeSubpath()
            }
            .fill(Color(red: 0.486, green: 0.424, blue: 0.980))
        }
        .offset(x: xPosition)
    }
}
