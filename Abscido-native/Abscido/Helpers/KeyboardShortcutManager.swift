import SwiftUI

// MARK: - Shortcut Action Enum

/// Every bindable action in the app. Cases are grouped by category.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    // Transport
    case playPause          = "play_pause"
    case stepForward        = "step_forward"
    case stepBackward       = "step_backward"
    case shuttleForward     = "shuttle_forward"
    case shuttleReverse     = "shuttle_reverse"
    case shuttlePause       = "shuttle_pause"
    case goToStart          = "go_to_start"
    case goToEnd            = "go_to_end"

    // Timeline Editing
    case cutClips           = "cut_clips"
    case copyClips          = "copy_clips"
    case pasteClips         = "paste_clips"
    case deleteClips        = "delete_clips"
    case linkClips          = "link_clips"
    case unlinkClips        = "unlink_clips"
    case selectAll          = "select_all"
    case razorAtPlayhead    = "razor_at_playhead"
    case rippleTrimStartToPlayhead = "ripple_trim_start_playhead"
    case rippleTrimEndToPlayhead  = "ripple_trim_end_playhead"

    // Timeline View
    case zoomIn             = "zoom_in"
    case zoomOut            = "zoom_out"

    // Tracks
    case addVideoTrack      = "add_video_track"
    case addAudioTrack      = "add_audio_track"

    // File
    case importMedia        = "import_media"
    case saveProject        = "save_project"
    case compileEdit        = "compile_edit"
    case exportDialog       = "export_dialog"
    case xmlExport          = "xml_export"

    // Undo/Redo
    case undo               = "undo"
    case redo               = "redo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .playPause:        return "Play / Pause"
        case .stepForward:      return "Step Forward"
        case .stepBackward:     return "Step Backward"
        case .shuttleForward:   return "Shuttle Forward"
        case .shuttleReverse:   return "Shuttle Reverse"
        case .shuttlePause:     return "Shuttle Pause"
        case .goToStart:        return "Go to Start"
        case .goToEnd:          return "Go to End"
        case .cutClips:         return "Cut Clips"
        case .copyClips:        return "Copy Clips"
        case .pasteClips:       return "Paste Clips"
        case .deleteClips:      return "Delete Clips"
        case .linkClips:        return "Link Clips"
        case .unlinkClips:      return "Unlink Clips"
        case .selectAll:        return "Select All"
        case .razorAtPlayhead:  return "Razor (Split at Playhead)"
        case .rippleTrimStartToPlayhead: return "Ripple Trim Start to Playhead"
        case .rippleTrimEndToPlayhead:  return "Ripple Trim End to Playhead"
        case .zoomIn:           return "Zoom In Timeline"
        case .zoomOut:          return "Zoom Out Timeline"
        case .addVideoTrack:    return "Add Video Track"
        case .addAudioTrack:    return "Add Audio Track"
        case .importMedia:      return "Import Media"
        case .saveProject:      return "Save Project"
        case .compileEdit:      return "Compile Edit"
        case .exportDialog:     return "Export..."
        case .xmlExport:        return "Export XML..."
        case .undo:             return "Undo"
        case .redo:             return "Redo"
        }
    }

    var category: ShortcutCategory {
        switch self {
        case .playPause, .stepForward, .stepBackward,
             .shuttleForward, .shuttleReverse, .shuttlePause,
             .goToStart, .goToEnd:
            return .transport
        case .cutClips, .copyClips, .pasteClips, .deleteClips,
             .linkClips, .unlinkClips, .selectAll,
             .razorAtPlayhead, .rippleTrimStartToPlayhead, .rippleTrimEndToPlayhead:
            return .editing
        case .zoomIn, .zoomOut:
            return .view
        case .addVideoTrack, .addAudioTrack:
            return .tracks
        case .importMedia, .saveProject, .compileEdit,
             .exportDialog, .xmlExport:
            return .file
        case .undo, .redo:
            return .history
        }
    }
}

enum ShortcutCategory: String, CaseIterable, Identifiable {
    case transport  = "Transport"
    case editing    = "Editing"
    case view       = "View"
    case tracks     = "Tracks"
    case file       = "File"
    case history    = "History"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var actions: [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.category == self }
    }
}

// MARK: - Shortcut Binding

/// A single key binding: key character/code + modifier flags.
struct ShortcutBinding: Codable, Equatable, Hashable {
    /// The key character (e.g. "a", " " for space). Empty string for special keys.
    var key: String
    /// For special keys: uses KeyEquivalent raw values
    var specialKey: SpecialKey?
    /// Modifier flags stored as raw UInt
    var modifierRawValue: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    enum SpecialKey: String, Codable {
        case space
        case delete
        case forwardDelete
        case returnKey
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
        case home
        case end
        case escape
        case tab
    }

