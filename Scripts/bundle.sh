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
#   VERSION         The version to write into Info.plist. Default: version.txt. Betas set it.
#   HARDENED_RUNTIME
#                   1 signs with the hardened runtime and a secure timestamp, as notarization
#                   needs. Default: on for a "Developer ID Application: …" identity name.
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
version="${VERSION:-$(tr -d '[:space:]' < version.txt)}"
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
if [[ "${HARDENED_RUNTIME:-}" == 1 || "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
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
    flags=(-c "$configuration" --arch "$arch")
    # SwiftPM 6.1 sometimes fails with "No target named … in build description" when one build
    # directory alternates between architectures, so a universal build gives each its own.
    [[ "$arches" == *" "* ]] && flags+=(--scratch-path "$root/.build/universal/$arch")
    echo "==> swift build ${flags[*]}"
    # shellcheck disable=SC2086
    swift build "${flags[@]}" --product "$product" ${SWIFT_FLAGS:-}
    bin="$(swift build "${flags[@]}" --show-bin-path)"
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
# in the binary. They are useless on other Macs, so drop everything that isn't relative. The
# relative one to Contents/Frameworks comes from Package.swift and is where Sparkle lives.
while IFS= read -r rpath; do
    [[ -z "$rpath" || "$rpath" == @* ]] && continue
    install_name_tool -delete_rpath "$rpath" "$executable"
done < <(otool -l "$executable" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | sort -u)  # once per slice
if [[ "$configuration" == release ]]; then
    # Symbols for reading crash reports, taken before stripping them from the app.
    rm -rf "$app.dSYM"
    dsymutil "$executable" -o "$app.dSYM"
    strip -x "$executable"
fi

plist="$contents/Info.plist"
cp Support/Info.plist "$plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build_number" "$plist"
if [[ "$configuration" == debug ]]; then
    plutil -replace CFBundleDisplayName -string "$product Dev" "$plist"
fi
# Updates only with a public key to check them against, and never for debug builds.
if [[ "$configuration" == release && -s Support/sparkle-public-key.txt ]]; then
    plutil -replace SUPublicEDKey -string "$(tr -d '[:space:]' < Support/sparkle-public-key.txt)" "$plist"
else
    plutil -remove SUFeedURL "$plist"
fi
plutil -lint "$plist" > /dev/null
printf 'APPL????' > "$contents/PkgInfo"

[[ -f Support/AppIcon.icns ]] && cp Support/AppIcon.icns "$contents/Resources/"

# Sparkle.framework, with the XPC services a sandboxed app needs. ditto keeps its symlinks.
if [[ -d "$first_bin/Sparkle.framework" ]]; then
    mkdir -p "$contents/Frameworks"
    ditto "$first_bin/Sparkle.framework" "$contents/Frameworks/Sparkle.framework"
fi

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
# Inside out, never --deep (Sparkle's sandboxing guide).
sparkle="$contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
    "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
    "${sign[@]}" "$sparkle/Versions/B/Autoupdate"
    "${sign[@]}" "$sparkle/Versions/B/Updater.app"
    "${sign[@]}" "$sparkle"
fi
entitlements="$root/.build/Spindle-$configuration.entitlements"
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$bundle_id/g" Support/Spindle.entitlements > "$entitlements"
"${sign[@]}" --entitlements "$entitlements" "$app"
codesign --verify --strict "$app"

echo "==> $app"
echo "    $bundle_id $version ($build_number), $(lipo -archs "$executable"), signed with $SIGN_IDENTITY"
