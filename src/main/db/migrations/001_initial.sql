CREATE TABLE IF NOT EXISTS projects (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL,
  created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT    NOT NULL DEFAULT (datetime('now')),
  export_path TEXT
);

CREATE TABLE IF NOT EXISTS media_files (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id     INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  file_path      TEXT    NOT NULL,
  duration_ms    INTEGER NOT NULL DEFAULT 0,
  width          INTEGER NOT NULL DEFAULT 0,
  height         INTEGER NOT NULL DEFAULT 0,
  fps            REAL    NOT NULL DEFAULT 0,
  codec          TEXT    NOT NULL DEFAULT '',
  thumbnail_path TEXT,
  created_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS timeline_clips (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id    INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  media_file_id INTEGER NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
  position_ms   INTEGER NOT NULL DEFAULT 0,
  in_point_ms   INTEGER NOT NULL DEFAULT 0,
  out_point_ms  INTEGER NOT NULL DEFAULT 0,
  track         INTEGER NOT NULL DEFAULT 0,
  is_deleted    INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS transcript_words (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  clip_id    INTEGER NOT NULL REFERENCES timeline_clips(id) ON DELETE CASCADE,
  word       TEXT    NOT NULL,
  start_ms   INTEGER NOT NULL,
  end_ms     INTEGER NOT NULL,
  confidence REAL    NOT NULL DEFAULT 1.0,
  speaker    TEXT,
  is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS transcript_segments (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  clip_id    INTEGER NOT NULL REFERENCES timeline_clips(id) ON DELETE CASCADE,
  text       TEXT    NOT NULL,
  start_ms   INTEGER NOT NULL,
  end_ms     INTEGER NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS schema_migrations (
  version    INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS idx_media_files_project_id       ON media_files(project_id);
CREATE INDEX IF NOT EXISTS idx_timeline_clips_project_id    ON timeline_clips(project_id);
CREATE INDEX IF NOT EXISTS idx_timeline_clips_media_file_id ON timeline_clips(media_file_id);
CREATE INDEX IF NOT EXISTS idx_transcript_words_clip_id     ON transcript_words(clip_id);
CREATE INDEX IF NOT EXISTS idx_transcript_words_start_ms    ON transcript_words(start_ms);
CREATE INDEX IF NOT EXISTS idx_transcript_segments_clip_id  ON transcript_segments(clip_id);
