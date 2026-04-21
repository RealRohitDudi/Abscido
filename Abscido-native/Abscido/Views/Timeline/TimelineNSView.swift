import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - NSViewRepresentable Wrapper

/// High-performance multi-track timeline using NSScrollView + CALayer.
/// Replaces SwiftUI ScrollView for smooth 60fps scrolling and native pinch-to-zoom.
struct TimelineNSView: NSViewRepresentable {
    var timelineVM: TimelineViewModel
    var playerVM: PlayerViewModel
    var mediaFiles: [MediaFile]

    // Snapshot values for dirty-checking — only rebuild when these change
    var trackCount: Int
    var totalDurationMs: Double
    var pixelsPerSecond: Double
    var selectedClipIds: Set<String>

    init(timelineVM: TimelineViewModel, playerVM: PlayerViewModel, mediaFiles: [MediaFile]) {
        self.timelineVM = timelineVM
        self.playerVM = playerVM
        self.mediaFiles = mediaFiles
        self.trackCount = timelineVM.tracks.count
        self.totalDurationMs = timelineVM.totalDurationMs
        self.pixelsPerSecond = timelineVM.pixelsPerSecond
        self.selectedClipIds = timelineVM.selectedClipIds
    }

    func makeNSView(context: Context) -> TimelineScrollContainer {
        let container = TimelineScrollContainer()
        container.coordinator = context.coordinator
        context.coordinator.container = container
        context.coordinator.setup()
        return container
    }

    func updateNSView(_ nsView: TimelineScrollContainer, context: Context) {
        let coord = context.coordinator

        // Only rebuild layers if timeline structure or zoom changed
        let needsRebuild = coord.lastTrackCount != trackCount
            || coord.lastTotalDurationMs != totalDurationMs
            || coord.lastPixelsPerSecond != pixelsPerSecond
            || coord.lastSelectedClipIds != selectedClipIds

        if needsRebuild {
            coord.lastTrackCount = trackCount
            coord.lastTotalDurationMs = totalDurationMs
            coord.lastPixelsPerSecond = pixelsPerSecond
            coord.lastSelectedClipIds = selectedClipIds
            coord.rebuildLayers()
        }

        // Always update playhead — this is cheap (single CALayer position change)
        coord.updatePlayheadOnly()
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
        scrollView.usesPredominantAxisScrolling = true

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

        rulerLayer.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor
        rootLayer.addSublayer(rulerLayer)

        playheadLayer.backgroundColor = NSColor.white.cgColor
        playheadLayer.zPosition = 100
        rootLayer.addSublayer(playheadLayer)

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
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        guard let rootLayer = layer else { CATransaction.commit(); return }

        trackLayers.forEach { $0.removeFromSuperlayer() }
        headerLayers.forEach { $0.removeFromSuperlayer() }
        trackLayers.removeAll()
        headerLayers.removeAll()

        let totalWidth = max(bounds.width, totalContentWidth(tracks: tracks, pps: pps))

        rulerLayer.frame = CGRect(x: 0, y: 0, width: totalWidth, height: rulerHeight)
        rebuildRulerTicks(pps: pps, width: totalWidth)

        for (index, track) in tracks.enumerated() {
            let trackY = rulerHeight + CGFloat(index) * trackHeight

            let header = makeTrackHeaderLayer(name: track.name, kind: track.kind, y: trackY)
            rootLayer.addSublayer(header)
            headerLayers.append(header)

            let trackBg = CALayer()
            trackBg.frame = CGRect(x: trackHeaderWidth, y: trackY, width: totalWidth - trackHeaderWidth, height: trackHeight)
            trackBg.backgroundColor = index % 2 == 0
                ? NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1).cgColor
                : NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1).cgColor

            let divider = CALayer()
            divider.frame = CGRect(x: 0, y: trackHeight - 0.5, width: trackBg.frame.width, height: 0.5)
            divider.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
            trackBg.addSublayer(divider)

            rootLayer.addSublayer(trackBg)
            trackLayers.append(trackBg)

