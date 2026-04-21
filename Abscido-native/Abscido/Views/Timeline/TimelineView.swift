import SwiftUI

/// Timeline view wrapper — header bar + NSScrollView-based timeline renderer.
struct TimelineView: View {
    @Bindable var timelineVM: TimelineViewModel
    @Bindable var playerVM: PlayerViewModel
    var mediaFiles: [MediaFile]

    var body: some View {
        VStack(spacing: 0) {
            // Timeline header bar
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

                Text("\(Int(timelineVM.pixelsPerSecond)) pps")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 50)

                Button(action: { timelineVM.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Divider()
                    .frame(height: 12)

                Text("\(timelineVM.tracks.count) tracks")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))

                Text(TimecodeFormatter.formatShort(ms: timelineVM.totalDurationMs))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.141, green: 0.141, blue: 0.141))

            Divider()

            // NSScrollView-based timeline renderer
            if timelineVM.tracks.isEmpty {
                emptyTimeline
            } else {
                TimelineNSView(
                    timelineVM: timelineVM,
                    playerVM: playerVM,
                    mediaFiles: mediaFiles
                )
            }
        }
    }

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
    }
}
