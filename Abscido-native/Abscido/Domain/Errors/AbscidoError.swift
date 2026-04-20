import Foundation

enum AbscidoError: LocalizedError, Sendable {
    case mediaImportFailed(url: URL, underlying: String)
    case compositionBuildFailed(clipId: Int64, reason: String)
    case transcriptionFailed(clipId: Int64, pythonError: String)
    case modelNotDownloaded(modelName: String)
    case aiRequestFailed(statusCode: Int, body: String)
    case aiResponseMalformed(raw: String)
    case xmlExportFailed(format: String, reason: String)
    case keychainError(status: Int32)
    case databaseError(underlying: String)
    case bookmarkStale(url: URL)
    case exportFailed(reason: String)
    case fileNotFound(path: String)
    case pythonRuntimeMissing
    case noActiveProject
    case noMediaFiles
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .mediaImportFailed(let url, let underlying):
            return "Failed to import media file '\(url.lastPathComponent)': \(underlying)"
        case .compositionBuildFailed(let clipId, let reason):
            return "Failed to build composition for clip \(clipId): \(reason)"
        case .transcriptionFailed(let clipId, let pythonError):
            return "Transcription failed for clip \(clipId): \(pythonError)"
        case .modelNotDownloaded(let modelName):
            return "Model '\(modelName)' is not downloaded. It will be fetched on first use."
        case .aiRequestFailed(let statusCode, let body):
            return "AI request failed with status \(statusCode): \(body)"
        case .aiResponseMalformed(let raw):
            return "AI response could not be parsed: \(raw.prefix(200))"
        case .xmlExportFailed(let format, let reason):
            return "XML export (\(format)) failed: \(reason)"
        case .keychainError(let status):
            return "Keychain operation failed with status \(status)"
        case .databaseError(let underlying):
            return "Database error: \(underlying)"
        case .bookmarkStale(let url):
            return "Security bookmark for '\(url.lastPathComponent)' is stale. Please re-import the file."
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .pythonRuntimeMissing:
            return "Bundled Python runtime not found. Reinstall Abscido to fix this."
        case .noActiveProject:
            return "No active project. Create or open a project first."
        case .noMediaFiles:
            return "No media files in the current project."
        case .noTranscript:
            return "No transcript available. Transcribe the media first."
        }
    }
}