            for clip in track.clips {
                let clipX = CGFloat(clip.startMs / 1000.0 * pps)
                let clipW = max(2, CGFloat(clip.durationMs / 1000.0 * pps))
                let clipLayer = makeClipLayer(clip: clip, x: clipX, width: clipW, waveformData: waveformData)
                trackBg.addSublayer(clipLayer)
            }
        }

        let totalHeight = rulerHeight + CGFloat(tracks.count) * trackHeight
        playheadLayer.frame = CGRect(x: trackHeaderWidth, y: 0, width: 1.5, height: totalHeight)
        dropIndicatorLayer.frame = CGRect(x: 0, y: rulerHeight, width: 2, height: totalHeight - rulerHeight)

        CATransaction.commit()
    }

    // MARK: - Update playhead position (lightweight — no re-layout)

    func updatePlayhead(ms: Double, pps: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playheadLayer.frame.origin.x = trackHeaderWidth + CGFloat(ms / 1000.0 * pps)
        CATransaction.commit()
    }

    // MARK: - Clip Layer Factory

    private func makeClipLayer(clip: TimelineViewModel.TimelineClipModel, x: CGFloat, width: CGFloat, waveformData: [Int64: [Float]]) -> CALayer {
        let clipLayer = CALayer()
        clipLayer.frame = CGRect(x: x, y: 2, width: width, height: trackHeight - 4)
        clipLayer.cornerRadius = 4

        let color: NSColor
        switch clip.color {
        case .video: color = NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 1)
        case .audio: color = NSColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 1)
        case .gap: color = NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        }

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

        if let samples = waveformData[clip.mediaFileId], !samples.isEmpty {
            let waveLayer = makeWaveformLayer(samples: samples, width: width, height: trackHeight - 4, color: color)
            clipLayer.addSublayer(waveLayer)
        }

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

        if clip.isSelected {
            clipLayer.borderColor = NSColor.white.cgColor
            clipLayer.borderWidth = 1.5
        } else {
            clipLayer.borderColor = color.withAlphaComponent(0.5).cgColor
            clipLayer.borderWidth = 0.5
        }

        clipLayer.name = clip.id
        return clipLayer
    }

    // MARK: - Waveform Layer

    private func makeWaveformLayer(samples: [Float], width: CGFloat, height: CGFloat, color: NSColor) -> CAShapeLayer {
        let waveLayer = CAShapeLayer()
        waveLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let path = CGMutablePath()
        let midY = height / 2
        // Downsample for rendering — max 1 bar per 2 pixels
        let maxBars = Int(width / 2)
        let stride = max(1, samples.count / max(1, maxBars))
        let barWidth = max(0.5, width / CGFloat(samples.count / stride))

        var barIndex = 0
        var i = 0
        while i < samples.count {
            var maxAmp: Float = 0
            for j in i..<min(i + stride, samples.count) {
                if samples[j] > maxAmp { maxAmp = samples[j] }
            }
            let x = CGFloat(barIndex) * barWidth
            let barH = CGFloat(maxAmp) * height * 0.8
            path.addRect(CGRect(x: x, y: midY - barH / 2, width: max(0.3, barWidth - 0.3), height: max(0.3, barH)))
            barIndex += 1
            i += stride
        }

        waveLayer.path = path
        waveLayer.fillColor = color.withAlphaComponent(0.3).cgColor
        return waveLayer
    }

    // MARK: - Ruler

    private func rebuildRulerTicks(pps: Double, width: CGFloat) {
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

        let indicator = CALayer()
        indicator.frame = CGRect(x: 0, y: 4, width: 3, height: trackHeight - 8)
        indicator.backgroundColor = color.cgColor
        indicator.cornerRadius = 1.5
        header.addSublayer(indicator)

        let label = CATextLayer()
        label.frame = CGRect(x: 8, y: (trackHeight - 14) / 2, width: trackHeaderWidth - 12, height: 14)
        label.string = name
        label.fontSize = 11
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        header.addSublayer(label)

        let divider = CALayer()
        divider.frame = CGRect(x: 0, y: trackHeight - 0.5, width: trackHeaderWidth, height: 0.5)
        divider.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        header.addSublayer(divider)

        return header
    }

    // MARK: - Content Size

    func totalContentWidth(tracks: [TimelineViewModel.TrackModel], pps: Double) -> CGFloat {
        let maxMs = tracks.map { $0.clips.map { $0.startMs + $0.durationMs }.max() ?? 0 }.max() ?? 0
        return trackHeaderWidth + CGFloat(maxMs / 1000.0 * pps) + 200
    }

    func totalContentHeight(trackCount: Int) -> CGFloat {
        rulerHeight + CGFloat(trackCount) * trackHeight + 20
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        coordinator?.handleMouseDown(at: convert(event.locationInWindow, from: nil), event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        coordinator?.handleRightClick(at: convert(event.locationInWindow, from: nil), event: event, view: self)
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropIndicatorLayer.isHidden = false
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropIndicatorLayer.frame.origin.x = convert(sender.draggingLocation, from: nil).x
        dropIndicatorLayer.isHidden = false
        CATransaction.commit()
        return sender.draggingSourceOperationMask.contains(.generic) ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropIndicatorLayer.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropIndicatorLayer.isHidden = true
        return coordinator?.handleDrop(at: convert(sender.draggingLocation, from: nil), info: sender) ?? false
    }
}

// MARK: - Coordinator

@MainActor
class TimelineCoordinator: NSObject {
    var timelineVM: TimelineViewModel
    var playerVM: PlayerViewModel
    var mediaFiles: [MediaFile]
    weak var container: TimelineScrollContainer?

    // Dirty tracking — only rebuild when these change
    var lastTrackCount: Int = -1
    var lastTotalDurationMs: Double = -1
    var lastPixelsPerSecond: Double = -1
    var lastSelectedClipIds: Set<String> = []

    private var basePixelsPerSecond: Double = 100
    private var timeObserverCancellable: AnyCancellable?

    init(timelineVM: TimelineViewModel, playerVM: PlayerViewModel, mediaFiles: [MediaFile]) {
        self.timelineVM = timelineVM
        self.playerVM = playerVM
        self.mediaFiles = mediaFiles
        super.init()
    }

