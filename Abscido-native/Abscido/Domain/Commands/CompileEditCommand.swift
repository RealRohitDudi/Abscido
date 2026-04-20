import Foundation

struct CompileEditCommand: Sendable {
    let projectName: String
    let editDecisions: [EditDecision]
    let mediaFiles: [MediaFile]

    /// Generates the output URL for the compiled ProRes intermediate.
    var outputURL: URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let exportDir = moviesDir.appendingPathComponent("Abscido Exports", isDirectory: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(projectName)_\(timestamp).mov"
        return exportDir.appendingPathComponent(filename)
    }

    /// Ensures the export directory exists.
    func prepareOutputDirectory() throws {
        let dir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
