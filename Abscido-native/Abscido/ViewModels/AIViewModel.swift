import Foundation

/// Manages the bad take detection and review workflow.
@MainActor
@Observable
final class AIViewModel {
    var badTakes: [BadTake] = []
    var isDetecting = false
    var isReviewPanelOpen = false
    var errorMessage: String?

    private let aiEngine = AIEngine()

    // MARK: - Computed

    var pendingTakes: [BadTake] {
        badTakes.filter { $0.status == .pending }
    }

    var acceptedTakes: [BadTake] {
        badTakes.filter { $0.status == .accepted }
    }

    var rejectedTakes: [BadTake] {
        badTakes.filter { $0.status == .rejected }
    }

    var hasPendingTakes: Bool {
        !pendingTakes.isEmpty
    }

    // MARK: - Detection

    /// Runs bad take detection on the transcript.
    func detectBadTakes(words: [TranscriptWord]) {
        isDetecting = true
        errorMessage = nil

        Task {
            do {
                let detected = try await aiEngine.detectBadTakes(words: words)
                badTakes = detected
                isReviewPanelOpen = !detected.isEmpty
                isDetecting = false
            } catch {
                errorMessage = error.localizedDescription
                isDetecting = false
            }
        }
    }

    // MARK: - Review Actions

    /// Accepts a bad take — marks its words for deletion.
    func acceptBadTake(
        _ take: BadTake,
        transcriptVM: TranscriptViewModel,
        mediaFile: MediaFile
    ) -> EditDecision? {
        guard let index = badTakes.firstIndex(where: { $0.id == take.id }) else { return nil }
        badTakes[index].status = .accepted

        let command = AcceptBadTakeCommand(badTake: take)
        _ = command.execute(on: &transcriptVM.words)

        return transcriptVM.computeEditDecision(mediaFile: mediaFile)
    }

    /// Rejects a bad take — restores its words to normal state.
    func rejectBadTake(_ take: BadTake, transcriptVM: TranscriptViewModel) {
        guard let index = badTakes.firstIndex(where: { $0.id == take.id }) else { return }
        badTakes[index].status = .rejected

        let command = AcceptBadTakeCommand(badTake: take)
        command.revert(on: &transcriptVM.words)
    }

    /// Accepts all pending bad takes.
    func acceptAll(
        transcriptVM: TranscriptViewModel,
        mediaFile: MediaFile
    ) -> EditDecision? {
        for i in badTakes.indices where badTakes[i].status == .pending {
            badTakes[i].status = .accepted
            let command = AcceptBadTakeCommand(badTake: badTakes[i])
            _ = command.execute(on: &transcriptVM.words)
        }
        return transcriptVM.computeEditDecision(mediaFile: mediaFile)
    }

    /// Rejects all pending bad takes.
    func rejectAll(transcriptVM: TranscriptViewModel) {
        for i in badTakes.indices where badTakes[i].status == .pending {
            badTakes[i].status = .rejected
        }
    }

    /// Gets a preview string for a bad take showing the first few words.
    func previewText(for take: BadTake, words: [TranscriptWord]) -> String {
        let takeWords = take.wordIds.compactMap { id in
            words.first { $0.id == id }
        }.sorted { $0.startMs < $1.startMs }

        if takeWords.count <= 6 {
            return takeWords.map(\.word).joined(separator: " ")
        }
        let first6 = takeWords.prefix(6).map(\.word).joined(separator: " ")
        return first6 + "..."
    }

    /// Closes the review panel.
    func closeReview() {
        isReviewPanelOpen = false
    }

    /// Clears all bad takes.
    func clear() {
        badTakes = []
        isReviewPanelOpen = false
        errorMessage = nil
    }
}
