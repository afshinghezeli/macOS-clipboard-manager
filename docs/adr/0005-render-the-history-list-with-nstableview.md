---
status: accepted
date: 2026-09-22
---

# Render the history list with NSTableView

## Context and problem statement

The panel's list must respond to every arrow key immediately, including when the history holds 100,000 items and the user holds ↓ or jumps to the end. The rest of the UI is SwiftUI, so SwiftUI's own list views were the obvious first choice. We measured all three candidates in an offscreen window: release build, M4, macOS 15.3, fixed 36 pt rows.

| 100,000 rows | NSTableView | SwiftUI `List(selection:)` | SwiftUI `LazyVStack` |
|---|---|---|---|
| Initial show | 45 ms | 150 ms | 49 ms |
| Arrow-key selection change | 1.5 ms | 145 ms | 2.2 ms |
| Jump to last row | 2.4 ms | 140 ms | 839 ms |
| Resident memory afterwards | 78 MB | 207 MB | 469 MB |

## Considered options

- SwiftUI `List` with selection
- SwiftUI `LazyVStack` in a `ScrollView`
- `NSTableView` wrapped in `NSViewRepresentable`

## Decision outcome

Chosen option: `NSTableView` behind `NSViewRepresentable`. On macOS 15, changing the selection in a `List` costs time proportional to the number of rows. `LazyVStack` creates every row it scrolls past, so jumping far down costs time and memory in proportion to the distance. `NSTableView` does both in constant time.

The table uses fixed row heights and cell reuse, with `NSTableCellView` cells rather than SwiftUI hosted in cells. Its model is an array of `seq` values; rows are fetched in pages and cached. ↑/↓ are forwarded from the search field so focus never leaves it. Everything else (search field, preview, footer, settings, onboarding) is SwiftUI.

### Consequences

- Good, because keyboard navigation cost stays constant as history grows.
- Bad, because the cells, their accessibility and their appearance are AppKit code that has to match the SwiftUI around it by hand.

## More information

WWDC25 claimed large speed-ups for `List` on macOS 26. Revisit once the deployment target is 26 or later and we can measure it against the same benchmark.
