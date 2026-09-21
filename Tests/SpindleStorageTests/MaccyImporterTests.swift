import Foundation
import GRDB
import SpindleCore
import Testing

@testable import SpindleStorage

/// Builds a store with Maccy's SwiftData schema (Core Data naming) and imports it.
@Suite
struct MaccyImporterTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "maccy-\(UUID().uuidString)")
    private let database: AppDatabase
    private let history: HistoryStore
    private let importer: MaccyImporter

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        database = try AppDatabase.inMemory()
        let blobs = BlobStore(directory: folder.appending(path: "blobs"))
        history = HistoryStore(database: database, blobs: blobs)
        importer = MaccyImporter(ingestor: Ingestor(database: database, blobs: blobs), history: history)
    }

    private struct Item {
        var app: String?
        var copiedAt: Date
        var pinned = false
        var contents: [(String, Data)]
    }

    private func writeMaccyStore(_ items: [Item]) throws {
        let store = try DatabaseQueue(path: folder.appending(path: "Storage.sqlite").path(percentEncoded: false))
        try store.write { db in
            try db.execute(
                sql: """
                    CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER,
                        ZNUMBEROFCOPIES INTEGER, ZFIRSTCOPIEDAT TIMESTAMP, ZLASTCOPIEDAT TIMESTAMP,
                        ZAPPLICATION VARCHAR, ZPIN VARCHAR, ZTITLE VARCHAR);
                    CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER,
                        ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
                    """)
            for (index, item) in items.enumerated() {
                let pk = index + 1
                try db.execute(
                    sql:
                        "INSERT INTO ZHISTORYITEM (Z_PK, ZLASTCOPIEDAT, ZAPPLICATION, ZPIN, ZTITLE) VALUES (?, ?, ?, ?, '')",
                    arguments: [pk, item.copiedAt.timeIntervalSinceReferenceDate, item.app, item.pinned ? "b" : nil])
                for (type, value) in item.contents {
                    try db.execute(
                        sql: "INSERT INTO ZHISTORYITEMCONTENT (ZITEM, ZTYPE, ZVALUE) VALUES (?, ?, ?)",
                        arguments: [pk, type, value])
                }
            }
        }
    }

    private func text(_ string: String) -> (String, Data) { ("public.utf8-plain-text", Data(string.utf8)) }

    @Test
    func importsItemsWithTheirOriginalOrderAndPins() async throws {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        try writeMaccyStore([
            Item(app: "com.apple.Safari", copiedAt: base.addingTimeInterval(20), contents: [text("newest")]),
            Item(app: "com.apple.Notes", copiedAt: base, pinned: true, contents: [text("oldest, pinned")]),
            Item(app: "com.apple.Terminal", copiedAt: base.addingTimeInterval(10), contents: [text("middle")]),
        ])
        #expect(try await importer.importHistory(from: folder, filter: CaptureFilter()) == 3)
        #expect(try await history.pinned().map(\.preview) == ["oldest, pinned"])
        let recent = try await history.recent()
        #expect(recent.map(\.preview) == ["newest", "middle"])
        #expect(recent.first?.createdAt == base.addingTimeInterval(20))
    }

    @Test
    func splitsMultiFileCopiesIntoOnePasteboardItemEach() async throws {
        let files = ["/tmp/a.txt", "/tmp/b.txt"].map { ("public.file-url", URL(filePath: $0).dataRepresentation) }
        try writeMaccyStore([Item(app: "com.apple.finder", copiedAt: .now, contents: files)])
        try await importer.importHistory(from: folder, filter: CaptureFilter())
        let id = try #require(try await history.recent().first?.id)
        #expect(try await history.pasteItems(for: id).count == 2)
    }

    @Test
    func leavesOutWhatSpindleWouldNeverHaveKept() async throws {
        try writeMaccyStore([
            Item(app: "com.1password.1password", copiedAt: .now, contents: [text("hunter2")]),
            Item(
                app: "com.apple.Safari", copiedAt: .now,
                contents: [text("secret"), ("org.nspasteboard.ConcealedType", Data())]),
            Item(app: "com.apple.Safari", copiedAt: .now, contents: [("dyn.ah62d4rv4gk81", Data("private".utf8))]),
            Item(app: "com.apple.Safari", copiedAt: .now, contents: [text("fine")]),
        ])
        #expect(try await importer.importHistory(from: folder, filter: CaptureFilter()) == 1)
        #expect(try await history.recent().map(\.preview) == ["fine"])
    }

    @Test
    func aFolderWithoutMaccyHistoryIsReported() async throws {
        await #expect(throws: MaccyImporter.ImportError.noHistoryFound) {
            try await importer.importHistory(from: folder, filter: CaptureFilter())
        }
    }
}
