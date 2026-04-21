import SwiftUI
import Combine

/// Transport controls, scrub slider, and playback rate display.
struct PlayerControlsView: View {
    @Bindable var playerVM: PlayerViewModel

    /// Local time state updated via Combine — avoids @Observable re-renders.
    @State private var displayTimeMs: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            // Scrub slider
            HStack(spacing: 8) {
                TimecodeView(ms: displayTimeMs, fps: 30)

                Slider(
                    value: Binding(
                        get: { displayTimeMs },
                        set: { playerVM.seek(to: $0) }
                    ),
                    in: 0...max(1, playerVM.durationMs)
                )
                .tint(Color(red: 0.486, green: 0.424, blue: 0.980))

                TimecodeView(ms: playerVM.durationMs, fps: 30)
            }

            // Transport buttons
            HStack(spacing: 16) {
                // JKL Shuttle
                Button(action: { playerVM.shuttleReverse() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Shuttle Reverse (J)")

                Button(action: { playerVM.stepBackward() }) {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Previous Frame (←)")

                Button(action: { playerVM.togglePlayPause() }) {
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(red: 0.486, green: 0.424, blue: 0.980))
                .help("Play/Pause (Space)")

                Button(action: { playerVM.stepForward() }) {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Next Frame (→)")

                Button(action: { playerVM.shuttleForward() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Shuttle Forward (L)")

                Spacer()

                // Playback rate
                Text("\(playerVM.playbackRate, specifier: "%.1f")x")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36)

                // Volume
                Image(systemName: playerVM.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { playerVM.volume },
                        set: { playerVM.setVolume($0) }
                    ),
                    in: 0...1
                )
                .frame(width: 80)
                .tint(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onReceive(playerVM.timeStream.throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)) { ms in
            displayTimeMs = ms
        }
        .onAppear {
            displayTimeMs = playerVM.currentTimeMs
        }
    }
}
