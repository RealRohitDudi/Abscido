import Foundation
import Combine

/// Root project state manager — owns the current project, media files, and coordinates persistence.
@MainActor
@Observable
final class ProjectViewModel {
    var currentProject: Project?
    var mediaFiles: [MediaFile] = []
    var isLoading = false
    var errorMessage: String?

    private let projectRepo = ProjectRepository()
    private let mediaRepo = MediaRepository()
    private let mediaEngine = MediaEngine()

    // MARK: - Project Management

    func createProject(name: String) {
        do {
            let project = try projectRepo.create(name: name)
            currentProject = project
            mediaFiles = []
            errorMessage = nil
        } catch {
            errorMessage = "Failed to create project: \(error.localizedDescription)"
        }
    }

    func loadProject(id: Int64) {
        do {
            guard let project = try projectRepo.fetch(id: id) else {
                errorMessage = "Project not found"
                return
            }
            currentProject = project
            mediaFiles = try mediaRepo.fetchAll(projectId: id)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load project: \(error.localizedDescription)"
        }
    }

    func loadAllProjects() -> [Project] {
        (try? projectRepo.fetchAll()) ?? []
    }

    func saveProject() {
        guard var project = currentProject else { return }
        project.updatedAt = Date()
        do {
            try projectRepo.update(project)
            currentProject = project
        } catch {
            errorMessage = "Failed to save project: \(error.localizedDescription)"
        }
    }

    func deleteProject(id: Int64) {
        do {
            try projectRepo.delete(id: id)
            if currentProject?.id == id {
                currentProject = nil
                mediaFiles = []
            }
        } catch {
            errorMessage = "Failed to delete project: \(error.localizedDescription)"
        }
    }

    // MARK: - Media Import

    func importMediaFiles(urls: [URL]) {
        guard let project = currentProject else {
            errorMessage = "No active project"
            return
        }

        isLoading = true
        Task {
            for url in urls {
                do {
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }

                    var file = try await mediaEngine.importFile(url, projectId: project.id)
                    file = try mediaRepo.create(file)
                    mediaFiles.append(file)
                } catch {
                    errorMessage = "Failed to import '\(url.lastPathComponent)': \(error.localizedDescription)"
                }
            }
            isLoading = false
        }
    }

    func removeMediaFile(_ file: MediaFile) {
        do {
            try mediaRepo.delete(id: file.id)
            mediaFiles.removeAll { $0.id == file.id }
        } catch {
            errorMessage = "Failed to remove file: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    func mediaFile(forId id: Int64) -> MediaFile? {
        mediaFiles.first { $0.id == id }
    }

    func clearError() {
        errorMessage = nil
    }
}
