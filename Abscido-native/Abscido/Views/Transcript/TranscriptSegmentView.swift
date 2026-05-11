import SwiftUI

/// Paragraph grouping of words with a custom FlowLayout for natural text wrapping.
struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let words: [TranscriptWord]
    let selectedWordIds: Set<Int64>
    let playingWordId: Int64?
    let transcriptCoordinateSpace: String
    /// Word IDs belonging to this segment — hit-testing ignores rects from other segments in the merged preference.
    let segmentWordIds: Set<Int64>
    var onTapWord: (Int64) -> Void
    var onDragSelectRange: (Int64, Int64) -> Void

    @State private var wordRects: [Int64: CGRect] = [:]
    @State private var dragExceededTapThreshold = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(TimecodeFormatter.formatShort(ms: segment.startMs))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))

                Rectangle()
                    .fill(Color(red: 0.18, green: 0.18, blue: 0.18))
                    .frame(height: 0.5)
            }

            FlowLayout(spacing: 2) {
                ForEach(words) { word in
                    TranscriptWordView(
                        word: word,
                        isSelected: selectedWordIds.contains(word.id),
                        isPlaying: word.id == playingWordId,
                        transcriptCoordinateSpace: transcriptCoordinateSpace
                    )
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(segmentDragGesture)
        }
        .padding(.horizontal, 4)
        .onPreferenceChange(TranscriptWordRectKey.self) { rects in
            wordRects = rects
        }
    }

    private var segmentDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(transcriptCoordinateSpace))
            .onChanged { value in
                let dist = hypot(value.translation.width, value.translation.height)
                if dist > 6 {
                    dragExceededTapThreshold = true
                }
                let startId = wordId(at: value.startLocation)
                let endId = wordId(at: value.location) ?? startId
                // Live marquee once the pointer moves enough, or as soon as we cross into another word.
                guard let s = startId, let e = endId else { return }
                if dist > 6 || s != e {
                    onDragSelectRange(s, e)
                }
            }
            .onEnded { value in
                let dist = hypot(value.translation.width, value.translation.height)
                let startW = wordId(at: value.startLocation)
                let endW = wordId(at: value.location)
                let crossedWords = startW != nil && endW != nil && startW != endW
                let treatAsMarquee = dragExceededTapThreshold || crossedWords
                if !treatAsMarquee, dist < 10, let w = startW {
                    onTapWord(w)
                }
                dragExceededTapThreshold = false
            }
    }

    /// Picks the word under `point` using rects from this segment only (same scroll coordinate space).
    private func wordId(at point: CGPoint) -> Int64? {
        let candidates = wordRects.filter { segmentWordIds.contains($0.key) }
        let hits = candidates.filter { $0.value.contains(point) }
        if hits.isEmpty { return nil }
        if hits.count == 1 { return hits.first?.key }
        return hits.min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height })?.key
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
