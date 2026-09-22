import Foundation
import GRDB
import SpindleCore
import Testing

@testable import SpindleStorage

@Suite
struct PrunerTests {
    private let database: AppDatabase
    private let blobs: BlobStore
    private let pruner: Pruner
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 86_400

    init() throws {
        database = try AppDatabase.inMemory()
        blobs = BlobStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "blobs-\(UUID().uuidString)"))
        pruner = Pruner(database: database, blobs: blobs)
    }

    /// Inserts `count` items directly, oldest first. Each is `size` bytes and was last used
    /// `age` seconds before `now`.
    private func seed(_ count: Int, kind: ItemKind = .text, size: Int = 10, age: TimeInterval = 0) throws {
        let usedAt = Int64((now.timeIntervalSince1970 - age) * 1000)
        try database.writer.write { db in
            var seq = try Int64.fetchOne(db, sql: "SELECT coalesce(max(seq), 0) FROM item") ?? 0
            for _ in 0..<count {
                seq += 1
                try db.execute(
                    sql: """
                        INSERT INTO item (seq, content_hash, kind, preview, search_text, byte_size, created_at, last_used_at)
                        VALUES (?, randomblob(32), ?, '', '', ?, ?, ?)
                        """,
                    arguments: [seq, kind.rawValue, size, usedAt, usedAt])
            }
        }
    }

    private func pinOldest(_ count: Int) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE item SET pinned_rank = seq WHERE id IN (SELECT id FROM item ORDER BY seq LIMIT ?)",
                arguments: [count])
        }
    }

    private func remaining() throws -> [Int64] {
        try database.writer.read { db in try Int64.fetchAll(db, sql: "SELECT seq FROM item ORDER BY seq") }
    }

    @Test
    func theDefaultPolicyKeepsASmallHistory() async throws {
        try seed(50)
        let result = try await pruner.prune(with: RetentionPolicy(), at: now)
        #expect(result.removedItems == 0)
        #expect(try remaining().count == 50)
    }

    @Test
    func keepsTheNewestItemsAndEveryPinnedOne() async throws {
        try seed(1_234)
        try pinOldest(2)
        let result = try await pruner.prune(with: RetentionPolicy(maxItems: 100, maxTotalBytes: nil), at: now)
        let seqs = try remaining()
        #expect(result.removedItems == 1_132)
        #expect(seqs.count == 102)
        #expect(seqs.prefix(2) == [1, 2])  // pinned
        #expect(seqs.dropFirst(2).first == 1_135)
        #expect(seqs.last == 1_234)
    }

    @Test
    func removesItemsUnusedForTooLong() async throws {
        try seed(3, age: 40 * day)
        try seed(2, age: 1 * day)
        try await pruner.prune(with: RetentionPolicy(maxAge: 30 * day, maxTotalBytes: nil), at: now)
        #expect(try remaining() == [4, 5])
    }

    @Test
    func perKindAgeLimitsOverrideTheGeneralOne() async throws {
        try seed(2, kind: .image, age: 45 * day)
        try seed(2, kind: .text, age: 45 * day)
        try seed(1, kind: .image, age: 2 * day)
        let policy = RetentionPolicy(maxTotalBytes: nil, maxAgeByKind: [.image: 30 * day])
        try await pruner.prune(with: policy, at: now)
        #expect(try remaining() == [3, 4, 5])
    }

    @Test
    func trimsTheOldestItemsToFitTheStorageLimit() async throws {
        try seed(20, size: 10_000)
        try await pruner.prune(with: RetentionPolicy(maxTotalBytes: 55_000), at: now)
        #expect(try remaining() == [16, 17, 18, 19, 20])
    }

    @Test
    func deletesPayloadFilesOfRemovedItems() async throws {
        let ingestor = Ingestor(database: database, blobs: blobs)
        let big = CapturedItem(representations: [Representation(flavor: .plainText, data: Data(count: 100_000))])
        try await ingestor.ingest(
            CapturedCopy(
                items: [big], declaredTypes: [.plainText], sourceBundleID: nil, changeCount: 1, capturedAt: now))
        let hash = ContentHash(of: Data(count: 100_000))
        #expect(throws: Never.self) { try blobs.read(hash) }

        let result = try await pruner.prune(
            // File ages come from the real file system, so this prune runs on the real clock.
            with: RetentionPolicy(maxItems: 0, maxTotalBytes: nil), at: .now, fileGracePeriod: -60)
        #expect(result.removedItems == 1)
        #expect(result.removedFiles == 1)
        #expect(throws: (any Error).self) { try blobs.read(hash) }
    }

    @Test
    func clearingErasesTheTextFromTheSearchIndex() async throws {
        try await database.writer.write { db in
            for seq in 1...1_200 {
                try db.execute(
                    sql: """
                        INSERT INTO item (seq, content_hash, kind, preview, search_text, byte_size, created_at, last_used_at)
                        VALUES (?, randomblob(32), 0, '', ?, 1, 0, 0)
                        """,
                    arguments: [seq, seq == 1 ? "pinned recipe" : "secret note \(seq)"])
            }
        }
        try pinOldest(1)
        try await pruner.clearHistory()

        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO item_fts(item_fts, rank) VALUES ('integrity-check', 1)")
            #expect(try Int64.fetchAll(db, sql: "SELECT rowid FROM item_fts WHERE item_fts MATCH '\"recipe\"'") == [1])
            #expect(try Int64.fetchAll(db, sql: "SELECT rowid FROM item_fts WHERE item_fts MATCH '\"secret\"'").isEmpty)
            // Only the pinned item's entries are left in the index: its averages and structure
            // records plus a page or two, not 1,199 items marked as deleted.
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM item_fts_data") ?? 0 <= 5)
            #expect(try Int.fetchOne(db, sql: "SELECT v FROM item_fts_config WHERE k = 'secure-delete'") == 1)
        }
    }

    @Test
    func clearingKeepsOnlyPinnedItems() async throws {
        try seed(1_200)
        try pinOldest(3)
        let removed = try await pruner.clearHistory()
        #expect(removed == 1_197)
        #expect(try remaining() == [1, 2, 3])
    }
}
