import Foundation
import GRDB
import Testing

@testable import SpindleStorage

@Suite
struct AppDatabaseTests {
    private func insertItem(_ db: Database, id: Int64, seq: Int64, text: String) throws {
        try db.execute(
            sql: """
                INSERT INTO item (id, seq, content_hash, kind, preview, search_text, byte_size, created_at, last_used_at)
                VALUES (?, ?, ?, 0, ?, ?, ?, 0, 0)
                """,
            arguments: [id, seq, Data("hash-\(id)".utf8), text, text, text.utf8.count])
    }

    private func matches(_ db: Database, _ phrase: String) throws -> [Int64] {
        try Int64.fetchAll(
            db, sql: "SELECT rowid FROM item_fts WHERE item_fts MATCH ? ORDER BY rowid DESC",
            arguments: ["\"\(phrase)\""])
    }

    @Test
    func migrationCreatesTheSchema() throws {
        let database = try AppDatabase.inMemory()
        let tables = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') ORDER BY name")
        }
        for table in ["item", "item_fts", "representation", "source_app", "thumbnail"] {
            #expect(tables.contains(table))
        }
    }

    @Test
    func searchIndexFollowsInsertsUpdatesAndDeletes() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try insertItem(db, id: 1, seq: 10, text: "the clipboard remembers")
            #expect(try matches(db, "clipb") == [10])

            // Copying the item again gives it a new seq; the index must follow.
            try db.execute(sql: "UPDATE item SET seq = 11 WHERE id = 1")
            #expect(try matches(db, "clipb") == [11])

            try db.execute(sql: "DELETE FROM item WHERE id = 1")
            #expect(try matches(db, "clipb").isEmpty)
        }
    }

    @Test
    func checkpointsTheWALOnceWritesStop() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "spindle-wal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = StorageLocation(directory: directory)
        let database = try AppDatabase.open(at: location)
        try await database.write { db in try insertItem(db, id: 1, seq: 1, text: "one") }

        // The wal-index keeps the number of frames in the WAL at byte 16 and the number already
        // copied into the database at byte 96 (sqlite.org/walformat.html).
        let shm = URL(filePath: location.databaseURL.path(percentEncoded: false) + "-shm")
        func isCheckpointed() throws -> Bool {
            let header = try Data(contentsOf: shm).prefix(100)
            let (frames, copied) = header.withUnsafeBytes {
                (
                    $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self),
                    $0.loadUnaligned(fromByteOffset: 96, as: UInt32.self)
                )
            }
            return frames > 0 && copied == frames
        }
        #expect(try !isCheckpointed())
        var waited = 0
        while try !isCheckpointed(), waited < 40 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        #expect(try isCheckpointed())
    }

    @Test
    func trigramIndexMatchesInsideWords() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try insertItem(db, id: 1, seq: 1, text: "grdb.swift and 東京タワー")
            #expect(try matches(db, "b.sw") == [1])
            #expect(try matches(db, "京タワ") == [1])
        }
    }

    @Test
    func deletingAnItemDeletesItsRepresentationsAndThumbnail() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try insertItem(db, id: 1, seq: 1, text: "x")
            try db.execute(
                sql: """
                    INSERT INTO representation (item_id, item_index, ordinal, uti, inline_data, byte_size)
                    VALUES (1, 0, 0, 'public.utf8-plain-text', x'78', 1)
                    """)
            try db.execute(sql: "INSERT INTO thumbnail (item_id, width, height, data) VALUES (1, 1, 1, x'00')")
            try db.execute(sql: "DELETE FROM item WHERE id = 1")
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM representation") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM thumbnail") == 0)
        }
    }

    @Test
    func aRepresentationIsEitherInlineOrABlobNeverBoth() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try insertItem(db, id: 1, seq: 1, text: "x")
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: """
                        INSERT INTO representation (item_id, item_index, ordinal, uti, inline_data, blob_hash, byte_size)
                        VALUES (1, 0, 0, 'public.png', x'00', x'00', 1)
                        """)
            }
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: """
                        INSERT INTO representation (item_id, item_index, ordinal, uti, byte_size)
                        VALUES (1, 0, 1, 'public.png', 1)
                        """)
            }
        }
    }

    @Test
    func strictTablesRejectValuesOfTheWrongType() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db -> Void in
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: """
                        INSERT INTO item (seq, content_hash, kind, preview, search_text, byte_size, created_at, last_used_at)
                        VALUES (1, x'00', 'text', '', '', 0, 0, 0)
                        """)
            }
        }
    }

    @Test
    func onDiskDatabaseUsesWALAndIncrementalVacuum() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "spindle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = StorageLocation(directory: directory)

        let database = try AppDatabase.open(at: location)
        let (journal, vacuum) = try database.writer.read { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"), try Int.fetchOne(db, sql: "PRAGMA auto_vacuum"))
        }
        #expect(journal == "wal")
        #expect(vacuum == 2)  // incremental

        // Opening an existing database runs no migrations twice and keeps the data.
        try database.writer.write { db in try insertItem(db, id: 1, seq: 1, text: "kept") }
        let reopened = try AppDatabase.open(at: location)
        #expect(try reopened.writer.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM item") } == 1)
    }
}

@Suite
struct StorageLocationTests {
    @Test
    func filesLiveInsideTheDirectory() {
        let location = StorageLocation(directory: URL(filePath: "/tmp/Spindle", directoryHint: .isDirectory))
        #expect(location.databaseURL.path(percentEncoded: false) == "/tmp/Spindle/history.sqlite")
        #expect(location.blobsDirectory.path(percentEncoded: false) == "/tmp/Spindle/blobs/")
    }
}
