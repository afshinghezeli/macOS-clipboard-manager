#!/usr/bin/env bash
# Build Spindle with SwiftPM and assemble a signed dist/<configuration>/Spindle.app.
#
# Usage: Scripts/bundle.sh [debug|release]
#
# Environment:
#   ARCHES          Architectures to build, e.g. "arm64 x86_64". Default: this Mac's.
#   SIGN_IDENTITY   "Developer ID Application: …", a certificate SHA-1, or "-" for ad hoc.
#                   Default: the identity from `make setup-signing`, else ad hoc.
#   SWIFT_FLAGS     Extra flags for `swift build`.
#
# Debug builds get the bundle id suffix ".dev" so they never share settings, history or
# permissions with an installed release.
set -euo pipefail

configuration="${1:-debug}"
case "$configuration" in
    debug | release) ;;
    *) echo "usage: $0 [debug|release]" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

product="Spindle"
bundle_id="com.afshinghezeli.Spindle"
[[ "$configuration" == debug ]] && bundle_id="$bundle_id.dev"
version="$(tr -d '[:space:]' < version.txt)"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
arches="${ARCHES:-$(uname -m)}"
app="$root/dist/$configuration/$product.app"
contents="$app/Contents"

# ------------------------------------------------------------------ signing identity
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if [[ -f .dev-signing-identity ]]; then
        SIGN_IDENTITY="$(tr -d '[:space:]' < .dev-signing-identity)"
        # The dev keychain locks after a restart; its password is in the login keychain.
        keychain="$HOME/Library/Keychains/com.afshinghezeli.Spindle.dev-signing.keychain-db"
        if [[ -f "$keychain" ]] && password="$(security find-generic-password -s com.afshinghezeli.Spindle.dev-signing -w 2>/dev/null)"; then
            security unlock-keychain -p "$password" "$keychain"
        fi
    else
        SIGN_IDENTITY="-"
        echo "note: signing ad hoc; macOS forgets permissions after each build. Run 'make setup-signing' once."
    fi
fi
sign=(codesign --force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
    # Notarization needs the hardened runtime and a secure timestamp. Only use them with a real
    # team ID: library validation rejects self-signed and ad-hoc signed frameworks.
    sign+=(--options runtime --timestamp)
fi

# ------------------------------------------------------------------------------ build
# One `swift build` per architecture, then lipo: building several architectures in one
# invocation needs Xcode's build system, which the Command Line Tools don't have.
slices="$root/.build/slices/$configuration"
rm -rf "$slices"
first_bin=""
for arch in $arches; do
    echo "==> swift build -c $configuration --arch $arch"
    # shellcheck disable=SC2086
    swift build -c "$configuration" --arch "$arch" --product "$product" ${SWIFT_FLAGS:-}
    bin="$(swift build -c "$configuration" --arch "$arch" --show-bin-path)"
    mkdir -p "$slices/$arch"
    cp "$bin/$product" "$slices/$arch/"
    [[ -n "$first_bin" ]] || first_bin="$bin"
done

# --------------------------------------------------------------------------- assemble
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"

executable="$contents/MacOS/$product"
lipo -create "$slices"/*/"$product" -output "$executable"

# SwiftPM leaves absolute build-machine rpaths (the toolchain's Testing.framework directory)
# in the binary. They are useless on other Macs, so drop everything that isn't relative.
while IFS= read -r rpath; do
    [[ -z "$rpath" || "$rpath" == @* ]] && continue
    install_name_tool -delete_rpath "$rpath" "$executable"
done < <(otool -l "$executable" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }')
[[ "$configuration" == release ]] && strip -x "$executable"

plist="$contents/Info.plist"
cp Support/Info.plist "$plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build_number" "$plist"
[[ "$configuration" == debug ]] && plutil -replace CFBundleDisplayName -string "$product Dev" "$plist"
plutil -lint "$plist" > /dev/null
printf 'APPL????' > "$contents/PkgInfo"

[[ -f Support/AppIcon.icns ]] && cp Support/AppIcon.icns "$contents/Resources/"

# SwiftPM resource bundles go in Contents/Resources. Never the bundle root: codesign rejects
# "unsealed contents present in the bundle root".
shopt -s nullglob
for resource_bundle in "$first_bin"/*.bundle; do
    cp -R "$resource_bundle" "$contents/Resources/"
done
shopt -u nullglob

# ------------------------------------------------------------------------------- sign
# Some dependencies' resources (GRDB's privacy manifest) are checked out read-only; codesign and
# xattr need to write to them.
chmod -R u+w "$app"
xattr -cr "$app"
"${sign[@]}" --entitlements Support/Spindle.entitlements "$app"
codesign --verify --strict "$app"

echo "==> $app"
echo "    $bundle_id $version ($build_number), $(lipo -archs "$executable"), signed with $SIGN_IDENTITY"
