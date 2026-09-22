public import Foundation
import GRDB
public import SpindleCore
import os

public struct SearchResult: Hashable, Sendable {
    public var item: ItemSummary
    public var score: Double
}

/// Finds history items for a typed query.
///
/// Every word of the query must occur in the item's folded text. Words of three or more characters
/// go through the trigram index, whose rowid is the recency key, so the newest matches come back
/// without sorting; shorter words in the same query are checked while walking those matches. A
/// query made only of shorter words scans the newest items instead. Pinned and often-used items are
/// always considered, however old. At most a few hundred candidates are ranked in Swift; the whole
/// history is never loaded.
public struct SearchEngine: Sendable {
    public static let resultLimit = 100
    /// Newest matches taken from the index or the scan.
    static let candidateLimit = 256
    /// Most-used items always considered, whatever their age.
    static let frecentPoolSize = 512
    /// How far back, in recency steps, a query of only short words looks.
    static let shortQueryScanBudget = 20_000
    /// How many index matches of its long words a query with short words too walks, looking for
    /// items that also have the short ones. Walking 20,000 took 35 ms (p99) at 100,000 items when
    /// none had them; the keystroke budget there is 25 ms.
    static let mixedQueryScanBudget = 8_000

    private let database: AppDatabase
    private let ranking: SearchRanking
    private let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: "Search")

    public init(database: AppDatabase, ranking: SearchRanking = SearchRanking()) {
        self.database = database
        self.ranking = ranking
    }

    /// Results for `text`, best first. An empty query returns nothing; the list shows the plain
    /// history instead. Throws `CancellationError` if the calling task is cancelled, which happens
    /// on every keystroke that supersedes this one.
    public func search(_ text: String, limit: Int = resultLimit, at now: Date = .now) async throws -> [SearchResult] {
        let query = TextFolding.fold(text, maxUTF8Bytes: 512)
        guard !query.isEmpty else { return [] }
        let interval = signposter.beginInterval("search")
        defer { signposter.endInterval("search", interval) }

        var seen = Set<String>()
        let words = query.split(separator: " ").map(String.init).filter { seen.insert($0).inserted }
        let candidates = try await database.writer.read { db in
            try Self.candidates(for: words, in: db)
        }
        try Task.checkCancellation()

        var results: [SearchResult] = []
        results.reserveCapacity(candidates.count)
        for candidate in candidates {
            let ranked = SearchRanking.Candidate(
                text: candidate.searchText,
                lastUsedAt: candidate.summary.lastUsedAt,
                frecencyKey: candidate.frecencyKey,
                isPinned: candidate.summary.isPinned)
            if let score = ranking.score(ranked, query: query, at: now) {
                results.append(SearchResult(item: candidate.summary, score: score))
            }
        }
        results.sort { $0.score != $1.score ? $0.score > $1.score : $0.item.seq > $1.item.seq }
        return Array(results.prefix(limit))
    }

    private struct Candidate: Sendable {
        var summary: ItemSummary
        var searchText: String
        var frecencyKey: Double
    }

    private static func candidates(for words: [String], in db: Database) throws -> [Candidate] {
        // Trigram tokens are characters, so words shorter than three can't use the index.
        let indexable = words.filter { $0.unicodeScalars.count >= 3 }
        let containsAll = words.map { _ in "instr(search_text, ?) > 0" }.joined(separator: " AND ")

        var seqs: [Int64]
        if !indexable.isEmpty {
            // Each word as a quoted phrase, so nothing the user types is read as FTS syntax.
            let match = indexable.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                .joined(separator: " AND ")
            let short = words.filter { $0.unicodeScalars.count < 3 }
            if short.isEmpty {
                seqs = try Int64.fetchAll(
                    db, sql: "SELECT rowid FROM item_fts WHERE item_fts MATCH ? ORDER BY rowid DESC LIMIT ?",
                    arguments: [match, candidateLimit])
            } else {
                // Taking the newest index matches and checking the short words afterwards misses
                // older items when the newest matches lack them ("git st"). So check them while
                // walking the matches newest first, and stop at enough candidates or at the budget.
                // CROSS JOIN keeps the walk as the outer loop, so the rows come out newest first
                // and the LIMIT stops it early, without sorting.
                let containsShort = short.map { _ in "instr(item.search_text, ?) > 0" }.joined(separator: " AND ")
                seqs = try Int64.fetchAll(
                    db,
                    sql: """
                        SELECT walk.seq FROM (
                            SELECT rowid AS seq FROM item_fts WHERE item_fts MATCH ? ORDER BY rowid DESC LIMIT ?
                        ) AS walk CROSS JOIN item ON item.seq = walk.seq
                        WHERE \(containsShort)
                        LIMIT ?
                        """,
                    arguments: [match, mixedQueryScanBudget] + StatementArguments(short) + [candidateLimit])
            }
        } else {
            seqs = try Int64.fetchAll(
                db,
                sql: """
                    SELECT seq FROM item
                    WHERE seq > (SELECT coalesce(max(seq), 0) FROM item) - ? AND \(containsAll)
                    ORDER BY seq DESC LIMIT ?
                    """,
                arguments: StatementArguments([shortQueryScanBudget] + words + [candidateLimit]))
        }

        // Pinned and often-used items are small pools; filtering them with instr is cheap. Combining
        // MATCH with `rowid IN (…)` instead would make FTS5 scan every match.
        seqs += try Int64.fetchAll(
            db,
            sql: """
                SELECT seq FROM (
                    SELECT seq, search_text FROM item WHERE pinned_rank IS NOT NULL
                    UNION ALL
                    SELECT seq, search_text FROM (SELECT seq, search_text FROM item ORDER BY frecency_key DESC LIMIT ?)
                ) WHERE \(containsAll)
                """,
            arguments: StatementArguments([frecentPoolSize] + words))

        guard !seqs.isEmpty else { return [] }
        let list = Set(seqs).map(String.init).joined(separator: ",")  // integers only
        return try Row.fetchAll(
            db,
            sql: "SELECT \(ItemSummary.columns), search_text, frecency_key FROM item WHERE seq IN (\(list))"
        ).map { row in
            Candidate(summary: ItemSummary(row: row), searchText: row["search_text"], frecencyKey: row["frecency_key"])
        }
    }
}
