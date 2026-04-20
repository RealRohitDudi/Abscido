import { getDatabase } from '../database';
import type { TranscriptWord, TranscriptSegment } from '../../../shared/types';

interface TranscriptWordRow {
  id: number;
  clip_id: number;
  word: string;
  start_ms: number;
  end_ms: number;
  confidence: number;
  speaker: string | null;
  is_deleted: number;
}

interface TranscriptSegmentRow {
  id: number;
  clip_id: number;
  text: string;
  start_ms: number;
  end_ms: number;
  is_deleted: number;
}

function rowToWord(row: TranscriptWordRow): TranscriptWord {
  return {
    id: row.id,
    clipId: row.clip_id,
    word: row.word,
    startMs: row.start_ms,
    endMs: row.end_ms,
    confidence: row.confidence,
    speaker: row.speaker,
    isDeleted: row.is_deleted === 1,
  };
}

function rowToSegment(row: TranscriptSegmentRow): TranscriptSegment {
  return {
    id: row.id,
    clipId: row.clip_id,
    text: row.text,
    startMs: row.start_ms,
    endMs: row.end_ms,
    isDeleted: row.is_deleted === 1,
  };
}

export const transcriptRepo = {
  // ─── Words ─────────────────────────────────────────────────────────────────

  insertWords(words: Omit<TranscriptWord, 'id'>[]): TranscriptWord[] {
    const db = getDatabase();
    const stmt = db.prepare(`
      INSERT INTO transcript_words (clip_id, word, start_ms, end_ms, confidence, speaker, is_deleted)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);

    const insertMany = db.transaction((items: Omit<TranscriptWord, 'id'>[]) => {
      const inserted: TranscriptWord[] = [];
      for (const w of items) {
        const result = stmt.run(
          w.clipId,
          w.word,
          w.startMs,
          w.endMs,
          w.confidence,
          w.speaker ?? null,
          w.isDeleted ? 1 : 0,
        );
        inserted.push({
          ...w,
          id: result.lastInsertRowid as number,
        });
      }
      return inserted;
    });

    return insertMany(words);
  },

  findWordsByClip(clipId: number): TranscriptWord[] {
    const db = getDatabase();
    const rows = db
      .prepare('SELECT * FROM transcript_words WHERE clip_id = ? ORDER BY start_ms')
      .all(clipId) as TranscriptWordRow[];
    return rows.map(rowToWord);
  },

  findActiveWordsByClip(clipId: number): TranscriptWord[] {
    const db = getDatabase();
    const rows = db
      .prepare(
        'SELECT * FROM transcript_words WHERE clip_id = ? AND is_deleted = 0 ORDER BY start_ms',
      )
      .all(clipId) as TranscriptWordRow[];
    return rows.map(rowToWord);
  },

  softDeleteWords(wordIds: number[]): void {
    if (wordIds.length === 0) return;
    const db = getDatabase();
    const placeholders = wordIds.map(() => '?').join(',');
    db.prepare(
      `UPDATE transcript_words SET is_deleted = 1 WHERE id IN (${placeholders})`,
    ).run(...wordIds);
  },

  restoreWords(wordIds: number[]): void {
    if (wordIds.length === 0) return;
    const db = getDatabase();
    const placeholders = wordIds.map(() => '?').join(',');
    db.prepare(
      `UPDATE transcript_words SET is_deleted = 0 WHERE id IN (${placeholders})`,
    ).run(...wordIds);
  },

  deleteWordsByClip(clipId: number): void {
    const db = getDatabase();
    db.prepare('DELETE FROM transcript_words WHERE clip_id = ?').run(clipId);
  },

  // ─── Segments ──────────────────────────────────────────────────────────────

  insertSegments(segments: Omit<TranscriptSegment, 'id'>[]): TranscriptSegment[] {
    const db = getDatabase();
    const stmt = db.prepare(`
      INSERT INTO transcript_segments (clip_id, text, start_ms, end_ms, is_deleted)
      VALUES (?, ?, ?, ?, ?)
    `);

    const insertMany = db.transaction((items: Omit<TranscriptSegment, 'id'>[]) => {
      const inserted: TranscriptSegment[] = [];
      for (const s of items) {
        const result = stmt.run(s.clipId, s.text, s.startMs, s.endMs, s.isDeleted ? 1 : 0);
        inserted.push({ ...s, id: result.lastInsertRowid as number });
      }
      return inserted;
    });

    return insertMany(segments);
  },

  findSegmentsByClip(clipId: number): TranscriptSegment[] {
    const db = getDatabase();
    const rows = db
      .prepare('SELECT * FROM transcript_segments WHERE clip_id = ? ORDER BY start_ms')
      .all(clipId) as TranscriptSegmentRow[];
    return rows.map(rowToSegment);
  },

  deleteSegmentsByClip(clipId: number): void {
    const db = getDatabase();
    db.prepare('DELETE FROM transcript_segments WHERE clip_id = ?').run(clipId);
  },

  // ─── Combined ──────────────────────────────────────────────────────────────

  clearTranscript(clipId: number): void {
    const db = getDatabase();
    db.transaction(() => {
      db.prepare('DELETE FROM transcript_words WHERE clip_id = ?').run(clipId);
      db.prepare('DELETE FROM transcript_segments WHERE clip_id = ?').run(clipId);
    })();
  },
};
