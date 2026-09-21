---
status: accepted
date: 2026-09-22
---

# Sign releases with a self-signed certificate until a Developer ID is worth it

## Context and problem statement

A downloaded app opens without warnings only if it is signed with a Developer ID certificate and notarized by Apple. That needs the Apple Developer Program at $99 a year. Spindle is free and the owner doesn't want to pay for distribution yet.

An unsigned or ad-hoc signed build has two problems. The first launch is blocked: since macOS 15, users must go to System Settings → Privacy & Security → Open Anyway. And every update changes the code signature, so macOS silently forgets the paste permission.

## Considered options

- Developer ID and notarization from the first release
- Ad-hoc signed releases
- Releases signed with a stable self-signed certificate, moving to Developer ID before a public launch

## Decision outcome

Chosen option: a stable self-signed certificate for now. The first launch still needs "Open Anyway" once, which the README explains. But the designated requirement stays the same across updates, so the paste permission survives them, and Sparkle's EdDSA signatures still protect the update path.

The release workflow takes the signing identity from secrets. Switching to a Developer ID later means replacing those secrets and turning on notarization; no code changes.

### Consequences

- Good, because releases cost nothing and permissions survive updates.
- Bad, because every new user sees a Gatekeeper warning on first launch, which hurts trust in an app that reads the clipboard.
- Bad, because the official Homebrew cask repository rejects apps that fail Gatekeeper, so only a personal tap is possible.
- Bad, because moving to a Developer ID changes the designated requirement, and existing users grant the paste permission once more after that update.

## More information

Revisit before announcing Spindle publicly (Hacker News, Reddit, Product Hunt). The warning on first launch costs more than the fee at that point. ADR 0002's sandbox decision is unaffected.
