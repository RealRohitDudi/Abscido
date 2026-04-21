import { ipcMain, BrowserWindow } from 'electron';
import { IpcChannel } from '../../shared/ipc-channels';
import type { IpcResult } from '../../shared/types';
import {
  whisperLocalService,
  type WhisperLocalModel,
  type WhisperLocalModelId,
  type LocalTranscribeResult,
} from '../services/whisper-local.service';
import { transcriptRepo } from '../db/repositories/transcript.repo';
import { clipRepo } from '../db/repositories/clip.repo';

export function registerWhisperLocalHandlers(): void {
  // ─── List available models with download status ───────────────────────────
  ipcMain.handle(IpcChannel.WHISPER_LOCAL_LIST_MODELS, () => {
    try {
      const models = whisperLocalService.listModels();
      const response: IpcResult<WhisperLocalModel[]> = { success: true, data: models };
      return response;
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : String(err),
        code: 'LIST_MODELS_ERROR',
      } satisfies IpcResult<never>;
    }
  });

  // ─── Download a model (with progress events) ──────────────────────────────
  ipcMain.handle(
    IpcChannel.WHISPER_LOCAL_DOWNLOAD_MODEL,
    async (_event, payload: { modelId: WhisperLocalModelId }) => {
      try {
        const win = BrowserWindow.getAllWindows()[0];

        await whisperLocalService.downloadModel(
          payload.modelId,
          (progress, status) => {
            if (win && !win.isDestroyed()) {
              win.webContents.send(IpcChannel.WHISPER_LOCAL_DOWNLOAD_PROGRESS, {
                modelId: payload.modelId,
                progress,
                status,
              });
            }
          },
        );

        return { success: true, data: null } satisfies IpcResult<null>;
      } catch (err) {
        return {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'DOWNLOAD_ERROR',
        } satisfies IpcResult<never>;
      }
    },
  );

  // ─── Delete a downloaded model ────────────────────────────────────────────
  ipcMain.handle(
    IpcChannel.WHISPER_LOCAL_DELETE_MODEL,
    (_event, payload: { modelId: WhisperLocalModelId }) => {
      try {
        whisperLocalService.deleteModel(payload.modelId);
        return { success: true, data: null } satisfies IpcResult<null>;
      } catch (err) {
        return {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'DELETE_MODEL_ERROR',
        } satisfies IpcResult<never>;
      }
    },
  );

  // ─── Transcribe using local model (with progress events) ──────────────────
  ipcMain.handle(
    IpcChannel.WHISPER_LOCAL_TRANSCRIBE,
    async (
      _event,
      payload: {
        clipId: number;
        mediaFilePath: string;
        modelId: WhisperLocalModelId;
        language: string;
      },
    ) => {
      try {
        const win = BrowserWindow.getAllWindows()[0];

        const result: LocalTranscribeResult = await whisperLocalService.transcribeLocal(
          payload.mediaFilePath,
          payload.modelId,
          payload.language,
          (progress, status) => {
            if (win && !win.isDestroyed()) {
              win.webContents.send(IpcChannel.WHISPER_LOCAL_TRANSCRIBE_PROGRESS, {
                clipId: payload.clipId,
                progress,
                status,
              });
            }
          },
        );

        // Persist words and segments to DB
        const wordsWithClipId = result.words.map((w, i) => ({
          ...w,
          clipId: payload.clipId,
          wordIndex: i,
          isDeleted: false,
        }));

        const segmentsWithClipId = result.segments.map((s) => ({
          ...s,
          clipId: payload.clipId,
        }));

        transcriptRepo.deleteWordsByClip(payload.clipId);
        transcriptRepo.deleteSegmentsByClip(payload.clipId);
        const savedWords = transcriptRepo.insertWords(wordsWithClipId);
        const savedSegments = transcriptRepo.insertSegments(segmentsWithClipId);

        // Mark clip as transcribed
        clipRepo.updateClip(payload.clipId, {});

        return {
          success: true,
          data: {
            words: savedWords,
            segments: savedSegments,
            fullText: result.fullText,
          },
        } satisfies IpcResult<{ words: typeof savedWords; segments: typeof savedSegments; fullText: string }>;
      } catch (err) {
        return {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'LOCAL_TRANSCRIBE_ERROR',
        } satisfies IpcResult<never>;
      }
    },
  );
}
