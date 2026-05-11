import SwiftUI
import Combine

/// CORE FEATURE: The transcript-as-timeline editor.
/// Renders words as individual views with custom FlowLayout for natural text wrapping.
/// NOT a TextEditor — each word is an individual SwiftUI View for selection and playback sync.
struct TranscriptEditorView: View {
    @Bindable var transcriptVM: TranscriptViewModel
    @Bindable var playerVM: PlayerViewModel
    @Bindable var timelineVM: TimelineViewModel
    var onDeleteWords: () -> Void

    @State private var cancellable: AnyCancellable?

    private static let transcriptScrollSpace = "transcriptScrollContent"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                if transcriptVM.isTranscribing {
                    transcribingView
                } else if transcriptVM.words.isEmpty {
                    emptyView
                } else {
                    transcriptScrollBody(proxy: proxy)
                }
            }
        }
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
        .onAppear {
            setupTimeSync()
            syncTranscriptHighlightToTimeline()
        }
        .onDisappear { cancellable?.cancel() }
        .onChange(of: transcriptVM.selectedWordIds) { _, _ in
            syncTranscriptHighlightToTimeline()
        }
        .onChange(of: transcriptVM.words) { _, _ in
            syncTranscriptHighlightToTimeline()
        }
        .onChange(of: timelineVM.timelineStructureRevision) { _, _ in
            syncTranscriptHighlightToTimeline()
        }
    }

    private func syncTranscriptHighlightToTimeline() {
        timelineVM.updateTranscriptSelectionHighlight(
            words: transcriptVM.words,
            selectedWordIds: transcriptVM.selectedWordIds
        )
    }

    // MARK: - Transcript Content

    @ViewBuilder
    private func transcriptScrollBody(proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .topLeading) {
            // Tap below / beside wrapped text to clear selection (words sit in a layer above).
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 560)
                .onTapGesture {
                    transcriptVM.clearSelection()
                    syncTranscriptHighlightToTimeline()
                }

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(transcriptVM.segments) { segment in
                    let segWords = wordsForSegment(segment)
                    TranscriptSegmentView(
                        segment: segment,
                        words: segWords,
                        selectedWordIds: transcriptVM.selectedWordIds,
                        playingWordId: transcriptVM.currentPlayingWordId,
                        transcriptCoordinateSpace: Self.transcriptScrollSpace,
                        segmentWordIds: Set(segWords.map(\.id)),
                        onTapWord: handleTapWord,
                        onDragSelectRange: { startId, endId in
                            transcriptVM.applyDragSelection(startWordId: startId, endWordId: endId)
                        }
                    )
                    .id(segment.id)
                }
            }
        }
        .coordinateSpace(name: Self.transcriptScrollSpace)
        .padding(16)
        .onChange(of: transcriptVM.currentPlayingWordId) { _, newId in
            if let wordId = newId,
               let word = transcriptVM.words.first(where: { $0.id == wordId }),
               let segment = transcriptVM.segments.first(where: {
                   word.startMs >= $0.startMs && word.endMs <= $0.endMs
               }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(segment.id, anchor: .center)
                }
            }
        }
    }

    // MARK: - States

    private var transcribingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: transcriptVM.transcriptionProgress)
                .tint(Color(red: 0.486, green: 0.424, blue: 0.980))
                .frame(width: 200)

            Text("Transcribing... \(Int(transcriptVM.transcriptionProgress * 100))%")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No transcript")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Click Transcribe to generate word-level transcript")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func wordsForSegment(_ segment: TranscriptSegment) -> [TranscriptWord] {
        transcriptVM.words.filter { word in
            word.clipId == segment.clipId &&
            word.startMs >= segment.startMs &&
            word.endMs <= segment.endMs
        }
    }

    private func handleTapWord(_ wordId: Int64) {
        if NSEvent.modifierFlags.contains(.shift) {
            let pivot = transcriptVM.selectionAnchorWordId ?? wordId
            transcriptVM.selectRange(from: pivot, to: wordId)
        } else if NSEvent.modifierFlags.contains(.command) {
            transcriptVM.toggleWordSelection(wordId)
        } else {
            transcriptVM.selectWord(wordId)
            if let word = transcriptVM.words.first(where: { $0.id == wordId }) {
                let seekMs = playerVM.timelinePlayheadTracksProgramTime
                    ? timelineVM.programTimeMs(forSourceTimeMs: word.startMs, mediaFileId: word.clipId) ?? word.startMs
                    : word.startMs
                playerVM.seek(to: seekMs)
            }
        }
    }

    private func setupTimeSync() {
        cancellable = playerVM.timeStream
            .receive(on: DispatchQueue.main)
            .sink { [transcriptVM, playerVM, timelineVM] timeMs in
                guard playerVM.timelinePlayheadTracksProgramTime,
                      let clipId = transcriptVM.words.first?.clipId
                else {
                    transcriptVM.updatePlayingWord(timeMs: timeMs)
                    return
                }

                guard let sourceTimeMs = timelineVM.sourceTimeMs(
                    forProgramTimeMs: timeMs,
                    mediaFileId: clipId
                ) else {
                    transcriptVM.updatePlayingWord(timeMs: -1)
                    return
                }

                transcriptVM.updatePlayingWord(timeMs: sourceTimeMs)
            }
    }
}
