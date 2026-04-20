import SwiftUI

/// Word state determines visual appearance.
enum WordDisplayState {
    case normal
    case playing
    case deleted
    case badTake
    case badAccepted
    case selected
}

/// Single word view with state-based styling and interaction.
struct TranscriptWordView: View {
    let word: TranscriptWord
    let isSelected: Bool
    let isPlaying: Bool
    var onTap: (Int64) -> Void
    var onDragStart: (Int64) -> Void
    var onDragUpdate: (Int64) -> Void

    private var displayState: WordDisplayState {
        if word.isDeleted && word.isBadTake { return .badAccepted }
        if word.isDeleted { return .deleted }
        if word.isBadTake { return .badTake }
        if isSelected { return .selected }
        if isPlaying { return .playing }
        return .normal
    }

    var body: some View {
        Text(word.word)
            .font(.system(.body, design: .default))
            .modifier(WordStyleModifier(state: displayState))
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(word.id)
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        onDragUpdate(word.id)
                    }
                    .onEnded { _ in }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        onDragStart(word.id)
                    }
            )
            .id(word.id)
    }
}

// MARK: - Word Style Modifier

struct WordStyleModifier: ViewModifier {
    let state: WordDisplayState

    func body(content: Content) -> some View {
        switch state {
        case .normal:
            content
                .foregroundColor(.primary)
        case .playing:
            content
                .foregroundColor(Color(red: 0.486, green: 0.424, blue: 0.980))
                .underline(true, color: Color(red: 0.486, green: 0.424, blue: 0.980))
                .fontWeight(.medium)
        case .deleted:
            content
                .foregroundColor(.red.opacity(0.6))
                .strikethrough(true, color: .red.opacity(0.8))
        case .badTake:
            content
                .foregroundColor(.orange)
                .underline(true, pattern: .dashDot, color: .orange)
        case .badAccepted:
            content
                .foregroundColor(.red.opacity(0.5))
                .strikethrough(true, color: .red.opacity(0.7))
        case .selected:
            content
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.486, green: 0.424, blue: 0.980).opacity(0.4))
                )
        }
    }
}
