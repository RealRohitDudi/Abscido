# Abscido — Native macOS Text-Based Video Editor

A professional text-based video editor built entirely in Swift and SwiftUI for macOS.
The transcript IS the timeline — delete words in the transcript, and the video edit updates in real time.
The main philosophy is to build a scalable and production grade Video editor.
The main inspiration is Davinci Resolve.

## Requirements

- **macOS 14 Sonoma** or later (macOS 15 Sequoia recommended)
- **Xcode 16** with Swift 5.10
- **OpenTimelineIO** Open Source API and interchange format for editorial timeline information.
- *(Optional)* **Apple Silicon** Mac + **Python 3.12** with `mlx-whisper` — only for the MLX-Whisper quality upgrade

## Quick Start

### 1. Open in Xcode

```bash
cd Abscido-native
open Package.swift
```

Xcode will resolve SPM dependencies automatically (SQLite.swift, OpenTimelineIO).

### 2. Transcription — Works Out of the Box

Abscido uses **Apple's built-in Speech Recognition** (`SFSpeechRecognizer`) as its primary transcription engine.

- **Zero setup required** — no Python, no model download, no internet required
- Runs fully **offline** on macOS 13+
- Supports **20+ languages** with word-level timestamps
- **Sandbox-safe** — works in all App Store builds

On first transcription, macOS will ask for Speech Recognition permission. Grant it in the system dialog.

If the app quits with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` in the crash log:

1. This project embeds **`NSSpeechRecognitionUsageDescription`** into the binary via linker `-sectcreate __TEXT __info_plist` (`Package.swift`). Run `swift build` after pulling so the Mach-O is relinked.
2. **`swift run` / a plain ⌘R build** often omits Speech’s entitlement from the ad-hoc signature (`codesign -d --entitlements`). On recent macOS, TCC validates **`com.apple.security.personal-information.speech-recognition`** in the *signed* entitlement blob; without it, Speech can still abort despite the embedded plist.

Use one of these **before** relying on Apple Speech:

```bash
cd Abscido-native
./scripts/run-with-speech-capability.sh

# Or SwiftPM command plugin (build → re-sign → launch)
swift package plugin run-with-speech --allow-writing-to-package-directory --allow-network-connections all
```

That uses **`Abscido/LocalSigning.entitlements`** (Speech + `get-task-allow`, intentionally **no app sandbox** so local dev keeps normal filesystem access).

**Xcode (Package.swift only):** The repo does **not** auto-apply entitlements to the SPM executable. Set the **Abscido** target → **Build Settings** → **Code Signing Entitlements** to `Abscido/LocalSigning.entitlements` for Debug, or launch via the script/plugin above. **`Abscido.entitlements`** (sandbox) is for distribution-style builds where you also add the Speech capability under Signing & Capabilities.

#### Optional: MLX-Whisper (Higher Accuracy on Apple Silicon)

For higher transcription accuracy, switch to the **MLX-Whisper** engine in the engine picker:

```bash
# Create a dedicated Python virtual environment
python3 -m venv ~/.abscido-python
source ~/.abscido-python/bin/activate

