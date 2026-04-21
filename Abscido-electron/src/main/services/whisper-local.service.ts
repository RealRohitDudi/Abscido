/**
 * Local on-device Whisper transcription service using @xenova/transformers.
 *
 * Models are downloaded once and cached in the app's userData directory.
 * No API key required — inference runs entirely on the local machine.
 * Uses ONNX Runtime under the hood; supports Apple Silicon via Core ML backend.
 */

import { app } from 'electron';
import path from 'path';
import { Worker } from 'worker_threads';
import fs from 'fs';
import type { TranscriptWord, TranscriptSegment } from '../../shared/types';
import { ffmpegService } from './ffmpeg.service';
import os from 'os';

// ─── Model definitions ──────────────────────────────────────────────────────

export type WhisperLocalModelId =
  | 'Xenova/whisper-tiny'
  | 'Xenova/whisper-tiny.en'
  | 'Xenova/whisper-base'
  | 'Xenova/whisper-base.en'
  | 'Xenova/whisper-small'
  | 'Xenova/whisper-small.en'
  | 'Xenova/whisper-medium'
  | 'Xenova/whisper-medium.en';

export interface WhisperLocalModel {
  id: WhisperLocalModelId;
  label: string;
  sizeLabel: string;
  sizeMB: number;
  englishOnly: boolean;
  isDownloaded: boolean;
}

export const WHISPER_LOCAL_MODELS: Omit<WhisperLocalModel, 'isDownloaded'>[] = [
  {
    id: 'Xenova/whisper-tiny',
    label: 'Tiny (Multilingual incl. Hindi)',
    sizeLabel: '~75 MB',
    sizeMB: 75,
    englishOnly: false,
  },
  {
    id: 'Xenova/whisper-tiny.en',
    label: 'Tiny (English Only)',
    sizeLabel: '~75 MB',
    sizeMB: 75,
    englishOnly: true,
  },
  {
    id: 'Xenova/whisper-base',
    label: 'Base (Multilingual incl. Hindi)',
    sizeLabel: '~145 MB',
    sizeMB: 145,
    englishOnly: false,
  },
  {
    id: 'Xenova/whisper-base.en',
    label: 'Base (English Only)',
    sizeLabel: '~145 MB',
    sizeMB: 145,
    englishOnly: true,
  },
  {
    id: 'Xenova/whisper-small',
    label: 'Small (Multilingual incl. Hindi)',
    sizeLabel: '~480 MB',
    sizeMB: 480,
    englishOnly: false,
  },
  {
    id: 'Xenova/whisper-small.en',
    label: 'Small (English Only)',
    sizeLabel: '~480 MB',
    sizeMB: 480,
    englishOnly: true,
  },
  {
    id: 'Xenova/whisper-medium',
    label: 'Medium (Multilingual incl. Hindi)',
    sizeLabel: '~1.5 GB',
    sizeMB: 1500,
    englishOnly: false,
  },
  {
    id: 'Xenova/whisper-medium.en',
    label: 'Medium (English Only)',
    sizeLabel: '~1.5 GB',
    sizeMB: 1500,
    englishOnly: true,
  },
];

// ─── Helpers ────────────────────────────────────────────────────────────────

function getModelsDir(): string {
  const dir = path.join(app.getPath('userData'), 'whisper-models');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return dir;
}

/**
 * Determine if a model's ONNX encoder file is present (download complete).
 * Transformers.js caches to: <cacheDir>/<org>/<model>/onnx/encoder_model.onnx
 */
function isModelDownloaded(modelId: WhisperLocalModelId): boolean {
  const [org, model] = modelId.split('/');
  const modelsDir = getModelsDir();
  // Check for the quantized encoder (smallest required file)
  const encoderPath = path.join(modelsDir, org, model, 'onnx', 'encoder_model.onnx');
  const encoderQuantPath = path.join(modelsDir, org, model, 'onnx', 'encoder_model_quantized.onnx');
  return fs.existsSync(encoderPath) || fs.existsSync(encoderQuantPath);
}

/** Read a 16-bit PCM WAV file and return Float32Array of samples */
function readWavToFloat32(wavPath: string): Float32Array {
  const buf = fs.readFileSync(wavPath);

  // Minimal WAV parser — assumes 16-bit PCM mono
  // WAV header is 44 bytes for simple PCM files
  let dataOffset = 12; // skip RIFF header
  while (dataOffset < buf.length - 8) {
    const chunkId = buf.toString('ascii', dataOffset, dataOffset + 4);
    const chunkSize = buf.readUInt32LE(dataOffset + 4);
    if (chunkId === 'data') {
      dataOffset += 8;
      break;
    }
    dataOffset += 8 + chunkSize;
  }

  const samples = (buf.length - dataOffset) / 2;
  const float32 = new Float32Array(samples);
  for (let i = 0; i < samples; i++) {
    const int16 = buf.readInt16LE(dataOffset + i * 2);
    float32[i] = int16 / 32768.0;
  }
  return float32;
}

