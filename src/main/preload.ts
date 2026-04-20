import { contextBridge, ipcRenderer } from 'electron';
import type { IpcChannel } from '../shared/ipc-channels';

// Expose a typed API to the renderer via contextBridge
const electronAPI = {
  invoke: <T = unknown>(channel: string, payload?: unknown): Promise<T> => {
    return ipcRenderer.invoke(channel, payload) as Promise<T>;
  },

  send: (channel: string, payload?: unknown): void => {
    ipcRenderer.send(channel, payload);
  },

  on: (channel: string, callback: (...args: unknown[]) => void): (() => void) => {
    const listener = (_event: Electron.IpcRendererEvent, ...args: unknown[]): void => {
      callback(...args);
    };
    ipcRenderer.on(channel, listener);
    // Return cleanup function
    return () => {
      ipcRenderer.removeListener(channel, listener);
    };
  },

  once: (channel: string, callback: (...args: unknown[]) => void): void => {
    ipcRenderer.once(channel, (_event, ...args) => callback(...args));
  },

  removeAllListeners: (channel: string): void => {
    ipcRenderer.removeAllListeners(channel);
  },

  // Convenience: typed channel constants for renderer use
  channels: {
    MEDIA_IMPORT: 'media:import',
    MEDIA_PROBE: 'media:probe',
    MEDIA_THUMBNAIL: 'media:thumbnail',
    MEDIA_WAVEFORM_DATA: 'media:waveformData',
    TRANSCRIBE_CLIP: 'transcribe:clip',
    TRANSCRIBE_PROGRESS: 'transcribe:progress',
    WHISPER_LOCAL_LIST_MODELS: 'whisper-local:listModels',
    WHISPER_LOCAL_DOWNLOAD_MODEL: 'whisper-local:downloadModel',
    WHISPER_LOCAL_DOWNLOAD_PROGRESS: 'whisper-local:downloadProgress',
    WHISPER_LOCAL_TRANSCRIBE: 'whisper-local:transcribe',
    WHISPER_LOCAL_TRANSCRIBE_PROGRESS: 'whisper-local:transcribeProgress',
    WHISPER_LOCAL_DELETE_MODEL: 'whisper-local:deleteModel',
    EDIT_COMPILE: 'edit:compile',
    EDIT_PREVIEW_SEGMENT: 'edit:previewSegment',
    EXPORT_RENDER: 'export:render',
    EXPORT_PROGRESS: 'export:progress',
    AI_REMOVE_BAD_TAKES: 'ai:removeBadTakes',
    PROJECT_CREATE: 'project:create',
    PROJECT_LOAD: 'project:load',
    PROJECT_SAVE: 'project:save',
    PROJECT_LIST: 'project:list',
    PROJECT_DELETE: 'project:delete',
    SETTINGS_GET: 'settings:get',
    SETTINGS_SET: 'settings:set',
    SETTINGS_HAS_KEYS: 'settings:hasKeys',
    APP_GET_VERSION: 'app:getVersion',
    APP_OPEN_FILE_DIALOG: 'app:openFileDialog',
    APP_OPEN_SAVE_DIALOG: 'app:openSaveDialog',
    APP_SHOW_IN_FINDER: 'app:showInFinder',
    APP_CLEANUP_TEMP: 'app:cleanupTemp',
    MEDIA_ADD_TO_PROJECT: 'media:addToProject',
    CLIP_ADD: 'clip:add',
    WORDS_SOFT_DELETE: 'words:softDelete',
    WORDS_RESTORE: 'words:restore',
  } as const,
};

contextBridge.exposeInMainWorld('electronAPI', electronAPI);

export type ElectronAPI = typeof electronAPI;
