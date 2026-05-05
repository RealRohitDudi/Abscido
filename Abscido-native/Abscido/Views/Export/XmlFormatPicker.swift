import SwiftUI
import UniformTypeIdentifiers

/// Interchange format selection (XML derived from OpenTimelineIO timeline graph, or native `.otio`).
enum XmlExportFormat: String, CaseIterable, Identifiable {
    case fcp7 = "Premiere Pro / Resolve (FCP7 XML)"
    case fcpxml = "Final Cut Pro X (FCPXML)"
    case both = "FCP7 XML + FCPXML"
    case edl = "EDL (CMX 3600)"
    case otio = "OpenTimelineIO (.otio)"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .fcp7: return "xml"
        case .fcpxml: return "fcpxml"
        case .both: return "xml"
        case .edl: return "edl"
        case .otio: return "otio"
        }
    }
}

/// Sheet for selecting interchange format and destination.
struct XmlFormatPicker: View {
    let projectName: String
    var onExport: (XmlExportFormat, URL) -> Void

    @State private var selectedFormat: XmlExportFormat = .fcp7
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Export timeline")
                .font(.headline)

            Text("Exports mirror your timeline—including spacing between clips. OpenTimelineIO (.otio) is the full-fidelity interchange format.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Format", selection: $selectedFormat) {
                ForEach(XmlExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.radioGroup)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export…") {
                    showSavePanel()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.486, green: 0.424, blue: 0.980))
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(projectName)_abscido.\(selectedFormat.fileExtension)"

        switch selectedFormat {
        case .fcp7, .both:
            panel.allowedContentTypes = [.xml]
        case .fcpxml:
            panel.allowedContentTypes = [
                UTType(tag: "fcpxml", tagClass: .filenameExtension, conformingTo: .xml) ?? .xml,
            ]
        case .edl:
            panel.allowedContentTypes = [UTType(filenameExtension: "edl") ?? .plainText]
        case .otio:
            panel.allowedContentTypes = [
                UTType(tag: "otio", tagClass: .filenameExtension, conformingTo: .json) ?? .json,
            ]
        }

        if panel.runModal() == .OK, let url = panel.url {
            onExport(selectedFormat, url)
            dismiss()
        }
    }
}
