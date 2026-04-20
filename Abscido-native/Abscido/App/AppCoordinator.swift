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
    var errorMessage: String?

    let projectVM = ProjectViewModel()
    let transcriptVM = TranscriptViewModel()
    let playerVM = PlayerViewModel()
    let timelineVM = TimelineViewModel()
    let aiVM = AIViewModel()

    init() {
        // Auto-create a default project if none exists
        let projects = projectVM.loadAllProjects()
        if let first = projects.first {
            projectVM.loadProject(id: first.id)
        } else {
            projectVM.createProject(name: "Untitled Project")
        }
    }

    // MARK: - Coordinated Actions

    func saveProject() {
        projectVM.saveProject()
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
