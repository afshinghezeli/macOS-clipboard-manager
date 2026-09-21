---
name: release
description: Prepare and ship a Spindle release (stable or beta) following docs/releasing.md. Only when the owner explicitly asks to cut a release.
disable-model-invocation: true
argument-hint: "[beta]"
---

# Release

Read docs/releasing.md first; it is the source of truth. This is the checklist.

## Before

1. `git fetch` and confirm `main` is clean, up to date and green in CI.
2. All roadmap tasks for the milestone are ticked, or explicitly moved to the next milestone.
3. `make check` passes locally.
4. Run the manual smoke test from docs/releasing.md on a release build (`make release`): capture text, image and files; paste into Safari, TextEdit, Terminal and an Electron app; search; pins; settings persist across relaunch; the menu bar icon and the hotkey both open the panel; no crash on a fresh install with no permissions granted.
5. Read the open release-please pull request. Rewrite changelog lines that a user wouldn't understand, and add Security, Deprecated or Removed notes by hand where needed.

## Ship (only with the owner's explicit go-ahead)

6. Stable: the owner merges the release-please PR. The release workflow builds, signs, notarizes, uploads the DMG and ZIP to the draft release, updates the appcast, then publishes.
7. Beta (`$ARGUMENTS` = `beta`): run the "Beta" workflow from the Actions tab with the version (`X.Y.Z-beta.N`). It leaves CHANGELOG.md and version.txt alone.
8. Watch the workflow to the end. Any failure stops the release; never publish half-signed artifacts.

## After

9. Download the DMG from the release page on a clean machine or user account. Check that Gatekeeper opens it without warnings and that `spctl -a -vv` reports "Notarized Developer ID".
10. Update from the previous version through Sparkle and confirm the history survives.
11. Update the Homebrew tap (stable only) and confirm `brew install --cask` works.
12. Move the finished milestone to "Done" in docs/roadmap.md.
