# Abscido — Text-Based Video Editor

> A production-grade macOS-native video editor focused entirely on text-based video editing.

![Abscido](https://img.shields.io/badge/Electron-30-blue) ![TypeScript](https://img.shields.io/badge/TypeScript-5.x-blue) ![React](https://img.shields.io/badge/React-18-61dafb)

## Overview

Abscido lets you edit video by editing text. Import your video, transcribe it with OpenAI Whisper, then select and delete words in the transcript — the corresponding video segments are automatically removed. Use Claude AI to detect and remove bad takes in one click.

## Features

- **Text-Based Editing** — Select transcript text → cut video. Delete words → cut video segments
- **Word-Level Timestamps** — Every word precisely synced to the video timeline
- **Real-Time Playback Sync** — Currently-playing word highlights in the transcript
- **AI Bad Take Removal** — Claude detects stutters, false starts, and repeated sentences
- **Non-Destructive** — All edits are soft-deletes with full undo/redo (Cmd+Z / Cmd+Shift+Z)
- **FFmpeg Compilation** — Compile edits to output MP4 using stream-copy (lossless when possible)
- **Multi-Clip Support** — Multiple clips on the timeline, each independently transcribed
- **Export Presets** — MP4/MOV/WebM with quality presets (lossless, high, medium, low)

## Tech Stack

| Layer | Technology |
|---|---|
| Runtime | Electron 30 |
| Language | TypeScript 5.x (strict) |
| UI | React 18 + Tailwind CSS 3 JIT |
| State | Zustand 4 (slices + devtools) |
| DB | better-sqlite3 |
| Video | fluent-ffmpeg + ffmpeg-static |
| Transcription | OpenAI Whisper API |
| AI | Anthropic Claude (claude-sonnet-4-20250514) |

## Setup

### Prerequisites

- Node.js 20+
- npm 10+
- macOS (arm64 or x64)

### Installation

```bash
cd /path/to/abscido
npm install
```

### Configuration

On first launch, Abscido will prompt you for API keys. You can also set them via:

```bash
cp .env.example .env
# Edit .env with your keys (development reference only — not used at runtime)
```

API keys are stored securely in macOS Keychain via `electron-store` (encrypted), never in plain files.

**Required:**
- `OPENAI_API_KEY` — for Whisper transcription (get one at [platform.openai.com](https://platform.openai.com))

**Optional:**
- `ANTHROPIC_API_KEY` — for Claude bad take detection (get one at [console.anthropic.com](https://console.anthropic.com))

### Development

```bash
# Start Vite dev server (renderer) + TypeScript watch (main process) concurrently
npm run dev

# Then launch Electron in a separate terminal:
npx electron .
```

Or, to start both together with Electron:

```bash
npm run dev &
sleep 3 && npx electron .
```

### Build

```bash
# Type-check everything
npm run typecheck

# Build renderer + main
npm run build

# Package macOS .dmg (arm64 + x64)
npm run dist
```

### Testing

```bash
# Unit tests (Vitest)
npm run test

# E2E tests (Playwright)
npm run test:e2e

# Type check only
npm run typecheck
```

## Usage

### Basic Workflow

1. **Create a project** — `Cmd+N` or File → New Project
2. **Import media** — `Cmd+I` or click "Import Media" in the Media Bin
3. **Add to timeline** — Hover over a clip in the Media Bin → "Add to Timeline"
4. **Transcribe** — Select language in the TranscriptEditor toolbar → click "Transcribe All"
5. **Edit by text** — Select words in the transcript → press `Delete` or `Backspace`
6. **Review deletions** — Deleted words show red strikethrough; original video untouched
7. **Undo/Redo** — `Cmd+Z` / `Cmd+Shift+Z`
8. **Remove bad takes** — Click "✦ Remove Bad Takes" → Claude highlights issues → Accept/Reject
9. **Compile edit** — `Cmd+Enter` or click "Compile Edit" → FFmpeg cuts the video
10. **Export** — `Cmd+E` → choose format and quality → renders final file

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+I` | Import media |
| `Space` | Play / Pause |
| `Cmd+Z` | Undo transcript deletion |
| `Cmd+Shift+Z` | Redo |
| `Delete` / `Backspace` | Delete selected words → cut video |
| `Cmd+Enter` | Compile edit |
| `Cmd+E` | Export dialog |
| `Cmd+S` | Save project |
| `Cmd+N` | New project |
| `Cmd+O` | Open project |
| `Cmd+,` | Settings |
| `J` / `L` | Shuttle playback speed |

## Architecture

```
src/
├── main/              # Electron main process (Node.js)
│   ├── ipc/           # IPC handler registration
│   ├── services/      # FFmpeg, Whisper, Claude, Project
│   └── db/            # SQLite database + repositories
├── renderer/          # React app (browser context)
│   ├── store/         # Zustand slices
│   ├── hooks/         # useTranscriptEdit, useTimelineSync, useIpc
│   └── components/    # UI components
└── shared/            # Types + IPC channel enums
```

## Security

- `contextIsolation: true`, `nodeIntegration: false` enforced
- API keys never exposed to renderer process
- CSP headers set on all windows
- All IPC channels are explicitly allowlisted

## Database

SQLite via `better-sqlite3` stored at `~/Library/Application Support/abscido/abscido.db`.

Tables: `projects`, `media_files`, `timeline_clips`, `transcript_words`, `transcript_segments`

## License

MIT
