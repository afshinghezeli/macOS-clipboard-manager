---
status: accepted
date: 2026-09-22
---

# Access the pasteboard only from one main-actor type

## Context and problem statement

`NSPasteboard` isn't thread-safe, yet it isn't annotated `@MainActor`, so Swift 6 won't stop us from using it anywhere. Other clipboard managers have crashed because of this. Clop saw type-cache corruption when two of its threads touched the pasteboard. ClipCascade (#173, September 2026) crashed in `objc_retain` from background polling while AppKit mutated owner state on the main thread. On the other hand, pasteboard reads are synchronous calls into the pasteboard server, and a slow source app can stall the calling thread.

## Considered options

- Read from whichever thread needs it
- One actor on a dedicated serial queue (Clop's design)
- One `@MainActor` type

## Decision outcome

Chosen option: one `@MainActor` type, `PasteboardGateway`, which is the only code that reads or writes `NSPasteboard.general`. Apple says the class is unsafe off the main thread. AppKit changes pasteboard state on the main thread, so a dedicated background queue would still race it. A crash loses the user's work, while a stall only delays it.

Measured main-thread costs on an M4:

| Operation | Cost |
|---|---|
| `changeCount` | 0.04–0.7 ms |
| `types` | 0.3–1.7 ms |
| Reading 20 MB | 4.7 ms |
| Reading 80 MB | 86 ms |

Mitigations:

- Read only allow-listed types. Skip file promises and other lazily produced data.
- Cap each type at 50 MB.
- Prefer PNG over TIFF.
- Make capturing Universal Clipboard items a setting.
- Hand the bytes to the `Ingestor` actor at once, which does hashing, thumbnails and database writes off the main thread.

### Consequences

- Good, because there is exactly one place to audit for privacy rules, marker handling and access prompts.
- Good, because there are no data races with AppKit's own pasteboard use (the search field's ⌘V, Services, drag and drop).
- Bad, because a slow source app can block the main thread during a read. Each capture is wrapped in a signpost so stalls show up in logs.

## More information

Revisit if signposts show captures over 100 ms in normal use, or if Apple documents thread-safety guarantees for NSPasteboard.
