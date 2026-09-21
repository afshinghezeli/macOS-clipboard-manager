#!/usr/bin/env bash
# Check a packaged Spindle.app the way a user's Mac would see it.
#
# Usage: Scripts/verify-bundle.sh dist/debug/Spindle.app
#
# Besides the signature and Info.plist, this launches a copy of the app with the source checkout
# unreadable. A resource lookup that only works on the build machine (SwiftPM's Bundle.module
# falls back to an absolute path there) fails here instead of on someone else's Mac.
set -euo pipefail

app="${1:?usage: $0 path/to/Spindle.app}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
executable_name="$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")"
executable="$app/Contents/MacOS/$executable_name"

codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist" > /dev/null

if otool -l "$executable" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | grep -v '^@'; then
    echo "verify-bundle: absolute rpath from the build machine left in $executable" >&2
    exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp -R "$app" "$scratch/"
# A process can't enter the App Sandbox once sandbox-exec has sandboxed it (it traps at launch),
# so the copy is re-signed without entitlements. Resource lookup doesn't depend on them, and the
# real bundle's signature was verified above.
codesign --force --sign - "$scratch/$(basename "$app")" 2> /dev/null
copy="$scratch/$(basename "$app")/Contents/MacOS/$executable_name"

# sandbox-exec is deprecated but still ships with macOS, and it is the simplest way to hide the
# checkout from a single process.
profile="(version 1)(allow default)(deny file-read* (subpath \"$root\"))"
if output="$(SPINDLE_SMOKE_TEST=1 sandbox-exec -p "$profile" "$copy" 2>&1)" && grep -q SMOKE_OK <<< "$output"; then
    echo "verify-bundle: OK"
else
    echo "verify-bundle: FAILED" >&2
    echo "$output" >&2
    exit 1
fi
