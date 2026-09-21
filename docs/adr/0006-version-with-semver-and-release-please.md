---
status: accepted
date: 2026-09-22
---

# Version with SemVer and release with release-please

## Context and problem statement

Spindle will ship many releases through GitHub, Sparkle and Homebrew. Users see version numbers in the About window and in update prompts, and Sparkle decides what "newer" means from the build number. We want versions that mean something, changelogs written for users, and a release that is a deliberate act rather than a side effect of every merge.

## Considered options

- Manual versioning and a hand-written changelog
- semantic-release (releases on every qualifying push; needs Node)
- git-cliff with a hand-rolled release workflow
- release-please, which keeps a release pull request open

## Decision outcome

Chosen option: Semantic Versioning 2.0 driven by Conventional Commits, with release-please.

- **Commits** follow Conventional Commits 1.0, checked locally by `.githooks/commit-msg`. Once changes arrive through pull requests, they are squash-merged and the PR title becomes the commit.
- **Versions** start at 0.1.0. Before 1.0, `feat` bumps the minor version, `fix` and `perf` bump the patch, and breaking changes bump the minor.
- **What counts as breaking** for a GUI app:
  - history data that isn't migrated
  - a changed default shortcut
  - a removed feature
  - a higher minimum macOS
- **`version.txt`** is the single source of `CFBundleShortVersionString`. release-please owns it; nobody edits it by hand.
- **`CFBundleVersion`** is `git rev-list --count HEAD` on a linear `main`. It always increases and can be reproduced from any checkout.
- **Tags** are `vX.Y.Z`. Betas are `vX.Y.Z-beta.N`, published from a separate workflow that leaves `version.txt` and CHANGELOG.md alone.
- **Merging** the release pull request creates the tag and a draft GitHub release. The release workflow builds, signs and notarizes, uploads the assets, updates the appcast, then publishes.

### Consequences

- Good, because the changelog is generated from commit subjects that were written for users, and a human reviews it in the release PR before it ships.
- Good, because nothing needs installing locally; release-please runs as a GitHub Action.
- Bad, because the commit discipline has to hold. A bad subject line ends up in the changelog until someone edits the release PR.
- Bad, because the release PR's checks only run if it is opened with a GitHub App token rather than the default `GITHUB_TOKEN`.

## More information

Process details are in [docs/releasing.md](../releasing.md). Revisit if hand-made beta tags turn out to confuse release-please's idea of the last release. git-cliff's `ignore_tags` is the fallback.
