import { ipcMain, BrowserWindow, app } from 'electron';
import path from 'path';
import fs from 'fs';
import { IpcChannel } from '../../shared/ipc-channels';
import type { TranscriptResult, IpcResult } from '../../shared/types';
import { ffmpegService } from '../services/ffmpeg.service';
import { whisperService } from '../services/whisper.service';
import Store from 'electron-store';

interface StoreSchema {
  openaiApiKey: string;
  anthropicApiKey: string;
  defaultLanguage: string;
  defaultExportPath: string;
}

const store = new Store<StoreSchema>();

export function registerTranscribeHandlers(): void {
  ipcMain.on(IpcChannel.TRANSCRIBE_CANCEL, () => {
    whisperService.cancel();
    // Use dynamic import or require for whisperLocalService if necessary, or import it at top
    import('../services/whisper-local.service').then((m) => {
      m.whisperLocalService.cancel();
    }).catch(err => console.error(err));
  });

  ipcMain.handle(
    IpcChannel.TRANSCRIBE_CLIP,
    async (
      event,
      payload: { clipId: number; mediaFilePath: string; language: string },
    ) => {
      try {
        const apiKey = store.get('openaiApiKey', '') as string;
        if (!apiKey) {
          const response: IpcResult<never> = {
            success: false,
            error: 'OpenAI API key not configured. Please add it in Settings.',
            code: 'NO_API_KEY',
          };
          return response;
        }

        const { clipId, mediaFilePath, language } = payload;

        // Emit initial progress
        const sendProgress = (stage: string, progress: number): void => {
          const win = BrowserWindow.fromWebContents(event.sender);
          if (win) {
            win.webContents.send(IpcChannel.TRANSCRIBE_PROGRESS, {
              clipId,
              stage,
              progress,
            });
          }
        };

        sendProgress('extracting', 5);

        // Extract audio to temp WAV
        const tempDir = path.join(app.getPath('temp'), 'abscido');
        if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

        const wavPath = path.join(tempDir, `clip_${clipId}_${Date.now()}.wav`);

        await ffmpegService.extractAudio(mediaFilePath, wavPath, { sampleRate: 16000 });
        sendProgress('uploading', 20);

        // Transcribe
        const result = await whisperService.transcribeClip(
          clipId,
          wavPath,
          language,
          apiKey,
          (stage, progress) => sendProgress(stage, progress),
        );

        // Clean up temp WAV
        try {
          fs.unlinkSync(wavPath);
        } catch {
          // Ignore cleanup failure
        }

        const response: IpcResult<TranscriptResult> = { success: true, data: result };
        return response;
      } catch (err) {
        const response: IpcResult<never> = {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'TRANSCRIBE_ERROR',
        };
        return response;
      }
    },
  );
}
