import SwiftUI

/// Horizontal scrolling timeline view backed by OTIO timeline data.
struct TimelineView: View {
    @Bindable var timelineVM: TimelineViewModel
    @Bindable var playerVM: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Timeline header
            HStack {
                Text("Timeline")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                // Zoom controls
                Button(action: { timelineVM.zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button(action: { timelineVM.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text(TimecodeFormatter.formatShort(ms: timelineVM.totalDurationMs))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.141, green: 0.141, blue: 0.141))

            Divider()

            // Timeline content
            if timelineVM.clips.isEmpty {
                emptyTimeline
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Ruler
                        timelineRuler

                        // Clips
                        HStack(spacing: 1) {
                            ForEach(timelineVM.clips) { clip in
                                TimelineClipView(
                                    clip: clip,
                                    pixelsPerSecond: timelineVM.pixelsPerSecond
                                )
                            }
                        }
                        .padding(.top, 24)

                        // Playhead
                        PlayheadView(
                            timeMs: playerVM.currentTimeMs,
                            pixelsPerSecond: timelineVM.pixelsPerSecond,
                            height: 120
                        )
                    }
                    .frame(
                        width: max(300, timelineVM.totalDurationMs / 1000.0 * timelineVM.pixelsPerSecond),
                        alignment: .leading
                    )
                }
                .background(Color(red: 0.102, green: 0.102, blue: 0.102))
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let ms = (location.x / timelineVM.pixelsPerSecond) * 1000.0
                    playerVM.seek(to: max(0, min(ms, timelineVM.totalDurationMs)))
                }
            }
        }
    }

    private var emptyTimeline: some View {
        VStack(spacing: 8) {
            Image(systemName: "timeline.selection")
                .font(.title2)
                .foregroundColor(.secondary.opacity(0.4))
            Text("Import media to see timeline")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
    }

    private var timelineRuler: some View {
        Canvas { context, size in
            let pps = timelineVM.pixelsPerSecond
            let totalSeconds = timelineVM.totalDurationMs / 1000.0
            let interval = rulerInterval(pps: pps)

            var t: Double = 0
            while t <= totalSeconds {
                let x = t * pps
                let isMajor = t.truncatingRemainder(dividingBy: interval * 5) < 0.001

                // Tick mark
                let tickHeight: CGFloat = isMajor ? 12 : 6
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 20 - tickHeight))
                        p.addLine(to: CGPoint(x: x, y: 20))
                    },
                    with: .color(.secondary.opacity(0.3)),
                    lineWidth: 0.5
                )

                // Label
                if isMajor {
                    let text = TimecodeFormatter.formatShort(ms: t * 1000)
                    context.draw(
                        Text(text)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5)),
                        at: CGPoint(x: x, y: 6),
                        anchor: .top
                    )
                }

                t += interval
            }
        }
        .frame(height: 24)
    }

    private func rulerInterval(pps: Double) -> Double {
        if pps > 200 { return 0.5 }
        if pps > 100 { return 1 }
        if pps > 50 { return 2 }
        if pps > 25 { return 5 }
        return 10
    }
}
