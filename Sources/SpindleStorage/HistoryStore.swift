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
}
