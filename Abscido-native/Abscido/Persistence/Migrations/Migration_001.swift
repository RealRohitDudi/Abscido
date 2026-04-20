import Foundation
@preconcurrency import SQLite

/// Initial database schema — creates all tables for projects, media, transcripts, and edit snapshots.
enum Migration001 {
    static func run(db: Connection) throws {

        try db.execute("""
            CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                otio_json TEXT
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS media_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                file_path TEXT NOT NULL,
                bookmark_data BLOB,
                duration_ms REAL NOT NULL DEFAULT 0,
                fps REAL NOT NULL DEFAULT 30,
                width INTEGER NOT NULL DEFAULT 0,
                height INTEGER NOT NULL DEFAULT 0,
                codec TEXT NOT NULL DEFAULT '',
                thumbnail_path TEXT,
                created_at REAL NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS transcript_words (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                clip_id INTEGER NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
                word TEXT NOT NULL,
                start_ms REAL NOT NULL,
                end_ms REAL NOT NULL,
                confidence REAL NOT NULL DEFAULT 1.0,
                speaker TEXT,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                is_bad_take INTEGER NOT NULL DEFAULT 0,
                bad_take_reason TEXT
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS transcript_segments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                clip_id INTEGER NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                start_ms REAL NOT NULL,
                end_ms REAL NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS edit_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                snapshot_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                label TEXT
            )
        """)

        // Indexes for performance
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_media_files_project ON media_files(project_id)"
        )
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_transcript_words_clip ON transcript_words(clip_id)"
        )
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_transcript_words_time ON transcript_words(clip_id, start_ms)"
        )
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_transcript_segments_clip ON transcript_segments(clip_id)"
        )
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_edit_snapshots_project ON edit_snapshots(project_id)"
        )
    }
}
