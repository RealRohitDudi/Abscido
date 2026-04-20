import SwiftUI

/// macOS toolbar commands for the workspace.
struct ToolbarView: ViewModifier {
    @Bindable var projectVM: ProjectViewModel
    @Bindable var transcriptVM: TranscriptViewModel
    var onImport: () -> Void
    var onTranscribe: () -> Void
    var onBadTakes: () -> Void
    var onCompile: () -> Void
    var onExport: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: onImport) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import Media (⌘I)")
                }

                ToolbarItemGroup(placement: .principal) {
                    Text("Abscido")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.486, green: 0.424, blue: 0.980))
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: onTranscribe) {
                        Label("Transcribe", systemImage: "waveform")
                    }
                    .disabled(projectVM.mediaFiles.isEmpty || transcriptVM.isTranscribing)
                    .help("Transcribe Media")

                    Button(action: onBadTakes) {
                        Label("✦ Bad Takes", systemImage: "sparkles")
                    }
                    .disabled(!transcriptVM.hasTranscript)
                    .help("AI: Remove Bad Takes")

                    Button(action: onCompile) {
                        Label("Compile", systemImage: "film.stack")
                    }
                    .disabled(!transcriptVM.hasTranscript)
                    .help("Compile Edit (⌘↩)")

                    Button(action: onExport) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!transcriptVM.hasTranscript)
                    .help("Export (⌘E)")
                }
            }
    }
}

extension View {
    func abscidoToolbar(
        projectVM: ProjectViewModel,
        transcriptVM: TranscriptViewModel,
        onImport: @escaping () -> Void,
        onTranscribe: @escaping () -> Void,
        onBadTakes: @escaping () -> Void,
        onCompile: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) -> some View {
        modifier(ToolbarView(
            projectVM: projectVM,
            transcriptVM: transcriptVM,
            onImport: onImport,
            onTranscribe: onTranscribe,
            onBadTakes: onBadTakes,
            onCompile: onCompile,
            onExport: onExport
        ))
    }
}
