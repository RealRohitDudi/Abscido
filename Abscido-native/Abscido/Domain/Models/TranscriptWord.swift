import Foundation

struct TranscriptWord: Identifiable, Codable, Equatable, Sendable {
    var id: Int64
    var clipId: Int64
    var word: String
    var startMs: Double
    var endMs: Double
    var confidence: Double
    var speaker: String?
    var isDeleted: Bool
    var isBadTake: Bool
    var badTakeReason: String?

    var durationMs: Double {
        endMs - startMs
    }

    /// Returns true if this word's time range contains the given millisecond timestamp.
    func contains(timeMs: Double) -> Bool {
        timeMs >= startMs && timeMs < endMs
    }

    init(
        id: Int64 = 0,
        clipId: Int64,
        word: String,
        startMs: Double,
        endMs: Double,
        confidence: Double = 1.0,
        speaker: String? = nil,
        isDeleted: Bool = false,
        isBadTake: Bool = false,
        badTakeReason: String? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.word = word
        self.startMs = startMs
        self.endMs = endMs
        self.confidence = confidence
        self.speaker = speaker
        self.isDeleted = isDeleted
        self.isBadTake = isBadTake
        self.badTakeReason = badTakeReason
    }
}
