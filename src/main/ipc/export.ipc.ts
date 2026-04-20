import { ipcMain, BrowserWindow, app } from 'electron';
import path from 'path';
import fs from 'fs';
import { IpcChannel } from '../../shared/ipc-channels';
import type { IpcResult, ExportPreset } from '../../shared/types';
import { ffmpegService } from '../services/ffmpeg.service';
import { clipRepo } from '../db/repositories/clip.repo';
import { transcriptRepo } from '../db/repositories/transcript.repo';
import type { EditDecisionList, EDLSegment } from '../../shared/types';

export function registerExportHandlers(): void {
  ipcMain.handle(
    IpcChannel.EXPORT_RENDER,
    async (
      event,
      payload: { projectId: number; outputPath: string; preset: ExportPreset },
    ) => {
      try {
        const { projectId, outputPath, preset } = payload;

        const sendProgress = (progress: number, eta: number): void => {
          const win = BrowserWindow.fromWebContents(event.sender);
          if (win) {
            win.webContents.send(IpcChannel.EXPORT_PROGRESS, {
              progress,
              eta,
              stage: progress < 50 ? 'compiling' : 'encoding',
            });
          }
        };

        // Step 1: Build EDL and compile to a temp intermediate file
        const clips = clipRepo.findClipsByProject(projectId);
        if (clips.length === 0) {
          const response: IpcResult<never> = {
            success: false,
            error: 'No clips in timeline',
            code: 'NO_CLIPS',
          };
          return response;
        }

        const tempDir = path.join(app.getPath('temp'), 'abscido');
        if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

        const intermediateFile = path.join(tempDir, `export_intermediate_${Date.now()}.mp4`);

        const edl: EditDecisionList = {
          projectId,
          clips: [],
        };

        for (const clip of clips) {
          const mediaFile = clipRepo.findMediaFileById(clip.mediaFileId);
          if (!mediaFile) continue;

          const activeWords = transcriptRepo.findActiveWordsByClip(clip.id);
          const keepSegments: EDLSegment[] = [];

          if (activeWords.length === 0) {
            keepSegments.push({ startMs: clip.inPointMs, endMs: clip.outPointMs });
          } else {
            let segStart = activeWords[0].startMs;
            let segEnd = activeWords[0].endMs;

            for (let i = 1; i < activeWords.length; i++) {
              const word = activeWords[i];
              const prevWord = activeWords[i - 1];

              if (word.startMs - prevWord.endMs < 100) {
                segEnd = word.endMs;
              } else {
                keepSegments.push({ startMs: segStart, endMs: segEnd });
                segStart = word.startMs;
                segEnd = word.endMs;
              }
            }
            keepSegments.push({ startMs: segStart, endMs: segEnd });
          }

          edl.clips.push({
            clipId: clip.id,
            mediaFilePath: mediaFile.filePath,
            segments: keepSegments,
          });
        }

        // Compile EDL (0-50% progress)
        await ffmpegService.compileEdl(edl, intermediateFile, (progress) => {
          sendProgress(Math.round(progress * 0.5), 0);
        });

        // Step 2: Render final export with preset (50-100% progress)
        await ffmpegService.renderExport(intermediateFile, outputPath, preset, (progress, eta) => {
          sendProgress(50 + Math.round(progress * 0.5), eta);
        });

        // Clean up intermediate
        try {
          fs.unlinkSync(intermediateFile);
        } catch {
          // Ignore
        }

        const response: IpcResult<{ outputPath: string }> = {
          success: true,
          data: { outputPath },
        };
        return response;
      } catch (err) {
        const response: IpcResult<never> = {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'EXPORT_ERROR',
        };
        return response;
      }
    },
  );
}
