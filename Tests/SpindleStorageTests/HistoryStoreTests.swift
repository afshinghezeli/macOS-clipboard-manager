import Foundation
import GRDB
import SpindleCore
import Testing
import UniformTypeIdentifiers

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
        history = HistoryStore(database: database, blobs: blobs)
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

    // MARK: - Contents

    @discardableResult
    func add(_ items: [[(PasteboardFlavor, Data)]], from app: String? = nil, name: String? = nil) async throws -> Int64
    {
        clock.advance(by: 1)
        let captured = items.map { CapturedItem(representations: $0.map { Representation(flavor: $0.0, data: $0.1) }) }
        let outcome = try await ingestor.ingest(
            CapturedCopy(
                items: captured, declaredTypes: captured.flatMap { $0.representations.map(\.flavor) },
                sourceBundleID: app, sourceAppName: name, changeCount: 1, capturedAt: clock.now))
        switch outcome {
        case .inserted(let id), .bumped(let id): return id
        case .skipped: throw CancellationError()
        }
    }

    @Test
    func detailsCarryTheTextAndWhereItCameFrom() async throws {
        let id = try await add(
            [[(.plainText, Data("hello\nworld".utf8)), (.rtf, Data("{\\rtf1 hello}".utf8))]],
            from: "com.apple.Notes", name: "Notes")
        let details = try #require(try await history.details(for: id))
        #expect(details.text == "hello\nworld")
        #expect(!details.isTextTruncated)
        #expect(details.sourceAppName == "Notes")
        #expect(details.sourceBundleID == "com.apple.Notes")
        #expect(details.flavors == [.plainText, .rtf])
        #expect(details.byteSize == 11 + 13)
    }

    @Test
    func longTextIsReadFromTheBlobStoreAndShortenedForPreview() async throws {
        let long = String(repeating: "0123456789", count: 20_000)  // 200 KB, stored as a file
        let id = try await add([[(.plainText, Data(long.utf8))]])
        let details = try #require(try await history.details(for: id))
        #expect(details.isTextTruncated)
        #expect(details.text?.utf8.count == ItemDetails.textLimit)
    }

    @Test
    func detailsListFilesAndImageSizes() async throws {
        let files = try await add([
            [(.fileURL, URL(filePath: "/tmp/a.txt").dataRepresentation)],
            [(.fileURL, URL(filePath: "/tmp/b.txt").dataRepresentation)],
        ])
        #expect(try await history.details(for: files)?.fileURLs.map(\.lastPathComponent) == ["a.txt", "b.txt"])

        let png = TestImages.make(width: 320, height: 200, transparent: false, as: .png)
        let image = try await add([[(.png, png)]])
        let details = try #require(try await history.details(for: image))
        #expect(details.imageWidth == 320)
        #expect(details.imageHeight == 200)
        #expect(try await history.imageData(for: image) == png)
        #expect(try await history.imageData(for: files) == nil)
    }

    @Test
    func pasteItemsRebuildTheOriginalPasteboardItems() async throws {
        let id = try await add([
            [(.fileURL, URL(filePath: "/tmp/a.txt").dataRepresentation), (.plainText, Data("a.txt".utf8))],
            [(.fileURL, URL(filePath: "/tmp/b.txt").dataRepresentation), (.plainText, Data("b.txt".utf8))],
        ])
        let all = try await history.pasteItems(for: id)
        #expect(all.map { $0.representations.map(\.flavor) } == [[.fileURL, .plainText], [.fileURL, .plainText]])
        let plain = try await history.pasteItems(for: id, plainTextOnly: true)
        #expect(plain.map { $0.representations.map(\.flavor) } == [[.plainText], [.plainText]])
        #expect(try await history.pasteItems(for: 999).isEmpty)
    }
}
