import Foundation

struct Project: Identifiable, Codable, Equatable, Sendable {
    var id: Int64
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var otioJSON: String?

    init(
        id: Int64 = 0,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        otioJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.otioJSON = otioJSON
    }
}
