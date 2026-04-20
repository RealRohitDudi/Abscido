import Foundation

struct AcceptBadTakeCommand: Sendable {
    let badTake: BadTake

    /// Marks all words belonging to this bad take as deleted and flagged.
    /// Returns the previous word states for undo.
    func execute(on words: inout [TranscriptWord]) -> [TranscriptWord] {
        let previousState = words
        let idSet = Set(badTake.wordIds)
        for index in words.indices {
            if idSet.contains(words[index].id) {
                words[index].isDeleted = true
                words[index].isBadTake = true
                words[index].badTakeReason = badTake.reason
            }
        }
        return previousState
    }

    /// Reverts the bad take acceptance — restores words to non-deleted state.
    func revert(on words: inout [TranscriptWord]) {
        let idSet = Set(badTake.wordIds)
        for index in words.indices {
            if idSet.contains(words[index].id) {
                words[index].isDeleted = false
                words[index].isBadTake = false
                words[index].badTakeReason = nil
            }
        }
    }
}
