import OpenAI from 'openai';
import fs from 'fs';
import type { TranscriptResult, TranscriptWord, TranscriptSegment } from '../../shared/types';
import { transcriptRepo } from '../db/repositories/transcript.repo';

function getClient(apiKey: string): OpenAI {
  return new OpenAI({ apiKey });
}

async function withRetry<T>(
  fn: () => Promise<T>,
  maxAttempts = 3,
  baseDelayMs = 1000,
): Promise<T> {
  let lastError: Error = new Error('Unknown error');
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      const isRetryable =
        lastError.message.includes('429') ||
        lastError.message.includes('500') ||
        lastError.message.includes('503') ||
        lastError.message.includes('rate_limit') ||
        lastError.message.includes('overloaded');

      if (!isRetryable || attempt === maxAttempts) throw lastError;

      const delay = baseDelayMs * Math.pow(2, attempt - 1) + Math.random() * 500;
      console.log(`[Whisper] Retrying attempt ${attempt + 1} in ${Math.round(delay)}ms...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw lastError;
}

// Whisper verbose_json word-level response types
interface WhisperWord {
  word: string;
  start: number;
  end: number;
}

interface WhisperSegment {
  id: number;
  text: string;
  start: number;
  end: number;
  words?: WhisperWord[];
}

interface WhisperVerboseResponse {
  task: string;
  language: string;
  duration: number;
  text: string;
  words?: WhisperWord[];
  segments?: WhisperSegment[];
}

export const whisperService = {
  abortController: null as AbortController | null,

  cancel(): void {
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = null;
    }
  },
  /**
   * Transcribe a WAV file using OpenAI Whisper API with word-level timestamps.
   * Stores results in the database and returns the full transcript.
   */
  async transcribeClip(
    clipId: number,
    wavPath: string,
    language: string,
    apiKey: string,
    onProgress: (stage: string, progress: number) => void,
  ): Promise<TranscriptResult> {
    const client = getClient(apiKey);

    onProgress('uploading', 10);

    const fileStream = fs.createReadStream(wavPath);

    onProgress('transcribing', 30);

    this.abortController = new AbortController();

    let response;
    try {
      response = await withRetry(async () => {
        const res = await client.audio.transcriptions.create(
          {
            model: 'whisper-1',
            file: fileStream,
            language,
            response_format: 'verbose_json',
            timestamp_granularities: ['word', 'segment'],
          },
          { signal: this.abortController?.signal }
        );
        return res as unknown as WhisperVerboseResponse;
      });
    } catch (err: any) {
      if (err.name === 'AbortError' || err.message?.includes('abort')) {
        throw new Error('CANCELLED_BY_USER');
      }
      throw err;
    }

    this.abortController = null;

    onProgress('processing', 70);

    // Map Whisper words to TranscriptWord[]
    const wordObjs: Omit<TranscriptWord, 'id'>[] = [];

    // Whisper returns words at top level when timestamp_granularities includes "word"
    const rawWords: WhisperWord[] = [];

    if (response.words && response.words.length > 0) {
      rawWords.push(...response.words);
    } else if (response.segments) {
      // Fall back to per-segment words
      for (const seg of response.segments) {
        if (seg.words) rawWords.push(...seg.words);
      }
    }

    for (const w of rawWords) {
      wordObjs.push({
        clipId,
        word: w.word.trim(),
        startMs: Math.round(w.start * 1000),
        endMs: Math.round(w.end * 1000),
        confidence: 1.0,
        speaker: null,
        isDeleted: false,
      });
    }

    // Map segments
    const segmentObjs: Omit<TranscriptSegment, 'id'>[] = [];
    if (response.segments) {
      for (const seg of response.segments) {
        segmentObjs.push({
          clipId,
          text: seg.text.trim(),
          startMs: Math.round(seg.start * 1000),
          endMs: Math.round(seg.end * 1000),
          isDeleted: false,
        });
      }
    } else if (wordObjs.length > 0) {
      // Create one big segment from all words if no segment data
      segmentObjs.push({
        clipId,
        text: response.text,
        startMs: wordObjs[0].startMs,
        endMs: wordObjs[wordObjs.length - 1].endMs,
        isDeleted: false,
      });
    }

    onProgress('saving', 85);

    // Clear any existing transcript for this clip and save fresh
    transcriptRepo.clearTranscript(clipId);
    const savedWords = transcriptRepo.insertWords(wordObjs);
    const savedSegments = transcriptRepo.insertSegments(segmentObjs);

    onProgress('complete', 100);

    return {
      clipId,
      words: savedWords,
      segments: savedSegments,
    };
  },
};
