import SwiftUI

/// Main application entry point — single window group with menu commands and keyboard shortcuts.
@main
struct AbscidoApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
                .onAppear {
                    setDarkAppearance()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            // MARK: - File Menu
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    coordinator.showNewProject = true
                }
                .keyboardShortcut("n")

                Divider()

                Button("Import Media...") {
                    coordinator.showImportPanel = true
                }
                .keyboardShortcut("i")

                Button("Save Project") {
                    coordinator.saveProject()
                }
                .keyboardShortcut("s")
            }

            // MARK: - Edit Menu
            CommandGroup(after: .undoRedo) {
                Button("Select All Words") {
                    coordinator.selectAllWords()
                }
                .keyboardShortcut("a")

                Divider()

                Button("Cut Clips") {
                    coordinator.timelineVM.cutSelected()
                }
                .keyboardShortcut("x")

                Button("Copy Clips") {
                    coordinator.timelineVM.copySelected()
                }
                .keyboardShortcut("c")

                Button("Paste Clips") {
                    coordinator.timelineVM.pasteAtPlayhead()
                }
                .keyboardShortcut("v")

                Button("Delete Clips") {
                    coordinator.timelineVM.deleteSelected()
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("Link Clips") {
                    coordinator.timelineVM.linkSelected()
                }
                .keyboardShortcut("l")

                Button("Unlink Clips") {
                    coordinator.timelineVM.unlinkSelected()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            // MARK: - Export Menu
            CommandMenu("Export") {
                Button("Compile Edit") {
                    coordinator.compileEdit()
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Export...") {
                    coordinator.showExport = true
                }
                .keyboardShortcut("e")

                Divider()

                Button("Export XML...") {
                    coordinator.showXmlExport = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // MARK: - View Menu
            CommandGroup(after: .toolbar) {
                Button("Zoom In Timeline") {
                    coordinator.zoomInTimeline()
                }
                .keyboardShortcut("+")

                Button("Zoom Out Timeline") {
                    coordinator.zoomOutTimeline()
                }
                .keyboardShortcut("-")
            }
        }
    }

    private func setDarkAppearance() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
