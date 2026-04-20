import Foundation
@preconcurrency import SQLite

/// Repository for CRUD operations on the projects table.
final class ProjectRepository: Sendable {
    private let db: Connection

    init(db: Connection = Database.shared.connection) {
        self.db = db
    }

    // MARK: - Table columns
    private let table = Table("projects")
    private let colId = SQLite.Expression<Int64>("id")
    private let colName = SQLite.Expression<String>("name")
    private let colCreatedAt = SQLite.Expression<Double>("created_at")
    private let colUpdatedAt = SQLite.Expression<Double>("updated_at")
    private let colOtioJSON = SQLite.Expression<String?>("otio_json")

    // MARK: - Create

    func create(name: String) throws -> Project {
        let now = Date().timeIntervalSince1970
        let id = try db.run(table.insert(
            colName <- name,
            colCreatedAt <- now,
            colUpdatedAt <- now
        ))
        return Project(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: now),
            updatedAt: Date(timeIntervalSince1970: now)
        )
    }

    // MARK: - Read

    func fetchAll() throws -> [Project] {
        try db.prepare(table.order(colUpdatedAt.desc)).map { row in
            Project(
                id: row[colId],
                name: row[colName],
                createdAt: Date(timeIntervalSince1970: row[colCreatedAt]),
                updatedAt: Date(timeIntervalSince1970: row[colUpdatedAt]),
                otioJSON: row[colOtioJSON]
            )
        }
    }

    func fetch(id: Int64) throws -> Project? {
        guard let row = try db.pluck(table.filter(colId == id)) else {
            return nil
        }
        return Project(
            id: row[colId],
            name: row[colName],
            createdAt: Date(timeIntervalSince1970: row[colCreatedAt]),
            updatedAt: Date(timeIntervalSince1970: row[colUpdatedAt]),
            otioJSON: row[colOtioJSON]
        )
    }

    // MARK: - Update

    func update(_ project: Project) throws {
        let row = table.filter(colId == project.id)
        try db.run(row.update(
            colName <- project.name,
            colUpdatedAt <- Date().timeIntervalSince1970,
            colOtioJSON <- project.otioJSON
        ))
    }

    func updateOTIOJSON(projectId: Int64, json: String) throws {
        let row = table.filter(colId == projectId)
        try db.run(row.update(
            colOtioJSON <- json,
            colUpdatedAt <- Date().timeIntervalSince1970
        ))
    }

    // MARK: - Delete

    func delete(id: Int64) throws {
        let row = table.filter(colId == id)
        try db.run(row.delete())
    }
}
