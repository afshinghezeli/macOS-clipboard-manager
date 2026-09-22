#!/usr/bin/env bash
# Write the Homebrew cask for a release into a checkout of the tap.
#
# Usage: Scripts/update-cask.sh <version> <path/to/Spindle-version.dmg> <tap-checkout>
#
# Fills Support/Homebrew/spindle.rb with the version and the DMG's SHA-256 and writes it to
# <tap-checkout>/Casks/spindle.rb. Committing and pushing is left to the caller.
set -euo pipefail

version="${1:?usage: $0 <version> <dmg> <tap-checkout>}"
dmg="${2:?usage: $0 <version> <dmg> <tap-checkout>}"
tap="${3:?usage: $0 <version> <dmg> <tap-checkout>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: $version isn't a release version; betas don't go to Homebrew" >&2
    exit 64
fi
sha256="$(shasum -a 256 "$dmg" | cut -d ' ' -f 1)"

mkdir -p "$tap/Casks"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha256/" "$root/Support/Homebrew/spindle.rb" \
    | grep -v '^# ' > "$tap/Casks/spindle.rb"
echo "Wrote $tap/Casks/spindle.rb for $version ($sha256)."
