public import Foundation
import GRDB
public import SpindleCore
import os

/// Applies a ``RetentionPolicy``: removes old items, then deletes payload files nothing refers to.
///
/// Deletes happen in transactions of at most 500 items. One huge delete would grow the WAL to the
/// size of the history and hold the writer for seconds, blocking every capture meanwhile.
public struct Pruner: Sendable {
    public struct Result: Hashable, Sendable {
        public var removedItems = 0
        public var removedFiles = 0
    }

    static let batchSize = 500

    private let database: AppDatabase
    private let blobs: BlobStore
    private let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: "Maintenance")

    public init(database: AppDatabase, blobs: BlobStore) {
        self.database = database
        self.blobs = blobs
    }

    /// - Parameter fileGracePeriod: payload files younger than this are never swept, because an
    ///   ingest may have written one and not yet committed the row that references it.
    @discardableResult
    public func prune(
        with policy: RetentionPolicy, at date: Date = .now, fileGracePeriod: TimeInterval = 3600
    ) async throws -> Result {
        let interval = signposter.beginInterval("prune")
        defer { signposter.endInterval("prune", interval) }

        var result = Result()
        let now = Int64(date.timeIntervalSince1970 * 1000)

        for kind in ItemKind.allCases {
            guard let maxAge = policy.maxAge(for: kind) else { continue }
            let cutoff = now - Int64(maxAge * 1000)
            result.removedItems += try await deleteInBatches(
                where: "kind = \(kind.rawValue) AND last_used_at < \(cutoff)")
        }

        if let maxItems = policy.maxItems {
            // Everything older than the newest `maxItems` unpinned items.
            result.removedItems += try await deleteInBatches(
                where: """
                    seq < coalesce((SELECT min(seq) FROM (SELECT seq FROM item WHERE pinned_rank IS NULL
                        ORDER BY seq DESC LIMIT \(max(maxItems, 0)))), 9223372036854775807)
                    """)
        }

        if let maxTotalBytes = policy.maxTotalBytes {
            result.removedItems += try await trimToSize(maxTotalBytes)
        }

        result.removedFiles = try await sweepFiles(olderThan: date.addingTimeInterval(-fileGracePeriod))
        try await database.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA incremental_vacuum(1000)")
        }
        return result
    }

    /// Deletes every unpinned item and its payload files, then compacts the database so the
    /// deleted text doesn't linger in free pages. Returns how many items were removed.
    @discardableResult
    public func clearHistory() async throws -> Int {
        let removed = try await deleteInBatches(where: "1")
        // A short grace period still protects a copy being stored right now.
        _ = try await sweepFiles(olderThan: .now.addingTimeInterval(-60))
        try await database.writer.vacuum()
        return removed
    }

    /// Deletes unpinned items matching `condition`, oldest first, one batch per transaction.
    private func deleteInBatches(where condition: String) async throws -> Int {
        var total = 0
        while true {
            let deleted = try await database.write { db in
                try db.execute(
                    sql: """
                        DELETE FROM item WHERE id IN (
                            SELECT id FROM item WHERE pinned_rank IS NULL AND (\(condition))
                            ORDER BY seq LIMIT \(Self.batchSize))
                        """)
                return db.changesCount
            }
            total += deleted
            if deleted < Self.batchSize { return total }
        }
    }

    /// Removes the oldest unpinned items until the stored payloads fit in `maxTotalBytes`.
    private func trimToSize(_ maxTotalBytes: Int) async throws -> Int {
        var total = 0
        while true {
            let deleted = try await database.write { db -> Int in
                let size = try Int.fetchOne(db, sql: "SELECT coalesce(sum(byte_size), 0) FROM item") ?? 0
                guard size > maxTotalBytes else { return 0 }
                var excess = size - maxTotalBytes
                // Pick the oldest items whose sizes add up to the excess, at most one batch.
                let candidates = try Row.fetchAll(
                    db,
                    sql: "SELECT id, byte_size FROM item WHERE pinned_rank IS NULL ORDER BY seq LIMIT \(Self.batchSize)"
                )
                var ids: [Int64] = []
                for row in candidates where excess > 0 {
                    ids.append(row["id"])
                    excess -= row["byte_size"] as Int
                }
                guard !ids.isEmpty else { return 0 }
                try db.execute(sql: "DELETE FROM item WHERE id IN (\(ids.map(String.init).joined(separator: ",")))")
                return ids.count
            }
            total += deleted
            if deleted < Self.batchSize { return total }
        }
    }

    private func sweepFiles(olderThan cutoff: Date) async throws -> Int {
        let referenced = try await database.writer.read { db in
            try Data.fetchAll(db, sql: "SELECT DISTINCT blob_hash FROM representation WHERE blob_hash IS NOT NULL")
        }
        return try blobs.sweep(keeping: Set(referenced.compactMap(ContentHash.init(bytes:))), olderThan: cutoff)
    }
}
