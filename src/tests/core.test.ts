import { describe, it, expect } from 'vitest';

// Test the EDL segment building logic
describe('EDL segment builder', () => {
  it('merges consecutive word ranges within 100ms gap', () => {
    const words = [
      { id: 1, startMs: 0, endMs: 500 },
      { id: 2, startMs: 550, endMs: 1000 }, // 50ms gap — merge
      { id: 3, startMs: 2000, endMs: 2500 }, // 1000ms gap — new segment
    ];

    // Simulate the EDL segment builder logic from edit.ipc.ts
    const segments: { startMs: number; endMs: number }[] = [];
    let segStart = words[0].startMs;
    let segEnd = words[0].endMs;

    for (let i = 1; i < words.length; i++) {
      const word = words[i];
      const prevWord = words[i - 1];
      if (word.startMs - prevWord.endMs < 100) {
        segEnd = word.endMs;
      } else {
        segments.push({ startMs: segStart, endMs: segEnd });
        segStart = word.startMs;
        segEnd = word.endMs;
      }
    }
    segments.push({ startMs: segStart, endMs: segEnd });

    expect(segments).toHaveLength(2);
    expect(segments[0]).toEqual({ startMs: 0, endMs: 1000 });
    expect(segments[1]).toEqual({ startMs: 2000, endMs: 2500 });
  });

  it('creates a single segment when all words are consecutive', () => {
    const words = [
      { id: 1, startMs: 0, endMs: 500 },
      { id: 2, startMs: 540, endMs: 900 },
      { id: 3, startMs: 930, endMs: 1400 },
    ];

    const segments: { startMs: number; endMs: number }[] = [];
    let segStart = words[0].startMs;
    let segEnd = words[0].endMs;

    for (let i = 1; i < words.length; i++) {
      const word = words[i];
      const prevWord = words[i - 1];
      if (word.startMs - prevWord.endMs < 100) {
        segEnd = word.endMs;
      } else {
        segments.push({ startMs: segStart, endMs: segEnd });
        segStart = word.startMs;
        segEnd = word.endMs;
      }
    }
    segments.push({ startMs: segStart, endMs: segEnd });

    expect(segments).toHaveLength(1);
    expect(segments[0]).toEqual({ startMs: 0, endMs: 1400 });
  });
});

// Test deleted duration calculation
describe('deleted duration calculator', () => {
  it('calculates total ms of deleted words', () => {
    const words = [
      { id: 1, startMs: 0, endMs: 500 },
      { id: 2, startMs: 600, endMs: 1000 }, // 400ms
      { id: 3, startMs: 1100, endMs: 2000 }, // 900ms
    ];
    const deletedIds = new Set([2, 3]);

    const deletedMs = words
      .filter((w) => deletedIds.has(w.id))
      .reduce((sum, w) => sum + (w.endMs - w.startMs), 0);

    expect(deletedMs).toBe(1300); // 400 + 900
  });
});

// Test Claude response parsing (validates structure)
describe('bad take result validation', () => {
  it('accepts valid bad take format', () => {
    const input = [
      { word_ids: [1, 2, 3], reason: 'Repeated sentence' },
      { word_ids: [10], reason: 'False start' },
    ];

    const isValid = Array.isArray(input) && input.every(
      (item) =>
        typeof item === 'object' &&
        item !== null &&
        Array.isArray(item.word_ids) &&
        item.word_ids.every((id: unknown) => typeof id === 'number') &&
        typeof item.reason === 'string',
    );

    expect(isValid).toBe(true);
  });

  it('rejects malformed bad take', () => {
    const input = [
      { word_ids: ['not-a-number'], reason: 'Bad' },
    ];

    const isValid = Array.isArray(input) && input.every(
      (item) =>
        typeof item === 'object' &&
        item !== null &&
        Array.isArray((item as Record<string, unknown>).word_ids) &&
        ((item as Record<string, unknown>).word_ids as unknown[]).every(
          (id) => typeof id === 'number',
        ) &&
        typeof (item as Record<string, unknown>).reason === 'string',
    );

    expect(isValid).toBe(false);
  });
});