// ─── Pipeline cache (avoid reloading on every transcription) ────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const pipelineCache = new Map<string, any>();

// ─── Service ────────────────────────────────────────────────────────────────

export interface LocalTranscribeResult {
  words: Omit<TranscriptWord, 'id' | 'clipId' | 'isDeleted'>[];
  segments: Omit<TranscriptSegment, 'id' | 'clipId'>[];
  fullText: string;
}

export const whisperLocalService = {
  /**
   * Return list of available models with download status
   */
  listModels(): WhisperLocalModel[] {
    return WHISPER_LOCAL_MODELS.map((m) => ({
      ...m,
      isDownloaded: isModelDownloaded(m.id),
    }));
  },

  cancelRequested: false,

  cancel(): void {
    this.cancelRequested = true;
  },

  /**
   * Download a model. Calls onProgress(0–100) during download.
   * Uses @xenova/transformers' built-in download with progress reporting.
   */
  async downloadModel(
    modelId: WhisperLocalModelId,
    onProgress: (progress: number, status: string) => void,
  ): Promise<void> {
    onProgress(0, 'Starting download…');

    // Dynamically import to avoid loading at startup
    // Use Function to bypass TypeScript's transpilation of import() to require()
    const { pipeline, env } = await new Function('return import("@xenova/transformers")')();

    // Point cache to our managed directory
    env.cacheDir = getModelsDir();
    env.allowLocalModels = true;

    console.log(`[WhisperLocal] Downloading model: ${modelId} → ${getModelsDir()}`);

    // The pipeline call itself triggers the download with progress callbacks
    // We need to override the progress callback
    const originalProgress = env.backends?.onnx?.wasm?.wasmPaths;
    void originalProgress;

    let lastPct = 0;

    const pipe = await pipeline(
      'automatic-speech-recognition',
      modelId,
      {
        progress_callback: (progressInfo: { status: string; name?: string; progress?: number; loaded?: number; total?: number }) => {
          const { status } = progressInfo;

          if (status === 'downloading' || status === 'progress') {
            const pct = progressInfo.progress ?? 0;
            if (Math.floor(pct) > lastPct) {
              lastPct = Math.floor(pct);
              const loaded = progressInfo.loaded ?? 0;
              const total = progressInfo.total ?? 1;
              const loadedMB = (loaded / 1024 / 1024).toFixed(1);
              const totalMB = (total / 1024 / 1024).toFixed(1);
              onProgress(
                Math.round(pct),
                `Downloading ${progressInfo.name?.split('/').pop() ?? 'model'} (${loadedMB} / ${totalMB} MB)`,
              );
            }
          } else if (status === 'loading') {
            onProgress(95, 'Loading model into memory…');
          } else if (status === 'ready') {
            onProgress(100, 'Model ready');
          } else if (status === 'initiate') {
            onProgress(lastPct, `Preparing: ${progressInfo.name?.split('/').pop() ?? ''}`);
          }
        },
      },
    );

    // Cache pipeline for subsequent use
    pipelineCache.set(modelId, pipe);
    console.log(`[WhisperLocal] Model ready: ${modelId}`);
  },

  /**
   * Delete a downloaded model from disk
   */
  deleteModel(modelId: WhisperLocalModelId): void {
    const [org, model] = modelId.split('/');
    const modelDir = path.join(getModelsDir(), org, model);
    if (fs.existsSync(modelDir)) {
      fs.rmSync(modelDir, { recursive: true, force: true });
      console.log(`[WhisperLocal] Deleted model: ${modelId}`);
    }
    pipelineCache.delete(modelId);
  },

  /**
   * Transcribe a media file using a locally downloaded Whisper model.
   *
   * Steps:
   *  1. Extract 16kHz mono WAV with ffmpeg
   *  2. Load WAV as Float32Array
   *  3. Run inference with transformers.js pipeline
   *  4. Map word timestamps to TranscriptWord format
   */
  async transcribeLocal(
    mediaFilePath: string,
    modelId: WhisperLocalModelId,
    language: string,
    onProgress: (progress: number, status: string) => void,
  ): Promise<LocalTranscribeResult> {
    // Use Function to bypass TypeScript's transpilation of import() to require()
    const { pipeline, env } = await new Function('return import("@xenova/transformers")')();
    env.cacheDir = getModelsDir();
    env.allowLocalModels = true;

    // Step 1: Extract audio
    onProgress(5, 'Extracting audio…');
    const tmpDir = path.join(os.tmpdir(), 'abscido');
    if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
    const wavPath = path.join(tmpDir, `local_whisper_${Date.now()}.wav`);

    try {
      await ffmpegService.extractAudio(mediaFilePath, wavPath, { sampleRate: 16000 });
      onProgress(15, 'Audio extracted, loading model…');

      // Step 2 & 3: Run inference in Worker thread
      this.cancelRequested = false;

      const workerPath = path.join(__dirname, '..', 'workers', 'whisper.worker.js');
      const output = await new Promise<any>((resolve, reject) => {
        const worker = new Worker(workerPath, {
          workerData: {
            wavPath,
            modelId,
            language: language === 'auto' ? 'auto' : language,
            modelsDir: getModelsDir(),
          },
        });

        // If cancel is requested while waiting for worker
        const cancelCheckInterval = setInterval(() => {
          if (this.cancelRequested) {
            clearInterval(cancelCheckInterval);
            worker.terminate();
            reject(new Error('CANCELLED_BY_USER'));
          }
        }, 500);

        worker.on('message', (msg) => {
          if (msg.type === 'progress') {
            onProgress(msg.progress, msg.status);
          } else if (msg.type === 'done') {
            clearInterval(cancelCheckInterval);
            resolve(msg.output);
            worker.terminate();
          } else if (msg.type === 'error') {
            clearInterval(cancelCheckInterval);
            reject(new Error(msg.error));
            worker.terminate();
          }
        });

        worker.on('error', (err) => {
          clearInterval(cancelCheckInterval);
          reject(err);
        });

        worker.on('exit', (code) => {
          clearInterval(cancelCheckInterval);
          if (code !== 0) {
            reject(new Error(`Worker stopped with exit code ${code}`));
          }
        });
      });

      // Pass completion message so UI jumps to 100% or indeterminate stops
      onProgress(90, 'Processing results…');

      // Step 5: Map results to our format
      const words: Omit<TranscriptWord, 'id' | 'clipId' | 'isDeleted'>[] = [];
      const segments: Omit<TranscriptSegment, 'id' | 'clipId'>[] = [];
      let wordIndex = 0;

      // Transformers.js returns: { text, chunks: [{ text, timestamp: [startSecs, endSecs] }] }
      const chunks = output?.chunks as Array<{ text: string; timestamp: [number, number | null] }> | undefined;

      if (chunks && chunks.length > 0) {
        // Word-level chunks
        let currentSegmentWords: typeof words = [];
        let segmentStartMs = 0;

        for (const chunk of chunks) {
          const word = chunk.text.trim();
          if (!word) continue;

          const startMs = Math.round((chunk.timestamp[0] ?? 0) * 1000);
          const endMs = Math.round((chunk.timestamp[1] ?? chunk.timestamp[0] + 0.3) * 1000);

          words.push({
            word,
            startMs,
            endMs,
            confidence: 1.0,
            speaker: null,
          });

          currentSegmentWords.push({
            word,
            startMs,
            endMs,
            confidence: 1.0,
            speaker: null,
          });
          wordIndex++;

          // Create segments every ~10 words or on sentence boundaries
          if (
            currentSegmentWords.length >= 10 ||
            word.endsWith('.') || word.endsWith('?') || word.endsWith('!')
          ) {
            const segEnd = endMs;
            segments.push({
              text: currentSegmentWords.map((w) => w.word).join(' '),
              startMs: segmentStartMs,
              endMs: segEnd,
              isDeleted: false,
            });
            currentSegmentWords = [];
            segmentStartMs = segEnd;
          }
        }

        // Flush remaining words into a final segment
        if (currentSegmentWords.length > 0) {
          segments.push({
            text: currentSegmentWords.map((w) => w.word).join(' '),
            startMs: segmentStartMs,
            endMs: currentSegmentWords[currentSegmentWords.length - 1].endMs,
            isDeleted: false,
          });
        }
      } else {
        // Fallback: no word timestamps, create one big segment
        const fullText = (output?.text as string) ?? '';
        const rawWords = fullText.trim().split(/\s+/);
        const fileSize = fs.statSync(wavPath).size;
        const totalDurationMs = Math.max(0, (fileSize - 44) / 32); // 16kHz 16-bit mono -> 32 bytes per ms

        rawWords.forEach((w, i) => {
          const startMs = Math.round((i / rawWords.length) * totalDurationMs);
          const endMs = Math.round(((i + 1) / rawWords.length) * totalDurationMs);
          words.push({ word: w, startMs, endMs, confidence: 1.0, speaker: null });
        });

        segments.push({
          text: fullText.trim(),
          startMs: 0,
          endMs: totalDurationMs,
          isDeleted: false,
        });
      }

      onProgress(100, 'Done');

      return {
        words,
        segments,
        fullText: output?.text as string ?? words.map((w) => w.word).join(' '),
      };
    } finally {
      // Clean up temp wav
      try {
        if (fs.existsSync(wavPath)) fs.unlinkSync(wavPath);
      } catch { /* ignore */ }
    }
  },
};
