import Foundation
import GRDB
import SpindleCore
import Testing
import UniformTypeIdentifiers

@testable import SpindleStorage

@Suite
struct IngestorTests {
    private let database: AppDatabase
    private let blobs: BlobStore
    private let ingestor: Ingestor
    private let clock = TestClock(start: Date(timeIntervalSince1970: 1_790_000_000))

    init() throws {
        database = try AppDatabase.inMemory()
        blobs = BlobStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "blobs-\(UUID().uuidString)"))
        ingestor = Ingestor(database: database, blobs: blobs, now: { [clock] in clock.now })
    }

    // MARK: - Fixtures

    private func copy(
        _ items: [[(PasteboardFlavor, Data)]], from app: String? = "com.apple.Safari",
        declaring extra: [PasteboardFlavor] = []
    ) -> CapturedCopy {
        let captured = items.map { CapturedItem(representations: $0.map { Representation(flavor: $0.0, data: $0.1) }) }
        return CapturedCopy(
            items: captured,
            declaredTypes: captured.flatMap { $0.representations.map(\.flavor) } + extra,
            sourceBundleID: app,
            sourceAppName: app.map { $0.components(separatedBy: ".").last! },
            changeCount: 1,
            capturedAt: clock.now)
    }

    private func text(_ string: String, from app: String? = "com.apple.Safari") -> CapturedCopy {
        copy([[(.plainText, Data(string.utf8))]], from: app)
    }

    private func item(_ id: Int64) throws -> Row {
        let row = try database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM item WHERE id = ?", arguments: [id])
        }
        return try #require(row)
    }

    private func representations(_ id: Int64) throws -> [Row] {
        try database.writer.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM representation WHERE item_id = ? ORDER BY ordinal", arguments: [id])
        }
    }

    private func itemCount() throws -> Int {
        try database.writer.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM item") ?? 0 }
    }

    // MARK: - Tests

    @Test
    func storesANewTextCopy() async throws {
        let outcome = try await ingestor.ingest(text("Crème brûlée recipe\nwith notes"))
        guard case .inserted(let id) = outcome else {
            Issue.record("expected an insert, got \(outcome)")
            return
        }
        let row = try item(id)
        #expect(row["kind"] as Int == ItemKind.text.rawValue)
        #expect(row["preview"] as String == "Crème brûlée recipe with notes")
        #expect(row["search_text"] as String == "creme brulee recipe with notes")
        #expect(row["use_count"] as Int == 1)
        #expect(row["seq"] as Int64 == 1)
        let stored = try representations(id)
        #expect(stored.count == 1)
        #expect(stored[0]["uti"] as String == PasteboardFlavor.plainText.rawValue)
        #expect(stored[0]["inline_data"] as Data? == Data("Crème brûlée recipe\nwith notes".utf8))
    }

    @Test
    func copyingTheSameTextAgainMovesItToTheTop() async throws {
        let first = try await ingestor.ingest(text("git status"))
        _ = try await ingestor.ingest(text("something else"))
        clock.advance(by: 60)
        let again = try await ingestor.ingest(
            copy(
                [[(.plainText, Data("git status".utf8)), (.rtf, Data("{\\rtf1 git status}".utf8))]],
                from: "com.apple.Terminal"))

        guard case .inserted(let id) = first, case .bumped(let bumped) = again else {
            Issue.record("expected insert then bump, got \(first) and \(again)")
            return
        }
        #expect(id == bumped)
        #expect(try itemCount() == 2)
        let row = try item(id)
        #expect(row["seq"] as Int64 == 3)
        #expect(row["use_count"] as Int == 2)
        #expect(row["kind"] as Int == ItemKind.richText.rawValue)
        #expect(try representations(id).map { $0["uti"] as String } == ["public.utf8-plain-text", "public.rtf"])
        let sourceID: Int64 = row["source_app_id"]
        let source = try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT bundle_id FROM source_app WHERE id = ?", arguments: [sourceID])
        }
        #expect(source == "com.apple.Terminal")
    }

    @Test
    func bumpingRaisesFrecency() async throws {
        guard case .inserted(let id) = try await ingestor.ingest(text("often")) else {
            Issue.record("unexpected ingest outcome")
            return
        }
        let before = try item(id)["frecency_key"] as Double
        _ = try await ingestor.ingest(text("often"))
        #expect(try item(id)["frecency_key"] as Double > before)
    }

    @Test
    func neverStoresCopiesWithPrivacyMarkers() async throws {
        let password = copy(
            [[(.plainText, Data("hunter2".utf8))]], from: "com.1password.1password", declaring: [.concealed])
        #expect(try await ingestor.ingest(password) == .skipped(.privacyMarker))
        #expect(try itemCount() == 0)
    }

    @Test
    func skipsEmptyCopies() async throws {
        #expect(try await ingestor.ingest(copy([[]])) == .skipped(.empty))
    }

    @Test
    func largePayloadsGoToTheBlobStore() async throws {
        let big = String(repeating: "0123456789", count: 10_000)  // 100 KB
        guard case .inserted(let id) = try await ingestor.ingest(text(big)) else {
            Issue.record("unexpected ingest outcome")
            return
        }
        let stored = try #require(try representations(id).first)
        #expect(stored["inline_data"] as Data? == nil)
        let hashBytes = try #require(stored["blob_hash"] as Data?)
        let hash = try #require(ContentHash(bytes: hashBytes))
        #expect(try blobs.read(hash) == Data(big.utf8))
        #expect(try item(id)["search_text"] as String == String(big.prefix(TextFolding.searchTextLimit)))
    }

    @Test
    func screenshotsArriveAsTIFFAndAreStoredAsPNGWithAThumbnail() async throws {
        let tiff = TestImages.make(width: 1200, height: 800, transparent: false, as: .tiff)
        guard
            case .inserted(let id) = try await ingestor.ingest(
                copy([[(.tiff, tiff)]], from: "com.apple.screencaptureui"))
        else {
            Issue.record("unexpected ingest outcome")
            return
        }
        let row = try item(id)
        #expect(row["kind"] as Int == ItemKind.image.rawValue)
        #expect(row["meta"] as String == #"{"imageHeight":800,"imageWidth":1200}"#)
        #expect(try representations(id).map { $0["uti"] as String } == ["public.png"])
        let thumbnailWidth = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT width FROM thumbnail WHERE item_id = ?", arguments: [id])
        }
        #expect(thumbnailWidth == 256)
    }

    @Test
    func tiffIsDroppedWhenACompressedImageIsAlsoOffered() async throws {
        let png = TestImages.make(width: 100, height: 100, transparent: false, as: .png)
        let tiff = TestImages.make(width: 100, height: 100, transparent: false, as: .tiff)
        guard case .inserted(let id) = try await ingestor.ingest(copy([[(.png, png), (.tiff, tiff)]])) else {
            Issue.record("unexpected ingest outcome")
            return
        }
        #expect(try representations(id).map { $0["uti"] as String } == ["public.png"])
    }

    @Test
    func multipleFilesKeepOnePasteboardItemEach() async throws {
        let files = ["/Users/me/Report.pdf", "/Users/me/Budget.numbers", "/Users/me/Notes.txt"].map { path in
            [(PasteboardFlavor.fileURL, URL(filePath: path).dataRepresentation)]
        }
        guard case .inserted(let id) = try await ingestor.ingest(copy(files, from: "com.apple.finder")) else {
            Issue.record("unexpected ingest outcome")
            return
        }
        let row = try item(id)
        #expect(row["kind"] as Int == ItemKind.file.rawValue)
        #expect(row["preview"] as String == "Report.pdf, Budget.numbers, Notes.txt")
        #expect(row["meta"] as String == #"{"fileCount":3}"#)
        #expect(try representations(id).map { $0["item_index"] as Int } == [0, 1, 2])
    }

    @Test
    func copiesWithoutASourceAppAreStillStored() async throws {
        guard case .inserted(let id) = try await ingestor.ingest(text("from nowhere", from: nil)) else {
            Issue.record("unexpected ingest outcome")
            return
        }
        #expect(try item(id)["source_app_id"] as Int64? == nil)
    }

    @Test
    func announcesInsertsAndBumpsInOrder() async throws {
        var changes = ingestor.changes.makeAsyncIterator()
        guard case .inserted(let a) = try await ingestor.ingest(text("a")),
            case .inserted(let b) = try await ingestor.ingest(text("b"))
        else {
            Issue.record("unexpected ingest outcome")
            return
        }
        _ = try await ingestor.ingest(text("a"))
        #expect(await changes.next() == .inserted(itemID: a))
        #expect(await changes.next() == .inserted(itemID: b))
        #expect(await changes.next() == .bumped(itemID: a))
    }
}

/// A clock tests can move by hand.
final class TestClock: @unchecked Sendable {
    // Only mutated from the test body, never concurrently with reads.
    private(set) var now: Date

    init(start: Date) { now = start }

    func advance(by interval: TimeInterval) { now.addTimeInterval(interval) }
}
