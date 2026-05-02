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

        // Don't intercept keystrokes while the user is typing in a text field.
        if let responder = event.window?.firstResponder,
           responder is NSTextView || responder is NSTextField {
            return event
        }

        guard let action = KeyboardShortcutManager.shared.action(for: event) else {
            return event
        }

        return dispatch(action: action, coordinator: coordinator) ? nil : event
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

        // MARK: History
        case .undo:
            _ = coordinator.transcriptVM.undo()
        case .redo:
            _ = coordinator.transcriptVM.redo()
        }

        return true
    }
}
