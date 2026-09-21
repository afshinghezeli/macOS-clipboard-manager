---
paths:
  - "Scripts/**"
  - "Makefile"
  - ".github/**"
  - ".githooks/**"
---

# Scripts, Makefile and CI

- Bash scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`; the git hook is POSIX `sh`. Quote every expansion.
- Scripts run from any directory: resolve the repo root from `${BASH_SOURCE[0]}`.
- Every script has a short header comment: what it does, usage, and the environment variables it reads.
- Scripts must work with the Command Line Tools only. Anything that needs Xcode (actool, xcodebuild) is optional and skipped with a note when missing.
- Never write signing identities, passwords, API keys or team IDs into files. They come from the environment or the keychain.
- Makefile targets are thin wrappers around scripts or single commands, each with a `## help` comment.
- GitHub Actions: pin third-party actions by full commit SHA with a version comment, set `permissions` explicitly (default `contents: read`), set `timeout-minutes` on every job, and never expose secrets to `pull_request` runs from forks.
- CI must run the same `make` targets developers run locally.
