# Roadmap

Spindle is clipboard history for the Mac. It remembers everything you copy, finds any of it in a keystroke, and pastes it back into the app you were using. It stays small and fast with a hundred thousand items. It is free, open source, and never touches the network.

## Priorities

When two of these conflict, the higher one wins.

1. **Instant at any size.** 100,000 items should feel the same as 100. See [performance.md](performance.md).
2. **Trustworthy with sensitive data.** Local only, no telemetry, no network access, password managers respected.
3. **Keyboard-first, Raycast-grade interaction.** List and preview side by side, ↵ pastes where you were, every action one shortcut away.
4. **One job.** Clipboard history and paste workflows, done deeply.
5. **Native and durable.** AppKit where it matters, and survive every macOS release.

## Not planned

These requests will come up. The answer is no, or not before 1.0.

- **Syncing history between devices.** It carries too much privacy risk and support load. Pinned items might sync one day; history won't.
- **AI features.** No rewriting, summarizing or cloud search. On-device semantic search may be looked at after 1.0.
- **Snippet expansion.** That needs keystroke monitoring. Pins and pinboards cover the need.
- **Plugins, scripting runtimes or a launcher.** Shortcuts, a URL scheme and a small CLI are the extension points.
- **Windows, Linux or iOS versions.**
- **Telemetry or crash-reporting SDKs.**

## How to read this file

Tasks have IDs (`M1.4`) so commits, ADRs and TODOs can refer to them. A task is done when its code is merged with tests and `make check` passes. Pick tasks in order within a milestone unless a note says otherwise. Tasks are sized for one sitting; if one turns out bigger, it gets split here first.

---

## M0: Foundations

Repository, tooling and build, before any feature code.

- [x] M0.1 Repository hygiene: editorconfig, gitignore, GPL-3.0 license, Conventional Commits hook.
- [x] M0.2 Claude Code rules, skills and shared settings.
- [x] M0.3 Initial architecture decisions (ADRs 0001–0006).
- [x] M0.4 Architecture overview, performance budgets and this roadmap.
- [x] M0.5 `CLAUDE.md`: project brief, working agreement, commit and versioning rules, toolchain constraints.
- [x] M0.6 Contributor docs: CONTRIBUTING, SECURITY, `docs/development.md`, `docs/releasing.md`, a README that is honest about the project's state.
- [x] M0.7 Swift package: the `Spindle` executable and `SpindleUI` with its resource-bundle accessor, `.swift-format`, and `make build`, `test`, `lint`, `format` and `check`. The other library targets are added by the first task that puts code in them (M1.1, M1.4, M1.8).
- [x] M0.8 App bundle: `Scripts/bundle.sh`, the Info.plist template, entitlements, a stable dev signing identity (`make setup-signing`), and `make app`, `run` and `verify-bundle`. Done when the app launches as a menu bar agent with a status item and survives `codesign --verify --strict`.
- [ ] M0.9 Sandbox spike for [ADR 0002](adr/0002-ship-a-sandboxed-developer-id-app.md): a sandboxed dev build (1) posts ⌘V into TextEdit and (2) updates itself with Sparkle from a local appcast. Accept or supersede the ADR based on the result.
- [ ] M0.10 CI: build, test and lint on `macos-15` with Xcode 16.4 (same Swift as local), a non-blocking job on the newest Xcode, PR title check, Dependabot, issue forms and PR template. Written and checked locally; tick once the first GitHub run passes.
- [x] M0.11 Release plumbing without signing: `version.txt`, release-please config and workflow, build number from commit count.
- [ ] M0.12 Code of conduct (Contributor Covenant 3.0). Needs a reporting contact address from the owner; a placeholder won't do.

## M1: Capture and storage

Spindle records the clipboard reliably and safely, with no UI beyond the menu bar icon.

- [x] M1.1 Core model: `ItemKind`, `CapturedCopy` / `CapturedItem` values, the allow-listed pasteboard types and the privacy markers as data.
- [x] M1.2 Text folding and preview sanitizing: case, diacritics and width folding; strip U+FFFC and control characters; 300-character previews. Tests cover CJK, emoji and combining marks.
- [x] M1.3 Content classification from the plain-text flavor: URL, email, color, file path. Cheap, capped at 64 KB, tested.
- [x] M1.4 `AppDatabase` with migration v1 (schema in [ADR 0003](adr/0003-store-history-in-sqlite-with-grdb.md)), pragmas, and a DEBUG-only erase-on-schema-change.
- [x] M1.5 `BlobStore`: content-addressed files over 64 KB, atomic writes, crash-safe ordering, orphan sweep.
- [x] M1.6 `Ingestor`, in three steps:
  - [x] M1.6a Frecency key: a decayed use count stored as one indexable number (half-life 72 hours).
  - [x] M1.6b Thumbnails: 256 px JPEG via ImageIO without decoding the full image, and TIFF-only copies transcoded to PNG.
  - [x] M1.6c The ingestor: dedup key (same text from another app bumps the existing item), insert or bump in one write transaction, representations inline or in the blob store, source app, and a change stream for the panel.
