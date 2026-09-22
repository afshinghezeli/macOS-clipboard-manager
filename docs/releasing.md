# Releasing

How Spindle is versioned and shipped. The reasoning is in [ADR 0006](adr/0006-version-with-semver-and-release-please.md). The automation described here is built in roadmap tasks M0.11 (release-please) and M5.2–M5.5 (signing, notarization, Sparkle, Homebrew). Until those land, this file is the specification they implement.

## Version numbers

Spindle follows [Semantic Versioning 2.0](https://semver.org). For an app, the "public API" is what people and their scripts rely on:

- stored history and settings
- default keyboard shortcuts
- the URL scheme and CLI, once they exist
- the minimum macOS version

| Bump | After 1.0 | Before 1.0 |
|---|---|---|
| Major | History not migrated, a default shortcut changed, a feature removed, minimum macOS raised | not used |
| Minor | New features or settings, new localizations, automatic migrations | new features **and** breaking changes |
| Patch | Bug and crash fixes, performance work, translation fixes | bug fixes and performance work |

The first release is 0.1.0. 1.0.0 comes once the update path has worked across real releases, the storage format has a migration policy, and the default shortcuts are settled.

## Where the numbers live

| Thing | Source |
|---|---|
| `CFBundleShortVersionString` | `version.txt`, written by release-please; never edited by hand |
| `CFBundleVersion` (build number) | `git rev-list --count HEAD`; only ever increases because `main` is linear |
| Git tag | `v` + version, e.g. `v0.3.1`; betas `v0.4.0-beta.1` |
| Changelog | `CHANGELOG.md`, generated from commit subjects by release-please |

`Scripts/bundle.sh` writes both Info.plist keys at build time, so the version exists in one place only. Sparkle compares build numbers, not version strings. A release whose build number isn't higher than the one in the live appcast is refused by the release workflow.

## Stable releases

1. Every push to `main` updates an open pull request titled `chore: release X.Y.Z`. It contains the new `CHANGELOG.md` section and the bumped `version.txt`.
2. When a release is due, edit the changelog in that PR until every line makes sense to a user. Add Security, Deprecated or Removed notes by hand where needed.
3. Run the smoke test below on a release build (`make release`).
4. Merge the PR. release-please tags the merge commit and creates a draft GitHub release.
5. The release workflow builds a universal binary, signs it with the Developer ID certificate, notarizes and staples it, and builds the DMG (for people and Homebrew) and the ZIP (for Sparkle). It uploads both plus the dSYMs, updates the appcast and publishes the release.
6. Update the Homebrew tap and check `brew install --cask afshinghezeli/tap/spindle`.

## Betas

Betas are published from the "Beta" workflow (manual run, input `X.Y.Z-beta.N`). They get a pre-release on GitHub and an appcast entry on Sparkle's `beta` channel, which users opt into in Settings. Betas leave `version.txt` and `CHANGELOG.md` alone, and they never go to Homebrew.

## Smoke test

Run on a release build before merging a release PR:

- Fresh start with no permissions granted: onboarding appears, nothing crashes.
- Copy text, rich text, an image and several files; all appear. A 1Password or KeePassXC password copy does not.
- The shortcut and the menu bar icon both open the panel. Search finds an old item. ↵ pastes into TextEdit, Safari and Terminal.
- Pins and settings survive quitting and relaunching.
- Updating from the previous release through Sparkle keeps the history.

## One-time repository setup

These are GitHub settings, done once by the owner:

- **Settings → General → Pull Requests:** allow squash merging only, with "Default commit message" set to "Pull request title". Turn on "Automatically delete head branches".
- **Settings → Rules:** a ruleset for `main` that requires a pull request, linear history, and the `ci-ok` and `Conventional PR title` checks, and blocks force pushes and deletion.
- **Release token:** create a GitHub App with Contents and Pull requests (read and write) on this repository. Store its client ID as the Actions variable `RELEASE_APP_CLIENT_ID` and its private key as the secret `RELEASE_APP_PRIVATE_KEY`. Without it, the release workflow falls back to `GITHUB_TOKEN`. That needs "Allow GitHub Actions to create and approve pull requests" under Settings → Actions, and CI won't run on the release PR.
- **Settings → Code security:** turn on private vulnerability reporting (SECURITY.md relies on it) and immutable releases.
- **Settings → Environments:** a `release` environment that holds the signing secrets, limited to tags matching `v*`.
- **Update signing key:** run `make sparkle-keys`. It creates an EdDSA key pair in your login keychain and writes the public half to `Support/sparkle-public-key.txt`; commit that file. Export the private half with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key`, paste the file's contents into the `release` environment secret `SPARKLE_PRIVATE_KEY`, and delete the file. Keep a backup of the key somewhere safe: installed copies accept only updates signed with it, so losing it strands every user on their current version. Release builds made without `Support/sparkle-public-key.txt` don't update themselves.

## Signing secrets

The Developer ID certificate, the App Store Connect API key for notarization and the Sparkle EdDSA private key live only in the `release` environment's secrets on GitHub and in the owner's keychain. They are never committed, and never available to workflows triggered by pull requests from forks.
