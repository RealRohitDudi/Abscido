import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - NSViewRepresentable Wrapper

/// High-performance multi-track timeline using NSScrollView + CALayer.
/// Replaces SwiftUI ScrollView for smooth 60fps scrolling and native pinch-to-zoom.
struct TimelineNSView: NSViewRepresentable {
    @Bindable var timelineVM: TimelineViewModel
    @Bindable var playerVM: PlayerViewModel
    var mediaFiles: [MediaFile]

    func makeNSView(context: Context) -> TimelineScrollContainer {
        let container = TimelineScrollContainer()
        container.coordinator = context.coordinator
        context.coordinator.container = container
        context.coordinator.setup()
        return container
    }

    func updateNSView(_ nsView: TimelineScrollContainer, context: Context) {
        context.coordinator.syncFromViewModel()
    }

    func makeCoordinator() -> TimelineCoordinator {
        TimelineCoordinator(timelineVM: timelineVM, playerVM: playerVM, mediaFiles: mediaFiles)
    }
}

// MARK: - Scroll Container

/// Hosts the NSScrollView and handles pinch-to-zoom.
class TimelineScrollContainer: NSView {
    var coordinator: TimelineCoordinator?
    let scrollView = NSScrollView()
    let contentView = TimelineContentView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScrollView()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let clipView = NSClipView()
        clipView.drawsBackground = true
        clipView.backgroundColor = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
        scrollView.contentView = clipView

        scrollView.documentView = contentView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Magnification gesture for pinch-to-zoom
        let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        scrollView.addGestureRecognizer(magnifyGesture)

        // Register for drag-and-drop
        contentView.registerForDraggedTypes([.init("com.abscido.mediafile")])
    }

    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        coordinator?.handleMagnify(gesture)
    }

    override func layout() {
        super.layout()
        coordinator?.updateContentSize()
    }
}

// MARK: - Content View (draws tracks + clips via CALayers)

class TimelineContentView: NSView {
    weak var coordinator: TimelineCoordinator?

    let trackHeaderWidth: CGFloat = 60
    let trackHeight: CGFloat = 52
    let rulerHeight: CGFloat = 26
    let clipGap: CGFloat = 1

