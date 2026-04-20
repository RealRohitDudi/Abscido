import Foundation
@preconcurrency import SQLite

/// Repository for CRUD operations on the media_files table.
final class MediaRepository: Sendable {
    private let db: Connection

    init(db: Connection = Database.shared.connection) {
        self.db = db
    }

    // MARK: - Table columns
    private let table = Table("media_files")
    private let colId = SQLite.Expression<Int64>("id")
    private let colProjectId = SQLite.Expression<Int64>("project_id")
    private let colFilePath = SQLite.Expression<String>("file_path")
    private let colBookmarkData = SQLite.Expression<Data?>("bookmark_data")
    private let colDurationMs = SQLite.Expression<Double>("duration_ms")
    private let colFps = SQLite.Expression<Double>("fps")
    private let colWidth = SQLite.Expression<Int64>("width")
    private let colHeight = SQLite.Expression<Int64>("height")
    private let colCodec = SQLite.Expression<String>("codec")
    private let colThumbnailPath = SQLite.Expression<String?>("thumbnail_path")
    private let colCreatedAt = SQLite.Expression<Double>("created_at")

    // MARK: - Create

    func create(_ file: MediaFile) throws -> MediaFile {
        let id = try db.run(table.insert(
            colProjectId <- file.projectId,
            colFilePath <- file.filePath,
            colBookmarkData <- file.bookmarkData,
            colDurationMs <- file.durationMs,
            colFps <- file.fps,
            colWidth <- Int64(file.width),
            colHeight <- Int64(file.height),
            colCodec <- file.codec,
            colThumbnailPath <- file.thumbnailPath,
            colCreatedAt <- file.createdAt.timeIntervalSince1970
        ))
        var result = file
        result.id = id
        return result
    }

    // MARK: - Read

    func fetchAll(projectId: Int64) throws -> [MediaFile] {
        try db.prepare(table.filter(colProjectId == projectId).order(colCreatedAt.asc)).map { row in
            MediaFile(
                id: row[colId],
                projectId: row[colProjectId],
                filePath: row[colFilePath],
                bookmarkData: row[colBookmarkData],
                durationMs: row[colDurationMs],
                fps: row[colFps],
                width: Int(row[colWidth]),
                height: Int(row[colHeight]),
                codec: row[colCodec],
                thumbnailPath: row[colThumbnailPath],
                createdAt: Date(timeIntervalSince1970: row[colCreatedAt])
            )
        }
    }

    func fetch(id: Int64) throws -> MediaFile? {
        guard let row = try db.pluck(table.filter(colId == id)) else { return nil }
        return MediaFile(
            id: row[colId],
            projectId: row[colProjectId],
            filePath: row[colFilePath],
            bookmarkData: row[colBookmarkData],
            durationMs: row[colDurationMs],
            fps: row[colFps],
            width: Int(row[colWidth]),
            height: Int(row[colHeight]),
            codec: row[colCodec],
            thumbnailPath: row[colThumbnailPath],
            createdAt: Date(timeIntervalSince1970: row[colCreatedAt])
        )
    }

    // MARK: - Update

    func update(_ file: MediaFile) throws {
        let row = table.filter(colId == file.id)
        try db.run(row.update(
            colFilePath <- file.filePath,
            colBookmarkData <- file.bookmarkData,
            colDurationMs <- file.durationMs,
            colFps <- file.fps,
            colWidth <- Int64(file.width),
            colHeight <- Int64(file.height),
            colCodec <- file.codec,
            colThumbnailPath <- file.thumbnailPath
        ))
    }

    func updateBookmark(id: Int64, bookmarkData: Data) throws {
        let row = table.filter(colId == id)
        try db.run(row.update(colBookmarkData <- bookmarkData))
    }

    // MARK: - Delete

    func delete(id: Int64) throws {
        let row = table.filter(colId == id)
        try db.run(row.delete())
    }
}
