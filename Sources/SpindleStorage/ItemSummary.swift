public import Foundation
import GRDB
public import SpindleCore

/// What the history list and search results show for one item. No payloads.
public struct ItemSummary: Hashable, Sendable, Identifiable {
    public var id: Int64
    /// Recency order: higher is more recent.
    public var seq: Int64
    public var kind: ItemKind
    public var preview: String
    /// A name the user gave the item, if any.
    public var title: String?
    public var sourceAppID: Int64?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var isPinned: Bool

    static let columns = """
        id, seq, kind, preview, title, source_app_id, created_at, last_used_at, use_count, pinned_rank
        """

    init(row: Row) {
        id = row["id"]
        seq = row["seq"]
        kind = ItemKind(rawValue: row["kind"]) ?? .text
        preview = row["preview"]
        title = row["title"]
        sourceAppID = row["source_app_id"]
        createdAt = Date(timeIntervalSince1970: Double(row["created_at"] as Int64) / 1000)
        lastUsedAt = Date(timeIntervalSince1970: Double(row["last_used_at"] as Int64) / 1000)
        useCount = row["use_count"]
        isPinned = row["pinned_rank"] != nil
    }
}
