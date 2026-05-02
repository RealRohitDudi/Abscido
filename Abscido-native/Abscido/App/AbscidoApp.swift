import SwiftUI
import AppKit

/// Ensures Abscido becomes the active application and installs its menus in the system menu bar.
/// Without `NSApplication.activate` + `.regular` activation policy (especially when launched via
/// `swift run` or certain debug hosts), macOS can keep Finder (or another app) “active” visually
/// even while Abscido’s window is foregrounded — so SwiftUI `.commands { }` never show as Abscido.
final class AbscidoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

/// Main application entry point — single window group with menu commands and keyboard shortcuts.
@main
struct AbscidoApp: App {
    @NSApplicationDelegateAdaptor(AbscidoAppDelegate.self) var appDelegate

    @State private var coordinator = AppCoordinator()
    private let shortcutManager = KeyboardShortcutManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    setDarkAppearance()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            // MARK: - Abscido App Menu
            CommandGroup(after: .appSettings) {
                Button("Keyboard Shortcuts…") {
                    coordinator.showKeyboardShortcuts = true
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }

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
                .modifier(DynamicShortcut(action: .importMedia))

                Button("Save Project") {
                    coordinator.saveProject()
                }
                .modifier(DynamicShortcut(action: .saveProject))
            }

            // MARK: - Edit Menu
            CommandGroup(after: .undoRedo) {
                Button("Select All Words") {
                    coordinator.selectAllWords()
                }
                .modifier(DynamicShortcut(action: .selectAll))

                Divider()

                Button("Cut Clips") {
                    coordinator.timelineVM.cutSelected()
                }
                .modifier(DynamicShortcut(action: .cutClips))

                Button("Copy Clips") {
                    coordinator.timelineVM.copySelected()
                }
                .modifier(DynamicShortcut(action: .copyClips))

                Button("Paste Clips") {
                    coordinator.timelineVM.pasteAtPlayhead()
                }
                .modifier(DynamicShortcut(action: .pasteClips))

                Button("Delete Clips") {
                    coordinator.timelineVM.deleteSelected()
                }
                .modifier(DynamicShortcut(action: .deleteClips))

                Divider()

                Button("Link Clips") {
                    coordinator.timelineVM.linkSelected()
                }
                .modifier(DynamicShortcut(action: .linkClips))

                Button("Unlink Clips") {
                    coordinator.timelineVM.unlinkSelected()
                }
                .modifier(DynamicShortcut(action: .unlinkClips))
            }

            // MARK: - Export Menu
            CommandMenu("Export") {
                Button("Compile Edit") {
                    coordinator.compileEdit()
                }
                .modifier(DynamicShortcut(action: .compileEdit))

                Button("Export...") {
                    coordinator.showExport = true
                }
                .modifier(DynamicShortcut(action: .exportDialog))

                Divider()

                Button("Export XML...") {
                    coordinator.showXmlExport = true
                }
                .modifier(DynamicShortcut(action: .xmlExport))
            }

            // MARK: - View Menu
            CommandGroup(after: .toolbar) {
                Button("Zoom In Timeline") {
                    coordinator.zoomInTimeline()
                }
                .modifier(DynamicShortcut(action: .zoomIn))

                Button("Zoom Out Timeline") {
                    coordinator.zoomOutTimeline()
                }
                .modifier(DynamicShortcut(action: .zoomOut))
            }

            // MARK: - Timeline Menu
            CommandMenu("Timeline") {
                Button("Add Video Track") {
                    coordinator.timelineVM.addTrack(kind: .video)
                }
                .modifier(DynamicShortcut(action: .addVideoTrack))

                Button("Add Audio Track") {
                    coordinator.timelineVM.addTrack(kind: .audio)
                }
                .modifier(DynamicShortcut(action: .addAudioTrack))

                Divider()

                Button("Go to Start") {
                    coordinator.playerVM.seek(to: 0)
                }
                .modifier(DynamicShortcut(action: .goToStart))

                Button("Go to End") {
                    coordinator.playerVM.seek(to: coordinator.playerVM.durationMs)
                }
                .modifier(DynamicShortcut(action: .goToEnd))
            }
        }
    }

    private func setDarkAppearance() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

// MARK: - Dynamic Shortcut Modifier

/// Applies a KeyboardShortcut from the KeyboardShortcutManager to a menu item.
/// Falls back gracefully if the action has no binding.
struct DynamicShortcut: ViewModifier {
    let action: ShortcutAction
    private let manager = KeyboardShortcutManager.shared

    func body(content: Content) -> some View {
        if let shortcut = manager.swiftUIShortcut(for: action) {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}
