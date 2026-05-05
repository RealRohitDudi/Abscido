import SwiftUI

/// Export panel with render and XML export options.
struct ExportSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var projectVM: ProjectViewModel
    @Bindable var transcriptVM: TranscriptViewModel
    @Bindable var timelineVM: TimelineViewModel

    @State private var selectedPreset: RenderPipeline.Preset = .highQuality
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var showXmlPicker = false
    @State private var exportMessage: String?

    private let exportEngine = ExportEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("Export")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityLabel("Close export")
            }

            // Render export
            HStack(spacing: 12) {
                Picker("Preset", selection: $selectedPreset) {
                    ForEach(RenderPipeline.Preset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Button(action: startRenderExport) {
                    HStack(spacing: 4) {
                        Image(systemName: "film.stack")
                            .font(.caption)
                        Text("Render")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.486, green: 0.424, blue: 0.980))
                .disabled(isExporting || !transcriptVM.hasTranscript)
            }

            // XML export
            Button(action: { showXmlPicker = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                    Text("Export interchange…")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .disabled(projectVM.currentProject == nil)
            .sheet(isPresented: $showXmlPicker) {
                XmlFormatPicker(
                    projectName: projectVM.currentProject?.name ?? "Untitled",
                    onExport: handleXmlExport
                )
            }

            // Progress
            if isExporting {
                ProgressView(value: exportProgress)
                    .tint(Color(red: 0.486, green: 0.424, blue: 0.980))
                Text("Exporting... \(Int(exportProgress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let message = exportMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(message.contains("Error") ? .red : .green)
            }
        }
    }

    // MARK: - Actions

    private func startRenderExport() {
        guard let project = projectVM.currentProject else { return }

        isExporting = true
        exportProgress = 0
        exportMessage = nil

        let edl = transcriptVM.computeAllEditDecisions(mediaFiles: projectVM.mediaFiles)
        let outputURL = RenderPipeline.defaultOutputURL(
            projectName: project.name,
            preset: selectedPreset
        )

        Task {
            do {
                try await exportEngine.render(
                    editDecisions: edl,
                    mediaFiles: projectVM.mediaFiles,
                    outputURL: outputURL,
                    config: selectedPreset.exportConfig,
                    onProgress: { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    }
                )
                isExporting = false
                exportMessage = "Exported to \(outputURL.lastPathComponent)"
            } catch {
                isExporting = false
                exportMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func handleXmlExport(format: XmlExportFormat, outputURL: URL) {
        guard let project = projectVM.currentProject else { return }

        Task { @MainActor in
            let seqName = "\(project.name) - Abscido Edit"
            do {
                let timeline = try await timelineVM.openTimelineForInterchangeExport(sequenceDisplayName: seqName)
                switch format {
                case .fcp7:
                    try await exportEngine.exportFcp7XML(
                        timeline: timeline,
                        mediaFiles: projectVM.mediaFiles,
                        projectName: project.name,
                        outputURL: outputURL
                    )
                case .fcpxml:
                    try await exportEngine.exportFCPXML(
                        timeline: timeline,
                        mediaFiles: projectVM.mediaFiles,
                        projectName: project.name,
                        outputURL: outputURL
                    )
                case .both:
                    let fcp7URL = outputURL.deletingPathExtension().appendingPathExtension("xml")
                    let fcpxURL = outputURL.deletingPathExtension().appendingPathExtension("fcpxml")
                    try await exportEngine.exportFcp7XML(
                        timeline: timeline,
                        mediaFiles: projectVM.mediaFiles,
                        projectName: project.name,
                        outputURL: fcp7URL
                    )
                    try await exportEngine.exportFCPXML(
                        timeline: timeline,
                        mediaFiles: projectVM.mediaFiles,
                        projectName: project.name,
                        outputURL: fcpxURL
                    )
                case .otio:
                    try await exportEngine.exportOTIOJSON(timeline: timeline, outputURL: outputURL)
                }
                exportMessage = "Exported successfully"
            } catch {
                exportMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
}
