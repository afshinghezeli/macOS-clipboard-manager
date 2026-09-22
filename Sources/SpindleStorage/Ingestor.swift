import Foundation
import GRDB
public import SpindleCore
import os

/// A change to the history that an open panel may want to show.
public enum HistoryChange: Hashable, Sendable {
    case inserted(itemID: Int64)
    case bumped(itemID: Int64)
}

/// What happened to a captured copy.
public enum IngestOutcome: Hashable, Sendable {
    case inserted(itemID: Int64)
    /// The copy matched an existing item, which moved to the top of the history.
    case bumped(itemID: Int64)
    case skipped(SkipReason)

    public enum SkipReason: Hashable, Sendable {
        case empty
        case privacyMarker
    }
}

/// Turns captured copies into history items.
///
/// Hashing, image work and file writes happen here, off the main thread, followed by one short
/// write transaction per copy. Callers should run ``ingest(_:)`` in a detached task: GRDB aborts a
/// write when its task is cancelled, and a copy must never be lost because a UI task went away.
public actor Ingestor {
    private let database: AppDatabase
    private let blobs: BlobStore
    private let continuation: AsyncStream<HistoryChange>.Continuation
    private let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: "Ingest")

    /// Every insert and bump, in the order they were committed.
    public nonisolated let changes: AsyncStream<HistoryChange>

    public init(database: AppDatabase, blobs: BlobStore) {
        self.database = database
        self.blobs = blobs
        (changes, continuation) = AsyncStream.makeStream(of: HistoryChange.self, bufferingPolicy: .bufferingNewest(64))
    }

    @discardableResult
    public func ingest(_ copy: CapturedCopy) async throws -> IngestOutcome {
        let interval = signposter.beginInterval("ingest")
        defer { signposter.endInterval("ingest", interval) }

        // The capture filter already drops these. Checking again costs nothing and means a bug
        // upstream can never write a password to disk.
        guard copy.privacyMarkers.isEmpty else { return .skipped(.privacyMarker) }

        let prepared = PreparedCopy(copy)
        guard !prepared.representations.isEmpty else { return .skipped(.empty) }

        // Files first, row second: a crash in between leaves an orphaned file for the sweep, never
        // a row that points at nothing.
        var blobHashes: [Int: ContentHash] = [:]
        for (position, representation) in prepared.representations.enumerated()
        where representation.data.count > BlobStore.inlineLimit {
            blobHashes[position] = try blobs.write(representation.data)
        }

        // The copy's own time: now for live capture, the original time for imported history.
        let date = copy.capturedAt
        let metadata = try String(decoding: JSONEncoder.sorted.encode(prepared.metadata), as: UTF8.self)
        let record = SaveRequest(prepared: prepared, blobHashes: blobHashes, metadata: metadata, copy: copy, date: date)
        let outcome = try await database.write { db in
            try Self.save(record, in: db)
        }

        switch outcome {
        case .inserted(let id): continuation.yield(.inserted(itemID: id))
        case .bumped(let id): continuation.yield(.bumped(itemID: id))
        case .skipped: break
        }
        return outcome
    }

    /// Everything one write transaction needs, gathered before it starts.
    private struct SaveRequest: Sendable {
        var prepared: PreparedCopy
        var blobHashes: [Int: ContentHash]
        var metadata: String
        var copy: CapturedCopy
        var date: Date
    }

    private static func save(_ request: SaveRequest, in db: Database) throws -> IngestOutcome {
        let (prepared, blobHashes, metadata, copy, date) = (
            request.prepared, request.blobHashes, request.metadata, request.copy, request.date
        )
        let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let sourceID = try copy.sourceBundleID.map { bundleID in
            try Int64.fetchOne(
                db,
                sql: """
                    INSERT INTO source_app (bundle_id, name) VALUES (?, ?)
                    ON CONFLICT (bundle_id) DO UPDATE SET name = excluded.name
                    RETURNING id
                    """,
                arguments: [bundleID, copy.sourceAppName ?? bundleID])
        }
        let seq = (try Int64.fetchOne(db, sql: "SELECT max(seq) FROM item") ?? 0) + 1

        let itemID: Int64
        let outcome: IngestOutcome
        if let existing = try Row.fetchOne(
            db, sql: "SELECT id, frecency_key FROM item WHERE content_hash = ?",
            arguments: [prepared.dedupKey.bytes])
        {
            itemID = existing["id"]
            let frecency = Frecency.key(existing["frecency_key"], usedAgainAt: date)
            // The text goes straight back into the search index under the new seq, so there is
            // nothing to erase. FTS5's secure delete would still search the whole index for the
            // old entry: at 100,000 items that made a re-copy take 3 ms, 13 ms at p99 (M2.6).
            try db.execute(sql: "INSERT INTO item_fts(item_fts, rank) VALUES ('secure-delete', 0)")
            try db.execute(
                sql: """
                    UPDATE item SET seq = ?, kind = ?, preview = ?, search_text = ?, byte_size = ?,
                        source_app_id = ?, last_used_at = ?, use_count = use_count + 1,
                        frecency_key = ?, meta = ?
                    WHERE id = ?
                    """,
                arguments: [
                    seq, prepared.kind.rawValue, prepared.preview, prepared.searchText, prepared.byteCount,
                    sourceID, milliseconds, frecency, metadata, itemID,
                ])
            try db.execute(sql: "INSERT INTO item_fts(item_fts, rank) VALUES ('secure-delete', 1)")
            // The newest copy's formatting replaces the old. Blob files the old rows pointed to
            // are left for the sweep, which only removes files no row references.
            try db.execute(sql: "DELETE FROM representation WHERE item_id = ?", arguments: [itemID])
            try db.execute(sql: "DELETE FROM thumbnail WHERE item_id = ?", arguments: [itemID])
            outcome = .bumped(itemID: itemID)
        } else {
            try db.execute(
                sql: """
                    INSERT INTO item (seq, content_hash, kind, preview, search_text, byte_size, source_app_id,
                        created_at, last_used_at, use_count, frecency_key, meta)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
                    """,
                arguments: [
                    seq, prepared.dedupKey.bytes, prepared.kind.rawValue, prepared.preview, prepared.searchText,
                    prepared.byteCount, sourceID, milliseconds, milliseconds,
                    Frecency.key(firstUsedAt: date), metadata,
                ])
            itemID = db.lastInsertedRowID
            outcome = .inserted(itemID: itemID)
        }

        for (position, representation) in prepared.representations.enumerated() {
            let blob = blobHashes[position]
            try db.execute(
                sql: """
                    INSERT INTO representation (item_id, item_index, ordinal, uti, inline_data, blob_hash, byte_size)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    itemID, representation.itemIndex, position, representation.flavor.rawValue,
                    blob == nil ? representation.data : nil, blob?.bytes, representation.data.count,
                ])
        }
        if let thumbnail = prepared.thumbnail {
            try db.execute(
                sql: "INSERT INTO thumbnail (item_id, width, height, data) VALUES (?, ?, ?, ?)",
                arguments: [itemID, thumbnail.width, thumbnail.height, thumbnail.data])
        }
        return outcome
    }
}

extension JSONEncoder {
    fileprivate static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
