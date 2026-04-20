import { ipcMain } from 'electron';
import { IpcChannel } from '../../shared/ipc-channels';
import type { BadTakeResult, IpcResult } from '../../shared/types';
import { claudeService } from '../services/claude.service';
import Store from 'electron-store';

interface StoreSchema {
  openaiApiKey: string;
  anthropicApiKey: string;
  defaultLanguage: string;
  defaultExportPath: string;
}

const store = new Store<StoreSchema>();

export function registerAiHandlers(): void {
  ipcMain.handle(
    IpcChannel.AI_REMOVE_BAD_TAKES,
    async (_event, payload: { transcriptJson: string }) => {
      try {
        const apiKey = store.get('anthropicApiKey', '') as string;
        if (!apiKey) {
          const response: IpcResult<never> = {
            success: false,
            error: 'Anthropic API key not configured. Please add it in Settings.',
            code: 'NO_API_KEY',
          };
          return response;
        }

        const results = await claudeService.detectBadTakes(payload.transcriptJson, apiKey);
        const response: IpcResult<BadTakeResult[]> = { success: true, data: results };
        return response;
      } catch (err) {
        const response: IpcResult<never> = {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'AI_ERROR',
        };
        return response;
      }
    },
  );
}
