# Abscido — Native macOS Text-Based Video Editor

A professional text-based video editor built entirely in Swift and SwiftUI for macOS.
The transcript IS the timeline — delete words in the transcript, and the video edit updates in real time.

## Requirements

- **macOS 14 Sonoma** or later (macOS 15 Sequoia recommended)
- **Xcode 16** with Swift 5.10
- **Apple Silicon** Mac (M1 or later) — required for MLX-Whisper transcription
- **Python 3.12** (arm64) — for MLX-Whisper local transcription

## Quick Start

### 1. Open in Xcode

```bash
cd Abscido-native
open Package.swift
```

Xcode will resolve SPM dependencies automatically (SQLite.swift).

### 2. Set Up Python Environment (for transcription)

MLX-Whisper runs locally on Apple Silicon. Set up a Python environment:

```bash
# Create a dedicated Python virtual environment
python3 -m venv ~/.abscido-python
source ~/.abscido-python/bin/activate

# Install MLX-Whisper
pip install mlx-whisper

# Verify installation
python3 -c "import mlx_whisper; print('MLX-Whisper ready')"
```

For development, the app falls back to system Python (`/opt/homebrew/bin/python3`).
For distribution, bundle the Python runtime in `Resources/python/`.

### 3. Model Download

The Whisper model downloads automatically on first transcription:
- **Model**: `mlx-community/whisper-large-v3-mlx` (~1.5GB)
- **Cache location**: `~/Library/Caches/Abscido/models/`

### 4. Anthropic API Key (for AI Bad Take Detection)

On first launch, go to **Settings** and enter your Anthropic API key.
The key is stored securely in the macOS Keychain — never in UserDefaults or on disk.

### 5. Build & Run

1. Open `Package.swift` in Xcode
2. Select the `Abscido` scheme
3. Press ⌘R to build and run

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
│   ├── OTIOEngine/         # Timeline data model (OTIO-compatible)
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

| Component        | Technology                              |
|------------------|-----------------------------------------|
| UI Framework     | SwiftUI (macOS lifecycle)               |
| Media Engine     | AVFoundation (AVPlayer, AVComposition)  |
| Transcription    | MLX-Whisper (local, Apple Silicon)      |
| Timeline Model   | OTIO-compatible native Swift types      |
| Database         | SQLite.swift                            |
| AI               | Anthropic Claude API (URLSession)       |
| XML Export       | Foundation XMLDocument (pure Swift)     |
| Secrets          | macOS Keychain (Security framework)     |

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

## Database

SQLite database stored at `~/Library/Application Support/Abscido/abscido.sqlite3`.
Uses WAL journal mode for concurrent read performance.

## License

Proprietary — Abscido.
