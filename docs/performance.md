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

- **Signposts.** Capture, ingest, search, panel open, first frame and thumbnail generation are wrapped in `OSSignposter` intervals. Read them with `log show --signpost --last 5m --predicate 'subsystem == "com.afshinghezeli.Spindle"'`, or in Instruments' Points of Interest track.
- **Benchmarks.** `make bench` runs the `Benchmarks/` package (package-benchmark) against generated histories of 10,000 and 100,000 items (roadmap task M2.4).
- **Memory.** `footprint -p Spindle`, with `--sample 1 --sample-duration 60` for drift.
- **Idle CPU and wake-ups.** `top -pid $(pgrep -x Spindle) -stats pid,cpu,idlew -l 30`.
- **Hangs.** `sample Spindle 5`.

Unit tests contain a few coarse timing checks with generous headroom. They catch accidental quadratic behavior, not small regressions; the benchmarks do that.

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
