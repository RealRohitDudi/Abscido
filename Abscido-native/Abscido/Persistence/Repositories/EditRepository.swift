import Foundation
@preconcurrency import SQLite

/// Repository for edit_snapshots table — stores versioned edit decision snapshots.
final class EditRepository: Sendable {
    private let db: Connection

    init(db: Connection = Database.shared.connection) {
        self.db = db
    }

    // MARK: - Table columns
    private let table = Table("edit_snapshots")
    private let colId = SQLite.Expression<Int64>("id")
    private let colProjectId = SQLite.Expression<Int64>("project_id")
    private let colSnapshotJSON = SQLite.Expression<String>("snapshot_json")
    private let colCreatedAt = SQLite.Expression<Double>("created_at")
    private let colLabel = SQLite.Expression<String?>("label")

    // MARK: - Create

    func saveSnapshot(
        projectId: Int64,
        editDecisions: [EditDecision],
        label: String? = nil
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(editDecisions)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        try db.run(table.insert(
            colProjectId <- projectId,
            colSnapshotJSON <- jsonString,
            colCreatedAt <- Date().timeIntervalSince1970,
            colLabel <- label
        ))
    }

    // MARK: - Read

    func fetchSnapshots(projectId: Int64) throws -> [(id: Int64, label: String?, createdAt: Date, json: String)] {
        try db.prepare(
            table.filter(colProjectId == projectId).order(colCreatedAt.desc)
        ).map { row in
            (
                id: row[colId],
                label: row[colLabel],
                createdAt: Date(timeIntervalSince1970: row[colCreatedAt]),
                json: row[colSnapshotJSON]
            )
        }
    }

    func fetchLatestSnapshot(projectId: Int64) throws -> [EditDecision]? {
        guard let row = try db.pluck(
            table.filter(colProjectId == projectId).order(colCreatedAt.desc)
        ) else {
            return nil
        }

        let json = row[colSnapshotJSON]
        guard let data = json.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode([EditDecision].self, from: data)
    }

    // MARK: - Delete

    func deleteSnapshot(id: Int64) throws {
        try db.run(table.filter(colId == id).delete())
    }

    func deleteAllSnapshots(projectId: Int64) throws {
        try db.run(table.filter(colProjectId == projectId).delete())
    }
}