    // Layers
    private var rulerLayer = CALayer()
    private var playheadLayer = CALayer()
    private var trackLayers: [CALayer] = []
    private var headerLayers: [CALayer] = []
    private var dropIndicatorLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1).cgColor
        setupBaseLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBaseLayers()
    }

    private func setupBaseLayers() {
        guard let rootLayer = layer else { return }

        // Ruler
        rulerLayer.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor
        rootLayer.addSublayer(rulerLayer)

        // Playhead
        playheadLayer.backgroundColor = NSColor.white.cgColor
        playheadLayer.zPosition = 100
        rootLayer.addSublayer(playheadLayer)

        // Drop indicator
        dropIndicatorLayer.backgroundColor = NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 1).cgColor
        dropIndicatorLayer.isHidden = true
        dropIndicatorLayer.zPosition = 99
        dropIndicatorLayer.shadowColor = NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 0.6).cgColor
        dropIndicatorLayer.shadowRadius = 4
        dropIndicatorLayer.shadowOpacity = 1
        rootLayer.addSublayer(dropIndicatorLayer)
    }

    // MARK: - Rebuild all clip layers

    func rebuildLayers(tracks: [TimelineViewModel.TrackModel], pps: Double, waveformData: [Int64: [Float]]) {
        guard let rootLayer = layer else { return }

        // Remove old track and header layers
        trackLayers.forEach { $0.removeFromSuperlayer() }
        headerLayers.forEach { $0.removeFromSuperlayer() }
        trackLayers.removeAll()
        headerLayers.removeAll()

        let totalWidth = max(bounds.width, totalContentWidth(tracks: tracks, pps: pps))

        // Ruler
        rulerLayer.frame = CGRect(x: 0, y: 0, width: totalWidth, height: rulerHeight)
        rebuildRulerTicks(pps: pps, width: totalWidth)

        // Tracks
        for (index, track) in tracks.enumerated() {
            let trackY = rulerHeight + CGFloat(index) * trackHeight

            // Track header
            let header = makeTrackHeaderLayer(name: track.name, kind: track.kind, y: trackY)
            rootLayer.addSublayer(header)
            headerLayers.append(header)

            // Track background
            let trackBg = CALayer()
            trackBg.frame = CGRect(x: trackHeaderWidth, y: trackY, width: totalWidth - trackHeaderWidth, height: trackHeight)
            trackBg.backgroundColor = index % 2 == 0
                ? NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1).cgColor
                : NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1).cgColor

            // Divider line
            let divider = CALayer()
            divider.frame = CGRect(x: 0, y: trackHeight - 0.5, width: trackBg.frame.width, height: 0.5)
            divider.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
            trackBg.addSublayer(divider)

            rootLayer.addSublayer(trackBg)
            trackLayers.append(trackBg)

            // Clips
            for clip in track.clips {
                let clipX = CGFloat(clip.startMs / 1000.0 * pps)
                let clipW = max(2, CGFloat(clip.durationMs / 1000.0 * pps))
                let clipLayer = makeClipLayer(clip: clip, x: clipX, width: clipW, waveformData: waveformData)
                trackBg.addSublayer(clipLayer)
            }
        }

        // Playhead spans all tracks
        let totalHeight = rulerHeight + CGFloat(tracks.count) * trackHeight
        playheadLayer.frame = CGRect(x: trackHeaderWidth, y: 0, width: 1.5, height: totalHeight)

        // Drop indicator
        dropIndicatorLayer.frame = CGRect(x: 0, y: rulerHeight, width: 2, height: totalHeight - rulerHeight)
    }

    // MARK: - Update playhead position (lightweight — no re-layout)

    func updatePlayhead(ms: Double, pps: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x = trackHeaderWidth + CGFloat(ms / 1000.0 * pps)
        playheadLayer.frame.origin.x = x
        CATransaction.commit()
    }

    // MARK: - Clip Layer Factory

    private func makeClipLayer(clip: TimelineViewModel.TimelineClipModel, x: CGFloat, width: CGFloat, waveformData: [Int64: [Float]]) -> CALayer {
        let clipLayer = CALayer()
        clipLayer.frame = CGRect(x: x, y: 2, width: width, height: trackHeight - 4)
        clipLayer.cornerRadius = 4

        let color: NSColor
        switch clip.color {
        case .video:
            color = NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 1)
        case .audio:
            color = NSColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 1)
        case .gap:
            color = NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        }

        // Gradient fill
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = clipLayer.bounds
        gradientLayer.cornerRadius = 4
        gradientLayer.colors = [
            color.withAlphaComponent(0.35).cgColor,
            color.withAlphaComponent(0.15).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        clipLayer.addSublayer(gradientLayer)

        // Waveform
        if let samples = waveformData[clip.mediaFileId], !samples.isEmpty {
            let waveLayer = makeWaveformLayer(samples: samples, width: width, height: trackHeight - 4, color: color)
            clipLayer.addSublayer(waveLayer)
        }

        // Name label
        if width > 50 {
            let textLayer = CATextLayer()
            textLayer.frame = CGRect(x: 6, y: 4, width: min(width - 12, 200), height: 16)
            textLayer.string = clip.name
            textLayer.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            textLayer.fontSize = 10
            textLayer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            textLayer.backgroundColor = color.withAlphaComponent(0.6).cgColor
            textLayer.cornerRadius = 3
            textLayer.truncationMode = .end
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            clipLayer.addSublayer(textLayer)
        }

        // Selection border
        if clip.isSelected {
            clipLayer.borderColor = NSColor.white.cgColor
            clipLayer.borderWidth = 1.5
        } else {
            clipLayer.borderColor = color.withAlphaComponent(0.5).cgColor
            clipLayer.borderWidth = 0.5
        }

        // Store clip ID for hit testing
        clipLayer.name = clip.id

        return clipLayer
    }

    // MARK: - Waveform Layer

    private func makeWaveformLayer(samples: [Float], width: CGFloat, height: CGFloat, color: NSColor) -> CAShapeLayer {
        let waveLayer = CAShapeLayer()
        waveLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let path = CGMutablePath()
        let midY = height / 2
        let barWidth = max(0.5, width / CGFloat(samples.count))

        for (i, amplitude) in samples.enumerated() {
            let x = CGFloat(i) * barWidth
            let barH = CGFloat(amplitude) * height * 0.8
            path.addRect(CGRect(x: x, y: midY - barH / 2, width: max(0.3, barWidth - 0.3), height: max(0.3, barH)))
        }

        waveLayer.path = path
        waveLayer.fillColor = color.withAlphaComponent(0.3).cgColor
        return waveLayer
    }

    // MARK: - Ruler

    private func rebuildRulerTicks(pps: Double, width: CGFloat) {
        // Remove old tick sublayers
        rulerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let interval = rulerInterval(pps: pps)
        let totalSeconds = width / CGFloat(pps)
        var t: Double = 0

        while t <= Double(totalSeconds) {
            let x = CGFloat(t) * CGFloat(pps)
            let isMajor = t.truncatingRemainder(dividingBy: interval * 5) < 0.001

            let tick = CALayer()
            let tickH: CGFloat = isMajor ? 12 : 6
            tick.frame = CGRect(x: trackHeaderWidth + x, y: rulerHeight - tickH, width: 0.5, height: tickH)
            tick.backgroundColor = NSColor(white: 0.4, alpha: 0.4).cgColor
            rulerLayer.addSublayer(tick)

            if isMajor {
                let label = CATextLayer()
                label.frame = CGRect(x: trackHeaderWidth + x - 20, y: 2, width: 40, height: 14)
                label.string = TimecodeFormatter.formatShort(ms: t * 1000)
                label.fontSize = 9
                label.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
                label.foregroundColor = NSColor(white: 0.5, alpha: 0.6).cgColor
                label.alignmentMode = .center
                label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
                rulerLayer.addSublayer(label)
            }

            t += interval
        }
    }

    private func rulerInterval(pps: Double) -> Double {
        if pps > 200 { return 0.5 }
        if pps > 100 { return 1 }
        if pps > 50 { return 2 }
        if pps > 25 { return 5 }
        return 10
    }

    // MARK: - Track Header

    private func makeTrackHeaderLayer(name: String, kind: OTIOTrackKind, y: CGFloat) -> CALayer {
        let header = CALayer()
        header.frame = CGRect(x: 0, y: y, width: trackHeaderWidth, height: trackHeight)
        header.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1).cgColor

        let color: NSColor = kind == .video
            ? NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 1)
            : NSColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 1)

        // Color indicator
        let indicator = CALayer()
        indicator.frame = CGRect(x: 0, y: 4, width: 3, height: trackHeight - 8)
        indicator.backgroundColor = color.cgColor
        indicator.cornerRadius = 1.5
        header.addSublayer(indicator)

        // Track name
        let label = CATextLayer()
        label.frame = CGRect(x: 8, y: (trackHeight - 14) / 2, width: trackHeaderWidth - 12, height: 14)
        label.string = name
        label.fontSize = 11
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        header.addSublayer(label)

        // Divider
        let divider = CALayer()
        divider.frame = CGRect(x: 0, y: trackHeight - 0.5, width: trackHeaderWidth, height: 0.5)
        divider.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        header.addSublayer(divider)

        return header
    }

    // MARK: - Content Size

    func totalContentWidth(tracks: [TimelineViewModel.TrackModel], pps: Double) -> CGFloat {
        let maxMs = tracks.map { track in
            track.clips.map { $0.startMs + $0.durationMs }.max() ?? 0
        }.max() ?? 0
        return trackHeaderWidth + CGFloat(maxMs / 1000.0 * pps) + 200
    }

    func totalContentHeight(trackCount: Int) -> CGFloat {
        rulerHeight + CGFloat(trackCount) * trackHeight + 20
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        coordinator?.handleMouseDown(at: location, event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        coordinator?.handleRightClick(at: location, event: event, view: self)
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropIndicatorLayer.isHidden = false
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropIndicatorLayer.frame.origin.x = location.x
        dropIndicatorLayer.isHidden = false
        CATransaction.commit()
        return sender.draggingSourceOperationMask.contains(.generic) ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropIndicatorLayer.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropIndicatorLayer.isHidden = true
        let location = convert(sender.draggingLocation, from: nil)
        return coordinator?.handleDrop(at: location, info: sender) ?? false
    }
}

