# Spindle

Clipboard history for macOS: a native menu bar app that remembers everything you copy, finds it in a keystroke, and pastes it back where you were. Swift 6, AppKit + SwiftUI, SQLite (GRDB). Local-only, no network entitlement.

- Owner: Afshin Ghezeli. License: GPL-3.0-only.
- Bundle id `com.afshinghezeli.Spindle`; debug builds use `com.afshinghezeli.Spindle.dev`.
- GitHub: `afshinghezeli/clipboard-manager` (public).

## Priorities

When two conflict, the higher one wins:

1. **Instant at any size.** 100,000 items feel like 100. Budgets are in `docs/performance.md`, and a change that breaks one doesn't land.
2. **Trustworthy with sensitive data.** Local only, no telemetry, never store concealed or transient items, never log clipboard contents.
3. **Keyboard-first, Raycast-grade interaction.** ↵ pastes into the previous app, ⌘K lists every action.
4. **One job.** Clipboard history and paste workflows.
5. **Native and durable.** Survive every macOS release.

Non-goals (say no, or ask the owner): history sync, AI features, snippet expansion, plugins or scripting runtimes, launcher features, other platforms, telemetry, keystroke monitoring.

## Working agreement

- Work from `docs/roadmap.md`, one task at a time, and finish it before starting the next. Use the `next-task` skill.
- Move in small steps. Every commit builds, passes `make check`, and does one thing.
- Run the `verify` skill before every commit. Never commit a red build or weaken a check to make it pass.
- Commit with the `commit` skill. Don't batch unrelated changes.
- Record hard-to-reverse decisions with the `adr` skill. Don't quietly contradict an accepted ADR; supersede it with a new one.
- Load `macos-clipboard` before touching capture, paste, hotkey, permission or panel-window code, and `performance` before touching storage, search, ingest or the history list.
- Keep docs in step with the code: `docs/ARCHITECTURE.md`, `docs/roadmap.md`, the README shortcut table.
- Ask the owner first before any of these:
  - pushing, tagging, releasing or changing GitHub settings;
  - adding a dependency that no accepted ADR names, or any entitlement or permission;
  - touching a non-goal;
  - changing a default shortcut or the storage format in a way that isn't migrated.
- Say plainly what was verified and what wasn't. UI changes need eyes on the running app. Capture, paste and hotkeys need manual checks, because TCC grants can't be scripted.

## Commands

| Command | What it does |
|---|---|
| `make setup` | One-time: enable the git hooks |
| `make setup-signing` | One-time: create the stable local code-signing identity, so permission grants survive rebuilds |
| `make build` / `make test` | Debug build / swift-testing suite |
| `make lint` / `make format` | `swift format` check / rewrite |
| `make check` | lint + build with warnings as errors + tests (run before every commit) |
| `make app` / `make run` | Assemble and sign `dist/debug/Spindle.app` / assemble, then relaunch it with `open` |
| `make verify-bundle` | Launch the packaged app with the checkout hidden, to catch resource-path bugs |
| `make logs` | Stream the app's `os_log` output |
| `make bench` | Performance benchmarks (`Benchmarks/` package) |

`make bench` arrives with roadmap task M2.4.

## Layout

```
Sources/SpindleCore      Foundation only: models, capture rules, folding, ranking, retention
Sources/SpindleStorage   GRDB database, migrations, blob store, Ingestor, SearchEngine
Sources/SpindleSystem    PasteboardGateway, ClipboardMonitor, PasteInjector, hotkeys, permissions
Sources/SpindleUI        menu bar icon, panel, NSTableView history list, preview, settings, onboarding
Sources/Spindle          executable: AppDelegate, main menu, Sparkle
Tests/<Target>Tests      swift-testing suites
Scripts/                 bundle.sh, signing, notarization
Support/                 Info.plist template, entitlements, icon, main-bundle localizations
docs/                    ARCHITECTURE, roadmap, performance, development, releasing, adr/
```

Dependencies point downward only: Core ← Storage/System ← UI ← executable.

## Toolchain constraints

- The local machine has **only the Command Line Tools** (Swift 6.1.2, macOS 15.5 SDK). No Xcode, no XCTest, no `actool`, no `xcstringstool`. CI uses Xcode 16.4, which has the same Swift.
- `swift-tools-version: 6.1`, Swift 6 language mode, deployment target macOS 15.0.
- Xcode-only macros don't compile here: no `#Preview`, SwiftData `@Model`, SwiftUI `@Entry` or `#Predicate`. Use `PreviewProvider`, GRDB, hand-written `EnvironmentKey`s. `@Observable` and swift-testing work.
- Never use `Bundle.module` in shipped code; each target with resources has its own accessor.
- macOS 26 SDK APIs (Liquid Glass) need both `#if compiler(>=6.2)` and `if #available(macOS 26, *)`.
- Tests: swift-testing only, private pasteboards (`NSPasteboard.withUniqueName()`), in-memory databases, no TCC-dependent code.
- If `swift build` fails with `Undefined symbols … PackageDescription.Package.__allocating_init`, see "Troubleshooting" in `docs/development.md`.

## Architecture rules that are easy to break

- `PasteboardGateway` (`@MainActor`) is the only code that touches `NSPasteboard.general` (ADR 0004).
- Check privacy markers before reading content; concealed, transient and auto-generated items are never stored.
- Nothing loads the whole history. The list pages by `seq`, and search returns at most a few hundred candidates.
- Database writes happen in the `Ingestor`/`HistoryStore`, never on the main thread and never from views.
- The history list is an `NSTableView` (ADR 0005); everything else is SwiftUI.
- Sanitize display strings: strip U+FFFC and control characters (a macOS 26 CoreText hang).
- The app has no network entitlement. Anything that would need the network is a conversation with the owner first.

## Commits and versions

The full rules are in the `commit` skill and `CONTRIBUTING.md`; `.githooks/commit-msg` enforces the format.

- Conventional Commits 1.0: `<type>(<scope>)!: <description>`.
- Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `style`, `chore`, `revert`. `feat` only when behavior reaches users; groundwork nothing calls yet is `chore(<scope>)`.
- Scopes (optional): `capture`, `history`, `storage`, `search`, `panel`, `paste`, `hotkey`, `privacy`, `settings`, `onboarding`, `menubar`, `updater`, `import`, `l10n`, `a11y`, `deps`, `release`.
- Description: imperative, lowercase, no period, about 50 characters (72 at most). `feat`, `fix` and `perf` subjects are shown to users in the changelog and the update window, so describe the effect.
- The body explains why, wrapped at 72 columns. Breaking changes get `!` and a `BREAKING CHANGE:` footer.
- **No AI attribution in commits or PRs**: no `Co-Authored-By` for tools, no "Generated with" lines.
- Never `--no-verify`, never amend or rewrite pushed commits, never push without the owner asking.
- SemVer 2.0 starting at 0.1.0. Before 1.0, `feat` bumps the minor version and `fix`/`perf` bump the patch.
- `version.txt` is owned by release-please. The build number is `git rev-list --count HEAD`. Tags are `vX.Y.Z`, betas `vX.Y.Z-beta.N`. Process: `docs/releasing.md` (ADR 0006).

## Writing

Docs, UI copy and commit messages should read like a careful person wrote them. Be specific, name exact places, state limits, use no emoji headings or hype words, and use American spelling. `.claude/rules/writing.md` has the full list.
