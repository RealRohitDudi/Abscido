import SwiftUI

/// Root workspace layout — NavigationSplitView with 3 columns:
/// Sidebar: MediaBin | Content: Player + TranscribeBar + Timeline | Detail: Transcript
struct WorkspaceView: View {
    @State var projectVM: ProjectViewModel
    @State var transcriptVM: TranscriptViewModel
    @State var playerVM: PlayerViewModel
    @State var timelineVM: TimelineViewModel
    @State var aiVM: AIViewModel

    @State private var selectedMediaFileId: Int64?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: - Sidebar: Media Bin
            MediaBinView(
                mediaFiles: projectVM.mediaFiles,
                selectedId: $selectedMediaFileId,
                onRemove: { file in projectVM.removeMediaFile(file) }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            // MARK: - Content: Player + TranscribeBar + Timeline
            VSplitView {
                VStack(spacing: 0) {
                    PlayerView(player: playerVM.player)
                        .frame(minHeight: 200)

                    PlayerControlsView(playerVM: playerVM)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    // Transcribe buttons bar — stays below player controls
                    TranscriptToolbarView(
                        transcriptVM: transcriptVM,
                        aiVM: aiVM,
                        selectedMediaFile: selectedMediaFile,
                        onTranscribe: handleTranscribe
                    )
                }
                .frame(minHeight: 280)

                // Timeline — moved here from detail column
                TimelineView(
                    timelineVM: timelineVM,
                    playerVM: playerVM,
                    mediaFiles: projectVM.mediaFiles
                )
                .frame(minHeight: 150)
            }
        } detail: {
            // MARK: - Detail: Transcript Editor
            TranscriptEditorView(
                transcriptVM: transcriptVM,
                playerVM: playerVM,
                onDeleteWords: handleDeleteWords
            )
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .background(Color(red: 0.059, green: 0.059, blue: 0.059)) // #0f0f0f
        .preferredColorScheme(.dark)
        .overlay(alignment: .trailing) {
            if aiVM.isReviewPanelOpen {
                BadTakeReviewView(
                    aiVM: aiVM,
                    transcriptVM: transcriptVM,
                    selectedMediaFile: selectedMediaFile,
                    onEditDecisionChanged: handleEditDecisionChanged
                )
                .frame(width: 320)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: aiVM.isReviewPanelOpen)
        .onChange(of: selectedMediaFileId) { _, newId in
            if let id = newId, let file = projectVM.mediaFile(forId: id) {
                loadMediaFile(file)
            }
        }
        .onAppear {
            if let first = projectVM.mediaFiles.first {
                selectedMediaFileId = first.id
                loadMediaFile(first)
            }
        }
    }

    // MARK: - Computed

    private var selectedMediaFile: MediaFile? {
        guard let id = selectedMediaFileId else { return nil }
        return projectVM.mediaFile(forId: id)
    }

    // MARK: - Actions

    private func loadMediaFile(_ file: MediaFile) {
        Task {
            await playerVM.loadMedia(url: file.url)
            transcriptVM.loadTranscript(clipId: file.id)
            timelineVM.buildInitial(mediaFiles: projectVM.mediaFiles)
        }
    }

    private func handleTranscribe() {
        guard let file = selectedMediaFile else { return }
        transcriptVM.transcribe(mediaFile: file)
    }

    private func handleDeleteWords() {
        guard let file = selectedMediaFile else { return }
        if let editDecision = transcriptVM.deleteSelectedWords(mediaFile: file) {
            rebuildComposition(editDecision: editDecision)
        }
    }

    private func handleEditDecisionChanged(_ editDecision: EditDecision) {
        rebuildComposition(editDecision: editDecision)
    }

    private func rebuildComposition(editDecision: EditDecision) {
        let allDecisions = transcriptVM.computeAllEditDecisions(
            mediaFiles: projectVM.mediaFiles
        )
        timelineVM.rebuild(editDecisions: allDecisions, mediaFiles: projectVM.mediaFiles)

        Task {
            let composition = try await CompositionBuilder.build(
                from: allDecisions,
                mediaFiles: projectVM.mediaFiles
            )
            playerVM.loadComposition(composition)
        }
    }
}