    /// Human-readable display string (e.g. "⌘⇧L" or "Space")
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyPart: String
        if let special = specialKey {
            switch special {
            case .space:          keyPart = "Space"
            case .delete:         keyPart = "⌫"
            case .forwardDelete:  keyPart = "⌦"
            case .returnKey:      keyPart = "↩"
            case .leftArrow:      keyPart = "←"
            case .rightArrow:     keyPart = "→"
            case .upArrow:        keyPart = "↑"
            case .downArrow:      keyPart = "↓"
            case .home:           keyPart = "↖"
            case .end:            keyPart = "↘"
            case .escape:         keyPart = "⎋"
            case .tab:            keyPart = "⇥"
            }
        } else {
            keyPart = key.uppercased()
        }

        parts.append(keyPart)
        return parts.joined()
    }

    /// Matches an incoming NSEvent key event.
    func matches(event: NSEvent) -> Bool {
        let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let bindingMods = modifiers.intersection([.command, .shift, .option, .control])
        guard eventMods == bindingMods else { return false }

        if let special = specialKey {
            switch special {
            case .space:          return event.keyCode == 49 // kVK_Space
            case .delete:         return event.keyCode == 51 // kVK_Delete
            case .forwardDelete:  return event.keyCode == 117 // kVK_ForwardDelete
            case .returnKey:      return event.keyCode == 36 // kVK_Return
            case .leftArrow:      return event.keyCode == 123 // kVK_LeftArrow
            case .rightArrow:     return event.keyCode == 124 // kVK_RightArrow
            case .upArrow:       return event.keyCode == 126 // kVK_UpArrow
            case .downArrow:     return event.keyCode == 125 // kVK_DownArrow
            case .home:           return event.keyCode == 115 // kVK_Home
            case .end:            return event.keyCode == 119 // kVK_End
            case .escape:         return event.keyCode == 53 // kVK_Escape
            case .tab:            return event.keyCode == 48 // kVK_Tab
            }
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return chars == key.lowercased()
    }

    /// Matches SwiftUI onKeyPress character values (for inline key handlers).
    func matchesKeyPress(_ keyEquiv: KeyEquivalent, modifiers eventMods: SwiftUI.EventModifiers) -> Bool {
        // Only used for non-special-key bindings checked via SwiftUI path
        if let special = specialKey {
            let ke: KeyEquivalent
            switch special {
            case .space: ke = .space
            case .delete: ke = .delete
            case .returnKey: ke = .return
            case .leftArrow: ke = .leftArrow
            case .rightArrow: ke = .rightArrow
            case .upArrow: ke = .upArrow
            case .downArrow: ke = .downArrow
            case .home: ke = .home
            case .end: ke = .end
            case .escape: ke = .escape
            case .tab: ke = .tab
            case .forwardDelete: ke = .deleteForward
            }
            return keyEquiv == ke
        }
        return String(keyEquiv.character).lowercased() == key.lowercased()
    }

    // MARK: - Convenience Initializers

    static func key(_ char: String, modifiers: NSEvent.ModifierFlags = []) -> ShortcutBinding {
        ShortcutBinding(key: char, specialKey: nil, modifierRawValue: modifiers.rawValue)
    }

    static func special(_ special: SpecialKey, modifiers: NSEvent.ModifierFlags = []) -> ShortcutBinding {
        ShortcutBinding(key: "", specialKey: special, modifierRawValue: modifiers.rawValue)
    }
}

// MARK: - Keyboard Shortcut Manager

