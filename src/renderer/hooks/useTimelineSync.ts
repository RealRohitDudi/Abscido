import { useEffect } from 'react';
import { useTimeline, useTranscript } from '../store';

/**
 * Keeps the timeline clips and transcript in sync:
 * - When words are deleted, calculates how much time that removes from each clip
 * - Updates the visual display of dimmed clip regions
 */
export function useTimelineSync() {
  const { clips, updateClip } = useTimeline();
  const { wordsByClipId, deletedWordIds, getActiveWords } = useTranscript();

  useEffect(() => {
    // For each clip with a transcript, compute the "effective" out point
    // based on non-deleted words. This is used to dim the deleted regions.
    for (const clip of clips) {
      const allWords = wordsByClipId[clip.id];
      if (!allWords || allWords.length === 0) continue;

      const activeWords = getActiveWords(clip.id);
      if (activeWords.length === 0) continue;

      // The active duration is the sum of keep-segment durations
      // We don't actually modify the clip's out_point here (that's only after Compile Edit)
      // Instead, we just track the deleted time for display purposes
    }
  }, [clips, wordsByClipId, deletedWordIds, updateClip, getActiveWords]);

  /**
   * Given a clip ID, returns the ranges (startMs, endMs) of deleted segments
   * for visual dimming on the timeline.
   */
  function getDeletedRangesForClip(clipId: number): Array<{ startMs: number; endMs: number }> {
    const words = wordsByClipId[clipId] ?? [];
    const deleted = words.filter((w) => deletedWordIds.has(w.id));

    if (deleted.length === 0) return [];

    // Merge consecutive deleted word ranges
    const ranges: Array<{ startMs: number; endMs: number }> = [];
    let rangeStart = deleted[0].startMs;
    let rangeEnd = deleted[0].endMs;

    for (let i = 1; i < deleted.length; i++) {
      const w = deleted[i];
      if (w.startMs - rangeEnd < 200) {
        // Merge
        rangeEnd = w.endMs;
      } else {
        ranges.push({ startMs: rangeStart, endMs: rangeEnd });
        rangeStart = w.startMs;
        rangeEnd = w.endMs;
      }
    }
    ranges.push({ startMs: rangeStart, endMs: rangeEnd });

    return ranges;
  }

  /**
   * Returns the total duration saved by deletions for a clip (in ms).
   */
  function getSavedDurationMs(clipId: number): number {
    const words = wordsByClipId[clipId] ?? [];
    return words
      .filter((w) => deletedWordIds.has(w.id))
      .reduce((sum, w) => sum + (w.endMs - w.startMs), 0);
  }

  return { getDeletedRangesForClip, getSavedDurationMs };
}
