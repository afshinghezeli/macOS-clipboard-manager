---
status: proposed
date: 2026-09-22
---

# Ship a sandboxed Developer ID app, updated with Sparkle

## Context and problem statement

Pasting into the app you were using means posting a synthetic ⌘V with `CGEvent`. In 2026, App Review has rejected new clipboard managers that do this under guideline 2.4.5, so the Mac App Store can't be the main channel. Outside the store we can choose whether to enable the App Sandbox. The history database holds everything a person copies. Since macOS 14, the system asks for consent before another app reads a sandboxed app's container, which protects the database from info-stealers and other snooping processes.

## Considered options

- Mac App Store only
- Developer ID, not sandboxed
- Developer ID with the App Sandbox (what Maccy ships)

## Decision outcome

Chosen option: Developer ID, notarized, with the App Sandbox enabled and Sparkle 2 for updates. Everything Spindle needs works inside the sandbox:

- Pasteboard access.
- Posting events under the PostEvent privilege (Apple DTS, forum thread 820594).
- Carbon hotkeys.
- `SMAppService` for launch at login.

The app gets no network entitlement at all. Sparkle downloads updates through its own XPC service, so "Spindle can't reach the network" is a guarantee macOS enforces, not just a promise.

### Consequences

- Good, because the history can only be read by other apps if the user allows it.
- Good, because the absence of network access is verifiable with `codesign -d --entitlements -`.
- Good, because a Mac App Store build stays possible later.
- Bad, because Sparkle needs its Installer and Downloader XPC services, plus the matching `mach-lookup` entitlements, which is more signing work.
- Bad, because files copied in Finder can be stored as references only. Reading their contents later would need security-scoped bookmarks.
- Bad, because importing another app's history (for example Maccy's) needs the user to pick the file in an open panel.

## More information

This stays **proposed** until roadmap task M0.9 proves both risky parts:

1. A sandboxed dev build pastes into TextEdit through `CGEvent`.
2. A sandboxed build updates itself through Sparkle.

If either fails, ship Developer ID without the sandbox instead. There are no users yet, so no container migration is needed.
