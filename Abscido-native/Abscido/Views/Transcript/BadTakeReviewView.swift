import SwiftUI

/// Slide-in panel for reviewing AI-detected bad takes.
struct BadTakeReviewView: View {
    @Bindable var aiVM: AIViewModel
    @Bindable var transcriptVM: TranscriptViewModel
    var selectedMediaFile: MediaFile?
    var onEditDecisionChanged: (EditDecision) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("✦ Bad Takes")
                        .font(.headline)
                    Text("\(aiVM.pendingTakes.count) remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { aiVM.closeReview() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(red: 0.141, green: 0.141, blue: 0.141))

            Divider()

            // Batch actions
            if aiVM.hasPendingTakes {
                HStack(spacing: 8) {
                    Button("Accept All") {
                        guard let file = selectedMediaFile else { return }
                        if let ed = aiVM.acceptAll(transcriptVM: transcriptVM, mediaFile: file) {
                            onEditDecisionChanged(ed)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .controlSize(.small)

                    Button("Reject All") {
                        aiVM.rejectAll(transcriptVM: transcriptVM)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Bad take list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(aiVM.badTakes) { take in
                        BadTakeCard(
                            take: take,
                            previewText: aiVM.previewText(for: take, words: transcriptVM.words),
                            onAccept: {
                                guard let file = selectedMediaFile else { return }
                                if let ed = aiVM.acceptBadTake(take, transcriptVM: transcriptVM, mediaFile: file) {
                                    onEditDecisionChanged(ed)
                                }
                            },
                            onReject: {
                                aiVM.rejectBadTake(take, transcriptVM: transcriptVM)
                            }
                        )
                    }
                }
                .padding(16)
            }

            if let error = aiVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
        .overlay(
            Rectangle()
                .frame(width: 0.5)
                .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18)),
            alignment: .leading
        )
    }
}

// MARK: - Bad Take Card

struct BadTakeCard: View {
    let take: BadTake
    let previewText: String
    var onAccept: () -> Void
    var onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(take.reason)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                statusIcon
            }

            Text(previewText)
                .font(.system(.caption, design: .default))
                .foregroundColor(.secondary)
                .lineLimit(2)

            if take.status == .pending {
                HStack(spacing: 8) {
                    Button(action: onAccept) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text("Accept")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .controlSize(.small)

                    Button(action: onReject) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                            Text("Reject")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.141, green: 0.141, blue: 0.141))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(red: 0.18, green: 0.18, blue: 0.18), lineWidth: 0.5)
        )
        .opacity(take.status == .rejected ? 0.5 : 1.0)
    }

    private var statusColor: Color {
        switch take.status {
        case .pending: return .orange
        case .accepted: return .green
        case .rejected: return .red
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch take.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.orange)
                .font(.caption)
        case .accepted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
}
