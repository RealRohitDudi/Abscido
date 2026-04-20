import { getDatabase } from '../database';
import type { MediaFile, TimelineClip } from '../../../shared/types';

interface MediaFileRow {
  id: number;
  project_id: number;
  file_path: string;
  duration_ms: number;
  width: number;
  height: number;
  fps: number;
  codec: string;
  thumbnail_path: string | null;
  created_at: string;
}

interface TimelineClipRow {
  id: number;
  project_id: number;
  media_file_id: number;
  position_ms: number;
  in_point_ms: number;
  out_point_ms: number;
  track: number;
  is_deleted: number;
  created_at: string;
}

function rowToMediaFile(row: MediaFileRow): MediaFile {
  return {
    id: row.id,
    projectId: row.project_id,
    filePath: row.file_path,
    durationMs: row.duration_ms,
    width: row.width,
    height: row.height,
    fps: row.fps,
    codec: row.codec,
    thumbnailPath: row.thumbnail_path,
    createdAt: row.created_at,
  };
}

function rowToClip(row: TimelineClipRow): TimelineClip {
  return {
    id: row.id,
    projectId: row.project_id,
    mediaFileId: row.media_file_id,
    positionMs: row.position_ms,
    inPointMs: row.in_point_ms,
    outPointMs: row.out_point_ms,
    track: row.track,
    isDeleted: row.is_deleted === 1,
    createdAt: row.created_at,
  };
}

export const clipRepo = {
  // ─── Media Files ───────────────────────────────────────────────────────────

  createMediaFile(data: Omit<MediaFile, 'id' | 'createdAt'>): MediaFile {
    const db = getDatabase();
    const stmt = db.prepare(`
      INSERT INTO media_files
        (project_id, file_path, duration_ms, width, height, fps, codec, thumbnail_path)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const result = stmt.run(
      data.projectId,
      data.filePath,
      data.durationMs,
      data.width,
      data.height,
      data.fps,
      data.codec,
      data.thumbnailPath,
    );
    return this.findMediaFileById(result.lastInsertRowid as number)!;
  },

  findMediaFileById(id: number): MediaFile | null {
    const db = getDatabase();
    const row = db
      .prepare('SELECT * FROM media_files WHERE id = ?')
      .get(id) as MediaFileRow | undefined;
    return row ? rowToMediaFile(row) : null;
  },

  findMediaFilesByProject(projectId: number): MediaFile[] {
    const db = getDatabase();
    const rows = db
      .prepare('SELECT * FROM media_files WHERE project_id = ? ORDER BY created_at')
      .all(projectId) as MediaFileRow[];
    return rows.map(rowToMediaFile);
  },

  updateMediaFileThumbnail(id: number, thumbnailPath: string): void {
    const db = getDatabase();
    db.prepare('UPDATE media_files SET thumbnail_path = ? WHERE id = ?').run(thumbnailPath, id);
  },

  deleteMediaFile(id: number): void {
    const db = getDatabase();
    db.prepare('DELETE FROM media_files WHERE id = ?').run(id);
  },

  // ─── Timeline Clips ────────────────────────────────────────────────────────

  createClip(data: Omit<TimelineClip, 'id' | 'createdAt' | 'isDeleted'>): TimelineClip {
    const db = getDatabase();
    const stmt = db.prepare(`
      INSERT INTO timeline_clips
        (project_id, media_file_id, position_ms, in_point_ms, out_point_ms, track)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    const result = stmt.run(
      data.projectId,
      data.mediaFileId,
      data.positionMs,
      data.inPointMs,
      data.outPointMs,
      data.track,
    );
    return this.findClipById(result.lastInsertRowid as number)!;
  },

  findClipById(id: number): TimelineClip | null {
    const db = getDatabase();
    const row = db
      .prepare('SELECT * FROM timeline_clips WHERE id = ?')
      .get(id) as TimelineClipRow | undefined;
    return row ? rowToClip(row) : null;
  },

  findClipsByProject(projectId: number): TimelineClip[] {
    const db = getDatabase();
    const rows = db
      .prepare(
        'SELECT * FROM timeline_clips WHERE project_id = ? AND is_deleted = 0 ORDER BY track, position_ms',
      )
      .all(projectId) as TimelineClipRow[];
    return rows.map(rowToClip);
  },

  updateClip(
    id: number,
    data: Partial<Pick<TimelineClip, 'positionMs' | 'inPointMs' | 'outPointMs' | 'track'>>,
  ): TimelineClip | null {
    const db = getDatabase();
    const fields: string[] = [];
    const values: (number | string)[] = [];

    if (data.positionMs !== undefined) {
      fields.push('position_ms = ?');
      values.push(data.positionMs);
    }
    if (data.inPointMs !== undefined) {
      fields.push('in_point_ms = ?');
      values.push(data.inPointMs);
    }
    if (data.outPointMs !== undefined) {
      fields.push('out_point_ms = ?');
      values.push(data.outPointMs);
    }
    if (data.track !== undefined) {
      fields.push('track = ?');
      values.push(data.track);
    }

    if (fields.length === 0) return this.findClipById(id);
    values.push(id);
    db.prepare(`UPDATE timeline_clips SET ${fields.join(', ')} WHERE id = ?`).run(...values);
    return this.findClipById(id);
  },

  softDeleteClip(id: number): void {
    const db = getDatabase();
    db.prepare('UPDATE timeline_clips SET is_deleted = 1 WHERE id = ?').run(id);
  },

  deleteClip(id: number): void {
    const db = getDatabase();
    db.prepare('DELETE FROM timeline_clips WHERE id = ?').run(id);
  },
};
