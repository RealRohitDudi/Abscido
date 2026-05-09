import SwiftUI

/// Toolbar above the transcript editor.
/// Contains: language picker, engine picker, model picker (WhisperKit), transcribe/cancel button,
/// AI button, word count, selection count, and an inline error banner.
struct TranscriptToolbarView: View {
    @Bindable var transcriptVM: TranscriptViewModel
    @Bindable var aiVM: AIViewModel
    /// Highlighted clip in the Media Bin (nil if none selected).
    var selectedMediaFile: MediaFile?
    /// Actual file used for transcription: selection, else first clip in bin.
    var transcribeTargetMedia: MediaFile?
    var mediaFileCount: Int
    var onTranscribe: () -> Void

    private var canTranscribe: Bool {
        transcribeTargetMedia != nil && !transcriptVM.isTranscribing
    }

    var body: some View {
        VStack(spacing: 0) {
            mainToolbar
            if let warning = nonEnglishModelWarning {
                warningBanner(message: warning)
            }
            if let error = transcriptVM.transcriptionError {
                errorBanner(message: error)
            }
        }
    }

    // MARK: - Non-English model warning

    /// `tiny` / `base` are auto-upgraded to `small` for non-English; explain when UI choice ≠ checkpoint used.
    private var nonEnglishModelWarning: String? {
        guard transcriptVM.selectedBackend == .whisperKit,
              !transcriptVM.isTranscribing,
              transcriptVM.selectedLanguage != "en"
        else { return nil }
        let code = LanguageRegistry.normalizedLanguageCode(transcriptVM.selectedLanguage) ?? "en"
        guard code != "en" else { return nil }
        let effective = WhisperKitModelSize.effectiveForTranscription(
            requested: transcriptVM.whisperKitModelSize,
            normalizedLanguageCode: code
        )
        guard effective != transcriptVM.whisperKitModelSize else { return nil }
        let langName = LanguageRegistry.language(forCode: transcriptVM.selectedLanguage)?.name
            ?? transcriptVM.selectedLanguage.uppercased()
        return "\(transcriptVM.whisperKitModelSize.shortLabel) cannot transcribe \(langName) reliably; this run uses the \(effective.shortLabel) Whisper checkpoint instead."
    }

