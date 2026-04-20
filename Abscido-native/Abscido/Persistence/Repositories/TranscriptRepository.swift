import Foundation
@preconcurrency import SQLite

/// Repository for transcript_words and transcript_segments tables.
final class TranscriptRepository: Sendable {
    private let db: Connection

    init(db: Connection = Database.shared.connection) {
        self.db = db
    }

    // MARK: - Word table columns
    private let wordTable = Table("transcript_words")
    private let wId = SQLite.Expression<Int64>("id")
    private let wClipId = SQLite.Expression<Int64>("clip_id")
    private let wWord = SQLite.Expression<String>("word")
    private let wStartMs = SQLite.Expression<Double>("start_ms")
    private let wEndMs = SQLite.Expression<Double>("end_ms")
    private let wConfidence = SQLite.Expression<Double>("confidence")
    private let wSpeaker = SQLite.Expression<String?>("speaker")
    private let wIsDeleted = SQLite.Expression<Int64>("is_deleted")
    private let wIsBadTake = SQLite.Expression<Int64>("is_bad_take")
    private let wBadTakeReason = SQLite.Expression<String?>("bad_take_reason")

    // MARK: - Segment table columns
    private let segTable = Table("transcript_segments")
    private let sId = SQLite.Expression<Int64>("id")
    private let sClipId = SQLite.Expression<Int64>("clip_id")
    private let sText = SQLite.Expression<String>("text")
    private let sStartMs = SQLite.Expression<Double>("start_ms")
    private let sEndMs = SQLite.Expression<Double>("end_ms")
    private let sIsDeleted = SQLite.Expression<Int64>("is_deleted")

    // MARK: - Word CRUD

    func insertWords(_ words: [TranscriptWord]) throws {
        try db.transaction {
            for word in words {
                try db.run(wordTable.insert(
                    wClipId <- word.clipId,
                    wWord <- word.word,
                    wStartMs <- word.startMs,
                    wEndMs <- word.endMs,
                    wConfidence <- word.confidence,
                    wSpeaker <- word.speaker,
                    wIsDeleted <- (word.isDeleted ? 1 : 0),
                    wIsBadTake <- (word.isBadTake ? 1 : 0),
                    wBadTakeReason <- word.badTakeReason
                ))
            }
        }
    }

    func fetchWords(clipId: Int64) throws -> [TranscriptWord] {
        try db.prepare(
            wordTable.filter(wClipId == clipId).order(wStartMs.asc)
        ).map { row in
            TranscriptWord(
                id: row[wId],
                clipId: row[wClipId],
                word: row[wWord],
                startMs: row[wStartMs],
                endMs: row[wEndMs],
                confidence: row[wConfidence],
                speaker: row[wSpeaker],
                isDeleted: row[wIsDeleted] != 0,
                isBadTake: row[wIsBadTake] != 0,
                badTakeReason: row[wBadTakeReason]
            )
        }
    }

    func updateWordDeletion(wordId: Int64, isDeleted: Bool) throws {
        let row = wordTable.filter(wId == wordId)
        try db.run(row.update(wIsDeleted <- (isDeleted ? 1 : 0)))
    }

    func updateWordsBatch(words: [TranscriptWord]) throws {
        try db.transaction {
            for word in words {
                let row = wordTable.filter(wId == word.id)
                try db.run(row.update(
                    wIsDeleted <- (word.isDeleted ? 1 : 0),
                    wIsBadTake <- (word.isBadTake ? 1 : 0),
                    wBadTakeReason <- word.badTakeReason
                ))
            }
        }
    }

    func deleteWords(clipId: Int64) throws {
        try db.run(wordTable.filter(wClipId == clipId).delete())
    }

    // MARK: - Segment CRUD

    func insertSegments(_ segments: [TranscriptSegment]) throws {
        try db.transaction {
            for seg in segments {
                try db.run(segTable.insert(
                    sClipId <- seg.clipId,
                    sText <- seg.text,
                    sStartMs <- seg.startMs,
                    sEndMs <- seg.endMs,
                    sIsDeleted <- (seg.isDeleted ? 1 : 0)
                ))
            }
        }
    }

    func fetchSegments(clipId: Int64) throws -> [TranscriptSegment] {
        try db.prepare(
            segTable.filter(sClipId == clipId).order(sStartMs.asc)
        ).map { row in
            TranscriptSegment(
                id: row[sId],
                clipId: row[sClipId],
                text: row[sText],
                startMs: row[sStartMs],
                endMs: row[sEndMs],
                isDeleted: row[sIsDeleted] != 0
            )
        }
    }

    func deleteSegments(clipId: Int64) throws {
        try db.run(segTable.filter(sClipId == clipId).delete())
    }
}
