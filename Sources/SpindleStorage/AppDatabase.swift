import Foundation
import GRDB

/// The history database: connection setup and schema migrations.
///
/// Stores such as the ingestor and the search engine share one `AppDatabase`. On disk it is a WAL
/// database pool (one writer, two readers); tests use an in-memory queue.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
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
                    PRAGMA synchronous = NORMAL;
                    PRAGMA cache_size = -4096;
                    PRAGMA temp_store = MEMORY;
                    PRAGMA journal_size_limit = 8388608;
                    """)
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
        return migrator
    }
}
