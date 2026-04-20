import Foundation

struct BadTake: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var wordIds: [Int64]
    var reason: String
    var status: BadTakeStatus

    enum BadTakeStatus: String, Codable, Sendable {
        case pending
        case accepted
        case rejected
    }

    init(
        id: String = UUID().uuidString,
        wordIds: [Int64],
        reason: String,
        status: BadTakeStatus = .pending
    ) {
        self.id = id
        self.wordIds = wordIds
        self.reason = reason
        self.status = status
    }
}