    func setup() {
        guard let container = container else { return }
        container.contentView.coordinator = self

        // Subscribe to player time stream for lightweight playhead updates
        // This bypasses SwiftUI's observable system entirely
        timeObserverCancellable = playerVM.timeStream
            .receive(on: RunLoop.main)
            .sink { [weak self] ms in
                self?.container?.contentView.updatePlayhead(
                    ms: ms,
                    pps: self?.timelineVM.pixelsPerSecond ?? 100
                )
            }

        rebuildLayers()
    }

    // MARK: - Rebuild (expensive — only when data changes)

    func rebuildLayers() {
        guard let container = container else { return }
        container.contentView.rebuildLayers(
            tracks: timelineVM.tracks,
            pps: timelineVM.pixelsPerSecond,
            waveformData: timelineVM.waveformData
        )
        updateContentSize()
        updatePlayheadOnly()
    }

    // MARK: - Playhead update (cheap — every frame)

    func updatePlayheadOnly() {
        container?.contentView.updatePlayhead(
            ms: playerVM.currentTimeMs,
            pps: timelineVM.pixelsPerSecond
        )
    }

    func updateContentSize() {
        guard let container = container else { return }
        let cv = container.contentView
        let width = cv.totalContentWidth(tracks: timelineVM.tracks, pps: timelineVM.pixelsPerSecond)
        let height = cv.totalContentHeight(trackCount: timelineVM.tracks.count)
        let newFrame = NSRect(x: 0, y: 0, width: width, height: max(height, container.scrollView.frame.height))
        if cv.frame != newFrame {
            cv.frame = newFrame
        }
    }

    // MARK: - Pinch-to-Zoom

    func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        switch gesture.state {
        case .began:
            basePixelsPerSecond = timelineVM.pixelsPerSecond
        case .changed:
            let newPps = basePixelsPerSecond * (1 + gesture.magnification)
            timelineVM.setZoom(newPps)
            rebuildLayers()
        case .ended, .cancelled:
            basePixelsPerSecond = timelineVM.pixelsPerSecond
        default:
            break
        }
    }

    // MARK: - Click-to-Seek / Select

    func handleMouseDown(at location: CGPoint, event: NSEvent) {
        guard let cv = container?.contentView else { return }
        let trackIndex = Int((location.y - cv.rulerHeight) / cv.trackHeight)

        if location.x > cv.trackHeaderWidth {
            let clipX = location.x - cv.trackHeaderWidth
            if let clip = timelineVM.clipAt(trackIndex: trackIndex, x: clipX) {
                timelineVM.selectClip(clip.id, exclusive: !event.modifierFlags.contains(.command))
                rebuildLayers()
                return
            }
            let ms = timelineVM.xToMs(clipX)
            playerVM.seek(to: min(ms, timelineVM.totalDurationMs))
            timelineVM.clearSelection()
            rebuildLayers()
        }
    }

    // MARK: - Right-Click Context Menu

    func handleRightClick(at location: CGPoint, event: NSEvent, view: NSView) {
        guard let cv = container?.contentView else { return }
        let trackIndex = Int((location.y - cv.rulerHeight) / cv.trackHeight)
        let clipX = location.x - cv.trackHeaderWidth

        if let clip = timelineVM.clipAt(trackIndex: trackIndex, x: clipX),
           !timelineVM.selectedClipIds.contains(clip.id) {
            timelineVM.selectClip(clip.id, exclusive: true)
            rebuildLayers()
        }

        NSMenu.popUpContextMenu(buildContextMenu(hasSelection: !timelineVM.selectedClipIds.isEmpty), with: event, for: view)
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

    @objc func cutAction() { timelineVM.cutSelected(); rebuildLayers() }
    @objc func copyAction() { timelineVM.copySelected() }
    @objc func pasteAction() { timelineVM.pasteAtPlayhead(); rebuildLayers() }
    @objc func deleteAction() { timelineVM.deleteSelected(); rebuildLayers() }
    @objc func linkAction() { timelineVM.linkSelected(); rebuildLayers() }
    @objc func unlinkAction() { timelineVM.unlinkSelected(); rebuildLayers() }
    @objc func addVideoTrack() { timelineVM.addTrack(kind: .video); rebuildLayers() }
    @objc func addAudioTrack() { timelineVM.addTrack(kind: .audio); rebuildLayers() }

    // MARK: - Drop Handler

    func handleDrop(at location: CGPoint, info: NSDraggingInfo) -> Bool {
        guard let cv = container?.contentView else { return false }
        guard let pasteboard = info.draggingPasteboard.data(forType: .init("com.abscido.mediafile")),
              let file = try? JSONDecoder().decode(MediaFile.self, from: pasteboard) else { return false }

        let timeMs = timelineVM.xToMs(location.x - cv.trackHeaderWidth)
        if NSEvent.modifierFlags.contains(.option) {
            timelineVM.overwriteMedia(file, atTimeMs: timeMs, allMediaFiles: mediaFiles)
        } else {
            timelineVM.insertMedia(file, atTimeMs: timeMs, allMediaFiles: mediaFiles)
        }
        return true
    }
}
