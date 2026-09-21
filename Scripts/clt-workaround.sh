#!/usr/bin/env bash
# Work around stale *.private.swiftinterface files in a Command Line Tools install.
#
# Some CLT installs keep private interface files from an older Swift. The compiler prefers them
# over the current ones, and every Package.swift then fails to link with
# "Undefined symbols ... PackageDescription.Package.__allocating_init". The real fix is to delete
# the stale files with sudo (see docs/development.md). This script is for when that isn't possible:
# it copies SwiftPM's manifest and plugin libraries into .local/swiftpm without the stale files
# and writes local.mk, which the Makefile includes, to point SWIFTPM_CUSTOM_LIBS_DIR at the copy.
#
# Usage: Scripts/clt-workaround.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pm="/Library/Developer/CommandLineTools/usr/lib/swift/pm"
dest="$root/.local/swiftpm"

if [[ ! -d "$pm/ManifestAPI" ]]; then
    echo "No Command Line Tools SwiftPM libraries at $pm; nothing to do."
    exit 0
fi

# A private interface is stale when it's older than the public interface next to it.
stale=()
while IFS= read -r -d '' private; do
    public="${private%.private.swiftinterface}.swiftinterface"
    if [[ -f "$public" && "$private" -ot "$public" ]]; then
        stale+=("$private")
    fi
done < <(find "$pm" -name '*.private.swiftinterface' -print0)

if [[ ${#stale[@]} -eq 0 ]]; then
    echo "No stale interface files found; the workaround isn't needed."
    rm -f "$root/local.mk"
    exit 0
fi

echo "Stale files:"
printf '  %s\n' "${stale[@]}"

rm -rf "$dest"
mkdir -p "$dest"
cp -R "$pm/ManifestAPI" "$pm/PluginAPI" "$dest/"
for file in "${stale[@]}"; do
    rm -f "$dest/${file#"$pm"/}"
done

printf 'export SWIFTPM_CUSTOM_LIBS_DIR := %s\n' "$dest" > "$root/local.mk"
echo "Wrote local.mk. make will now build with the cleaned copy in .local/swiftpm."
echo "To fix the install itself: sudo rm ${stale[*]}"
