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
        scrollView.usesPredominantAxisScrolling = false

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

        // Magnification gesture — on the container, not the scroll view
        let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(magnifyGesture)

        // Register for drag-and-drop
        contentView.registerForDraggedTypes([
            .init(UTType.abscidoMediaFile.identifier),
            .fileURL
        ])
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
    private var rulerCornerLayer = CALayer()

    override var isFlipped: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }

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

    private var playheadLineLayer = CALayer()
    private var playheadHandleLayer = CAShapeLayer()

    private func setupBaseLayers() {
        guard let rootLayer = layer else { return }

        rulerLayer.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor
        rulerLayer.zPosition = 50
        rootLayer.addSublayer(rulerLayer)

        playheadLayer.zPosition = 100
        
        playheadLineLayer.backgroundColor = NSColor.systemRed.cgColor
        playheadLayer.addSublayer(playheadLineLayer)
        
        playheadHandleLayer.fillColor = NSColor.systemRed.cgColor
        playheadLayer.addSublayer(playheadHandleLayer)
        
        rootLayer.addSublayer(playheadLayer)

        dropIndicatorLayer.backgroundColor = NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 1).cgColor
        dropIndicatorLayer.isHidden = true
        dropIndicatorLayer.zPosition = 99
        dropIndicatorLayer.shadowColor = NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 0.6).cgColor
        dropIndicatorLayer.shadowRadius = 4
        dropIndicatorLayer.shadowOpacity = 1
        rootLayer.addSublayer(dropIndicatorLayer)

        // Ruler corner (top-left) stays fixed over scroll
        rulerCornerLayer.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1).cgColor
        rulerCornerLayer.zPosition = 200
        rootLayer.addSublayer(rulerCornerLayer)
    }

    // MARK: - Rebuild all clip layers

    func rebuildLayers(tracks: [TimelineViewModel.TrackModel], trackHeights: [Int: CGFloat], pps: Double, waveformData: [Int64: [Float]]) {
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

        var currentY = rulerHeight

        for track in tracks {
            let tHeight = trackHeights[track.trackIndex] ?? trackHeight
            
            let header = makeTrackHeaderLayer(name: track.name, kind: track.kind, y: currentY, height: tHeight)
            rootLayer.addSublayer(header)
            headerLayers.append(header)

            let trackBg = CALayer()
            trackBg.frame = CGRect(x: trackHeaderWidth, y: currentY, width: totalWidth - trackHeaderWidth, height: tHeight)
            trackBg.backgroundColor = track.trackIndex % 2 == 0
                ? NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1).cgColor
                : NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1).cgColor

            let divider = CALayer()
            divider.frame = CGRect(x: 0, y: tHeight - 0.5, width: trackBg.frame.width, height: 0.5)
            divider.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
            trackBg.addSublayer(divider)

            rootLayer.addSublayer(trackBg)
            trackLayers.append(trackBg)

            for clip in track.clips {
                let clipX = CGFloat(clip.startMs / 1000.0 * pps)
                let clipW = max(2, CGFloat(clip.durationMs / 1000.0 * pps))
                let clipLayer = makeClipLayer(clip: clip, kind: track.kind, x: clipX, width: clipW, height: tHeight, waveformData: waveformData)
                trackBg.addSublayer(clipLayer)
            }
            
            currentY += tHeight
        }

        let totalHeight = currentY
        playheadLayer.frame = CGRect(x: trackHeaderWidth, y: 0, width: 14, height: totalHeight)
        playheadLineLayer.frame = CGRect(x: 6.5, y: 0, width: 1.5, height: totalHeight)
        
        // DaVinci Resolve style flag
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 14, y: 0))
        path.addLine(to: CGPoint(x: 14, y: 12))
        path.addLine(to: CGPoint(x: 7.25, y: 20))
        path.addLine(to: CGPoint(x: 0, y: 12))
        path.closeSubpath()
        playheadHandleLayer.path = path
        
        dropIndicatorLayer.frame = CGRect(x: 0, y: rulerHeight, width: 2, height: totalHeight - rulerHeight)
        rulerCornerLayer.frame = CGRect(x: 0, y: 0, width: trackHeaderWidth, height: rulerHeight)

        CATransaction.commit()
    }

    // MARK: - Update playhead position (lightweight — no re-layout)

    func updatePlayhead(ms: Double, pps: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playheadLayer.frame.origin.x = trackHeaderWidth + CGFloat(ms / 1000.0 * pps) - 7.25 // Center the handle
        CATransaction.commit()
    }

    // MARK: - Clip Layer Factory

    private func makeClipLayer(clip: TimelineViewModel.TimelineClipModel, kind: OTIOTrackKind, x: CGFloat, width: CGFloat, height: CGFloat, waveformData: [Int64: [Float]]) -> CALayer {
        let clipLayer = CALayer()
        clipLayer.frame = CGRect(x: x, y: 2, width: width, height: height - 4)
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

        if kind == .audio, let samples = waveformData[clip.mediaFileId], !samples.isEmpty {
            let waveLayer = makeWaveformLayer(samples: samples, width: width, height: height - 4, color: color)
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

    private func makeTrackHeaderLayer(name: String, kind: OTIOTrackKind, y: CGFloat, height: CGFloat) -> CALayer {
        let header = CALayer()
        header.frame = CGRect(x: 0, y: y, width: trackHeaderWidth, height: height)
        header.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1).cgColor
        header.zPosition = 150 // Above tracks/clips so headers float over scrolled content

        let color: NSColor = kind == .video
            ? NSColor(red: 0.486, green: 0.424, blue: 0.980, alpha: 1)
            : NSColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 1)

        let indicator = CALayer()
        indicator.frame = CGRect(x: 0, y: 4, width: 3, height: height - 8)
        indicator.backgroundColor = color.cgColor
        indicator.cornerRadius = 1.5
        header.addSublayer(indicator)

        let label = CATextLayer()
        label.frame = CGRect(x: 8, y: (height - 14) / 2, width: trackHeaderWidth - 12, height: 14)
        label.string = name
        label.fontSize = 11
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        header.addSublayer(label)

        let divider = CALayer()
        divider.frame = CGRect(x: 0, y: height - 0.5, width: trackHeaderWidth, height: 0.5)
        divider.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        header.addSublayer(divider)

        return header
    }

    /// Re-pins header layers and ruler corner to current scroll offset so they stay fixed.
    func pinHeaders(scrollX: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for header in headerLayers {
            header.frame.origin.x = scrollX
        }
        rulerCornerLayer.frame.origin.x = scrollX
        CATransaction.commit()
    }

    // MARK: - Content Size

    func totalContentWidth(tracks: [TimelineViewModel.TrackModel], pps: Double) -> CGFloat {
        let maxMs = tracks.map { $0.clips.map { $0.startMs + $0.durationMs }.max() ?? 0 }.max() ?? 0
        return trackHeaderWidth + CGFloat(maxMs / 1000.0 * pps) + 200
    }

    func totalContentHeight(tracks: [TimelineViewModel.TrackModel], trackHeights: [Int: CGFloat]) -> CGFloat {
        var total = rulerHeight
        for track in tracks {
            total += trackHeights[track.trackIndex] ?? trackHeight
        }
        return total + 20
    }

    // MARK: - Mouse Events

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let ta = trackingArea { addTrackingArea(ta) }
    }

    /// Called by AppKit's cursor-rect system — the reliable way to set cursors.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let coordinator = coordinator else { return }
        var currentY = rulerHeight
        for track in coordinator.timelineVM.tracks {
            let tHeight = coordinator.timelineVM.trackHeights[track.trackIndex] ?? trackHeight
            currentY += tHeight
            // 8-pt hit zone at the track boundary — full width of header area
            let resizeRect = CGRect(x: 0, y: currentY - 4, width: trackHeaderWidth, height: 8)
            addCursorRect(resizeRect, cursor: .resizeUpDown)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        coordinator?.cursorForLocation(loc).set()
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        coordinator?.cursorForLocation(loc).set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func magnify(with event: NSEvent) {
        coordinator?.handleMagnifyEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.handleMouseDown(at: convert(event.locationInWindow, from: nil), event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        coordinator?.handleMouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.handleMouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        coordinator?.handleRightClick(at: convert(event.locationInWindow, from: nil), event: event, view: self)
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard coordinator?.canAcceptDrop(from: sender) == true else { return [] }
        dropIndicatorLayer.isHidden = false
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard coordinator?.canAcceptDrop(from: sender) == true else { return [] }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropIndicatorLayer.frame.origin.x = convert(sender.draggingLocation, from: nil).x
        dropIndicatorLayer.isHidden = false
        CATransaction.commit()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropIndicatorLayer.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropIndicatorLayer.isHidden = true
        return coordinator?.handleDrop(at: convert(sender.draggingLocation, from: nil), info: sender) ?? false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
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
    private var currentPinchScale: Double = 1
    private var timeObserverCancellable: AnyCancellable?
    private var scrollObserver: NSObjectProtocol?

    init(timelineVM: TimelineViewModel, playerVM: PlayerViewModel, mediaFiles: [MediaFile]) {
        self.timelineVM = timelineVM
        self.playerVM = playerVM
        self.mediaFiles = mediaFiles
        super.init()
    }

    deinit {
        if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func setup() {
        guard let container = container else { return }
        container.contentView.coordinator = self

        // Subscribe to player time stream for lightweight playhead updates
        timeObserverCancellable = playerVM.timeStream
            .receive(on: RunLoop.main)
            .sink { [weak self] ms in
                self?.container?.contentView.updatePlayhead(
                    ms: ms,
                    pps: self?.timelineVM.pixelsPerSecond ?? 100
                )
            }

        // Observe horizontal scroll to pin headers in place
        container.scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: container.scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let cv = self.container?.scrollView.contentView else { return }
                let scrollX = cv.bounds.origin.x
                self.container?.contentView.pinHeaders(scrollX: scrollX)
            }
        }

        rebuildLayers()
    }

    // MARK: - Rebuild (expensive — only when data changes)

    func rebuildLayers() {
        guard let container = container else { return }
        container.contentView.rebuildLayers(
            tracks: timelineVM.tracks,
            trackHeights: timelineVM.trackHeights,
            pps: timelineVM.pixelsPerSecond,
            waveformData: timelineVM.waveformData
        )
        updateContentSize()
        updatePlayheadOnly()
        container.contentView.window?.invalidateCursorRects(for: container.contentView)
        // Re-pin headers after rebuild
        let scrollX = container.scrollView.contentView.bounds.origin.x
        container.contentView.pinHeaders(scrollX: scrollX)
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
        let contentHeight = cv.totalContentHeight(tracks: timelineVM.tracks, trackHeights: timelineVM.trackHeights)
        
        let targetHeight = max(contentHeight, container.scrollView.contentSize.height)
        let newFrame = NSRect(x: 0, y: 0, width: width, height: targetHeight)
        
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

    func handleMagnifyEvent(_ event: NSEvent) {
        if event.phase == .began {
            basePixelsPerSecond = timelineVM.pixelsPerSecond
            currentPinchScale = 1
        }

        // NSEvent magnification is delta per event; accumulate for smooth native pinch.
        currentPinchScale *= (1 + event.magnification)
        timelineVM.setZoom(basePixelsPerSecond * currentPinchScale)
        rebuildLayers()

        if event.phase == .ended || event.phase == .cancelled {
            basePixelsPerSecond = timelineVM.pixelsPerSecond
            currentPinchScale = 1
        }
    }

    // MARK: - Click-to-Seek / Select / Resize / Scrub

    var resizingTrackIndex: Int?
    var initialDragY: CGFloat?
    var initialTrackHeight: CGFloat?
    var isScrubbing: Bool = false

    func handleMouseDown(at location: CGPoint, event: NSEvent) {
        guard let cv = container?.contentView else { return }
        
        // ── Ruler area: start playhead scrubbing immediately ──────────────────
        if location.y < cv.rulerHeight {
            if location.x > cv.trackHeaderWidth {
                isScrubbing = true
                let clipX = location.x - cv.trackHeaderWidth
                let ms = min(timelineVM.xToMs(clipX), timelineVM.totalDurationMs)
                playerVM.seek(to: ms)
                cv.updatePlayhead(ms: ms, pps: timelineVM.pixelsPerSecond)
            }
            return
        }

        // ── Track area: find which track was clicked ───────────────────────────
        var currentY = cv.rulerHeight
        var foundTrackIndex = -1
        
        for track in timelineVM.tracks {
            let tHeight = timelineVM.trackHeights[track.trackIndex] ?? cv.trackHeight
            currentY += tHeight
            
            // Resize boundary hit (4-pt zone at bottom of header)
            if location.x <= cv.trackHeaderWidth && abs(location.y - currentY) < 4 {
                resizingTrackIndex = track.trackIndex
                initialDragY = location.y
                initialTrackHeight = tHeight
                NSCursor.resizeUpDown.push() // lock cursor for the full drag
                return
            }
            
            if location.y >= currentY - tHeight && location.y < currentY {
                foundTrackIndex = track.trackIndex
                if location.x <= cv.trackHeaderWidth { break }
            }
        }
        
        guard foundTrackIndex != -1 else { return }

        if location.x > cv.trackHeaderWidth {
            isScrubbing = true
            let clipX = location.x - cv.trackHeaderWidth
            
            if let clip = timelineVM.clipAt(trackIndex: foundTrackIndex, x: clipX) {
                timelineVM.selectClip(clip.id, exclusive: !event.modifierFlags.contains(.command))
            } else {
                timelineVM.clearSelection()
            }
            
            let ms = min(timelineVM.xToMs(clipX), timelineVM.totalDurationMs)
            playerVM.seek(to: ms)
            cv.updatePlayhead(ms: ms, pps: timelineVM.pixelsPerSecond)
            rebuildLayers()
        }
    }

    func handleMouseDragged(with event: NSEvent) {
        guard let cv = container?.contentView else { return }
        
        let loc = cv.convert(event.locationInWindow, from: nil)
        
        // ── Track resize ─────────────────────────────────────────────────────
        if let trackIndex = resizingTrackIndex,
           let startY = initialDragY,
           let startHeight = initialTrackHeight {
            
            let deltaY = loc.y - startY
            let newHeight = max(30, startHeight + deltaY)
            
            if timelineVM.trackHeights[trackIndex] != newHeight {
                timelineVM.trackHeights[trackIndex] = newHeight
                rebuildLayers()
            }
            return
        }
        
        // ── Playhead scrubbing ────────────────────────────────────────────────
        if isScrubbing && loc.x > cv.trackHeaderWidth {
            let clipX = loc.x - cv.trackHeaderWidth
            let ms = min(timelineVM.xToMs(clipX), timelineVM.totalDurationMs)
            // Update playhead layer instantly (don't wait for async seek callback)
            cv.updatePlayhead(ms: ms, pps: timelineVM.pixelsPerSecond)
            playerVM.seek(to: ms)
        }
    }

    func handleMouseUp(with event: NSEvent) {
        if resizingTrackIndex != nil {
            NSCursor.pop() // restore arrow after resize drag
        }
        resizingTrackIndex = nil
        initialDragY = nil
        initialTrackHeight = nil
        isScrubbing = false
        container?.contentView.window?.invalidateCursorRects(for: container!.contentView)
    }

    // MARK: - Cursor Hit Testing

    func cursorForLocation(_ location: CGPoint) -> NSCursor {
        guard let cv = container?.contentView else { return .arrow }

        // Track boundary resize handles (header edges).
        var currentY = cv.rulerHeight
        for track in timelineVM.tracks {
            currentY += timelineVM.trackHeights[track.trackIndex] ?? cv.trackHeight
            if location.x <= cv.trackHeaderWidth && abs(location.y - currentY) < 4 {
                return .resizeUpDown
            }
        }

        // Clip trim edges (left/right clip edges in track lanes).
        guard location.x > cv.trackHeaderWidth, location.y >= cv.rulerHeight else { return .arrow }
        let timelineX = location.x - cv.trackHeaderWidth
        let edgeThreshold: CGFloat = 4

        var laneBottomY = cv.rulerHeight
        for track in timelineVM.tracks {
            let tHeight = timelineVM.trackHeights[track.trackIndex] ?? cv.trackHeight
            laneBottomY += tHeight
            let trackTop = laneBottomY - tHeight
            let trackBottom = laneBottomY
            if location.y >= trackTop && location.y < trackBottom {
                for clip in track.clips where clip.color != .gap {
                    let clipStartX = CGFloat(clip.startMs / 1000.0 * timelineVM.pixelsPerSecond)
                    let clipEndX = CGFloat((clip.startMs + clip.durationMs) / 1000.0 * timelineVM.pixelsPerSecond)
                    if abs(timelineX - clipStartX) <= edgeThreshold || abs(timelineX - clipEndX) <= edgeThreshold {
                        return .resizeLeftRight
                    }
                }
                break
            }
        }

        return .arrow
    }

    // MARK: - Right-Click Context Menu

    func handleRightClick(at location: CGPoint, event: NSEvent, view: NSView) {
        guard let cv = container?.contentView else { return }
        
        // Find track index
        var currentY = cv.rulerHeight
        var foundTrackIndex = -1
        
        for track in timelineVM.tracks {
            let tHeight = timelineVM.trackHeights[track.trackIndex] ?? cv.trackHeight
            if location.y >= currentY && location.y < currentY + tHeight {
                foundTrackIndex = track.trackIndex
                break
            }
            currentY += tHeight
        }

        let clipX = location.x - cv.trackHeaderWidth

        if foundTrackIndex != -1,
           let clip = timelineVM.clipAt(trackIndex: foundTrackIndex, x: clipX),
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

        let dropX = max(0, location.x - cv.trackHeaderWidth)
        let timeMs = timelineVM.xToMs(dropX)
        var droppedFile: MediaFile?

        if let pasteboardData = info.draggingPasteboard.data(forType: .init(UTType.abscidoMediaFile.identifier)),
           let file = try? JSONDecoder().decode(MediaFile.self, from: pasteboardData) {
            droppedFile = file
        } else if let urlStr = info.draggingPasteboard.string(forType: .fileURL), let url = URL(string: urlStr) {
            droppedFile = mediaFiles.first { $0.url == url }
        } else if let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let first = urls.first {
            droppedFile = mediaFiles.first { $0.url == first }
        }
        
        guard let file = droppedFile else {
            print("Failed to read media file from pasteboard. Available types: \(info.draggingPasteboard.types ?? [])")
            return false
        }

        if NSEvent.modifierFlags.contains(.option) {
            timelineVM.insertMedia(file, atTimeMs: timeMs, allMediaFiles: mediaFiles)
        } else {
            timelineVM.overwriteMedia(file, atTimeMs: timeMs, allMediaFiles: mediaFiles)
        }
        rebuildLayers()
        return true
    }

    func canAcceptDrop(from info: NSDraggingInfo) -> Bool {
        let pb = info.draggingPasteboard
        if pb.data(forType: .init(UTType.abscidoMediaFile.identifier)) != nil {
            return true
        }
        if pb.string(forType: .fileURL) != nil {
            return true
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return true
        }
        return false
    }
}
