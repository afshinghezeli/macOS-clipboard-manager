# Releasing

How Spindle is versioned and shipped. The reasoning is in [ADR 0006](adr/0006-version-with-semver-and-release-please.md) (versions) and [ADR 0007](adr/0007-sign-releases-with-a-self-signed-certificate-for-now.md) (signing).

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
5. The Publish job (`.github/workflows/release.yml`) builds the universal app from the tagged commit and signs it with the release certificate. With a Developer ID certificate it also notarizes and staples. It then makes the ZIP (for Sparkle), the DMG (for people and Homebrew) and the dSYMs, and adds an appcast entry with the EdDSA signature and the changelog as release notes. Last, it uploads the files, publishes the release and pushes the appcast to the `gh-pages` branch.
6. Update the Homebrew tap and check `brew install --cask afshinghezeli/tap/spindle`.

To rehearse steps 5 and 6 locally, run `make release package`. That signs with your development identity, and without `Support/sparkle-public-key.txt` the build doesn't update itself.

## Betas

Betas are published from the "Beta" workflow (Actions → Beta → Run workflow on `main`, version `X.Y.Z-beta.N`). They get a pre-release on GitHub, whose notes list the `feat`, `fix` and `perf` commits since the last tag, and an appcast entry on Sparkle's `beta` channel. Only people who turned on Settings → General → Include beta versions are offered them. Betas leave `version.txt` and `CHANGELOG.md` alone, and they never go to Homebrew.

A beta's build number is the commit count of `main` when it was made, so a release made later always has a higher one. Two betas from the same commit are refused.

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
- **Settings → Environments:** a `release` environment that holds the secrets below. Under "Deployment branches and tags", allow only `main`: releases and betas are both built by workflows running on `main`.
- **Release certificate:** run `Scripts/create-release-certificate.sh ~/somewhere-private` and follow what it prints. It creates the self-signed certificate that signs every release and stores it as `RELEASE_CERTIFICATE_P12` and `RELEASE_CERTIFICATE_PASSWORD`. Keep the `.p12` and its password in a password manager. macOS ties the paste permission to this certificate, so a release signed with another one makes everyone who updates grant the permission again.
- **Update signing key:** run `make sparkle-keys`. It creates an EdDSA key pair in your login keychain and writes the public half to `Support/sparkle-public-key.txt`; commit that file. Export the private half with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key`, paste the file's contents into the `release` environment secret `SPARKLE_PRIVATE_KEY`, and delete the file. Keep a backup of the key somewhere safe: installed copies accept only updates signed with it, so losing it strands every user on their current version. Release builds made without `Support/sparkle-public-key.txt` don't update themselves, so the Publish job refuses to build one.
- **Settings → Pages:** after the first release has created the `gh-pages` branch, choose "Deploy from a branch", `gh-pages`, `/ (root)`. The appcast is then served at the `SUFeedURL` in `Support/Info.plist`. The Publish job warns when the feed doesn't show a new release within 10 minutes.

## Signing secrets

All of them live only in the `release` environment on GitHub and with the owner. They are never committed, and never available to workflows triggered by pull requests from forks.

| Secret | What it is |
|---|---|
| `RELEASE_CERTIFICATE_P12` | base64 of the `.p12` with the release certificate and its private key |
| `RELEASE_CERTIFICATE_PASSWORD` | the `.p12`'s password |
| `SPARKLE_PRIVATE_KEY` | the EdDSA key that signs updates, exported with `generate_keys -x` |
| `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | only with a Developer ID: an App Store Connect API key with the Developer role |

## Moving to a Developer ID

When the Apple Developer Program is worth it ([ADR 0007](adr/0007-sign-releases-with-a-self-signed-certificate-for-now.md)):

1. Export the "Developer ID Application" certificate with its private key as a `.p12`, and replace `RELEASE_CERTIFICATE_P12` and `RELEASE_CERTIFICATE_PASSWORD`.
2. Add the three `NOTARY_*` secrets.

No code changes. The Publish job recognizes the certificate by its name, turns on the hardened runtime and notarizes the app and the disk image. The first update signed this way changes Spindle's designated requirement, so its release notes must tell people to grant the paste permission again.
