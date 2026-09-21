#!/usr/bin/env bash
# PostToolUse hook: format a Swift file with the toolchain's swift-format right
# after Claude edits or writes it. Never blocks the edit; formatting problems
# surface later in `make lint`.
set -uo pipefail

file=$(jq -r '.tool_input.file_path // empty')
[[ "$file" == *.swift && -f "$file" ]] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
config="$root/.swift-format"
[[ -f "$config" ]] || exit 0

swift format --in-place --configuration "$config" "$file" 2>/dev/null || true
exit 0
