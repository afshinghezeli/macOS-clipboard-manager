import GRDB

/// Reads the history for the UI. Writes go through the ``Ingestor``.
public struct HistoryStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func itemCount() async throws -> Int {
        try await database.writer.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM item") ?? 0 }
    }
}
