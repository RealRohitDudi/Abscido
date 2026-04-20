import { ipcMain, dialog, shell } from 'electron';
import path from 'path';
import fs from 'fs';
import { IpcChannel } from '../../shared/ipc-channels';
import type { MediaInfo, IpcResult } from '../../shared/types';
import { ffmpegService } from '../services/ffmpeg.service';
import { clipRepo } from '../db/repositories/clip.repo';

export function registerMediaHandlers(): void {
  // ─── MEDIA_IMPORT: Open file dialog and probe selected files ───────────────
  ipcMain.handle(IpcChannel.MEDIA_IMPORT, async (_event, payload: { filePaths?: string[] }) => {
    try {
      let filePaths = payload?.filePaths;

      if (!filePaths || filePaths.length === 0) {
        const result = await dialog.showOpenDialog({
          title: 'Import Media',
          properties: ['openFile', 'multiSelections'],
          filters: [
            {
              name: 'Video & Audio',
              extensions: [
                'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'm4v',
                'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac',
              ],
            },
            { name: 'All Files', extensions: ['*'] },
          ],
        });

        if (result.canceled || result.filePaths.length === 0) {
          const response: IpcResult<never> = { success: false, error: 'Import cancelled', code: 'CANCELLED' };
          return response;
        }

        filePaths = result.filePaths;
      }

      const probed: MediaInfo[] = [];
      for (const fp of filePaths) {
        if (!fs.existsSync(fp)) {
          throw new Error(`File not found: ${fp}`);
        }
        const info = await ffmpegService.probeMedia(fp);
        probed.push(info);
      }

      const response: IpcResult<MediaInfo[]> = { success: true, data: probed };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'IMPORT_ERROR',
      };
      return response;
    }
  });

  // ─── MEDIA_PROBE: Probe a single file ──────────────────────────────────────
  ipcMain.handle(IpcChannel.MEDIA_PROBE, async (_event, payload: { filePath: string }) => {
    try {
      const info = await ffmpegService.probeMedia(payload.filePath);
      const response: IpcResult<MediaInfo> = { success: true, data: info };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'PROBE_ERROR',
      };
      return response;
    }
  });

  // ─── MEDIA_THUMBNAIL: Generate thumbnail at timestamp ──────────────────────
  ipcMain.handle(
    IpcChannel.MEDIA_THUMBNAIL,
    async (_event, payload: { filePath: string; timeMs: number; mediaFileId?: number }) => {
      try {
        const thumbPath = await ffmpegService.generateThumbnail(payload.filePath, payload.timeMs);

        // Read and convert to base64
        const data = fs.readFileSync(thumbPath);
        const base64 = data.toString('base64');

        // Update DB record if mediaFileId provided
        if (payload.mediaFileId) {
          clipRepo.updateMediaFileThumbnail(payload.mediaFileId, thumbPath);
        }

        const response: IpcResult<string> = {
          success: true,
          data: `data:image/png;base64,${base64}`,
        };
        return response;
      } catch (err) {
        const response: IpcResult<never> = {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'THUMBNAIL_ERROR',
        };
        return response;
      }
    },
  );

  // ─── APP_OPEN_FILE_DIALOG ──────────────────────────────────────────────────
  ipcMain.handle(IpcChannel.APP_OPEN_FILE_DIALOG, async (_event, payload) => {
    try {
      const result = await dialog.showOpenDialog({
        properties: ['openFile'],
        filters: payload?.filters ?? [],
      });
      const response: IpcResult<string[]> = {
        success: true,
        data: result.canceled ? [] : result.filePaths,
      };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'DIALOG_ERROR',
      };
      return response;
    }
  });

  // ─── APP_OPEN_SAVE_DIALOG ──────────────────────────────────────────────────
  ipcMain.handle(IpcChannel.APP_OPEN_SAVE_DIALOG, async (_event, payload) => {
    try {
      const result = await dialog.showSaveDialog({
        defaultPath: payload?.defaultPath,
        filters: payload?.filters ?? [],
      });
      const response: IpcResult<string | null> = {
        success: true,
        data: result.canceled ? null : (result.filePath ?? null),
      };
      return response;
    } catch (err) {
      const response: IpcResult<never> = {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'DIALOG_ERROR',
      };
      return response;
    }
  });

  // ─── APP_SHOW_IN_FINDER ────────────────────────────────────────────────────
  ipcMain.handle(IpcChannel.APP_SHOW_IN_FINDER, (_event, payload: { filePath: string }) => {
    shell.showItemInFolder(payload.filePath);
    return { success: true, data: null };
  });
}
