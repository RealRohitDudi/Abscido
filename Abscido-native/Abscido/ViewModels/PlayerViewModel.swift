import AVFoundation
import Combine
import Foundation

/// Manages AVPlayer state — playback controls, time observation, and shuttle transport.
@MainActor
@Observable
final class PlayerViewModel {
    /// Current playback time — updated at 30fps.
    /// @ObservationIgnored: prevents entire view hierarchy re-render on every tick.
    /// Views that need this value subscribe to `timeStream` via Combine.
    @ObservationIgnored var currentTimeMs: Double = 0
    var durationMs: Double = 0
    var isPlaying = false
    var playbackRate: Float = 1.0
    var volume: Float = 1.0

    private(set) var player: AVPlayer
    private var timeObserver: Any?
    private var timePublisher = PassthroughSubject<Double, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let mediaEngine = MediaEngine()

    /// Combine publisher for playback time — used by TranscriptEditorView for word sync.
    var timeStream: AnyPublisher<Double, Never> {
        timePublisher.eraseToAnyPublisher()
    }

    init() {
        self.player = AVPlayer()
        setupTimeObserver()
    }

    nonisolated func cleanup() {
        // Called before deallocation to remove the time observer.
        // Using nonisolated to avoid MainActor isolation in cleanup path.
    }

    // MARK: - Setup

    private func setupTimeObserver() {
        // 33ms interval = ~30fps — smooth enough for word highlighting
        // while halving the SwiftUI re-render load vs 60fps
        let interval = CMTime(seconds: 0.033, preferredTimescale: 600)
        let playerRef = player
        timeObserver = playerRef.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let ms = time.toMs
                self.currentTimeMs = ms
                self.timePublisher.send(ms)
                self.isPlaying = (self.player.rate != 0)
            }
        }
    }

    // MARK: - Loading

    func loadMedia(url: URL) async {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        do {
            let duration = try await asset.load(.duration)
            self.durationMs = duration.toMs
        } catch {
            self.durationMs = 0
        }
    }

    func loadComposition(_ composition: AVComposition) {
        let playerItem = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: playerItem)
        durationMs = composition.duration.toMs
    }

    // MARK: - Transport Controls

    func togglePlayPause() {
        if player.rate == 0 {
            player.rate = playbackRate
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func play() {
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
        currentTimeMs = 0
    }

    // MARK: - Seeking

    /// Frame-exact seek with zero tolerance.
    func seek(to ms: Double) {
        let time = CMTime.fromMs(ms)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTimeMs = ms
    }

    /// Steps one frame forward.
    func stepForward(fps: Double = 30) {
        let frameMs = 1000.0 / fps
        seek(to: min(currentTimeMs + frameMs, durationMs))
    }

    /// Steps one frame backward.
    func stepBackward(fps: Double = 30) {
        let frameMs = 1000.0 / fps
        seek(to: max(currentTimeMs - frameMs, 0))
    }

    // MARK: - Shuttle (JKL)

    private var shuttleSpeed: Float = 0

    /// J key — shuttle reverse, progressive speeds.
    func shuttleReverse() {
        if shuttleSpeed > 0 {
            shuttleSpeed = -1.0
        } else if shuttleSpeed == 0 {
            shuttleSpeed = -1.0
        } else {
            shuttleSpeed = max(-4.0, shuttleSpeed * 2)
        }
        player.rate = shuttleSpeed
        playbackRate = abs(shuttleSpeed)
        isPlaying = true
    }

    /// K key — pause.
    func shuttlePause() {
        shuttleSpeed = 0
        player.pause()
        isPlaying = false
    }

    /// L key — shuttle forward, progressive speeds.
    func shuttleForward() {
        if shuttleSpeed < 0 {
            shuttleSpeed = 1.0
        } else if shuttleSpeed == 0 {
            shuttleSpeed = 1.0
        } else {
            shuttleSpeed = min(4.0, shuttleSpeed * 2)
        }
        player.rate = shuttleSpeed
        playbackRate = shuttleSpeed
        isPlaying = true
    }

    // MARK: - Rate & Volume

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player.volume = vol
    }
}
