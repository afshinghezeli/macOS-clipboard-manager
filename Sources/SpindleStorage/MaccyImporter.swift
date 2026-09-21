public import Foundation
import GRDB
public import SpindleCore

/// Brings over the history of Maccy, the most common clipboard manager people switch from.
///
/// Maccy keeps its history in a SwiftData store: SQLite with Core Data's naming, one row per item in
/// `ZHISTORYITEM` and one row per pasteboard type in `ZHISTORYITEMCONTENT`. The store runs in WAL
/// mode, so its three files are copied together before reading; Maccy can keep running meanwhile.
public struct MaccyImporter: Sendable {
    public enum ImportError: Error, Equatable {
        /// The chosen folder has no Maccy history in it.
        case noHistoryFound
    }

    /// Where a sandboxed Maccy keeps its history; offered as the starting folder of the open panel.
    public static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(
            path: "Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy",
            directoryHint: .isDirectory)

    private let ingestor: Ingestor
    private let history: HistoryStore

    public init(ingestor: Ingestor, history: HistoryStore) {
        self.ingestor = ingestor
        self.history = history
    }

    /// Imports every item from the Maccy folder, oldest first, and returns how many were stored.
    /// `filter` applies as it does to live copies, so copies from ignored apps and copies marked
    /// private don't come in through the back door.
    @discardableResult
    public func importHistory(from folder: URL, filter: CaptureFilter) async throws -> Int {
        let source = folder.appending(path: "Storage.sqlite")
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw ImportError.noHistoryFound
        }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "spindle-maccy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for suffix in ["", "-wal", "-shm"] {
            let file = folder.appending(path: "Storage.sqlite\(suffix)")
            if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: file, to: scratch.appending(path: "Storage.sqlite\(suffix)"))
            }
        }

        let database = try DatabaseQueue(path: scratch.appending(path: "Storage.sqlite").path(percentEncoded: false))
        let items = try await database.read { db in try Self.readItems(db) }

        var imported = 0
        for item in items where filter.skipReason(for: item.copy) == nil {
            guard case .inserted(let id) = try await ingestor.ingest(item.copy) else { continue }
            imported += 1
            if item.isPinned { try await history.setPinned(id, true) }
        }
        return imported
    }

    private struct MaccyItem: Sendable {
        var copy: CapturedCopy
        var isPinned: Bool
    }

    private static func readItems(_ db: Database) throws -> [MaccyItem] {
        guard try db.tableExists("ZHISTORYITEM"), try db.tableExists("ZHISTORYITEMCONTENT") else {
            throw ImportError.noHistoryFound
        }
        var contents: [Int64: [Representation]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT ZITEM, ZTYPE, ZVALUE FROM ZHISTORYITEMCONTENT ORDER BY Z_PK") {
            guard let item: Int64 = row["ZITEM"], let type: String = row["ZTYPE"], let value: Data = row["ZVALUE"]
            else { continue }
            contents[item, default: []].append(Representation(flavor: PasteboardFlavor(type), data: value))
        }

        return try Row.fetchAll(
            db, sql: "SELECT Z_PK, ZAPPLICATION, ZLASTCOPIEDAT, ZPIN FROM ZHISTORYITEM ORDER BY ZLASTCOPIEDAT"
        ).compactMap { row -> MaccyItem? in
            let all = contents[row["Z_PK"]] ?? []
            let declared = all.map(\.flavor)
            // Core Data stores dates as seconds since 2001.
            let copiedAt = Date(timeIntervalSinceReferenceDate: row["ZLASTCOPIEDAT"] ?? 0)
            let kept = all.filter { $0.flavor.isCaptured }
            guard !kept.isEmpty else { return nil }
            let copy = CapturedCopy(
                items: pasteboardItems(kept), declaredTypes: declared, sourceBundleID: row["ZAPPLICATION"],
                changeCount: 0, capturedAt: copiedAt)
            return MaccyItem(copy: copy, isPinned: row["ZPIN"] as String? != nil)
        }
    }

    /// Maccy flattens a multi-file copy into several file URL rows; they become one pasteboard item
    /// each again, so pasting brings back every file.
    private static func pasteboardItems(_ representations: [Representation]) -> [CapturedItem] {
        let files = representations.filter { $0.flavor == .fileURL }
        guard files.count > 1 else { return [CapturedItem(representations: representations)] }
        return files.map { CapturedItem(representations: [$0]) }
    }
}
