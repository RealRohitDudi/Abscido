import SwiftUI
import Combine

/// Root coordinator — manages window state, shared actions, and error presentation.
@MainActor
@Observable
final class AppCoordinator {
    var showNewProject = false
    var showImportPanel = false
    var showExport = false
    var showXmlExport = false
    var showSettings = false
    var showKeyboardShortcuts = false
    var errorMessage: String?

    let projectVM = ProjectViewModel()
    let transcriptVM = TranscriptViewModel()
    let playerVM = PlayerViewModel()
    let timelineVM = TimelineViewModel()
    let aiVM = AIViewModel()

    /// Global shortcut event handler — installed on first window appear.
    private(set) var shortcutHandler: ShortcutEventHandler?

    init() {
        // Auto-create a default project if none exists
        let projects = projectVM.loadAllProjects()
        if let first = projects.first {
            projectVM.loadProject(id: first.id)
        } else {
            projectVM.createProject(name: "Untitled Project")
        }

        // Install global shortcut handler
        shortcutHandler = ShortcutEventHandler(coordinator: self)
        shortcutHandler?.install()

        // Every OTIO mutation (Q ripple-trim start, E ripple-trim end, razor, paste-at-playhead,
        // move/insert, link/unlink, gap delete, manual edge trim, etc.) calls
        // `timelineVM.onTimelineChanged`. Rebuilding the player composition from the current OTIO
        // timeline here keeps the AVPlayer aligned with what the user sees on the timeline —
        // otherwise a Q at playhead 3 s on a 10 s clip would shrink the clip to 7 s on the timeline
        // but the player would keep playing the raw asset's full 10 s, making it look like the
        // clip's TAIL got trimmed (the original `[0, 7s]` of source) instead of its HEAD.
        timelineVM.onTimelineChanged = { [weak self] in
            self?.rebuildPlayerCompositionFromTimeline()
            self?.persistCurrentTimelineJSON()
        }
    }

    private func rebuildPlayerCompositionFromTimeline() {
        let mediaFiles = projectVM.mediaFiles
        let programMs = timelineVM.playheadMs
        Task { [weak self] in
            guard let self else { return }
            guard let timeline = await self.timelineVM.otioEngine.currentTimeline() else { return }
            do {
                let composition = try await CompositionBuilder.build(
                    from: timeline,
                    mediaFiles: mediaFiles
                )
                await MainActor.run {
                    self.playerVM.loadComposition(composition)
                    // Replacing `currentItem` often resets playback time — restore the CTI so Q/E and
                    // other trims don't jump the playhead (e.g. to 0 or to a former seek target).
                    let dur = composition.duration.toMs
                    let clamped = min(max(0, programMs), max(0, dur))
                    self.playerVM.seek(to: clamped)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Serializes the OTIO bridge timeline into `projects.otio_json` (debounced by caller frequency).
    private func persistCurrentTimelineJSON() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let json = try await self.timelineVM.exportBridgeJSONForPersistence()
                await MainActor.run {
                    self.projectVM.persistOTIOTimelineJSON(json)
                }
            } catch {
                // Empty or invalid engine state — skip silently.
            }
        }
    }

    // MARK: - Coordinated Actions

    func saveProject() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let json = try await self.timelineVM.exportBridgeJSONForPersistence()
                await MainActor.run {
                    self.projectVM.persistOTIOTimelineJSON(json)
                    self.projectVM.saveProject()
                }
            } catch {
                await MainActor.run {
                    self.projectVM.saveProject()
                }
            }
        }
    }

    func selectAllWords() {
        transcriptVM.selectAll()
    }

    func compileEdit() {
        guard let project = projectVM.currentProject else { return }
        guard transcriptVM.hasTranscript else { return }

        let edl = transcriptVM.computeAllEditDecisions(mediaFiles: projectVM.mediaFiles)
        let command = CompileEditCommand(
            projectName: project.name,
            editDecisions: edl,
            mediaFiles: projectVM.mediaFiles
        )

        Task {
            do {
                try command.prepareOutputDirectory()

                let composition = try await CompositionBuilder.build(
                    from: edl,
                    mediaFiles: projectVM.mediaFiles
                )

                try await ExportSession.export(
                    composition: composition,
                    to: command.outputURL,
                    config: .highestQuality,
                    onProgress: { _ in }
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func importMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .movie, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2Video,
            .audio, .mp3, .wav, .aiff,
        ]

        if panel.runModal() == .OK {
            projectVM.importMediaFiles(urls: panel.urls)
        }
    }

    func zoomInTimeline() {
        timelineVM.zoomIn()
    }

    func zoomOutTimeline() {
        timelineVM.zoomOut()
    }

    func clearError() {
        errorMessage = nil
    }
}
