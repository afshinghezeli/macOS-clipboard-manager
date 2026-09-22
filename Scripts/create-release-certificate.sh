#!/usr/bin/env bash
# Create the self-signed certificate that signs Spindle releases (ADR 0007). The owner runs this
# once and stores the result in the GitHub "release" environment's secrets.
#
# Usage: Scripts/create-release-certificate.sh <output-directory>
#
# Environment:
#   CERTIFICATE_NAME  the certificate's common name, shown by `codesign -dv`.
#                     Default: "Spindle Release".
#
# Writes spindle-release.p12 and spindle-release.p12.base64 into the output directory, which
# must be outside the repository, and prints the password once. Keep the .p12 and its password
# in a password manager. macOS ties the paste permission to this certificate, so releasing with
# a different one makes everyone who updates grant the permission again.
set -euo pipefail

out="${1:?usage: $0 <output-directory outside the repository>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
name="${CERTIFICATE_NAME:-Spindle Release}"
openssl=/usr/bin/openssl

parent="$(cd "$(dirname "$out")" && pwd -P)" || { echo "error: $(dirname "$out") doesn't exist" >&2; exit 64; }
out="$parent/$(basename "$out")"
case "$out/" in
    "$root/"*) echo "error: $out is inside the repository; pick a folder outside it" >&2; exit 64 ;;
esac
mkdir -p "$out"
p12="$out/spindle-release.p12"
if [[ -e "$p12" ]]; then
    echo "error: $p12 exists; a new certificate would change every user's designated requirement" >&2
    exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
umask 077

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
# Twenty years: renewing the certificate would change the designated requirement too.
"$openssl" req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$scratch/cert.cnf" \
    -keyout "$scratch/key.pem" -out "$scratch/cert.pem" 2> /dev/null

password="$("$openssl" rand -hex 24)"
# Explicit algorithms: `security import` rejects OpenSSL 3's defaults ("MAC verification failed").
"$openssl" pkcs12 -export -inkey "$scratch/key.pem" -in "$scratch/cert.pem" -name "$name" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -out "$p12" -passout "pass:$password"
base64 -i "$p12" > "$p12.base64"

fingerprint="$("$openssl" x509 -in "$scratch/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
cat << DONE
Created "$name" (SHA-1 $fingerprint) in $out.

Password (shown once; save it with the .p12 in your password manager):

    $password

Store both in the release environment's secrets:

    gh secret set RELEASE_CERTIFICATE_P12 --env release < "$p12.base64"
    gh secret set RELEASE_CERTIFICATE_PASSWORD --env release

Then delete $p12.base64.
DONE
