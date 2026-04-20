import SwiftUI

/// Toolbar above the transcript editor: language picker, transcribe button, AI button.
struct TranscriptToolbarView: View {
    @Bindable var transcriptVM: TranscriptViewModel
    @Bindable var aiVM: AIViewModel
    var selectedMediaFile: MediaFile?
    var onTranscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Language picker
            Picker("Language", selection: $transcriptVM.selectedLanguage) {
                ForEach(LanguageRegistry.languages) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Divider()
                .frame(height: 20)

            // Transcribe button
            Button(action: onTranscribe) {
                HStack(spacing: 4) {
                    if transcriptVM.isTranscribing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "waveform")
                            .font(.caption)
                    }
                    Text("Transcribe")
                        .font(.caption)
                }
            }
            .disabled(selectedMediaFile == nil || transcriptVM.isTranscribing)
            .buttonStyle(.bordered)
            .tint(Color(red: 0.486, green: 0.424, blue: 0.980))

            // AI Bad Takes button
            Button(action: {
                aiVM.detectBadTakes(words: transcriptVM.words)
            }) {
                HStack(spacing: 4) {
                    if aiVM.isDetecting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("✦")
                            .font(.caption)
                    }
                    Text("Bad Takes")
                        .font(.caption)
                }
            }
            .disabled(!transcriptVM.hasTranscript || aiVM.isDetecting)
            .buttonStyle(.bordered)

            Spacer()

            // Word count
            if transcriptVM.hasTranscript {
                HStack(spacing: 6) {
                    Text("\(transcriptVM.activeWords.count) words")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)

                    if transcriptVM.deletedCount > 0 {
                        Text("(\(transcriptVM.deletedCount) deleted)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }

            // Selection count
            if !transcriptVM.selectedWordIds.isEmpty {
                Text("\(transcriptVM.selectedWordIds.count) selected")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Color(red: 0.486, green: 0.424, blue: 0.980))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.141, green: 0.141, blue: 0.141))
    }
}
