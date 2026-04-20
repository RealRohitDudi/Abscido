import Anthropic from '@anthropic-ai/sdk';
import type { BadTakeResult } from '../../shared/types';

const SYSTEM_PROMPT = `You are a professional video editor assistant. You receive a transcript of a video recording with word-level timestamps. Your job is to identify "bad takes" — repeated sentences, stutters, filler restarts (e.g. "um... actually let me restart", repeated identical phrases), false starts, and clearly botched delivery attempts.

Return ONLY a JSON array of objects, no explanation:
[{ "word_ids": [number], "reason": string }]

Each object represents one bad take: list all word IDs that belong to that bad take, and a short human-readable reason (e.g. "Repeated sentence", "False start", "Stutter restart").

If there are no bad takes, return an empty array: []`;

function getClient(apiKey: string): Anthropic {
  return new Anthropic({ apiKey });
}

async function withRetry<T>(
  fn: () => Promise<T>,
  maxAttempts = 3,
  baseDelayMs = 1500,
): Promise<T> {
  let lastError: Error = new Error('Unknown error');
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      const isRetryable =
        lastError.message.includes('overloaded') ||
        lastError.message.includes('529') ||
        lastError.message.includes('429') ||
        lastError.message.includes('500') ||
        lastError.message.includes('503');

      if (!isRetryable || attempt === maxAttempts) throw lastError;

      const delay = baseDelayMs * Math.pow(2, attempt - 1) + Math.random() * 1000;
      console.log(`[Claude] Retrying attempt ${attempt + 1} in ${Math.round(delay)}ms...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw lastError;
}

function validateBadTakeResults(parsed: unknown): BadTakeResult[] {
  if (!Array.isArray(parsed)) {
    throw new Error('Claude response is not an array');
  }

  return parsed.map((item: unknown, index: number) => {
    if (typeof item !== 'object' || item === null) {
      throw new Error(`Item ${index} is not an object`);
    }

    const obj = item as Record<string, unknown>;

    if (!Array.isArray(obj['word_ids'])) {
      throw new Error(`Item ${index} missing word_ids array`);
    }
    if (typeof obj['reason'] !== 'string') {
      throw new Error(`Item ${index} missing reason string`);
    }

    const wordIds = obj['word_ids'] as unknown[];
    if (!wordIds.every((id) => typeof id === 'number')) {
      throw new Error(`Item ${index} word_ids contains non-numbers`);
    }

    return {
      wordIds: wordIds as number[],
      reason: obj['reason'] as string,
    };
  });
}

export const claudeService = {
  /**
   * Analyze transcript and detect bad takes using Claude.
   */
  async detectBadTakes(transcriptJson: string, apiKey: string): Promise<BadTakeResult[]> {
    const client = getClient(apiKey);

    const response = await withRetry(async () => {
      return client.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 4096,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: 'user',
            content: transcriptJson,
          },
        ],
      });
    });

    const rawText = response.content[0].type === 'text' ? response.content[0].text : '';

    // Extract JSON from the response (may be wrapped in markdown code blocks)
    let jsonText = rawText.trim();
    const jsonMatch = jsonText.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (jsonMatch) {
      jsonText = jsonMatch[1].trim();
    }

    // Find JSON array in response
    const arrayMatch = jsonText.match(/\[[\s\S]*\]/);
    if (!arrayMatch) {
      console.warn('[Claude] No JSON array found in response, returning empty');
      return [];
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(arrayMatch[0]);
    } catch (err) {
      throw new Error(`Failed to parse Claude response as JSON: ${err}`);
    }

    return validateBadTakeResults(parsed);
  },
};
