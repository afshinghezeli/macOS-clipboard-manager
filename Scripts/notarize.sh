#!/usr/bin/env bash
# Notarize an app or disk image with Apple and staple the ticket to it. Only for builds signed
# with a Developer ID; the self-signed releases of ADR 0007 skip this step.
#
# Usage: Scripts/notarize.sh dist/release/Spindle.app
#        Scripts/notarize.sh dist/Spindle-1.2.3.dmg
#
# Environment (an App Store Connect API key with the Developer role):
#   NOTARY_KEY        contents of the AuthKey_XXXX.p8 file
#   NOTARY_KEY_ID     the key's ID
#   NOTARY_ISSUER_ID  the issuer ID shown above the key list
#
# Needs Xcode for notarytool and stapler.
set -euo pipefail

target="${1:?usage: $0 <path to .app or .dmg>}"
: "${NOTARY_KEY:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
key="$scratch/key.p8"
(umask 077 && printf '%s\n' "$NOTARY_KEY" > "$key")

case "$target" in
    *.app)
        # notarytool takes archives, not bundles.
        upload="$scratch/$(basename "$target" .app).zip"
        ditto -c -k --sequesterRsrc --keepParent "$target" "$upload"
        ;;
    *.dmg) upload="$target" ;;
    *) echo "error: expected a .app or .dmg, got $target" >&2; exit 64 ;;
esac

xcrun notarytool submit "$upload" --key "$key" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --wait --timeout 30m
xcrun stapler staple "$target"
xcrun stapler validate "$target"
