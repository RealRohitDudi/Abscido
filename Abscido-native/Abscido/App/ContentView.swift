import SwiftUI

/// Root content view — the workspace with toolbar, import sheet, and settings.
struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var newProjectName = ""
    @State private var showSettingsSheet = false

    var body: some View {
        @Bindable var coord = coordinator

        WorkspaceView(
            projectVM: coord.projectVM,
            transcriptVM: coord.transcriptVM,
            playerVM: coord.playerVM,
            timelineVM: coord.timelineVM,
            aiVM: coord.aiVM
        )
        .abscidoToolbar(
            projectVM: coord.projectVM,
            transcriptVM: coord.transcriptVM,
            onImport: { coord.importMedia() },
            onTranscribe: handleTranscribe,
            onBadTakes: handleBadTakes,
            onCompile: { coord.compileEdit() },
            onExport: { coord.showExport = true }
        )
        // MARK: - Keyboard Shortcuts
        .onKeyPress(.space) {
            coord.playerVM.togglePlayPause()
            return .handled
        }
        .onKeyPress(.delete) {
            // Delete selected timeline clips, or fall back to transcript word deletion
            if !coord.timelineVM.selectedClipIds.isEmpty {
                coord.timelineVM.deleteSelected()
            } else {
                handleDelete()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            coord.playerVM.stepBackward()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            coord.playerVM.stepForward()
            return .handled
        }
        .onKeyPress("j") {
            coord.playerVM.shuttleReverse()
            return .handled
        }
        .onKeyPress("k") {
            coord.playerVM.shuttlePause()
            return .handled
        }
        .onKeyPress("l") {
            coord.playerVM.shuttleForward()
            return .handled
        }
        // MARK: - Sheets & Alerts
        .sheet(isPresented: $coord.showNewProject) {
            newProjectSheet
        }
        .sheet(isPresented: $showSettingsSheet) {
            settingsSheet
        }
        .onChange(of: coord.showImportPanel) { _, show in
            if show {
                coord.importMedia()
                coord.showImportPanel = false
            }
        }
        .alert("Error", isPresented: Binding(
            get: { coord.errorMessage != nil },
            set: { if !$0 { coord.clearError() } }
        )) {
            Button("OK") { coord.clearError() }
        } message: {
            Text(coord.errorMessage ?? "")
        }
    }

    // MARK: - Actions

    private func handleTranscribe() {
        guard let file = coordinator.projectVM.mediaFiles.first else { return }
        coordinator.transcriptVM.transcribe(mediaFile: file)
    }

    private func handleBadTakes() {
        coordinator.aiVM.detectBadTakes(words: coordinator.transcriptVM.words)
    }

    private func handleDelete() {
        guard let file = coordinator.projectVM.mediaFiles.first else { return }
        if let editDecision = coordinator.transcriptVM.deleteSelectedWords(mediaFile: file) {
            let allDecisions = coordinator.transcriptVM.computeAllEditDecisions(
                mediaFiles: coordinator.projectVM.mediaFiles
            )
            coordinator.timelineVM.rebuild(
                editDecisions: allDecisions,
                mediaFiles: coordinator.projectVM.mediaFiles
            )
            Task {
                let composition = try await CompositionBuilder.build(
                    from: allDecisions,
                    mediaFiles: coordinator.projectVM.mediaFiles
                )
                coordinator.playerVM.loadComposition(composition)
            }
        }
    }

    // MARK: - Sheets

    private var newProjectSheet: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.headline)

            TextField("Project Name", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    coordinator.showNewProject = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    coordinator.projectVM.createProject(name: newProjectName)
                    newProjectName = ""
                    coordinator.showNewProject = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProjectName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var settingsSheet: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic API Key")
                    .font(.subheadline)

                HStack {
                    if let masked = Keychain.maskedValue(key: "anthropic_api_key") {
                        Text(masked)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not set")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Update...") {
                        showApiKeyDialog()
                    }
                }
            }

            Spacer()

            Button("Done") {
                showSettingsSheet = false
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 400, height: 200)
    }

    private func showApiKeyDialog() {
        let alert = NSAlert()
        alert.messageText = "Enter Anthropic API Key"
        alert.informativeText = "This key is stored securely in the macOS Keychain."

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Save to Keychain")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let key = input.stringValue
            if !key.isEmpty {
                try? Keychain.save(key: "anthropic_api_key", value: key)
            }
        }
    }
}
