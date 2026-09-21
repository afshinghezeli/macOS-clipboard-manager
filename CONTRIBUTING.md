# Contributing to Spindle

Thanks for taking a look. A few things keep reviews short and the history clean.

## Before you write code

Open an issue for anything bigger than a bug fix, so we can agree on the approach before you spend time on it. Check [the roadmap](docs/roadmap.md) first, including the "Not planned" list. Spindle deliberately does one job, and some popular requests (history sync, snippet expansion, AI features) are out of scope.

Small fixes and typo corrections can go straight to a pull request.

## Setting up

You need macOS 15 or later and either the Command Line Tools (`xcode-select --install`) or Xcode 16.4+.

```sh
make setup           # enables the commit-msg hook
make setup-signing   # stable local signing identity, so macOS remembers the paste permission
make run             # builds dist/debug/Spindle.app and launches it
make check           # what CI runs: format check, build, tests
```

[docs/development.md](docs/development.md) explains the build, the signing identity, permissions and troubleshooting.

## Commit messages and pull request titles

Spindle uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). Pull requests are squash-merged, so the PR title becomes the commit on `main` and, for user-facing changes, a line in the changelog. Write it for users:

```
fix(paste): keep Terminal focused after pasting
feat(search): match text inside copied screenshots
```

- **Types:** `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `style`, `chore`, `revert`.
- **Scopes** (optional): `capture`, `history`, `storage`, `search`, `panel`, `paste`, `hotkey`, `privacy`, `settings`, `onboarding`, `menubar`, `updater`, `import`, `l10n`, `a11y`, `deps`, `release`.
- **Description:** imperative, lowercase first word, no trailing period, 72 characters at most.
- **`feat` is for what users can see.** Internal building blocks that nothing uses yet are `chore`, so each feature appears once in the changelog.
- **Breaking changes** (data that isn't migrated, a changed default shortcut, a removed feature, a higher minimum macOS) get a `!`, as in `feat(hotkey)!: …`, and a `BREAKING CHANGE:` note in the description.

The hook enabled by `make setup` checks commit messages locally.

## Code

- Follow the existing style; `make format` applies it.
- Add swift-testing tests for logic changes. Tests must not need Accessibility or other permissions.
- Performance matters here. If you touch storage, search or the list, check the budgets in [docs/performance.md](docs/performance.md) and include before/after numbers in the PR.
- In the PR, note the macOS version you tested on and, for paste changes, which apps you pasted into.

## AI tools

Using them is fine. Say so in the PR, and only submit code you have run and understand; you'll be asked about it in review.

## License

Spindle is licensed under GPL-3.0-only. By contributing, you agree that your contribution is licensed under the same terms.
