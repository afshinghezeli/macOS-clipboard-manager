---
name: commit
description: Stage and commit work in the Spindle repo as a Conventional Commit that passes the commit-msg hook and reads well in the changelog. Use whenever committing, or when asked to "commit", "write a commit message" or "save this work".
argument-hint: "[optional note about intent]"
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git --no-pager diff *) Bash(git --no-pager log *) Bash(git add *) Bash(git commit *) Bash(git log *)
---

# Commit

## Steps

1. Inspect: `git status --short` and `git --no-pager diff`. Identify the single logical change to commit. If the tree mixes unrelated changes, commit them separately, one purpose per commit.
2. Stage by explicit path. Never `git add -A` or `git add .`. Don't stage files you didn't create or change for this piece of work; if an untracked file's origin is unclear, leave it and mention it.
3. Unless the change is docs-only, make sure `/verify` passed for this exact state. Never commit a red build.
4. Read what you are about to commit: `git --no-pager diff --cached`. The message describes this diff and nothing else.
5. Write the message using the rules below, then commit with a heredoc so formatting survives:
   ```sh
   git commit -F - <<'MSG'
   fix(paste): keep Terminal focused after pasting

   Terminal re-activated itself before our ⌘V arrived, so the paste
   went to the previous window. Wait for the target app to report
   itself frontmost before posting the key events.
   MSG
   ```
6. If the hook rejects the message, fix the message. Never use `--no-verify`.
7. Show the result with `git --no-pager log --oneline -3`.

## Message rules

Header: `<type>(<scope>)!: <description>`, where the scope and `!` are optional.

| Type | Use for | Release effect |
|---|---|---|
| `feat` | New user-visible capability or setting | minor bump, "Added" in changelog |
| `fix` | User-visible bug or crash fix | patch bump, "Fixed" |
| `perf` | Measurable speed or memory improvement | patch bump, "Changed" |
| `revert` | Reverting an earlier commit | patch bump |
| `refactor` | Code change with no behaviour change | none |
| `docs` | README, docs/, code comments | none |
| `test` | Tests only | none |
| `build` | Package.swift, Scripts/, bundling, dependencies | none |
| `ci` | .github/workflows | none |
| `style` | Formatting only | none |
| `chore` | Anything else (tooling, repo config) | none |

Scopes (optional, closed list): `capture`, `history`, `storage`, `search`, `panel`, `paste`, `hotkey`, `privacy`, `settings`, `onboarding`, `menubar`, `updater`, `import`, `l10n`, `a11y`, `deps`, `release`.

- Description: imperative mood, lowercase first word, no trailing period. Aim for 50 characters; the hook rejects more than 72.
- `feat`, `fix` and `perf` descriptions are read by users. They land verbatim in CHANGELOG.md, the GitHub release and the Sparkle update window. Describe the effect: `fix(paste): keep Terminal focused after pasting`, not `fix: fix bug in PasteInjector`.
- Body (optional): explain why and what behaviour changed, wrapped at 72 columns. Skip it when the header says everything. Don't list files; the diff already does.
- Breaking changes: add `!` before the colon and a `BREAKING CHANGE: <what users must know>` footer. For an app that means a history store that isn't migrated, a changed default shortcut, a removed feature or a higher minimum macOS.
- Footers: `Refs: #12`, `Closes #12`. Use `Release-As: x.y.z` only when the owner asks for it.
- No AI attribution of any kind: no `Co-Authored-By` lines for tools, no "Generated with" lines. `Co-Authored-By` is only for real human co-authors.
- Never amend, rebase or force-push commits that are already on the remote. Never push unless the owner asks.

## Examples

```
feat(search): match text inside copied screenshots
perf(storage): page the history list instead of loading it at once
fix(capture): skip items marked as concealed by password managers
build(deps): bump GRDB to 7.11.1
docs: explain why Spindle asks for Accessibility
feat(hotkey)!: change the default shortcut to ⌥⌘V
```
