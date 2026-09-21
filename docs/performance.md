# Performance

Spindle's first priority is feeling instant no matter how much history you keep. These budgets are the contract. A change that breaks one doesn't land until it is fixed or the budget is deliberately revised here.

## Budgets

Measured on a release build on an M1-class Mac.

| Metric | Budget |
|---|---|
| Keystroke → results in the model | p99 ≤ 8 ms at 10,000 items, ≤ 25 ms at 100,000 |
| Keystroke → frame on screen | p95 ≤ 16 ms at 10,000 items, p99 ≤ 50 ms at 100,000 |
| Arrow key → selection moved | ≤ 4 ms |
| Shortcut → first panel frame | ≤ 50 ms when warm, ≤ 100 ms for the first open after launch |
| Cold launch → menu bar icon ready | ≤ 200 ms; opening the database ≤ 10 ms |
| Capture work on the main thread | ≤ 2 ms per text copy, ≤ 10 ms per image up to 20 MB |
| Ingest per text copy (background) | p99 ≤ 2 ms |
| CPU while idle, panel hidden | ≤ 0.1 % of one core, averaged over 10 minutes |
| Memory (`phys_footprint`) | ≤ 40 MB idle, ≤ 80 MB with the panel open, ≤ 5 MB growth over 1,000 copies |

History size must not change the idle memory figure. Nothing in Spindle loads the whole history.

## How it is measured

All of this works with the Command Line Tools; Instruments is optional.

- **Signposts.** Capture, ingest, search, panel open, first frame and thumbnail generation are wrapped in `OSSignposter` intervals. Read them with `/usr/bin/log show --signpost --last 5m --predicate 'subsystem == "com.afshinghezeli.Spindle"'` (use the full path: in zsh, `log` is a shell builtin), or in Instruments' Points of Interest track.
- **Benchmarks.** `make bench` builds histories of 10,000 and 100,000 items from a fixed seed and times search, paging and ingest in a release build (`Sources/SpindleBench`).
- **Memory.** `footprint -p Spindle`, with `--sample 1 --sample-duration 60` for drift.
- **Idle CPU and wake-ups.** `top -pid $(pgrep -x Spindle) -stats pid,cpu,idlew -l 30`.
- **Hangs.** `sample Spindle 5`.

Unit tests contain a few coarse timing checks with generous headroom. They catch accidental quadratic behavior, not small regressions; the benchmarks do that.

## Measured on Spindle

Numbers from the app itself, replacing prototype figures as each part lands. Each row says how it was measured.

| Date | Build | Mac | Metric | Result | Budget |
|---|---|---|---|---|---|
| 2026-09-22 | release, arm64, M1.11 | M4, macOS 15.3 | CPU while idle, panel hidden (`top`, 30 × 1 s) | 0.01 % | ≤ 0.1 % |
| 2026-09-22 | release, arm64, M1.11 | M4, macOS 15.3 | Memory while idle, empty history (`footprint`) | 11 MB | ≤ 40 MB |

| 2026-09-22 | release, arm64, M2.4 | M4, macOS 15.3 | Search, 10 query types, p99 (`make bench`) | 3.4 ms at 10,000 items, 3.7 ms at 100,000 | ≤ 8 ms / ≤ 25 ms |
| 2026-09-22 | release, arm64, M2.4 | M4, macOS 15.3 | Slowest query ("a", scans recent items), p99 | 3.9 ms / 4.3 ms | ≤ 8 ms / ≤ 25 ms |
| 2026-09-22 | release, arm64, M2.4 | M4, macOS 15.3 | A page of 100 items, top or mid-history, p99 | ≤ 1.1 ms | |
| 2026-09-22 | release, arm64, M2.4 | M4, macOS 15.3 | Ingest one text copy, p50 / p99 | 0.12 ms / 4.5 ms at 100,000 | p99 ≤ 2 ms: **missed** |

The ingest p99 misses its budget: the median is 0.12 ms, but about one copy in a hundred takes several milliseconds. It happens off the main thread, so nobody waits for it; the likely cause is SQLite merging search-index segments or checkpointing the WAL. Roadmap task M2.6 tracks it. The memory figure will be repeated with 100,000 items in the running app.

## Prototype measurements

These come from a throwaway prototype built in September 2026 while choosing the design (M4, macOS 15.3, release build). They show the design can meet the budgets; they are not measurements of Spindle itself. Real numbers will replace this table as the pieces land.

| Operation | 10,000 items | 100,000 items |
|---|---|---|
| Search, 3+ characters, ranked top 100 | 0.35–0.85 ms | 0.4–2.4 ms |
| Search, 1–2 characters, worst case | 7.5 ms | 19.5 ms |
| Ingest one text copy | 0.26 ms | 0.53 ms |
| Open database and read first page | | 2.4–7 ms |
| Arrow-key selection in NSTableView | 1.65 ms | 1.5 ms |
| Idle polling at 500 ms | 0.06 % CPU | |
