import SwiftUI
import Combine

/// CORE FEATURE: The transcript-as-timeline editor.
/// Renders words as individual views with custom FlowLayout for natural text wrapping.
/// NOT a TextEditor — each word is a clickable, selectable, highlightable View element.
struct TranscriptEditorView: View {
    @Bindable var transcriptVM: TranscriptViewModel
    @Bindable var playerVM: PlayerViewModel
    var onDeleteWords: () -> Void

    @State private var dragStartId: Int64?
    @State private var cancellable: AnyCancellable?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                if transcriptVM.isTranscribing {
                    transcribingView
                } else if transcriptVM.words.isEmpty {
                    emptyView
                } else {
                    transcriptContent(proxy: proxy)
                }
            }
        }
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
        .onAppear { setupTimeSync() }
        .onDisappear { cancellable?.cancel() }
    }

    // MARK: - Transcript Content

    @ViewBuilder
    private func transcriptContent(proxy: ScrollViewProxy) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(transcriptVM.segments) { segment in
                TranscriptSegmentView(
                    segment: segment,
                    words: wordsForSegment(segment),
                    selectedWordIds: transcriptVM.selectedWordIds,
                    playingWordId: transcriptVM.currentPlayingWordId,
                    onTapWord: handleTapWord,
                    onDragStart: { id in dragStartId = id },
                    onDragUpdate: { id in handleDragUpdate(id) }
                )
                .id(segment.id)
            }
        }
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
        if NSEvent.modifierFlags.contains(.shift), let lastSelected = transcriptVM.selectedWordIds.first {
            transcriptVM.selectRange(from: lastSelected, to: wordId)
        } else if NSEvent.modifierFlags.contains(.command) {
            transcriptVM.toggleWordSelection(wordId)
        } else {
            transcriptVM.selectWord(wordId)
            // Seek player to word start
            if let word = transcriptVM.words.first(where: { $0.id == wordId }) {
                playerVM.seek(to: word.startMs)
            }
        }
    }

    private func handleDragUpdate(_ wordId: Int64) {
        if let startId = dragStartId {
            transcriptVM.selectRange(from: startId, to: wordId)
        }
    }

    private func setupTimeSync() {
        cancellable = playerVM.timeStream
            .receive(on: DispatchQueue.main)
            .sink { [transcriptVM] timeMs in
                transcriptVM.updatePlayingWord(timeMs: timeMs)
            }
    }
}
