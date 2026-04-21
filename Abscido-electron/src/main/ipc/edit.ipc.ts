import { ipcMain, BrowserWindow, app } from 'electron';
import path from 'path';
import fs from 'fs';
import { IpcChannel } from '../../shared/ipc-channels';
import type { IpcResult, EditDecisionList, EDLSegment } from '../../shared/types';
import { ffmpegService } from '../services/ffmpeg.service';
import { clipRepo } from '../db/repositories/clip.repo';
import { transcriptRepo } from '../db/repositories/transcript.repo';

export function registerEditHandlers(): void {
  // ─── EDIT_COMPILE: Build EDL from non-deleted words and cut video ──────────
  ipcMain.handle(
    IpcChannel.EDIT_COMPILE,
    async (event, payload: { projectId: number; outputPath: string }) => {
      try {
        const { projectId, outputPath } = payload;

        const sendProgress = (progress: number): void => {
          const win = BrowserWindow.fromWebContents(event.sender);
          if (win) {
            win.webContents.send(IpcChannel.EXPORT_PROGRESS, {
              progress,
              eta: 0,
              stage: 'compiling',
            });
          }
        };

        // Get all active clips for this project
        const clips = clipRepo.findClipsByProject(projectId);
        if (clips.length === 0) {
          const response: IpcResult<never> = {
            success: false,
            error: 'No clips in timeline',
            code: 'NO_CLIPS',
          };
          return response;
        }

        // Build EDL from non-deleted transcript words
        const edl: EditDecisionList = {
          projectId,
          clips: [],
        };

        for (const clip of clips) {
          const mediaFile = clipRepo.findMediaFileById(clip.mediaFileId);
          if (!mediaFile) continue;

          // Get non-deleted words for this clip
          const activeWords = transcriptRepo.findActiveWordsByClip(clip.id);

          if (activeWords.length === 0) {
            // If no transcript, include the whole clip
            edl.clips.push({
              clipId: clip.id,
              mediaFilePath: mediaFile.filePath,
              segments: [{ startMs: clip.inPointMs, endMs: clip.outPointMs }],
            });
            continue;
          }

          // Build keep segments from consecutive non-deleted word ranges
          const keepSegments: EDLSegment[] = [];
          let segStart = activeWords[0].startMs;
          let segEnd = activeWords[0].endMs;

          for (let i = 1; i < activeWords.length; i++) {
            const word = activeWords[i];
            const prevWord = activeWords[i - 1];

            // If gap between words is very small (<100ms), merge segments
            if (word.startMs - prevWord.endMs < 100) {
              segEnd = word.endMs;
            } else {
              // Check if words are consecutive (no deleted words between them)
              keepSegments.push({ startMs: segStart, endMs: segEnd });
              segStart = word.startMs;
              segEnd = word.endMs;
            }
          }
          keepSegments.push({ startMs: segStart, endMs: segEnd });

          edl.clips.push({
            clipId: clip.id,
            mediaFilePath: mediaFile.filePath,
            segments: keepSegments,
          });
        }

        // Compile the EDL
        await ffmpegService.compileEdl(edl, outputPath, sendProgress);

        const response: IpcResult<{ outputPath: string }> = {
          success: true,
          data: { outputPath },
        };
        return response;
      } catch (err) {
        const response: IpcResult<never> = {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'COMPILE_ERROR',
        };
        return response;
      }
    },
  );

  // ─── EDIT_PREVIEW_SEGMENT: Create a temp preview of a segment ─────────────
  ipcMain.handle(
    IpcChannel.EDIT_PREVIEW_SEGMENT,
    async (_event, payload: { clipId: number; startMs: number; endMs: number }) => {
      try {
        const { clipId, startMs, endMs } = payload;

        const clip = clipRepo.findClipById(clipId);
        if (!clip) {
          const response: IpcResult<never> = {
            success: false,
            error: `Clip ${clipId} not found`,
            code: 'CLIP_NOT_FOUND',
          };
          return response;
        }

        const mediaFile = clipRepo.findMediaFileById(clip.mediaFileId);
        if (!mediaFile) {
          const response: IpcResult<never> = {
            success: false,
            error: 'Media file not found',
            code: 'MEDIA_NOT_FOUND',
          };
          return response;
        }

        const tempDir = path.join(app.getPath('temp'), 'abscido');
        if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

        const previewPath = path.join(tempDir, `preview_${clipId}_${Date.now()}.mp4`);

        const edl: EditDecisionList = {
          projectId: clip.projectId,
          clips: [
            {
              clipId,
              mediaFilePath: mediaFile.filePath,
              segments: [{ startMs, endMs }],
            },
          ],
        };

        await ffmpegService.compileEdl(edl, previewPath, () => {});

        const response: IpcResult<string> = { success: true, data: previewPath };
        return response;
      } catch (err) {
        const response: IpcResult<never> = {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'PREVIEW_ERROR',
        };
        return response;
      }
    },
  );
}
