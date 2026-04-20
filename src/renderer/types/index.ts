// Re-export all shared types for use in renderer
export * from '../../shared/types';

// ─── Renderer-specific UI types ────────────────────────────────────────────────

export type ToastType = 'success' | 'error' | 'warning' | 'info';

export interface Toast {
  id: string;
  type: ToastType;
  message: string;
  duration?: number;
}

export type ModalType = 'settings' | 'export' | 'newProject' | 'openProject' | 'confirm';

export interface WordSelectionRange {
  startWordId: number;
  endWordId: number;
  clipId: number;
}

export interface TimelineViewport {
  startMs: number;
  endMs: number;
  pixelsPerMs: number;
}

export type TranscribeStatus = 'idle' | 'extracting' | 'uploading' | 'transcribing' | 'saving' | 'complete' | 'error';

export interface TranscribeProgress {
  clipId: number;
  stage: TranscribeStatus;
  progress: number;
}

export interface ExportProgress {
  progress: number;
  eta: number;
  stage: 'compiling' | 'encoding' | 'muxing';
}

// Window augmentation for electronAPI
declare global {
  interface Window {
    electronAPI: {
      invoke: <T = unknown>(channel: string, payload?: unknown) => Promise<T>;
      send: (channel: string, payload?: unknown) => void;
      on: (channel: string, callback: (...args: unknown[]) => void) => () => void;
      once: (channel: string, callback: (...args: unknown[]) => void) => void;
      removeAllListeners: (channel: string) => void;
      channels: {
        MEDIA_IMPORT: string;
        MEDIA_PROBE: string;
        MEDIA_THUMBNAIL: string;
        MEDIA_WAVEFORM_DATA: string;
        TRANSCRIBE_CLIP: string;
        TRANSCRIBE_PROGRESS: string;
        EDIT_COMPILE: string;
        EDIT_PREVIEW_SEGMENT: string;
        EXPORT_RENDER: string;
        EXPORT_PROGRESS: string;
        AI_REMOVE_BAD_TAKES: string;
        PROJECT_CREATE: string;
        PROJECT_LOAD: string;
        PROJECT_SAVE: string;
        PROJECT_LIST: string;
        PROJECT_DELETE: string;
        SETTINGS_GET: string;
        SETTINGS_SET: string;
        SETTINGS_HAS_KEYS: string;
        APP_GET_VERSION: string;
        APP_OPEN_FILE_DIALOG: string;
        APP_OPEN_SAVE_DIALOG: string;
        APP_SHOW_IN_FINDER: string;
        APP_CLEANUP_TEMP: string;
        MEDIA_ADD_TO_PROJECT: string;
        CLIP_ADD: string;
        WORDS_SOFT_DELETE: string;
        WORDS_RESTORE: string;
      };
    };
  }
}
