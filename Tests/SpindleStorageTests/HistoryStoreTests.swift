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
}
