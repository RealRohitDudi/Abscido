import SwiftUI
import UniformTypeIdentifiers

/// Horizontal scrolling timeline view backed by OTIO timeline data.
/// Supports drag-and-drop from Media Bin, pinch-to-zoom, and waveform visualization.
struct TimelineView: View {
    @Bindable var timelineVM: TimelineViewModel
    @Bindable var playerVM: PlayerViewModel
    var mediaFiles: [MediaFile]

    /// Base zoom level stored at gesture start for smooth pinch-to-zoom.
    @State private var basePixelsPerSecond: Double = 100.0
    /// Tracks whether a drag is currently hovering over the timeline.
    @State private var isDragHovering = false
    /// The x-position of the current drag hover for the drop indicator.
    @State private var dragHoverX: CGFloat = 0

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
                timelineContent
            }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let newPps = basePixelsPerSecond * value.magnification
                    timelineVM.setZoom(newPps)
                }
                .onEnded { _ in
                    basePixelsPerSecond = timelineVM.pixelsPerSecond
                }
        )
        .onAppear {
            basePixelsPerSecond = timelineVM.pixelsPerSecond
        }
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                // Ruler
                timelineRuler

                // Clips
                HStack(spacing: 1) {
                    ForEach(timelineVM.clips) { clip in
                        TimelineClipView(
                            clip: clip,
                            pixelsPerSecond: timelineVM.pixelsPerSecond,
                            waveformSamples: timelineVM.waveformSamples(for: clip)
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

                // Drop indicator
                if isDragHovering {
                    dropIndicator
                }
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
        .dropDestination(for: MediaFile.self) { droppedFiles, location in
            guard let file = droppedFiles.first else { return false }
            let insertIndex = timelineVM.insertionIndex(forDropX: location.x)
            timelineVM.insertMediaFile(file, at: insertIndex, allMediaFiles: mediaFiles)
            isDragHovering = false
            return true
        } isTargeted: { isTargeted in
            isDragHovering = isTargeted
        }
    }

    // MARK: - Drop Indicator

    private var dropIndicator: some View {
        Rectangle()
            .fill(Color(red: 0.486, green: 0.424, blue: 0.980))
            .frame(width: 2, height: 80)
            .shadow(color: Color(red: 0.486, green: 0.424, blue: 0.980).opacity(0.6), radius: 4)
            .padding(.top, 24)
    }

    // MARK: - Empty State

    private var emptyTimeline: some View {
        VStack(spacing: 8) {
            Image(systemName: "timeline.selection")
                .font(.title2)
                .foregroundColor(.secondary.opacity(0.4))
            Text("Drop media here or import to see timeline")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
        .dropDestination(for: MediaFile.self) { droppedFiles, _ in
            guard let file = droppedFiles.first else { return false }
            timelineVM.insertMediaFile(file, at: 0, allMediaFiles: mediaFiles)
            return true
        } isTargeted: { isTargeted in
            isDragHovering = isTargeted
        }
    }

    // MARK: - Ruler

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
