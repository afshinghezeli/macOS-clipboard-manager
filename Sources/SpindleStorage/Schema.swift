import GRDB

/// Schema migrations. A migration that has shipped in a release is never edited; changes go into a
/// new migration (ADR 0003).
enum Schema {
    static func v1(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE source_app (
                    id        INTEGER PRIMARY KEY,
                    bundle_id TEXT NOT NULL UNIQUE,
                    name      TEXT NOT NULL
                ) STRICT;

                -- One small row per history item. Payloads live in `representation`, so paging
                -- through the list touches few database pages.
                CREATE TABLE item (
                    id            INTEGER PRIMARY KEY,
                    -- Recency key: reassigned when the item is copied or pasted again, and the
                    -- rowid of item_fts, so newest-first search needs no sort.
                    seq           INTEGER NOT NULL UNIQUE,
                    content_hash  BLOB    NOT NULL UNIQUE,
                    kind          INTEGER NOT NULL,
                    preview       TEXT    NOT NULL,
                    search_text   TEXT    NOT NULL,
                    title         TEXT,
                    byte_size     INTEGER NOT NULL,
                    source_app_id INTEGER REFERENCES source_app(id) ON DELETE SET NULL,
                    created_at    INTEGER NOT NULL,
                    last_used_at  INTEGER NOT NULL,
                    use_count     INTEGER NOT NULL DEFAULT 1,
                    frecency_key  REAL    NOT NULL DEFAULT 0,
                    pinned_rank   INTEGER,
                    meta          TEXT
                ) STRICT;
                CREATE INDEX item_pinned   ON item(pinned_rank) WHERE pinned_rank IS NOT NULL;
                CREATE INDEX item_frecency ON item(frecency_key DESC);
                CREATE INDEX item_created  ON item(created_at);
                CREATE INDEX item_kind     ON item(kind, seq);
                CREATE INDEX item_source   ON item(source_app_id, seq);

                -- One row per pasteboard flavor of an item, in the order the source app offered
                -- them. Payloads up to 64 KB are inline; larger ones are files in the blob store.
                CREATE TABLE representation (
                    id          INTEGER PRIMARY KEY,
                    item_id     INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
                    item_index  INTEGER NOT NULL,
                    ordinal     INTEGER NOT NULL,
                    uti         TEXT    NOT NULL,
                    inline_data BLOB,
                    blob_hash   BLOB,
                    byte_size   INTEGER NOT NULL,
                    UNIQUE (item_id, item_index, ordinal),
                    CHECK ((inline_data IS NULL) <> (blob_hash IS NULL))
                ) STRICT;
                CREATE INDEX representation_blob ON representation(blob_hash) WHERE blob_hash IS NOT NULL;

                CREATE TABLE thumbnail (
                    item_id INTEGER PRIMARY KEY REFERENCES item(id) ON DELETE CASCADE,
                    width   INTEGER NOT NULL,
                    height  INTEGER NOT NULL,
                    data    BLOB    NOT NULL
                ) STRICT;

                -- Trigram index over the folded text, keyed by seq. External content: the text is
                -- stored once, in `item`, and the index can always be rebuilt from it.
                CREATE VIRTUAL TABLE item_fts USING fts5(
                    search_text, content='item', content_rowid='seq', tokenize='trigram', detail='full'
                );
                CREATE TRIGGER item_fts_insert AFTER INSERT ON item BEGIN
                    INSERT INTO item_fts(rowid, search_text) VALUES (new.seq, new.search_text);
                END;
                CREATE TRIGGER item_fts_delete AFTER DELETE ON item BEGIN
                    INSERT INTO item_fts(item_fts, rowid, search_text) VALUES ('delete', old.seq, old.search_text);
                END;
                CREATE TRIGGER item_fts_update AFTER UPDATE OF seq, search_text ON item BEGIN
                    INSERT INTO item_fts(item_fts, rowid, search_text) VALUES ('delete', old.seq, old.search_text);
                    INSERT INTO item_fts(rowid, search_text) VALUES (new.seq, new.search_text);
                END;
                """)
    }
}
