import Foundation
import GRDB
import Synchronization

/// The history database: connection setup and schema migrations.
///
/// Stores such as the ingestor and the search engine share one `AppDatabase`. On disk it is a WAL
/// database pool (one writer, two readers); tests use an in-memory queue.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter
    private let checkpoints = CheckpointScheduler()

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Runs `updates` in a write transaction. All writes go through here or
    /// `writeWithoutTransaction`, so the WAL is checkpointed once they stop.
    func write<T: Sendable>(_ updates: @escaping @Sendable (Database) throws -> T) async throws -> T {
        defer { checkpoints.schedule(writer) }
        return try await writer.write(updates)
    }

    func writeWithoutTransaction<T: Sendable>(_ updates: @escaping @Sendable (Database) throws -> T) async throws -> T {
        defer { checkpoints.schedule(writer) }
        return try await writer.writeWithoutTransaction(updates)
    }

    /// Opens (or creates) the database at `location`.
    public static func open(at location: StorageLocation) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        var configuration = Configuration()
        // Every reader connection keeps its own page cache, so the count bounds memory.
        configuration.maximumReaderCount = 2
        configuration.prepareDatabase { db in
            // auto_vacuum only takes effect on an empty file, before the first table exists.
            // Incremental mode lets pruning give space back without a full VACUUM.
            if try Int.fetchOne(db, sql: "PRAGMA page_count") == 0 {
                try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
            }
            try db.execute(
                sql: """
                    PRAGMA secure_delete = FAST;
                    PRAGMA synchronous = NORMAL;
                    PRAGMA cache_size = -4096;
                    PRAGMA temp_store = MEMORY;
                    PRAGMA journal_size_limit = 8388608;
                    """)
            // SQLite checkpoints inside the commit that crosses the threshold, which made about one
            // copy in 50 take 4 ms or more at 100,000 items (M2.6). CheckpointScheduler does it
            // after writes stop instead; this higher limit only bounds the WAL during long bursts
            // such as an import (10,000 pages is 40 MB).
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 10000")
        }
        let pool = try DatabasePool(
            path: location.databaseURL.path(percentEncoded: false), configuration: configuration)
        return try AppDatabase(pool)
    }

    /// A private, empty database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // While a migration is still being written, editing it rebuilds development databases.
        // Release builds never do this: shipped migrations are never edited, only added.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1", migrate: Schema.v1)
        migrator.registerMigration("v2", migrate: Schema.v2)
        return migrator
    }
}

/// Checkpoints the WAL a second after the last write, as its own step on the writer's queue, so no
/// single write pays for it. Nothing runs while nothing is written.
final class CheckpointScheduler: Sendable {
    private static let delay: Duration = .seconds(1)
    private let pending = Mutex<Task<Void, Never>?>(nil)

    func schedule(_ writer: any DatabaseWriter) {
        pending.withLock { task in
            task?.cancel()
            task = Task.detached(priority: .utility) {
                try? await Task.sleep(for: Self.delay)
                guard !Task.isCancelled else { return }
                // PASSIVE never waits for readers; what it can't copy yet waits for the next one.
                _ = try? await writer.writeWithoutTransaction { db in
                    try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
                }
            }
        }
    }
}
