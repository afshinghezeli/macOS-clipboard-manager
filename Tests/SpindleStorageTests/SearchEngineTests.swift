import Foundation
import GRDB
import SpindleCore
import Testing

@testable import SpindleStorage

@Suite
struct SearchEngineTests {
    private let database: AppDatabase
    private let ingestor: Ingestor
    private let engine: SearchEngine
    private let clock = TestClock(start: Date(timeIntervalSince1970: 1_790_000_000))

    init() throws {
        database = try AppDatabase.inMemory()
        let blobs = BlobStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "blobs-\(UUID().uuidString)"))
        ingestor = Ingestor(database: database, blobs: blobs)
        engine = SearchEngine(database: database)
    }

    @discardableResult
    private func add(_ text: String) async throws -> Int64 {
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

    private func previews(_ query: String) async throws -> [String] {
        try await engine.search(query, at: clock.now).map(\.item.preview)
    }

    @Test
    func findsTextInsideWords() async throws {
        try await add("the clipboard remembers")
        try await add("unrelated")
        #expect(try await previews("clipb") == ["the clipboard remembers"])
    }

    @Test
    func ignoresCaseAndAccents() async throws {
        try await add("Crème brûlée recipe")
        #expect(try await previews("CREME BRU") == ["Crème brûlée recipe"])
    }

    @Test
    func shortQueriesScanRecentItems() async throws {
        try await add("ab cd")
        try await add("東京タワー")
        #expect(try await previews("cd") == ["ab cd"])
        #expect(try await previews("東京") == ["東京タワー"])
    }

    @Test
    func wordsMatchInAnyOrder() async throws {
        try await add("git status --short")
        #expect(try await previews("status git") == ["git status --short"])
        #expect(try await previews("git st") == ["git status --short"])
        #expect(try await previews("git rebase").isEmpty)
    }

    @Test
    func betterMatchesComeFirst() async throws {
        try await add("invoice")
        try await add("send the invoice")
        try await add("voice memo")
        #expect(try await previews("invoice") == ["invoice", "send the invoice"])
    }

    @Test
    func pinnedItemsAreFoundHoweverOld() async throws {
        let pinned = try await add("match: the pinned one")
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE item SET pinned_rank = 1 WHERE id = ?", arguments: [pinned])
        }
        for index in 0..<300 { try await add("match number \(index)") }

        let results = try await engine.search("match", at: clock.now)
        #expect(results.count == SearchEngine.resultLimit)
        #expect(results.contains { $0.item.id == pinned && $0.item.isPinned })
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankQueriesReturnNothing(_ query: String) async throws {
        try await add("anything")
        #expect(try await previews(query).isEmpty)
    }

    @Test(arguments: [#"say "hi""#, "*", "hi*", "NEAR(a b)", "a AND b", "col:value", "-x", "^", #"""""#])
    func queryTextIsNeverReadAsSearchSyntax(_ query: String) async throws {
        try await add("before \(query) after")
        // No FTS syntax error, and the literal text is found.
        #expect(try await engine.search(query, at: clock.now).count == 1)
    }

    @Test
    func staysFastWithTenThousandItems() async throws {
        let words = ["alpha", "invoice", "status", "clipboard", "https://example.org", "東京タワー", "meeting", "notes"]
        try await database.writer.write { db in
            for seq in 1...10_000 {
                let text = TextFolding.fold("\(words[seq % words.count]) item \(seq) \(words[(seq * 7) % words.count])")
                try db.execute(
                    sql: """
                        INSERT INTO item (seq, content_hash, kind, preview, search_text, byte_size, created_at, last_used_at)
                        VALUES (?, randomblob(32), 0, ?, ?, 10, 0, 0)
                        """,
                    arguments: [seq, text, text])
            }
        }
        _ = try await engine.search("invoice", at: clock.now)  // warm up
        for query in ["invoice", "status meet", "item 9", "東京", "a"] {
            let start = ContinuousClock.now
            let results = try await engine.search(query, at: clock.now)
            // A coarse guard against accidental full scans, in a debug build. Real numbers: make bench.
            #expect(ContinuousClock.now - start < .milliseconds(100), "\(query)")
            #expect(!results.isEmpty, "\(query)")
        }
    }

    @Test
    func unmatchedQueriesReturnNothing() async throws {
        try await add("git status")
        #expect(try await previews("zebra").isEmpty)
        #expect(try await previews("zz").isEmpty)
    }
}
