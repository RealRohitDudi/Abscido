import { ipcMain, app } from 'electron';
import { IpcChannel } from '../../shared/ipc-channels';
import type {
  Project,
  FullProjectState,
  PartialProjectState,
  IpcResult,
  AppSettings,
} from '../../shared/types';
import { projectRepo } from '../db/repositories/project.repo';
import { clipRepo } from '../db/repositories/clip.repo';
import { transcriptRepo } from '../db/repositories/transcript.repo';
import { projectService } from '../services/project.service';
import Store from 'electron-store';
import { registerMediaHandlers } from './media.ipc';
import { registerTranscribeHandlers } from './transcribe.ipc';
import { registerEditHandlers } from './edit.ipc';
import { registerExportHandlers } from './export.ipc';
import { registerAiHandlers } from './ai.ipc';
import { registerWhisperLocalHandlers } from './whisper-local.ipc';

interface StoreSchema {
  openaiApiKey: string;
  anthropicApiKey: string;
  defaultLanguage: string;
  defaultExportPath: string;
}

const store = new Store<StoreSchema>();

export function registerAllHandlers(): void {
  // Register domain handlers
  registerMediaHandlers();
  registerTranscribeHandlers();
  registerEditHandlers();
  registerExportHandlers();
  registerAiHandlers();
  registerWhisperLocalHandlers();

  // ─── PROJECT handlers ──────────────────────────────────────────────────────

  ipcMain.handle(IpcChannel.PROJECT_CREATE, (_event, payload: { name: string }) => {
    try {
      const project = projectRepo.create(payload.name);
      const response: IpcResult<Project> = { success: true, data: project };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'PROJECT_CREATE_ERROR',
      };
      return response;
    }
  });

  ipcMain.handle(IpcChannel.PROJECT_LOAD, (_event, payload: { projectId: number }) => {
    try {
      const state = projectService.loadProject(payload.projectId);
      const response: IpcResult<FullProjectState> = { success: true, data: state };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'PROJECT_LOAD_ERROR',
      };
      return response;
    }
  });

  ipcMain.handle(
    IpcChannel.PROJECT_SAVE,
    (_event, payload: { projectId: number; state: PartialProjectState }) => {
      try {
        projectService.saveProject(payload.projectId, payload.state);
        const response: IpcResult<null> = { success: true, data: null };
        return response;
      } catch (err) {
        const response: IpcResult<never> = {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'PROJECT_SAVE_ERROR',
        };
        return response;
      }
    },
  );

  ipcMain.handle(IpcChannel.PROJECT_LIST, () => {
    try {
      const projects = projectRepo.findAll();
      const response: IpcResult<Project[]> = { success: true, data: projects };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'PROJECT_LIST_ERROR',
      };
      return response;
    }
  });

  ipcMain.handle(IpcChannel.PROJECT_DELETE, (_event, payload: { projectId: number }) => {
    try {
      projectRepo.delete(payload.projectId);
      const response: IpcResult<null> = { success: true, data: null };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'PROJECT_DELETE_ERROR',
      };
      return response;
    }
  });

  // ─── SETTINGS handlers ─────────────────────────────────────────────────────

  ipcMain.handle(IpcChannel.SETTINGS_GET, () => {
    const settings: AppSettings = {
      openaiApiKey: store.get('openaiApiKey', '') as string,
      anthropicApiKey: store.get('anthropicApiKey', '') as string,
      defaultLanguage: store.get('defaultLanguage', 'en') as string,
      defaultExportPath: store.get('defaultExportPath', '') as string,
    };
    // Mask keys for renderer (only show if set)
    const masked: AppSettings = {
      ...settings,
      openaiApiKey: settings.openaiApiKey ? '••••••••••••••••' : '',
      anthropicApiKey: settings.anthropicApiKey ? '••••••••••••••••' : '',
    };
    const response: IpcResult<AppSettings> = { success: true, data: masked };
    return response;
  });

  ipcMain.handle(IpcChannel.SETTINGS_SET, (_event, payload: Partial<AppSettings>) => {
    try {
      if (payload.openaiApiKey !== undefined && payload.openaiApiKey !== '••••••••••••••••') {
        store.set('openaiApiKey', payload.openaiApiKey);
      }
      if (payload.anthropicApiKey !== undefined && payload.anthropicApiKey !== '••••••••••••••••') {
        store.set('anthropicApiKey', payload.anthropicApiKey);
      }
      if (payload.defaultLanguage !== undefined) {
        store.set('defaultLanguage', payload.defaultLanguage);
      }
      if (payload.defaultExportPath !== undefined) {
        store.set('defaultExportPath', payload.defaultExportPath);
      }
      const response: IpcResult<null> = { success: true, data: null };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'SETTINGS_ERROR',
      };
      return response;
    }
  });

  ipcMain.handle(IpcChannel.SETTINGS_HAS_KEYS, () => {
    const hasOpenAI = !!(store.get('openaiApiKey', '') as string);
    const hasAnthropic = !!(store.get('anthropicApiKey', '') as string);
    const response: IpcResult<{ hasOpenAI: boolean; hasAnthropic: boolean }> = {
      success: true,
      data: { hasOpenAI, hasAnthropic },
    };
    return response;
  });

  // ─── APP handlers ──────────────────────────────────────────────────────────

  ipcMain.handle(IpcChannel.APP_GET_VERSION, () => {
    return { success: true, data: app.getVersion() };
  });

  ipcMain.handle(IpcChannel.APP_CLEANUP_TEMP, () => {
    try {
      projectService.recoverFromCrash();
      return { success: true, data: null };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'CLEANUP_ERROR',
      };
    }
  });

  // Additional DB handlers for media files and clips
  ipcMain.handle(
    'media:addToProject',
    (
      _event,
      payload: {
        projectId: number;
        filePath: string;
        durationMs: number;
        width: number;
        height: number;
        fps: number;
        codec: string;
      },
    ) => {
      try {
        const mediaFile = clipRepo.createMediaFile({
          projectId: payload.projectId,
          filePath: payload.filePath,
          durationMs: payload.durationMs,
          width: payload.width,
          height: payload.height,
          fps: payload.fps,
          codec: payload.codec,
          thumbnailPath: null,
        });
        return { success: true, data: mediaFile };
      } catch (err) {
        return {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'ADD_MEDIA_ERROR',
        };
      }
    },
  );

  ipcMain.handle(
    'clip:add',
    (
      _event,
      payload: {
        projectId: number;
        mediaFileId: number;
        positionMs: number;
        inPointMs: number;
        outPointMs: number;
        track: number;
      },
    ) => {
      try {
        const clip = clipRepo.createClip(payload);
        return { success: true, data: clip };
      } catch (err) {
        return {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'ADD_CLIP_ERROR',
        };
      }
    },
  );

  ipcMain.handle('words:softDelete', (_event, payload: { wordIds: number[] }) => {
    try {
      transcriptRepo.softDeleteWords(payload.wordIds);
      return { success: true, data: null };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'DELETE_WORDS_ERROR',
      };
    }
  });

  ipcMain.handle('words:restore', (_event, payload: { wordIds: number[] }) => {
    try {
      transcriptRepo.restoreWords(payload.wordIds);
      return { success: true, data: null };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'RESTORE_WORDS_ERROR',
      };
    }
  });

  console.log('[IPC] All handlers registered');
}
