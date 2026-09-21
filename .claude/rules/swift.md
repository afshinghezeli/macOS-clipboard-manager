---
paths:
  - "**/*.swift"
  - "Package.swift"
---

# Swift conventions

## Language and toolchain

- Swift 6 language mode, `swift-tools-version: 6.1`. Code must build with the Command Line Tools alone (no Xcode).
- Only enable upcoming features that Swift 6.1 knows. An unknown feature name is silently ignored, so local and CI builds would drift apart.
- Never use macros that ship only with Xcode: `#Preview`, SwiftData `@Model`, SwiftUI `@Entry`, Foundation `#Predicate`. Use `PreviewProvider`, GRDB records, hand-written `EnvironmentKey`s and plain closures instead. `@Observable` and swift-testing macros are fine.
- Never use SwiftPM's generated `Bundle.module` in code that ships. Use the resource-bundle accessor in the target's `Resources.swift`; `Bundle.module` crashes inside a signed `.app` on other people's Macs.
- APIs newer than macOS 15.0 go behind `if #available`. APIs from the macOS 26 SDK (Liquid Glass) also need `#if compiler(>=6.2)`, because the local SDK is 15.5.

## Concurrency

- UI types, view models and AppKit glue are `@MainActor`.
- `NSPasteboard.general` is touched only inside the `@MainActor` `PasteboardGateway` (SpindleSystem), never elsewhere. See ADR 0004.
- Database writes go through the `Ingestor` or `HistoryStore` APIs; views never open transactions.
- Values that cross actors are `Sendable` structs or enums. No `NSImage`, `NSAttributedString` or `NSPasteboardItem` across isolation boundaries.
- No `@unchecked Sendable` or `nonisolated(unsafe)` without a comment explaining why it is safe.
- No `DispatchQueue.main.async` in new code; use `@MainActor` and `Task`.
- Long-running work checks `Task.isCancelled`. Search cancels the previous query on each keystroke.

## Style

- `swift format` with the repo's `.swift-format` owns layout: 4 spaces, 120 columns. Don't hand-format around it.
- Access control: start `private`/`internal`; make something `public` only when another module needs it.
- Prefer value types. Classes are `final` unless designed for subclassing.
- No force unwraps or `try!` outside tests, except for provably constant input (e.g. a literal regex), with a comment.
- Errors: throw typed domain errors (`enum ...Error: Error`). Log with `Logger` (subsystem = bundle id, category = type name). Never log clipboard contents, not even at debug level.
- Name things after the domain: `ClipItem`, `Representation`, `PasteTarget`, not `DataModel` or `Manager`.
- One primary type per file, file named after it. Extensions go in `Type+Purpose.swift`.

## Comments

- Comment the why, not the what: constraints, platform bugs, measured numbers, links to issues or ADRs.
- Doc comments (`///`) on public API and on anything with a non-obvious contract (threading, units, ownership).
- No commented-out code, no TODO without a roadmap task ID (`// TODO(M3.4): ...`).
