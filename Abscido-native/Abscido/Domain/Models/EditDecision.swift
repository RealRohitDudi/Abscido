import Foundation

struct TimeRangeMs: Codable, Equatable, Sendable {
    var startMs: Double
    var endMs: Double

    var durationMs: Double {
        endMs - startMs
    }

    init(startMs: Double, endMs: Double) {
        self.startMs = startMs
        self.endMs = endMs
    }
}

struct EditDecision: Identifiable, Codable, Equatable, Sendable {
    var id: Int64
    var clipId: Int64
    var mediaFilePath: String
    var keepRanges: [TimeRangeMs]

    var totalKeptDurationMs: Double {
        keepRanges.reduce(0.0) { $0 + $1.durationMs }
    }

    init(
        id: Int64 = 0,
        clipId: Int64,
        mediaFilePath: String,
        keepRanges: [TimeRangeMs]
    ) {
        self.id = id
        self.clipId = clipId
        self.mediaFilePath = mediaFilePath
        self.keepRanges = keepRanges
    }
}