    private func warningBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.yellow)

            Text(message)
                .font(.caption)
                .foregroundColor(Color(white: 0.9))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.27, green: 0.20, blue: 0.06))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.yellow.opacity(0.25)),
            alignment: .top
        )
    }

    // MARK: - Main Toolbar

    private var mainToolbar: some View {
        HStack(spacing: 8) {

            // Language picker
            Picker("Language", selection: $transcriptVM.selectedLanguage) {
                ForEach(LanguageRegistry.languages) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .help("Transcription language")

            // Engine picker
            Picker("Engine", selection: $transcriptVM.selectedBackend) {
                ForEach(TranscriptionBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 190)
            .help(enginePickerHelp)
            .disabled(transcriptVM.isTranscribing)

            // WhisperKit model size picker (only visible when WhisperKit is selected)
            if transcriptVM.selectedBackend == .whisperKit {
                Picker("Model", selection: $transcriptVM.whisperKitModelSize) {
                    ForEach(WhisperKitModelSize.allCases, id: \.self) { size in
                        Text(size.shortLabel).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .help(modelPickerHelp)
                .disabled(transcriptVM.isTranscribing)
                .transition(.opacity)
            }

            divider

            // Transcribe / Cancel button
            if transcriptVM.isTranscribing {
                cancelButton
            } else {
                transcribeCluster
            }

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
            .help("AI-powered bad take detection via Anthropic Claude")

            Spacer()

            statusLabels
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.141, green: 0.141, blue: 0.141))
        .animation(.easeInOut(duration: 0.15), value: transcriptVM.selectedBackend)
    }

    // MARK: - Help Strings

    private var enginePickerHelp: String {
        switch transcriptVM.selectedBackend {
        case .whisperKit:
            return "WhisperKit: on-device CoreML, no internet after first model download, no signing required. Recommended."
        case .appleSpeech:
            return "Apple Speech: built-in, fast, requires the binary to carry a speech entitlement — launch via ./scripts/run-with-speech-capability.sh."
        case .mlxWhisper:
            return "MLX-Whisper: Python subprocess (pip install mlx-whisper). Development only; blocked in sandboxed builds."
        }
    }

    private var modelPickerHelp: String {
        switch transcriptVM.whisperKitModelSize {
        case .tiny:         return "Tiny (~75 MB). Fastest, English-only quality. Will produce wrong-script output for Hindi / Arabic / CJK audio."
        case .base:         return "Base (~150 MB). Fast but English-only quality. Will produce wrong-script output for non-English audio."
        case .small:        return "Small (~480 MB). Minimum recommended for non-English transcription. Solid quality / speed balance."
        case .largeV3Turbo: return "Large v3 Turbo (~632 MB). Highest quality, ANE-accelerated. Recommended for Hindi, Arabic, CJK and any production work."
        }
    }

    // MARK: - Buttons

    private var transcribeCluster: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onTranscribe) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.caption)
                    Text("Transcribe")
                        .font(.caption)
                }
            }
            .disabled(!canTranscribe)
            .buttonStyle(.bordered)
            .tint(Color(red: 0.486, green: 0.424, blue: 0.980))
            .help(transcribeTooltip)

            if !transcriptVM.isTranscribing, mediaFileCount > 0, let target = transcribeTargetMedia {
                let usingFallbackSelection = selectedMediaFile == nil
                    || selectedMediaFile?.id != transcribeTargetMedia?.id

                Text(
                    usingFallbackSelection
                        ? "Target: \(target.url.lastPathComponent) (tap a clip to choose another)"
                        : "Target: \(target.url.lastPathComponent)"
                )
                .font(.system(.caption2, design: .default))
                .foregroundColor(.secondary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
    }

    private var transcribeTooltip: String {
        if mediaFileCount == 0 {
            return "Import media with ⌘I before transcribing."
        }
        if let target = transcribeTargetMedia {
            return "Generate a word-level transcript for \(target.url.lastPathComponent)."
        }
        return "Unable to resolve a clip to transcribe."
    }

    private var cancelButton: some View {
        Button(action: { transcriptVM.cancelTranscription() }) {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
                Text("\(Int(transcriptVM.transcriptionProgress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .help("Cancel transcription")
    }

    private var divider: some View {
        Divider()
            .frame(height: 20)
    }

    // MARK: - Status Labels

    private var statusLabels: some View {
        HStack(spacing: 8) {
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

            if !transcriptVM.selectedWordIds.isEmpty {
                Text("\(transcriptVM.selectedWordIds.count) selected")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Color(red: 0.486, green: 0.424, blue: 0.980))
            }

            if transcriptVM.hasTranscript {
                engineBadge
            }
        }
    }

    private var engineBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: badgeIcon)
                .font(.system(size: 8))
            Text(badgeLabel)
                .font(.system(.caption2, design: .monospaced))
        }
        .foregroundColor(.secondary.opacity(0.6))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help("Transcript was generated with \(transcriptVM.selectedBackend.displayName)")
    }

    private var badgeIcon: String {
        switch transcriptVM.selectedBackend {
        case .whisperKit:  return "cpu"
        case .appleSpeech: return "apple.logo"
        case .mlxWhisper:  return "bolt.fill"
        }
    }

    private var badgeLabel: String {
        let lang = transcriptVM.selectedLanguage.uppercased()
        switch transcriptVM.selectedBackend {
        case .whisperKit:
            let code = LanguageRegistry.normalizedLanguageCode(transcriptVM.selectedLanguage) ?? "en"
            let model = WhisperKitModelSize.effectiveForTranscription(
                requested: transcriptVM.whisperKitModelSize,
                normalizedLanguageCode: code
            )
            return "WK·\(model.shortLabel)·\(lang)"
        case .appleSpeech: return "Apple·\(lang)"
        case .mlxWhisper:  return "MLX·\(lang)"
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.yellow)

            Text(message)
                .font(.caption)
                .foregroundColor(Color(white: 0.9))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: { transcriptVM.clearTranscriptionError() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.35, green: 0.22, blue: 0.07))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.yellow.opacity(0.3)),
            alignment: .top
        )
    }
}
