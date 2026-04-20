import Foundation

struct MediaFile: Identifiable, Codable, Equatable, Sendable {
    var id: Int64
    var projectId: Int64
    var filePath: String
    var bookmarkData: Data?
    var durationMs: Double
    var fps: Double
    var width: Int
    var height: Int
    var codec: String
    var thumbnailPath: String?
    var createdAt: Date

    var url: URL {
        URL(fileURLWithPath: filePath)
    }

    var formattedDuration: String {
        let totalSeconds = durationMs / 1000.0
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var resolution: String {
        "\(width)×\(height)"
    }

    init(
        id: Int64 = 0,
        projectId: Int64,
        filePath: String,
        bookmarkData: Data? = nil,
        durationMs: Double,
        fps: Double,
        width: Int,
        height: Int,
        codec: String,
        thumbnailPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.filePath = filePath
        self.bookmarkData = bookmarkData
        self.durationMs = durationMs
        self.fps = fps
        self.width = width
        self.height = height
        self.codec = codec
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
    }
}
