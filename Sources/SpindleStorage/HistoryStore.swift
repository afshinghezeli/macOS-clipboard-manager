public import Foundation
import GRDB
public import SpindleCore

/// Reads the history for the UI, and records what the user does with items. New copies are written
/// by the ``Ingestor``.
public struct HistoryStore: Sendable {
    private let database: AppDatabase
    private let blobs: BlobStore

    public init(database: AppDatabase, blobs: BlobStore) {
        self.database = database
        self.blobs = blobs
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

    // MARK: - Contents

    public func details(for itemID: Int64) async throws -> ItemDetails? {
        let blobs = blobs
        return try await database.writer.read { db -> ItemDetails? in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT \(ItemSummary.columns), byte_size, meta,
                            (SELECT bundle_id FROM source_app WHERE source_app.id = item.source_app_id) AS bundle_id,
                            (SELECT name FROM source_app WHERE source_app.id = item.source_app_id) AS name
                        FROM item WHERE id = ?
                        """,
                    arguments: [itemID])
            else { return nil }
            let representations = try Self.representations(of: itemID, in: db)
            let metadata = (row["meta"] as String?).flatMap {
                try? JSONDecoder().decode(Metadata.self, from: Data($0.utf8))
            }

            var text: String?
            var truncated = false
            if let plain = representations.first(where: { $0.flavor == .plainText }) {
                let data = try Self.payload(plain, blobs: blobs)
                truncated = data.count > ItemDetails.textLimit
                text = String(decoding: data.prefix(ItemDetails.textLimit), as: UTF8.self)
            }
            let files = try representations.filter { $0.flavor == .fileURL }.compactMap {
                URL(dataRepresentation: try Self.payload($0, blobs: blobs), relativeTo: nil)
            }
            var seen = Set<PasteboardFlavor>()
            return ItemDetails(
                summary: ItemSummary(row: row),
                text: text,
                isTextTruncated: truncated,
                fileURLs: files,
                imageWidth: metadata?.imageWidth,
                imageHeight: metadata?.imageHeight,
                sourceBundleID: row["bundle_id"],
                sourceAppName: row["name"],
                byteSize: row["byte_size"],
                flavors: representations.map(\.flavor).filter { seen.insert($0).inserted })
        }
    }

    /// The bytes of the item's best image format, for showing it larger than its thumbnail.
    public func imageData(for itemID: Int64) async throws -> Data? {
        let blobs = blobs
        return try await database.writer.read { db -> Data? in
            let representations = try Self.representations(of: itemID, in: db)
            for flavor in [PasteboardFlavor.png, .heic, .jpeg, .tiff, .pdf] {
                if let match = representations.first(where: { $0.flavor == flavor }) {
                    return try Self.payload(match, blobs: blobs)
                }
            }
            return nil
        }
    }

    /// The item as pasteboard items, ready to be written back: every format it was copied with, or
    /// only its plain text. Empty when there's nothing to write in that mode.
    public func pasteItems(for itemID: Int64, plainTextOnly: Bool = false) async throws -> [CapturedItem] {
        let blobs = blobs
        return try await database.writer.read { db in
            let representations = try Self.representations(of: itemID, in: db)
            var items: [Int: [Representation]] = [:]
            for stored in representations where !plainTextOnly || stored.flavor == .plainText {
                items[stored.itemIndex, default: []].append(
                    Representation(flavor: stored.flavor, data: try Self.payload(stored, blobs: blobs)))
            }
            return items.keys.sorted().map { CapturedItem(representations: items[$0]!) }
        }
    }

    // MARK: - Payloads

    private struct StoredRepresentation {
        var itemIndex: Int
        var flavor: PasteboardFlavor
        var inline: Data?
        var blobHash: Data?
    }

    private struct Metadata: Decodable {
        var imageWidth: Int?
        var imageHeight: Int?
    }

    private static func representations(of itemID: Int64, in db: Database) throws -> [StoredRepresentation] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT item_index, uti, inline_data, blob_hash FROM representation
                WHERE item_id = ? ORDER BY item_index, ordinal
                """,
            arguments: [itemID]
        ).map { row in
            StoredRepresentation(
                itemIndex: row["item_index"], flavor: PasteboardFlavor(row["uti"] as String),
                inline: row["inline_data"], blobHash: row["blob_hash"])
        }
    }

    private static func payload(_ representation: StoredRepresentation, blobs: BlobStore) throws -> Data {
        if let inline = representation.inline { return inline }
        guard let bytes = representation.blobHash, let hash = ContentHash(bytes: bytes) else { return Data() }
        return try blobs.read(hash)
    }
}
