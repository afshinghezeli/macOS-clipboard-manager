#!/usr/bin/env bash
# Check that the private key that signs updates matches Support/sparkle-public-key.txt, the public
# key every build checks updates against. If they differ, installed copies reject every update.
#
# Usage: Scripts/check-sparkle-key.sh
#
# Environment:
#   SPARKLE_PRIVATE_KEY  the private key as `generate_keys -x` exports it. Default: the key in
#                        your login keychain, where `make sparkle-keys` put it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
public_key_file="$root/Support/sparkle-public-key.txt"
sign_update="$root/.build/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -s "$public_key_file" ]] || { echo "error: $public_key_file is missing; run 'make sparkle-keys'" >&2; exit 1; }
[[ -x "$sign_update" ]] || (cd "$root" && swift package resolve)

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
probe="$scratch/probe"
echo "Spindle update key check $(date -u +%FT%TZ)" > "$probe"

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    signature="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - -p "$probe")"
else
    signature="$("$sign_update" -p "$probe")"
fi

if swift "$root/Scripts/verify-ed25519.swift" "$(cat "$public_key_file")" "$signature" "$probe"; then
    echo "The update signing key matches Support/sparkle-public-key.txt."
else
    echo "error: the update signing key doesn't match Support/sparkle-public-key.txt;" \
        "installed copies would reject updates signed with it" >&2
    exit 1
fi
