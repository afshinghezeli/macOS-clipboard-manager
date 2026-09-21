import Foundation
import GRDB
import SpindleCore
import Testing

@testable import SpindleStorage

@Suite
struct HistoryStoreTests {
    let database: AppDatabase
    let ingestor: Ingestor
    let history: HistoryStore
    let clock = TestClock(start: Date(timeIntervalSince1970: 1_790_000_000))

    init() throws {
        database = try AppDatabase.inMemory()
        let blobs = BlobStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "blobs-\(UUID().uuidString)"))
        ingestor = Ingestor(database: database, blobs: blobs, now: { [clock] in clock.now })
        history = HistoryStore(database: database)
    }

    @discardableResult
    func add(_ text: String) async throws -> Int64 {
        clock.advance(by: 1)
        let item = CapturedItem(representations: [Representation(flavor: .plainText, data: Data(text.utf8))])
        let outcome = try await ingestor.ingest(
            CapturedCopy(
                items: [item], declaredTypes: [.plainText], sourceBundleID: nil, changeCount: 1, capturedAt: clock.now))
        switch outcome {
        case .inserted(let id), .bumped(let id): return id
        case .skipped: throw CancellationError()
        }
    }

    func row(_ id: Int64) throws -> Row? {
        try database.writer.read { db in try Row.fetchOne(db, sql: "SELECT * FROM item WHERE id = ?", arguments: [id]) }
    }

    @Test
    func countsItems() async throws {
        #expect(try await history.itemCount() == 0)
        try await add("one")
        try await add("two")
        try await add("one")
        #expect(try await history.itemCount() == 2)
    }

    @Test
    func pastingAnItemMovesItToTheTopAndCountsTheUse() async throws {
        let first = try await add("first")
        try await add("second")
        let before = try #require(try row(first))

        clock.advance(by: 60)
        try await history.markUsed(first, at: clock.now)

        let after = try #require(try row(first))
        #expect(after["seq"] as Int64 == 3)
        #expect(after["use_count"] as Int == 2)
        #expect(after["last_used_at"] as Int64 > before["last_used_at"] as Int64)
        #expect(after["frecency_key"] as Double > before["frecency_key"] as Double)
        #expect(after["created_at"] as Int64 == before["created_at"] as Int64)
    }

    @Test
    func markingAMissingItemIsHarmless() async throws {
        try await history.markUsed(999, at: clock.now)
        #expect(try await history.itemCount() == 0)
    }

    func pin(_ id: Int64, rank: Int) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE item SET pinned_rank = ? WHERE id = ?", arguments: [rank, id])
        }
    }

    @Test
    func pagesThroughRecentItemsNewestFirst() async throws {
        for index in 1...25 { try await add("item \(index)") }
        let first = try await history.recent(limit: 10)
        #expect(first.map(\.preview) == (16...25).reversed().map { "item \($0)" })
        let second = try await history.recent(before: first.last?.seq, limit: 10)
        #expect(second.map(\.preview) == (6...15).reversed().map { "item \($0)" })
        let last = try await history.recent(before: second.last?.seq, limit: 10)
        #expect(last.count == 5)
        #expect(try await history.recent(before: last.last?.seq, limit: 10).isEmpty)
    }

    @Test
    func pinnedItemsAreListedApartInPinOrder() async throws {
        let a = try await add("a")
        let b = try await add("b")
        try await add("c")
        try pin(a, rank: 2)
        try pin(b, rank: 1)
        #expect(try await history.pinned().map(\.preview) == ["b", "a"])
        #expect(try await history.recent(limit: 10).map(\.preview) == ["c"])
    }

    @Test
    func readsOneSummary() async throws {
        let id = try await add("single")
        let summary = try #require(try await history.summary(for: id))
        #expect(summary.preview == "single")
        #expect(summary.kind == .text)
        #expect(!summary.isPinned)
        #expect(try await history.summary(for: 999) == nil)
    }

    @Test
    func readsThumbnails() async throws {
        let id = try await add("no image")
        #expect(try await history.thumbnail(for: id) == nil)
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO thumbnail (item_id, width, height, data) VALUES (?, 1, 1, x'FFD8')", arguments: [id])
        }
        #expect(try await history.thumbnail(for: id) == Data([0xFF, 0xD8]))
    }

    @Test
    func pinningAppendsAndUnpinningReturnsToHistory() async throws {
        let a = try await add("a")
        let b = try await add("b")
        try await history.setPinned(b, true)
        try await history.setPinned(a, true)
        try await history.setPinned(b, true)  // already pinned: keeps its place
        #expect(try await history.pinned().map(\.preview) == ["b", "a"])
        try await history.setPinned(b, false)
        #expect(try await history.pinned().map(\.preview) == ["a"])
        #expect(try await history.recent().map(\.preview) == ["b"])
    }
}