/// Singleton that owns all shortcut bindings, persists to UserDefaults, and provides
/// lookup by action or by incoming key event.
@MainActor
@Observable
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    /// Current bindings — action → binding.
    var bindings: [ShortcutAction: ShortcutBinding] = [:]

    /// When the user is recording a new shortcut, this is the action being reassigned.
    var recordingAction: ShortcutAction?

    /// Conflict detected during reassignment.
    var conflictAction: ShortcutAction?

    private let defaultsKey = "com.abscido.keyboard-shortcuts"

    private init() {
        load()
    }

    // MARK: - Defaults

    static let defaults: [ShortcutAction: ShortcutBinding] = [
        // Transport
        .playPause:         .special(.space),
        .stepForward:       .special(.rightArrow),
        .stepBackward:      .special(.leftArrow),
        .shuttleForward:    .key("l"),
        .shuttleReverse:    .key("j"),
        .shuttlePause:      .key("k"),
        .goToStart:         .special(.home),
        .goToEnd:           .special(.end),

        // Editing
        .cutClips:          .key("x", modifiers: .command),
        .copyClips:         .key("c", modifiers: .command),
        .pasteClips:        .key("v", modifiers: .command),
        .deleteClips:       .special(.delete),
        .linkClips:         .key("l", modifiers: .command),
        .unlinkClips:       .key("l", modifiers: [.command, .shift]),
        .selectAll:         .key("a", modifiers: .command),
        .razorAtPlayhead:   .key("w"),
        .rippleTrimStartToPlayhead: .key("q"),
        .rippleTrimEndToPlayhead: .key("e"),

        // View
        .zoomIn:            .key("=", modifiers: .command),
        .zoomOut:           .key("-", modifiers: .command),

        // Tracks
        .addVideoTrack:     .key("t", modifiers: [.command, .shift]),
        .addAudioTrack:     .key("t", modifiers: [.command, .option]),

        // File
        .importMedia:       .key("i", modifiers: .command),
        .saveProject:       .key("s", modifiers: .command),
        .compileEdit:       .special(.returnKey, modifiers: .command),
        .exportDialog:      .key("e", modifiers: .command),
        .xmlExport:         .key("e", modifiers: [.command, .shift]),

        // History
        .undo:              .key("z", modifiers: .command),
        .redo:              .key("z", modifiers: [.command, .shift]),
    ]

    // MARK: - Persistence

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) else {
            bindings = Self.defaults
            return
        }

        // Merge saved bindings with defaults (in case new actions were added)
        var result = Self.defaults
        for (rawKey, binding) in decoded {
            if let action = ShortcutAction(rawValue: rawKey) {
                result[action] = binding
            }
        }
        bindings = result
    }

    func save() {
        let encoded: [String: ShortcutBinding] = bindings.reduce(into: [:]) { dict, pair in
            dict[pair.key.rawValue] = pair.value
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func resetToDefaults() {
        bindings = Self.defaults
        save()
    }

    func resetAction(_ action: ShortcutAction) {
        if let defaultBinding = Self.defaults[action] {
            bindings[action] = defaultBinding
            save()
        }
    }

    // MARK: - Binding Management

    func binding(for action: ShortcutAction) -> ShortcutBinding? {
        bindings[action]
    }

    /// Assigns a new binding to an action, resolving conflicts.
    /// Returns the conflicting action if there is one (the old binding is removed from the conflicting action).
    @discardableResult
    func assign(_ binding: ShortcutBinding, to action: ShortcutAction) -> ShortcutAction? {
        // Find conflicts
        var conflict: ShortcutAction?
        for (existingAction, existingBinding) in bindings {
            if existingAction != action && existingBinding == binding {
                conflict = existingAction
                break
            }
        }

        // Remove the conflicting binding
        if let conflict {
            bindings[conflict] = nil
        }

        bindings[action] = binding
        save()
        return conflict
    }

    /// Removes the binding for an action (unbinds the shortcut).
    func unbind(_ action: ShortcutAction) {
        bindings[action] = nil
        save()
    }

    // MARK: - Event Matching

    /// Returns the action that matches the given NSEvent, or nil.
    func action(for event: NSEvent) -> ShortcutAction? {
        for (action, binding) in bindings {
            if binding.matches(event: event) {
                return action
            }
        }
        return nil
    }

    /// Checks if a specific action matches the given key press parameters.
    func matches(action: ShortcutAction, key: KeyEquivalent, modifiers: SwiftUI.EventModifiers) -> Bool {
        guard let binding = bindings[action] else { return false }
        return binding.matchesKeyPress(key, modifiers: modifiers)
    }

    // MARK: - SwiftUI KeyboardShortcut conversion

    /// Returns a SwiftUI KeyboardShortcut for menu items. Returns nil if action has no binding.
    func swiftUIShortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        guard let binding = bindings[action] else { return nil }

        let keyEquiv: KeyEquivalent
        if let special = binding.specialKey {
            switch special {
            case .space: keyEquiv = .space
            case .delete: keyEquiv = .delete
            case .forwardDelete: keyEquiv = .deleteForward
            case .returnKey: keyEquiv = .return
            case .leftArrow: keyEquiv = .leftArrow
            case .rightArrow: keyEquiv = .rightArrow
            case .upArrow: keyEquiv = .upArrow
            case .downArrow: keyEquiv = .downArrow
            case .home: keyEquiv = .home
            case .end: keyEquiv = .end
            case .escape: keyEquiv = .escape
            case .tab: keyEquiv = .tab
            }
        } else {
            keyEquiv = KeyEquivalent(Character(binding.key))
        }

        var mods: SwiftUI.EventModifiers = []
        if binding.modifiers.contains(.command) { mods.insert(.command) }
        if binding.modifiers.contains(.shift) { mods.insert(.shift) }
        if binding.modifiers.contains(.option) { mods.insert(.option) }
        if binding.modifiers.contains(.control) { mods.insert(.control) }

        return KeyboardShortcut(keyEquiv, modifiers: mods)
    }
}
