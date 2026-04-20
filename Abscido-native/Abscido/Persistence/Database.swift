import Foundation
@preconcurrency import SQLite

/// Singleton database manager for SQLite.swift. Manages the connection
/// and runs schema migrations on first access.
final class Database: Sendable {
    static let shared = Database()

    let connection: Connection

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Abscido", isDirectory: true)

        try! FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        let dbPath = appSupport.appendingPathComponent("abscido.sqlite3").path
        connection = try! Connection(dbPath)

        // Enable WAL mode for better concurrent read performance
        try! connection.execute("PRAGMA journal_mode = WAL")
        try! connection.execute("PRAGMA foreign_keys = ON")

        runMigrations()
    }

    private func runMigrations() {
        // Create migration tracking table
        try! connection.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            )
        """)

        let currentVersion = (try? connection.scalar(
            "SELECT MAX(version) FROM schema_migrations"
        ) as? Int64) ?? 0

        // Each migration receives the already-open connection directly —
        // never re-access Database.shared here (dispatch_once deadlock).
        let migrations: [(version: Int64, migration: (Connection) throws -> Void)] = [
            (1, Migration001.run),
        ]

        for migration in migrations where migration.version > currentVersion {
            do {
                try connection.transaction {
                    try migration.migration(self.connection)
                    try self.connection.run(
                        "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                        migration.version,
                        Date().timeIntervalSince1970
                    )
                }
            } catch {
                fatalError("Migration \(migration.version) failed: \(error)")
            }
        }
    }
}
