#!/usr/bin/env bash
# Import a signing certificate into a temporary keychain for a CI build.
#
# Usage: Scripts/import-certificate.sh
#
# Environment:
#   CERTIFICATE_P12       base64 of a .p12 holding the certificate and its private key: the
#                         self-signed release certificate, or later a Developer ID Application one
#   CERTIFICATE_PASSWORD  the .p12's password
#   RUNNER_TEMP           where the keychain goes. Default: a new temporary directory.
#   GITHUB_OUTPUT         when set, gets `identity=<SHA-1>` and `developer-id=<true|false>`
#
# Prints the certificate's SHA-1, which Scripts/bundle.sh accepts as SIGN_IDENTITY.
set -euo pipefail

: "${CERTIFICATE_P12:?CERTIFICATE_P12 is empty; see docs/releasing.md}"
: "${CERTIFICATE_PASSWORD:?CERTIFICATE_PASSWORD is empty; see docs/releasing.md}"

directory="${RUNNER_TEMP:-$(mktemp -d)}"
keychain="$directory/spindle-signing.keychain-db"
keychain_password="$(/usr/bin/openssl rand -hex 24)"

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings "$keychain"  # no automatic locking during a long build
security unlock-keychain -p "$keychain_password" "$keychain"

p12="$directory/certificate.p12"
(umask 077 && printf '%s' "$CERTIFICATE_P12" | base64 --decode > "$p12")
security import "$p12" -k "$keychain" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign > /dev/null
rm -f "$p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > /dev/null

# codesign only finds identities in keychains on the search list.
existing=()
while IFS= read -r item; do
    existing+=("$item")
done < <(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
security list-keychains -d user -s "$keychain" "${existing[@]}"

# Without -v, so a self-signed certificate that isn't trusted is listed too.
line="$(security find-identity -p codesigning "$keychain" | grep -m 1 -E '^[[:space:]]+[0-9]+\) [0-9A-F]{40} ')"
identity="$(awk '{ print $2 }' <<< "$line")"
name="$(sed -E 's/^[^"]*"([^"]*)".*$/\1/' <<< "$line")"
developer_id=false
[[ "$name" == "Developer ID Application:"* ]] && developer_id=true

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "identity=$identity"
        echo "developer-id=$developer_id"
    } >> "$GITHUB_OUTPUT"
fi
echo "Imported \"$name\" ($identity)." >&2
echo "$identity"
