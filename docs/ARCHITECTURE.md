# Architecture

This is a map of how Spindle is put together and why. The reasons behind the bigger choices are in the [decision records](adr/). Spindle is being built in the order of the [roadmap](roadmap.md), which shows what exists today; this document describes the design those tasks implement.

## Shape of the app

Spindle is a menu bar agent (`LSUIElement`) with no Dock icon. It does three things:

1. **Capture.** It notices every copy, filters out what it must never keep, and stores the rest.
2. **Find.** A global shortcut opens a floating panel where typing narrows the history instantly.
3. **Paste.** Choosing an item puts it back on the clipboard and pastes it into the app you were using.

## Modules

The Swift package is split so that most of the logic can be tested without AppKit or a running app.

```
Spindle (executable)     composition root: AppDelegate, main menu, Sparkle
   │
   ├── SpindleUI         menu bar icon, panel window, history table, preview, settings, onboarding
   │     ├── SpindleStorage
   │     └── SpindleSystem
   │
   ├── SpindleStorage    GRDB database, migrations, blob store, ingest, search, pruning
   │     └── SpindleCore
   │
   ├── SpindleSystem     pasteboard gateway and monitor, paste injection, hotkeys,
   │     │               permissions, launch at login
   │     └── SpindleCore
   │
   └── SpindleCore       Foundation only: item model, capture rules, text folding,
                         content classification, ranking, retention policy
```

Rules:

- `SpindleCore` imports Foundation only. No AppKit, no GRDB. It holds the decisions (what to keep, how to rank, what to prune) as pure functions over value types.
- `SpindleStorage` knows SQLite and the file system, but not NSPasteboard.
- `SpindleSystem` knows the OS, but not the database.
- Only the executable target wires them together. No module reaches "up".

## Capture path

```
any app copies
      │
      ▼
ClipboardMonitor (main actor, 500 ms timer)   changeCount changed?
      │ yes
      ▼
PasteboardGateway.read() (main actor)          markers → access behavior → allow-listed types, size caps
      │ CapturedCopy (Sendable value: types + bytes + source app)
      ▼
CaptureFilter (SpindleCore)                    ignored app? ignore-next-copy? paused?
      │
      ▼
Ingestor (actor, off main)                     SHA-256 → dedup or bump → fold text → preview
      │                                        → blobs > 64 KB to disk → thumbnail → one write
      ▼
ChangeEvent stream  ──────────────────────────▶ panel model, if the panel is open
```

- `PasteboardGateway` is the only type that touches `NSPasteboard.general` ([ADR 0004](adr/0004-access-the-pasteboard-only-from-the-main-actor.md)). It checks nspasteboard.org markers before reading any content, so concealed and transient items are never read, let alone stored.
- Copies made by Spindle itself are recognized by their change count and skipped.
- The main thread only reads bytes. Hashing, image work and database writes happen in the `Ingestor`, which runs in a detached task so that UI cancellation can never abort a write.

## Find and paste path

```
global shortcut (Carbon hotkey)
      │ remember the frontmost app as the paste target
      ▼
PanelController shows the pre-built panel on the screen with the mouse
      │
      ▼
SearchModel ──(each keystroke cancels the last query)──▶ SearchEngine (FTS5 trigram, re-rank)
      │ results: at most a few hundred rows
      ▼
HistoryTableView (NSTableView, fixed rows, paged)       PreviewView (SwiftUI)
      │ ↵
      ▼
PasteboardGateway.write(item) → hide panel → PasteInjector posts ⌘V to the target → bump item
```

- The panel is a non-activating `NSPanel`, so the target app stays active the whole time and the synthetic ⌘V lands where the user expects.
- ⌘↵ stops after writing to the clipboard. ⇧↵ writes only the plain-text representation.

## Storage

Data lives in the app's sandbox container:

```
~/Library/Containers/com.afshinghezeli.Spindle/Data/Library/Application Support/Spindle/
    history.sqlite         (+ -wal, -shm)
    blobs/ab/abcdef…       payloads over 64 KB, named by SHA-256
```

Tables ([ADR 0003](adr/0003-store-history-in-sqlite-with-grdb.md)):

| Table | Holds |
|---|---|
| `item` | One small row per clip: `seq` (recency key), content hash, kind, preview, folded search text, sizes, timestamps, use count, frecency key, pin rank, source app |
| `representation` | One row per flavor of each pasteboard item in a clip (a multi-file copy has several items), in original order; inline bytes up to 64 KB, else a blob hash |
| `thumbnail` | A 256 px JPEG for image items |
| `source_app` | Bundle id and name, normalized |
| `item_fts` | FTS5 trigram index over `search_text`, with `rowid = seq` |

Re-copying or pasting an item gives it a new `seq`, which moves it to the top without duplicating anything. Pinned items are never pruned.

## Search

Queries are folded (case, diacritics, width) exactly as the stored text was.

- **Three or more characters.** The trigram index is walked newest-first (`ORDER BY rowid DESC LIMIT 256`), which needs no sort because the rowid is the recency key.
- **Shorter queries.** A bounded scan of the newest 20,000 items is used instead.
- **Ranking.** Pinned and frequently used items join the candidate set. Everything is re-ranked in Swift by match quality, recency, frecency and pin state.
- **Fuzzy fallback.** When exact matches are scarce, fuzzy matching runs over a small in-memory pool.

Budgets and how they are measured: [performance.md](performance.md).

## Concurrency

| Where | What runs there |
|---|---|
| Main actor | Pasteboard reads and writes, the monitor timer, hotkeys, all UI, view models (`@Observable`) |
| `Ingestor` actor | Hashing, blob files, thumbnails, database writes during capture |
| GRDB `DatabasePool` | One writer and two readers. Search and paging read concurrently with ingest writes. |
| Background activity scheduler | Pruning, blob garbage collection, FTS optimize, vacuum |

Only `Sendable` values cross these boundaries. `NSImage`, `NSAttributedString` and `NSPasteboardItem` never leave the main actor.

## Privacy model

- Never read or stored:
  - items marked `org.nspasteboard.ConcealedType`, `TransientType` or `AutoGeneratedType`, and the legacy password-manager markers;
  - copies from ignored apps (Passwords, Keychain Access and the common password managers by default);
  - copies made while capture is paused.
- Universal Clipboard items are captured only if the user allows it.
- The app has **no network entitlement**. Update checks run in Sparkle's separate XPC service ([ADR 0002](adr/0002-ship-a-sandboxed-developer-id-app.md)).
- Logs never contain clipboard contents.
- On macOS 15.4 and later, Spindle respects the pasteboard access setting. If macOS says to ask or deny, it stops reading in the background instead of triggering a stream of system prompts.

## Decisions

| ADR | Decision | Status |
|---|---|---|
| [0001](adr/0001-build-with-swiftpm-and-a-bundle-script.md) | Build with SwiftPM and a bundle script, without an Xcode project; macOS 15 minimum | accepted |
| [0002](adr/0002-ship-a-sandboxed-developer-id-app.md) | Ship a sandboxed Developer ID app, updated with Sparkle | proposed |
| [0003](adr/0003-store-history-in-sqlite-with-grdb.md) | Store history in SQLite with GRDB | accepted |
| [0004](adr/0004-access-the-pasteboard-only-from-the-main-actor.md) | Access the pasteboard only from one main-actor type | accepted |
| [0005](adr/0005-render-the-history-list-with-nstableview.md) | Render the history list with NSTableView | accepted |
| [0006](adr/0006-version-with-semver-and-release-please.md) | Version with SemVer and release with release-please | accepted |
