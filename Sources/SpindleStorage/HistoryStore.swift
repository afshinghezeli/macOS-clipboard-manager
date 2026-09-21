public import Foundation
import GRDB
import SpindleCore

/// Reads the history for the UI, and records what the user does with items. New copies are written
/// by the ``Ingestor``.
public struct HistoryStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func itemCount() async throws -> Int {
        try await database.writer.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM item") ?? 0 }
    }

    /// Records that the item was pasted or copied from Spindle: it moves to the top of the history
    /// and its frecency rises. Pasting writes the pasteboard, and capture ignores Spindle's own
    /// writes, so this is the only place that use is counted.
    public func markUsed(_ itemID: Int64, at date: Date = .now) async throws {
        try await database.writer.write { db in
            guard
                let key = try Double.fetchOne(
                    db, sql: "SELECT frecency_key FROM item WHERE id = ?", arguments: [itemID])
            else { return }
            let seq = (try Int64.fetchOne(db, sql: "SELECT max(seq) FROM item") ?? 0) + 1
            let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
            try db.execute(
                sql: """
                    UPDATE item SET seq = ?, last_used_at = ?, use_count = use_count + 1, frecency_key = ?
                    WHERE id = ?
                    """,
                arguments: [seq, milliseconds, Frecency.key(key, usedAgainAt: date), itemID])
        }
    }

    /// Pins the item at the end of the pinned list, or unpins it. Pinned items are never pruned.
    public func setPinned(_ itemID: Int64, _ pinned: Bool) async throws {
        try await database.writer.write { db in
            if pinned {
                try db.execute(
                    sql: """
                        UPDATE item SET pinned_rank = (SELECT coalesce(max(pinned_rank), 0) + 1 FROM item)
                        WHERE id = ? AND pinned_rank IS NULL
                        """,
                    arguments: [itemID])
            } else {
                try db.execute(sql: "UPDATE item SET pinned_rank = NULL WHERE id = ?", arguments: [itemID])
            }
        }
    }

    // MARK: - Listing

    /// Pinned items, in the order the user arranged them.
    public func pinned() async throws -> [ItemSummary] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db, sql: "SELECT \(ItemSummary.columns) FROM item WHERE pinned_rank IS NOT NULL ORDER BY pinned_rank"
            ).map(ItemSummary.init(row:))
        }
    }

    /// Unpinned items, newest first. Pass the last `seq` of one page as `before` to get the next;
    /// keyset paging costs the same on page 1 and page 1,000.
    public func recent(before seq: Int64? = nil, limit: Int = 100) async throws -> [ItemSummary] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT \(ItemSummary.columns) FROM item
                    WHERE pinned_rank IS NULL AND seq < ?
                    ORDER BY seq DESC LIMIT ?
                    """,
                arguments: [seq ?? Int64.max, limit]
            ).map(ItemSummary.init(row:))
        }
    }

    public func summary(for itemID: Int64) async throws -> ItemSummary? {
        try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT \(ItemSummary.columns) FROM item WHERE id = ?", arguments: [itemID])
                .map(ItemSummary.init(row:))
        }
    }

    /// The item's list thumbnail (JPEG or PNG), if it is an image.
    public func thumbnail(for itemID: Int64) async throws -> Data? {
        try await database.writer.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM thumbnail WHERE item_id = ?", arguments: [itemID])
        }
    }
}
