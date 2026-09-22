#!/usr/bin/env bash
# Package dist/release/Spindle.app for publishing. Run `make release` first.
#
# Usage: Scripts/package.sh
#
# Makes, in dist/:
#   Spindle-<version>.zip        what Sparkle downloads to update
#   Spindle-<version>.dmg        what people and Homebrew download
#   Spindle-<version>.dSYM.zip   debug symbols, for reading crash reports
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist="$root/dist"
app="$dist/release/Spindle.app"
[[ -d "$app" ]] || { echo "error: $app is missing; run 'make release' first" >&2; exit 1; }
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
name="Spindle-$version"

rm -f "$dist/$name.zip" "$dist/$name.dmg" "$dist/$name.dSYM.zip"

# ditto keeps the framework's symlinks and extended attributes, which zip would break.
ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/$name.zip"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Spindle.app"
ln -s /Applications "$staging/Applications"
# ULFO (LZFSE) needs macOS 10.11 or later; Spindle needs 15.
# hdiutil sometimes fails with "Resource busy" on CI machines; a retry usually succeeds.
for attempt in 1 2 3; do
    hdiutil create -quiet -ov -volname Spindle -srcfolder "$staging" -fs HFS+ -format ULFO "$dist/$name.dmg" && break
    [[ "$attempt" == 3 ]] && exit 1
    echo "hdiutil failed; trying again" >&2
    sleep 5
done

if [[ -d "$dist/release/Spindle.app.dSYM" ]]; then
    ditto -c -k --keepParent "$dist/release/Spindle.app.dSYM" "$dist/$name.dSYM.zip"
fi

ls -l "$dist/$name".*
