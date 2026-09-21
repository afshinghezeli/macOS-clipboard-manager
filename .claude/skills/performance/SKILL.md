---
name: performance
description: Spindle's performance budgets and how to measure them with the Command Line Tools (signposts, benchmarks, footprint, idle CPU). Load when changing storage, search, ingest, the history list, the panel, or anything that runs on the main thread, and before claiming that something is fast.
---

# Performance

"Instant at any size" is Spindle's first priority. The budgets live in [docs/performance.md](../../../docs/performance.md); that file is the contract, and this skill is how to check it.

## Budgets (release build, M1-class Mac)

| Metric | Budget |
|---|---|
| Keystroke → results in the model | p99 ≤ 8 ms at 10k items, ≤ 25 ms at 100k |
| Keystroke → frame | p95 ≤ 16 ms at 10k, p99 ≤ 50 ms at 100k |
| Arrow-key selection change | ≤ 4 ms |
| Hotkey → first panel frame | ≤ 50 ms warm, ≤ 100 ms first open |
| Cold launch → status item | ≤ 200 ms, database open ≤ 10 ms |
| Capture on main per copy | ≤ 2 ms text, ≤ 10 ms image up to 20 MB |
| Ingest per clip (off main) | p99 ≤ 2 ms for text |
| Idle CPU (panel hidden) | ≤ 0.1 % averaged over 10 min |
| Memory (`phys_footprint`) | ≤ 40 MB idle, ≤ 80 MB with the panel open, ≤ 5 MB drift over 1,000 copies |

## Design rules that keep us inside the budgets

- Nothing ever loads the full history. The list pages by `seq`; search returns at most a few hundred candidates.
- `item` rows stay small; payloads live in `representation` or the blob store.
- FTS5 trigram rowid = `seq`, so `ORDER BY rowid DESC LIMIT n` needs no sort. Never join-and-sort all matches, and never combine `MATCH` with `rowid IN (subquery)`.
- Search is "latest wins": cancel the previous task on each keystroke; no fixed debounce.
- Pruning deletes at most 500 rows per transaction.
- Thumbnails are generated once at ingest (ImageIO, 256 px) and decoded off-main into an `NSCache`.
- The main thread does pasteboard reads and UI only. No database writes, hashing, image decoding or file I/O on it.
- When the panel is hidden, the only recurring work is the 500 ms `changeCount` poll.

## Measuring without Xcode

- Signposts: every hot path has an `OSSignposter` interval (`capture`, `ingest`, `search`, `panelOpen`, `firstFrame`, `thumbnail`). Read them with
  `log show --signpost --last 5m --predicate 'subsystem == "com.afshinghezeli.Spindle.dev"'`.
- Benchmarks: `make bench` runs the separate `Benchmarks/` package (package-benchmark 1.34.1) against deterministic 10k and 100k fixtures. Compare with `make bench-compare` before and after a change.
- Memory: `footprint -p Spindle` for one sample, `footprint -p Spindle --sample 1 --sample-duration 60` for drift, `leaks Spindle` for leaks.
- Idle CPU and wakeups: `top -pid $(pgrep -x Spindle) -stats pid,cpu,idlew -l 30`.
- Hangs: `sample Spindle 5`, or `spindump` for system-wide stalls.

## Checklist for a performance-sensitive change

1. Name the budget(s) it affects.
2. Measure before the change: benchmark or signpost numbers, with item count and build configuration.
3. Measure after, the same way.
4. Put both numbers in the commit body ("search p99 at 100k: 2.4 ms → 1.1 ms, `make bench`, M4").
5. If a budget is exceeded, the change doesn't land. Either fix it or bring the trade-off to the owner.

Never claim a speed-up that wasn't measured, and never report numbers from a debug build.
