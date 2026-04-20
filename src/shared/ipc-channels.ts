// Typed IPC channel enum for type-safe communication between main and renderer

export enum IpcChannel {
  // ─── Media ──────────────────────────────────────────────────────────────
  MEDIA_IMPORT = 'media:import',
  MEDIA_PROBE = 'media:probe',
  MEDIA_THUMBNAIL = 'media:thumbnail',
  MEDIA_ADD_TO_PROJECT = 'media:addToProject',
  CLIP_ADD = 'clip:add',

  // ─── Transcription ──────────────────────────────────────────────────────
  TRANSCRIBE_CLIP = 'transcribe:clip',
  TRANSCRIBE_PROGRESS = 'transcribe:progress',
  TRANSCRIBE_CANCEL = 'transcribe:cancel',

  // ─── Local Whisper ──────────────────────────────────────────────────────────
  WHISPER_LOCAL_LIST_MODELS = 'whisper-local:listModels',
  WHISPER_LOCAL_DOWNLOAD_MODEL = 'whisper-local:downloadModel',
  WHISPER_LOCAL_DOWNLOAD_PROGRESS = 'whisper-local:downloadProgress',
  WHISPER_LOCAL_TRANSCRIBE = 'whisper-local:transcribe',
  WHISPER_LOCAL_TRANSCRIBE_PROGRESS = 'whisper-local:transcribeProgress',
  WHISPER_LOCAL_DELETE_MODEL = 'whisper-local:deleteModel',

  // ─── Edit ───────────────────────────────────────────────────────────────
  EDIT_COMPILE = 'edit:compile',
  EDIT_PREVIEW_SEGMENT = 'edit:previewSegment',

  // ─── Export ─────────────────────────────────────────────────────────────
  EXPORT_RENDER = 'export:render',
  EXPORT_PROGRESS = 'export:progress',

  // ─── AI ─────────────────────────────────────────────────────────────────
  AI_REMOVE_BAD_TAKES = 'ai:removeBadTakes',

  // ─── Project ────────────────────────────────────────────────────────────
  PROJECT_CREATE = 'project:create',
  PROJECT_LOAD = 'project:load',
  PROJECT_SAVE = 'project:save',
  PROJECT_LIST = 'project:list',
  PROJECT_DELETE = 'project:delete',

  // ─── Settings ───────────────────────────────────────────────────────────
  SETTINGS_GET = 'settings:get',
  SETTINGS_SET = 'settings:set',
  SETTINGS_HAS_KEYS = 'settings:hasKeys',

  // ─── App ─────────────────────────────────────────────────────────────────
  APP_GET_VERSION = 'app:getVersion',
  APP_OPEN_FILE_DIALOG = 'app:openFileDialog',
  APP_OPEN_SAVE_DIALOG = 'app:openSaveDialog',
  APP_SHOW_IN_FINDER = 'app:showInFinder',
  APP_CLEANUP_TEMP = 'app:cleanupTemp',
}

// Inline file filter type (avoids Electron namespace dependency in shared/)
export interface FileFilter {
  name: string;
  extensions: string[];
}

// Payload type mapping for each channel
export interface IpcChannelPayloads {
  [IpcChannel.MEDIA_ADD_TO_PROJECT]: {
    projectId: number;
    filePath: string;
    durationMs: number;
    width: number;
    height: number;
    fps: number;
    codec: string;
  };
  [IpcChannel.CLIP_ADD]: {
    projectId: number;
    mediaFileId: number;
    positionMs: number;
    inPointMs: number;
    outPointMs: number;
    track: number;
  };
  [IpcChannel.MEDIA_IMPORT]: { filePaths?: string[] };
  [IpcChannel.MEDIA_PROBE]: { filePath: string };
  [IpcChannel.MEDIA_THUMBNAIL]: { filePath: string; timeMs: number };
  [IpcChannel.TRANSCRIBE_CLIP]: { clipId: number; mediaFilePath: string; language: string };
  [IpcChannel.EDIT_COMPILE]: { projectId: number; outputPath: string };
  [IpcChannel.EDIT_PREVIEW_SEGMENT]: { clipId: number; startMs: number; endMs: number };
  [IpcChannel.EXPORT_RENDER]: {
    projectId: number;
    outputPath: string;
    preset: import('./types').ExportPreset;
  };
  [IpcChannel.AI_REMOVE_BAD_TAKES]: { transcriptJson: string };
  [IpcChannel.PROJECT_CREATE]: { name: string };
  [IpcChannel.PROJECT_LOAD]: { projectId: number };
  [IpcChannel.PROJECT_SAVE]: { projectId: number; state: import('./types').PartialProjectState };
  [IpcChannel.PROJECT_LIST]: Record<string, never>;
  [IpcChannel.PROJECT_DELETE]: { projectId: number };
  [IpcChannel.SETTINGS_GET]: Record<string, never>;
  [IpcChannel.SETTINGS_SET]: Partial<import('./types').AppSettings>;
  [IpcChannel.SETTINGS_HAS_KEYS]: Record<string, never>;
  [IpcChannel.APP_GET_VERSION]: Record<string, never>;
  [IpcChannel.APP_OPEN_FILE_DIALOG]: { filters?: FileFilter[] };
  [IpcChannel.APP_OPEN_SAVE_DIALOG]: { defaultPath?: string; filters?: FileFilter[] };
  [IpcChannel.APP_SHOW_IN_FINDER]: { filePath: string };
  [IpcChannel.APP_CLEANUP_TEMP]: Record<string, never>;
}
