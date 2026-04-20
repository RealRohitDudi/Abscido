import Database from 'better-sqlite3';
import { app } from 'electron';
import fs from 'fs';
import path from 'path';

let db: Database.Database | null = null;

function getMigrationsDir(): string {
  // In production, migrations are in resources; in dev, relative to project
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'migrations');
  }
  return path.join(__dirname, '..', '..', 'main', 'db', 'migrations');
}

function runMigrations(database: Database.Database): void {
  // Ensure schema_migrations table exists before anything else
  database.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    INTEGER PRIMARY KEY,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);

  const appliedVersions = database
    .prepare('SELECT version FROM schema_migrations ORDER BY version')
    .all() as Array<{ version: number }>;
  const appliedSet = new Set(appliedVersions.map((r) => r.version));

  const migrationsDir = getMigrationsDir();

  if (!fs.existsSync(migrationsDir)) {
    // Fallback: run inline migration
    runInlineMigration(database, 1, appliedSet);
    return;
  }

  const migrationFiles = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  for (const file of migrationFiles) {
    const version = parseInt(file.split('_')[0], 10);
    if (appliedSet.has(version)) continue;

    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf-8');
    database.transaction(() => {
      database.exec(sql);
      database.prepare('INSERT INTO schema_migrations (version) VALUES (?)').run(version);
    })();
    console.log(`[DB] Applied migration ${file}`);
  }
}

function runInlineMigration(
  database: Database.Database,
  version: number,
  appliedSet: Set<number>,
): void {
  if (appliedSet.has(version)) return;

  const sql = `
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

    CREATE INDEX IF NOT EXISTS idx_media_files_project_id       ON media_files(project_id);
    CREATE INDEX IF NOT EXISTS idx_timeline_clips_project_id    ON timeline_clips(project_id);
    CREATE INDEX IF NOT EXISTS idx_timeline_clips_media_file_id ON timeline_clips(media_file_id);
    CREATE INDEX IF NOT EXISTS idx_transcript_words_clip_id     ON transcript_words(clip_id);
    CREATE INDEX IF NOT EXISTS idx_transcript_words_start_ms    ON transcript_words(start_ms);
    CREATE INDEX IF NOT EXISTS idx_transcript_segments_clip_id  ON transcript_segments(clip_id);
  `;

  database.transaction(() => {
    database.exec(sql);
    database.prepare('INSERT INTO schema_migrations (version) VALUES (?)').run(version);
  })();
  console.log(`[DB] Applied inline migration v${version}`);
}

export function getDatabase(): Database.Database {
  if (db) return db;

  const userDataPath = app.getPath('userData');
  const dbPath = path.join(userDataPath, 'abscido.db');

  console.log(`[DB] Opening database at: ${dbPath}`);

  db = new Database(dbPath);

  // Performance settings
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.pragma('synchronous = NORMAL');
  db.pragma('cache_size = -8000'); // 8MB cache

  runMigrations(db);

  console.log('[DB] Database initialized successfully');
  return db;
}

export function closeDatabase(): void {
  if (db) {
    db.close();
    db = null;
    console.log('[DB] Database closed');
  }
}
