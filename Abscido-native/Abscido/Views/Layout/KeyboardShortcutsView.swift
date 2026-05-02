import SwiftUI
import Carbon.HIToolbox

/// Full keyboard shortcuts customization panel — shown from Abscido menu → Keyboard Shortcuts.
/// Professional editor-style UI with category grouping, inline recording, and conflict resolution.
struct KeyboardShortcutsView: View {
    @State private var manager = KeyboardShortcutManager.shared
    @State private var searchText = ""
    @State private var showResetConfirm = false
    @State private var conflictAlert: (action: ShortcutAction, conflicting: ShortcutAction)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Search bar
            searchBar

            // Shortcut list
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(ShortcutCategory.allCases) { category in
                        let filtered = filteredActions(for: category)
                        if !filtered.isEmpty {
                            Section {
                                ForEach(filtered) { action in
                                    ShortcutRow(
                                        action: action,
                                        binding: manager.bindings[action],
                                        isRecording: manager.recordingAction == action,
                                        onStartRecording: {
                                            manager.recordingAction = action
                                        },
                                        onStopRecording: {
                                            manager.recordingAction = nil
                                        },
                                        onBindingRecorded: { newBinding in
                                            let conflict = manager.assign(newBinding, to: action)
                                            manager.recordingAction = nil
                                            if let conflict {
                                                conflictAlert = (action: action, conflicting: conflict)
                                            }
                                        },
                                        onReset: {
                                            manager.resetAction(action)
                                        },
                                        onUnbind: {
                                            manager.unbind(action)
                                        }
                                    )
                                }
                            } header: {
                                sectionHeader(category.displayName)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: 560, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Shortcut Conflict", isPresented: Binding(
            get: { conflictAlert != nil },
            set: { if !$0 { conflictAlert = nil } }
        )) {
            Button("OK") { conflictAlert = nil }
        } message: {
            if let conflict = conflictAlert {
                Text("\"\(conflict.action.displayName)\" was assigned the shortcut. The previous binding for \"\(conflict.conflicting.displayName)\" has been removed.")
            }
        }
        .confirmationDialog("Reset All Shortcuts?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset All to Defaults", role: .destructive) {
                manager.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all keyboard shortcuts to their default values.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Text("Click a shortcut to reassign. Press Escape to cancel recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search shortcuts…", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Reset All to Defaults") {
                showResetConfirm = true
            }
            .foregroundColor(.red)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Filtering

    private func filteredActions(for category: ShortcutCategory) -> [ShortcutAction] {
        let actions = category.actions
        if searchText.isEmpty { return actions }
        return actions.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }
}

// MARK: - Shortcut Row

struct ShortcutRow: View {
    let action: ShortcutAction
    let binding: ShortcutBinding?
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onBindingRecorded: (ShortcutBinding) -> Void
    let onReset: () -> Void
    let onUnbind: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Action name
            Text(action.displayName)
                .font(.system(.body))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Shortcut badge or recording state
            if isRecording {
                recordingBadge
            } else {
                shortcutBadge
            }

            // Action buttons (visible on hover)
            if isHovering && !isRecording {
                HStack(spacing: 4) {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Reset to default")

                    if binding != nil {
                        Button(action: onUnbind) {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Remove shortcut")
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording
                    ? Color.accentColor.opacity(0.1)
                    : (isHovering ? Color(nsColor: .controlBackgroundColor) : .clear))
        )
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRecording {
                onStartRecording()
            }
        }
    }

    private var shortcutBadge: some View {
        Group {
            if let binding {
                Text(binding.displayString)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var recordingBadge: some View {
        ShortcutRecorderView(
            onRecorded: onBindingRecorded,
            onCancel: onStopRecording
        )
    }
}

// MARK: - Shortcut Recorder (NSViewRepresentable)

/// An invisible NSView that captures the next key event and converts it to a ShortcutBinding.
/// Uses NSViewRepresentable because SwiftUI's .onKeyPress doesn't capture all key combos.
struct ShortcutRecorderView: NSViewRepresentable {
    let onRecorded: (ShortcutBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onRecorded = onRecorded
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}
}

final class ShortcutRecorderNSView: NSView {
    var onRecorded: ((ShortcutBinding) -> Void)?
    var onCancel: (() -> Void)?

    private var pulseLayer: CALayer?

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.controlAccentColor.cgColor

        // Pulsing recording indicator
        let pulse = CALayer()
        pulse.frame = bounds
        pulse.cornerRadius = 5
        pulse.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        layer?.addSublayer(pulse)
        pulseLayer = pulse

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.15
        animation.toValue = 0.35
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        pulse.add(animation, forKey: "pulse")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func keyDown(with event: NSEvent) {
        // Escape cancels recording
        if event.keyCode == 53 { // kVK_Escape
            onCancel?()
            return
        }

        let binding = bindingFromEvent(event)
        onRecorded?(binding)
    }

    private func bindingFromEvent(_ event: NSEvent) -> ShortcutBinding {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Map special key codes
        let specialKey: ShortcutBinding.SpecialKey? = switch event.keyCode {
        case 49:  .space
        case 51:  .delete
        case 117: .forwardDelete
        case 36:  .returnKey
        case 123: .leftArrow
        case 124: .rightArrow
        case 126: .upArrow
        case 125: .downArrow
        case 115: .home
        case 119: .end
        case 48:  .tab
        default:  nil
        }

        if let specialKey {
            return .special(specialKey, modifiers: mods)
        }

        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        return .key(chars, modifiers: mods)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text = "Press shortcut…" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attrs)
    }
}
