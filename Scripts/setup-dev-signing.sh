#!/usr/bin/env bash
# Create a stable, self-signed code-signing identity for local development builds.
#
# Usage: Scripts/setup-dev-signing.sh            create it (safe to run again)
#        Scripts/setup-dev-signing.sh --remove   delete it and its keychain
#
# macOS remembers permissions such as posting keyboard events by the app's code signature. An
# ad-hoc signature changes with every build, so those permissions silently stop applying. A
# self-signed certificate keeps the signature stable across builds. It lives in its own
# keychain, whose random password is stored in your login keychain so signing never prompts.
# Nobody else trusts this certificate; releases are signed with a Developer ID.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="Spindle Local Development"
service="com.afshinghezeli.Spindle.dev-signing"
keychain="$HOME/Library/Keychains/$service.keychain-db"
# The keychain search list stores resolved paths; resolve ours the same way so lookups match.
mkdir -p "$(dirname "$keychain")"
keychain="$(cd "$(dirname "$keychain")" && pwd -P)/$(basename "$keychain")"
openssl=/usr/bin/openssl

search_list() { security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//'; }

if [[ "${1:-}" == "--remove" ]]; then
    remaining=()
    while IFS= read -r item; do
        [[ "$item" != "$keychain" ]] && remaining+=("$item")
    done < <(search_list)
    security list-keychains -d user -s "${remaining[@]}"
    security delete-keychain "$keychain" 2> /dev/null || true
    security delete-generic-password -s "$service" > /dev/null 2>&1 || true
    rm -f "$root/.dev-signing-identity"
    echo "Removed. Reset old grants with: tccutil reset All com.afshinghezeli.Spindle.dev"
    exit 0
fi

if ! password="$(security find-generic-password -s "$service" -w 2> /dev/null)"; then
    password="$("$openssl" rand -hex 24)"
    security add-generic-password -a "$USER" -s "$service" -w "$password" -U
fi

if [[ ! -f "$keychain" ]]; then
    security create-keychain -p "$password" "$keychain"
    security set-keychain-settings "$keychain"  # no automatic locking
fi
security unlock-keychain -p "$password" "$keychain"

# codesign only finds identities in keychains on the user's search list.
if ! search_list | grep -qxF "$keychain"; then
    current=()
    while IFS= read -r item; do current+=("$item"); done < <(search_list)
    security list-keychains -d user -s "${current[@]}" "$keychain"
fi

certificate_hash() {
    { security find-certificate -c "$name" -Z "$keychain" 2> /dev/null || true; } | awk '/SHA-1 hash:/ { print $3; exit }'
}

hash="$(certificate_hash)"
if [[ -z "$hash" ]]; then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT
    cat > "$scratch/cert.cnf" << CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $name
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
    "$openssl" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$scratch/cert.cnf" \
        -keyout "$scratch/key.pem" -out "$scratch/cert.pem" 2> /dev/null
    # Explicit algorithms: `security import` rejects OpenSSL 3's defaults ("MAC verification failed").
    "$openssl" pkcs12 -export -inkey "$scratch/key.pem" -in "$scratch/cert.pem" -name "$name" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -out "$scratch/identity.p12" -passout pass:import
    security import "$scratch/identity.p12" -k "$keychain" -P import -T /usr/bin/codesign > /dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" > /dev/null
    hash="$(certificate_hash)"
    [[ -n "$hash" ]] || { echo "error: importing the identity failed" >&2; exit 1; }
fi

# Signing by SHA-1 works without marking the certificate as trusted.
echo "$hash" > "$root/.dev-signing-identity"
echo "Dev builds will be signed with \"$name\" ($hash)."
echo "If an ad-hoc build was granted permissions before, run: tccutil reset All com.afshinghezeli.Spindle.dev"