# Install MLX-Whisper and ffmpeg (required shell dependency for audio decode)
brew install ffmpeg
pip install mlx-whisper
```

The Whisper model (`mlx-community/whisper-large-v3-mlx`, ~1.5 GB) downloads automatically on first use.
Cache location: `~/Library/Caches/Abscido/models/`

If ffmpeg is installed but MLX still fails, point Abscido at the binary explicitly:  
`export ABSCIDO_FFMPEG="/full/path/to/ffmpeg"` then launch from the same Terminal session (or add it under **Scheme → Run → Arguments → Environment Variables** in Xcode).

> **Note**: App Sandbox (**⌘R** from Xcode using `Abscido.entitlements`) can block subprocesses from executing **`/opt/homebrew/bin/ffmpeg`**. MLX-Whisper works most reliably when you run **`./scripts/run-with-speech-capability.sh`** / a **non-sandboxed** local build alongside **`brew install ffmpeg`**.

### 3. Anthropic API Key (for AI Bad Take Detection)

On first launch, go to **Settings** and enter your Anthropic API key.
The key is stored securely in the macOS Keychain — never in UserDefaults or on disk.

### 4. Build & Run

1. Open `Package.swift` in Xcode
2. Select the `Abscido` scheme
3. Press ⌘R to build and run

For **Apple Speech**, if transcription shows a re-signing error, use **Build & Run** only after setting **Code Signing Entitlements** (see Speech section above) or start the app via `./scripts/run-with-speech-capability.sh` / the `run-with-speech` package plugin.

## Architecture

### Core Philosophy

> The transcript IS the timeline. Every word is a data point: `{ word, startMs, endMs }`.
> Deleting a word in the transcript ripples that deletion through the video timeline
> with frame-exact precision. The user thinks in language. The app thinks in time.

### Project Structure

```
Abscido/
├── App/                    # @main entry, coordinator, root view
├── Domain/                 # Pure Swift models, commands, errors
│   ├── Models/             # Project, MediaFile, TranscriptWord, EditDecision, BadTake
│   ├── Commands/           # DeleteWords, AcceptBadTake, CompileEdit
│   └── Errors/             # AbscidoError enum
├── Engines/                # Core processing (all Swift actors)
│   ├── OTIOEngine/         # OpenTimelineIO (opensource) Timeline data model (OTIO-compatible)
│   ├── MediaEngine/        # AVFoundation: import, composition, playback, export
│   ├── TranscriptionEngine/# MLX-Whisper Python subprocess management
│   ├── AIEngine/           # Anthropic API for bad take detection
│   └── ExportEngine/       # Render + XML export (FCP7, FCPXML)
├── Persistence/            # SQLite.swift database, migrations, repositories
├── ViewModels/             # @Observable @MainActor state managers
├── Views/                  # SwiftUI views
│   ├── Layout/             # WorkspaceView, ToolbarView
│   ├── MediaBin/           # Sidebar clip list
│   ├── Player/             # AVPlayerLayer, controls, timecode
│   ├── Transcript/         # Word-level editor (core feature)
│   ├── Timeline/           # Horizontal scroll timeline
│   └── Export/             # Render + XML export UI
├── Helpers/                # Keychain, CMTime extensions, GCD, TimecodeFormatter
└── Resources/
    └── scripts/            # transcribe.py (MLX-Whisper)
```

### Tech Stack

| Component        | Technology                                          |
|------------------|-----------------------------------------------------|
| UI Framework     | SwiftUI (macOS lifecycle)                           |
| Media Engine     | AVFoundation (AVPlayer, AVComposition)              |
| Transcription    | SFSpeechRecognizer (primary) + MLX-Whisper (opt.)  |
| Timeline Model   | OTIO-compatible native Swift types                  |
| Database         | SQLite.swift                                        |
| AI               | Anthropic Claude API (URLSession)                   |
| XML Export       | Foundation XMLDocument (pure Swift)                 |
| Secrets          | macOS Keychain (Security framework)                 |

### Key Design Decisions

- **Words as Views, not TextEditor**: Each transcript word is an individual SwiftUI View element, enabling word-level selection, highlighting, and playback sync without fighting a text engine.
- **AVComposition for instant preview**: Deleted words are omitted from the AVComposition — no render step needed to preview edits.
- **Binary search for playback sync**: Word highlighting during playback uses O(log n) binary search on the sorted word array, running at 60fps (16ms intervals).
- **Actors for all engines**: MediaEngine, TranscriptionEngine, AIEngine, ExportEngine are all Swift actors, serializing state access for safe concurrency.

## Keyboard Shortcuts

| Shortcut         | Action                              |
|------------------|-------------------------------------|
| ⌘I               | Import media                        |
| Space             | Play / Pause                        |
| ⌘Z               | Undo word deletion                  |
| ⌘⇧Z              | Redo                                |
| Delete            | Delete selected words               |
| ⌘↩               | Compile edit (ProRes export)        |
| ⌘E               | Open export dialog                  |
| ⌘⇧E              | XML export dialog                   |
| ⌘S               | Save project                        |
| ⌘A               | Select all non-deleted words        |
| J                 | Shuttle reverse                     |
| K                 | Pause (shuttle stop)                |
| L                 | Shuttle forward                     |
| ←                 | Step one frame backward             |
| →                 | Step one frame forward              |

## Export Formats

### Render Export
- **ProRes 422 LT** (.mov) — lossless intermediate for NLE import
- **High Quality H.264** (.mov) — hardware-encoded via VideoToolbox
- **Medium Quality** (.mp4) — smaller file size

### XML Export
- **FCP7 XML** — compatible with Premiere Pro, DaVinci Resolve
- **FCPXML 1.10** — compatible with Final Cut Pro X
- **EDL** — compatible with Davinci resolve
- **OTIO** — compatible with Davinci Resolve

## Database

SQLite database stored at `~/Library/Application Support/Abscido/abscido.sqlite3`.
Uses WAL journal mode for concurrent read performance.

## License

Proprietary — Abscido.
