import SwiftUI

/// Paragraph grouping of words with a custom FlowLayout for natural text wrapping.
struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let words: [TranscriptWord]
    let selectedWordIds: Set<Int64>
    let playingWordId: Int64?
    var onTapWord: (Int64) -> Void
    var onDragStart: (Int64) -> Void
    var onDragUpdate: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp label
            HStack(spacing: 6) {
                Text(TimecodeFormatter.formatShort(ms: segment.startMs))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))

                Rectangle()
                    .fill(Color(red: 0.18, green: 0.18, blue: 0.18))
                    .frame(height: 0.5)
            }

            // Word flow layout
            FlowLayout(spacing: 2) {
                ForEach(words) { word in
                    TranscriptWordView(
                        word: word,
                        isSelected: selectedWordIds.contains(word.id),
                        isPlaying: word.id == playingWordId,
                        onTap: onTapWord,
                        onDragStart: onDragStart,
                        onDragUpdate: onDragUpdate
                    )
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Custom FlowLayout (SwiftUI, no UIKit)

/// A layout that arranges its children in a flow pattern, wrapping to the next line
/// when the available width is exceeded. Built from scratch as required.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let position = result.positions[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                // Wrap to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, currentX)
        }

        let totalHeight = currentY + lineHeight
        return LayoutResult(
            size: CGSize(width: maxX, height: totalHeight),
            positions: positions
        )
    }
}