// MARK: - Coordinator

@MainActor
class TimelineCoordinator: NSObject {
    var timelineVM: TimelineViewModel
    var playerVM: PlayerViewModel
    var mediaFiles: [MediaFile]
    weak var container: TimelineScrollContainer?

    private var basePixelsPerSecond: Double = 100
    private var displayLink: CVDisplayLink?
    private var lastPlayheadMs: Double = -1

    init(timelineVM: TimelineViewModel, playerVM: PlayerViewModel, mediaFiles: [MediaFile]) {
        self.timelineVM = timelineVM
        self.playerVM = playerVM
        self.mediaFiles = mediaFiles
        super.init()
    }

    func setup() {
        guard let container = container else { return }
        container.contentView.coordinator = self
        syncFromViewModel()
    }

    // MARK: - Sync from ViewModel

    func syncFromViewModel() {
        guard let container = container else { return }
        let cv = container.contentView

        // Rebuild clip layers
        cv.rebuildLayers(
            tracks: timelineVM.tracks,
            pps: timelineVM.pixelsPerSecond,
            waveformData: timelineVM.waveformData
        )

        // Update content size
        updateContentSize()

        // Update playhead
        cv.updatePlayhead(ms: playerVM.currentTimeMs, pps: timelineVM.pixelsPerSecond)
    }

    func updateContentSize() {
        guard let container = container else { return }
        let cv = container.contentView
        let width = cv.totalContentWidth(tracks: timelineVM.tracks, pps: timelineVM.pixelsPerSecond)
        let height = cv.totalContentHeight(trackCount: timelineVM.tracks.count)
        cv.frame = NSRect(x: 0, y: 0, width: width, height: max(height, container.scrollView.frame.height))
    }

    // MARK: - Pinch-to-Zoom