- [x] M1.7 `CaptureFilter`: markers, default ignored apps, the bundle-id prefix heuristic, pause and ignore-next-copy state.
- [ ] M1.8 `PasteboardGateway`: allow-listed reads per item, size caps, PNG over TIFF, stale-read detection, own-write suppression, `accessBehavior` branches. Tested on private pasteboards.
- [ ] M1.9 `ClipboardMonitor`: 500 ms common-mode timer with tolerance, idle backoff, sleep and wake handling, signposts.
- [ ] M1.10 Wire capture into the app. The status menu shows the item count and a Pause toggle. Manual test: text, rich text, image, multiple files, 1Password desktop and KeePassXC copies.
- [ ] M1.11 Retention: limits by count, age and total size, per-kind overrides, pinned items exempt, 500 rows per transaction, blob sweep, scheduled in the background.

## M2: Search

- [ ] M2.1 `SearchEngine`: trigram path, short-query scan, pinned and frecent pools, ranking blend with the weights in one tested struct.
- [ ] M2.2 Frecency key and bumping on copy and paste.
- [ ] M2.3 Fuzzy fallback over a small in-memory pool when exact matches are scarce.
- [ ] M2.4 `Benchmarks/` package with deterministic 10k and 100k fixtures, `make bench`, and measured numbers in performance.md.

## M3: Panel and paste

The core loop works end to end: shortcut, type, ↵, pasted.

- [ ] M3.1 Panel window: non-activating `NSPanel`, pre-built for instant show, screen under the mouse, dismiss on click-away and Esc, Edit menu for the search field.
- [ ] M3.2 Global shortcut with a Carbon hotkey wrapper. Choose the default shortcut in an ADR after checking conflicts in Finder, browsers and common editors.
- [ ] M3.3 History table: `NSTableView` representable, keyset paging, row cache, thumbnail cache, change-event inserts.
- [ ] M3.4 Search field and keyboard routing: ↑/↓, ⌃N/⌃P, ⌘1–9, Esc clears then closes, pressing the shortcut again moves down.
- [ ] M3.5 Preview pane for text, rich text, images, files, colors and links, with metadata (source app, copied at, times used, size).
- [ ] M3.6 `PasteInjector`: PostEvent check, layout-aware V key, modifier release wait, settle delay. ↵ pastes, ⌘↵ copies, ⇧↵ pastes plain text. The footer says "Paste to <App>".
- [ ] M3.7 Actions menu (⌘K) listing every action with its shortcut.
- [ ] M3.8 Pins: pin and unpin (⌘.), a pinned section, reordering.
- [ ] M3.9 Type filter (⌘P): all, text, images, files, links, colors.
- [ ] M3.10 Status item menu: open, pause, ignore next copy, settings, quit. Reopening the app from Finder opens settings, because macOS 26 can hide menu bar icons.
- [ ] M3.11 Liquid Glass panel background on macOS 26+, behind availability and compiler checks. Needs the macOS 26 SDK, so it is built in CI until the local toolchain is upgraded.

## M4: Settings, onboarding and privacy

- [ ] M4.1 Typed settings store over `UserDefaults`.
- [ ] M4.2 Settings window: General, History, Privacy, Advanced.
- [ ] M4.3 Shortcut recorder.
- [ ] M4.4 Launch at login with `SMAppService`, including the "requires approval" state.
- [ ] M4.5 Onboarding: what Spindle keeps, the paste permission, clipboard access on macOS 15.4+, choosing the shortcut.
- [ ] M4.6 Pasteboard access handling: degraded mode when macOS asks or denies, a banner, and deep links to System Settings.
- [ ] M4.7 Pause for a period and ignore the next copy, from the menu and a shortcut.
- [ ] M4.8 Clear history: FTS secure-delete, VACUUM, blob removal, with confirmation.
- [ ] M4.9 Import from Maccy through an open panel.

## M5: First release (0.1.0)

- [ ] M5.1 App icon, drawn by hand. Needs the owner.
- [ ] M5.2 Sparkle: updater controller, "check for updates", feed URL, beta channel setting.
- [ ] M5.3 Developer ID signing and notarization scripts. Needs the owner's Apple Developer account.
- [ ] M5.4 Release workflow: universal build, sign, notarize, DMG and ZIP, appcast, publish the draft release.
- [ ] M5.5 Homebrew tap.
- [ ] M5.6 README with real screenshots, shortcuts table, privacy section, permissions FAQ and a short motivation.
- [ ] M5.7 Manual QA on macOS 15, 26 and 27: keyboard layouts, multiple displays, full-screen apps, common target apps.
- [ ] M5.8 Ship 0.1.0, then 0.1.1 to prove the update path end to end.

## After 0.1

Rough order; each becomes a milestone with tasks when it is next.

- **0.2** Text in images: on-device OCR with Vision, searchable, and "copy text from image".
- **0.3** Multi-select and paste stack: paste several items joined or one after another; a collect mode.
- **0.4** Paste as (rich, plain, HTML, RTF), Quick Look, drag out of the panel, save image, open link, reveal file, filter by source app and date.
- **0.5** Secret-aware handling: detect API keys, tokens and card numbers, mask their previews and expire them. Optional hide-from-screen-sharing. Revisit encryption at rest.
- **0.6** Automation: Shortcuts actions, a URL scheme, a small CLI, and about ten built-in text transforms.
- **1.0** Stable storage format with export and import, tested at one million items, accessibility and localization pass, pinboards (named groups of pins), and a written routine for macOS betas.
