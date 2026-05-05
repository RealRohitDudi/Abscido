@preconcurrency import AppKit

/// Global NSEvent monitor that dispatches all keyboard shortcuts to coordinator actions.
///
/// ## Swift concurrency note
/// `NSEvent.addLocalMonitorForEvents` callbacks fire on the main thread but are NOT
/// automatically within `@MainActor` isolation. The idiomatic fix is to mark `dispatch`
/// `@MainActor` and enter isolation with `MainActor.assumeIsolated` at the call site.
/// This is safe because Apple guarantees local monitors fire on the main thread.
final class ShortcutEventHandler {
    private var monitor: Any?
    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func install() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent local monitors always fire on the main thread — safe to assume isolation.
            MainActor.assumeIsolated {
                self?.handleKeyEvent(event) ?? event
            }
        }
    }

    func uninstall() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    // MARK: - Handler (called inside MainActor.assumeIsolated, so @MainActor is satisfied)

    @MainActor
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let coordinator else { return event }

        // Let ShortcutRecorderNSView capture the keystroke for reassignment.
        if event.window?.firstResponder is ShortcutRecorderNSView { return event }

        guard let action = KeyboardShortcutManager.shared.action(for: event) else {
            return event
        }

        // When the transcript / a text control is focused, send only keystrokes through that
        // genuinely belong to editing (⌘CXV/A, arrows, undo, etc.). Timeline and other app
        // shortcuts (⌘⇧T add track, ⌘⌥T, zoom, link clips, ⌘Return compile, ⌘S save…) still dispatch.
        if passesToFocusedTextResponder(action, coordinator: coordinator, window: event.window) {
            return event
        }

        return dispatch(action: action, coordinator: coordinator) ? nil : event
    }

    /// When `NSTextView` / `NSTextField` is first responder, return true to leave the event for text editing.
    @MainActor
    private func passesToFocusedTextResponder(_ action: ShortcutAction, coordinator: AppCoordinator, window: NSWindow?) -> Bool {
        guard let fr = window?.firstResponder else { return false }
        guard fr is NSTextView || fr is NSTextField else { return false }

        switch action {
        case .cutClips, .copyClips, .pasteClips, .selectAll:
            return true
        case .undo, .redo:
            return true
        case .deleteClips:
            return coordinator.timelineVM.selectedClipIds.isEmpty
        case .playPause,
             .stepForward, .stepBackward,
             .shuttleForward, .shuttleReverse, .shuttlePause,
             .goToStart, .goToEnd:
            return true
        // Prefer standard text-control semantics while typing (timeline uses these only after clicking the timeline).
        case .importMedia, .exportDialog, .compileEdit, .zoomIn, .zoomOut:
            return true
        case .razorAtPlayhead, .rippleTrimStartToPlayhead, .rippleTrimEndToPlayhead:
            return true
        default:
            return false
        }
    }

    // MARK: - Dispatch

    @MainActor
    private func dispatch(action: ShortcutAction, coordinator: AppCoordinator) -> Bool {
        switch action {

        // MARK: Transport
        case .playPause:
            coordinator.playerVM.togglePlayPause()
        case .stepForward:
            coordinator.playerVM.stepForward()
        case .stepBackward:
            coordinator.playerVM.stepBackward()
        case .shuttleForward:
            coordinator.playerVM.shuttleForward()
        case .shuttleReverse:
            coordinator.playerVM.shuttleReverse()
        case .shuttlePause:
            coordinator.playerVM.shuttlePause()
        case .goToStart:
            coordinator.playerVM.seek(to: 0)
        case .goToEnd:
            coordinator.playerVM.seek(to: coordinator.playerVM.durationMs)

        // MARK: Editing
        case .cutClips:
            coordinator.timelineVM.cutSelected()
        case .copyClips:
            coordinator.timelineVM.copySelected()
        case .pasteClips:
            coordinator.timelineVM.pasteAtPlayhead()
        case .deleteClips:
            if !coordinator.timelineVM.selectedClipIds.isEmpty {
                coordinator.timelineVM.deleteSelected()
            } else {
                return false // Pass through so transcript word deletion can handle it
            }
        case .linkClips:
            coordinator.timelineVM.linkSelected()
        case .unlinkClips:
            coordinator.timelineVM.unlinkSelected()
        case .selectAll:
            coordinator.selectAllWords()
        case .razorAtPlayhead:
            coordinator.timelineVM.razorAtPlayhead()
        case .rippleTrimStartToPlayhead:
            coordinator.timelineVM.rippleTrimStartToPlayhead()
        case .rippleTrimEndToPlayhead:
            coordinator.timelineVM.rippleTrimEndToPlayhead()

        // MARK: View
        case .zoomIn:
            coordinator.zoomInTimeline()
        case .zoomOut:
            coordinator.zoomOutTimeline()

        // MARK: Tracks
        case .addVideoTrack:
            coordinator.timelineVM.addTrack(kind: .video)
        case .addAudioTrack:
            coordinator.timelineVM.addTrack(kind: .audio)

        // MARK: File
        case .importMedia:
            coordinator.showImportPanel = true
        case .saveProject:
            coordinator.saveProject()
        case .compileEdit:
            coordinator.compileEdit()
        case .exportDialog:
            coordinator.showExport = true
        case .xmlExport:
            coordinator.showXmlExport = true
        case .edlExport:
            coordinator.presentEDLExport()

        // MARK: History
        case .undo:
            _ = coordinator.transcriptVM.undo()
        case .redo:
            _ = coordinator.transcriptVM.redo()
        }

        return true
    }
}