    func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        switch gesture.state {
        case .began:
            basePixelsPerSecond = timelineVM.pixelsPerSecond
        case .changed:
            let newPps = basePixelsPerSecond * (1 + gesture.magnification)
            timelineVM.setZoom(newPps)
            syncFromViewModel()
        case .ended, .cancelled:
            basePixelsPerSecond = timelineVM.pixelsPerSecond
        default:
            break
        }
    }

    // MARK: - Click-to-Seek / Select

    func handleMouseDown(at location: CGPoint, event: NSEvent) {
        guard let container = container else { return }
        let cv = container.contentView

        // Check if clicking in a track area
        let trackIndex = Int((location.y - cv.rulerHeight) / cv.trackHeight)

        if location.x > cv.trackHeaderWidth {
            let clipX = location.x - cv.trackHeaderWidth

            // Check for clip hit
            if let clip = timelineVM.clipAt(trackIndex: trackIndex, x: clipX) {
                let exclusive = !event.modifierFlags.contains(.command)
                timelineVM.selectClip(clip.id, exclusive: exclusive)
                syncFromViewModel()
                return
            }

            // Click on empty area = seek
            let ms = timelineVM.xToMs(clipX)
            playerVM.seek(to: min(ms, timelineVM.totalDurationMs))
            timelineVM.clearSelection()
            syncFromViewModel()
        }
    }

    // MARK: - Right-Click Context Menu

    func handleRightClick(at location: CGPoint, event: NSEvent, view: NSView) {
        guard let container = container else { return }
        let cv = container.contentView
        let trackIndex = Int((location.y - cv.rulerHeight) / cv.trackHeight)
        let clipX = location.x - cv.trackHeaderWidth

        // Select the clip under cursor if not already selected
        if let clip = timelineVM.clipAt(trackIndex: trackIndex, x: clipX) {
            if !timelineVM.selectedClipIds.contains(clip.id) {
                timelineVM.selectClip(clip.id, exclusive: true)
                syncFromViewModel()
            }
        }

        let menu = buildContextMenu(hasSelection: !timelineVM.selectedClipIds.isEmpty)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func buildContextMenu(hasSelection: Bool) -> NSMenu {
        let menu = NSMenu()

        if hasSelection {
            menu.addItem(withTitle: "Cut", action: #selector(cutAction), keyEquivalent: "x").target = self
            menu.addItem(withTitle: "Copy", action: #selector(copyAction), keyEquivalent: "c").target = self
            menu.addItem(withTitle: "Paste", action: #selector(pasteAction), keyEquivalent: "v").target = self
            menu.addItem(withTitle: "Delete", action: #selector(deleteAction), keyEquivalent: "\u{08}").target = self
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Link", action: #selector(linkAction), keyEquivalent: "l").target = self
            menu.addItem(withTitle: "Unlink", action: #selector(unlinkAction), keyEquivalent: "L").target = self
        } else {
            menu.addItem(withTitle: "Paste", action: #selector(pasteAction), keyEquivalent: "v").target = self
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Add Video Track", action: #selector(addVideoTrack), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Add Audio Track", action: #selector(addAudioTrack), keyEquivalent: "").target = self

        return menu
    }

    @objc func cutAction() { timelineVM.cutSelected(); syncFromViewModel() }
    @objc func copyAction() { timelineVM.copySelected() }
    @objc func pasteAction() { timelineVM.pasteAtPlayhead(); syncFromViewModel() }
    @objc func deleteAction() { timelineVM.deleteSelected(); syncFromViewModel() }
    @objc func linkAction() { timelineVM.linkSelected(); syncFromViewModel() }
    @objc func unlinkAction() { timelineVM.unlinkSelected(); syncFromViewModel() }
    @objc func addVideoTrack() { timelineVM.addTrack(kind: .video); syncFromViewModel() }
    @objc func addAudioTrack() { timelineVM.addTrack(kind: .audio); syncFromViewModel() }

    // MARK: - Drop Handler

    func handleDrop(at location: CGPoint, info: NSDraggingInfo) -> Bool {
        guard let container = container else { return false }
        let cv = container.contentView

        guard let pasteboard = info.draggingPasteboard.data(forType: .init("com.abscido.mediafile")),
              let file = try? JSONDecoder().decode(MediaFile.self, from: pasteboard) else {
            return false
        }

        let clipX = location.x - cv.trackHeaderWidth
        let timeMs = timelineVM.xToMs(clipX)
        let isOverwrite = NSEvent.modifierFlags.contains(.option)

        if isOverwrite {
            timelineVM.overwriteMedia(file, atTimeMs: timeMs, allMediaFiles: mediaFiles)
        } else {
            timelineVM.insertMedia(file, atTimeMs: timeMs, allMediaFiles: mediaFiles)
        }

        // Sync will happen via updateNSView when VM updates
        return true
    }
}
