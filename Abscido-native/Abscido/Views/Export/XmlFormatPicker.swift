import SwiftUI

/// XML export format selection.
enum XmlExportFormat: String, CaseIterable, Identifiable {
    case fcp7 = "Premiere Pro / Resolve (FCP7 XML)"
    case fcpxml = "Final Cut Pro X (FCPXML)"
    case both = "Both"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .fcp7: return "xml"
        case .fcpxml: return "fcpxml"
        case .both: return "xml"
        }
    }
}

/// Sheet for selecting XML export format and destination.
struct XmlFormatPicker: View {
    let projectName: String
    var onExport: (XmlExportFormat, URL) -> Void

    @State private var selectedFormat: XmlExportFormat = .fcp7
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Export XML")
                .font(.headline)

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

                Button("Export...") {
                    showSavePanel()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.486, green: 0.424, blue: 0.980))
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(projectName)_abscido.\(selectedFormat.fileExtension)"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            onExport(selectedFormat, url)
            dismiss()
        }
    }
}
