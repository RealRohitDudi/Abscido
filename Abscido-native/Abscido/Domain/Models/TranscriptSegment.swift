import Foundation

struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    var id: Int64
    var clipId: Int64
    var text: String
    var startMs: Double
    var endMs: Double
    var isDeleted: Bool

    var durationMs: Double {
        endMs - startMs
    }

    init(
        id: Int64 = 0,
        clipId: Int64,
        text: String,
        startMs: Double,
        endMs: Double,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.clipId = clipId
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.isDeleted = isDeleted
    }
}
