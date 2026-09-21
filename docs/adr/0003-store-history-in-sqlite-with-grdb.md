---
status: accepted
date: 2026-09-22
---

# Store history in SQLite with GRDB

## Context and problem statement

Spindle promises unlimited history that stays instant at 100,000 items without memory growing along with it. The biggest open-source competitor loads its whole history into memory. After moving to SwiftData, its store leaked orphaned payloads: 1.89 GB in 11 days, with reports of 81 GB and 211 GB (Maccy #1496, #1535). We need substring search over all history, precise control over the schema and pruning, and it has to build with the Command Line Tools.

## Considered options

- SwiftData
- Core Data
- SQLite through its C API
- SQLite through GRDB.swift 7

## Decision outcome

Chosen option: SQLite through GRDB 7.11.1, pinned exactly. SwiftData's `@Model` macro doesn't compile without Xcode. Core Data has no full-text search. The raw C API would mean rewriting GRDB's connection pool, migrations and cancellation for no speed gain.

Storage rules that follow from this:

- `item` rows are small and never hold payloads. Each pasteboard type becomes a `representation` row, stored inline up to 64 KB. Larger payloads go to a content-addressed file store named by SHA-256: write the file before committing the row, delete the row before removing the file.
- `seq` is a recency key that is bumped whenever an item is copied or pasted again. It is also the rowid of an FTS5 `trigram` index, so newest-first search needs no sort.
- Text is folded (case, diacritics, width) in Swift. The system SQLite on macOS 15 (3.43) doesn't support the trigram tokenizer's `remove_diacritics` option.
- Migrations are forward-only. A migration that has shipped is never edited.
- Pruning deletes at most 500 rows per transaction, off the main thread.

### Consequences

- Good, because a prototype measured 0.4–2.4 ms per search at 100,000 items, including ranking, and about 13 MB of memory for the whole data layer.
- Good, because the database is an ordinary SQLite file that can be inspected, backed up and exported.
- Bad, because we write SQL and migrations by hand and own their correctness.
- Bad, because encryption at rest isn't included. SQLCipher needs a fork of GRDB until SwiftPM package traits land. Until then Spindle relies on FileVault and the sandbox container, never stores concealed items, and "Clear history" uses FTS5 secure-delete plus VACUUM.

## More information

Revisit encryption when GRDB ships SQLCipher support through package traits (tracked on the roadmap).
