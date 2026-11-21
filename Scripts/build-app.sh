#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

feed_url="${KOPY_UPDATE_FEED:-}"
public_key="${KOPY_UPDATE_PUBLIC_KEY:-}"
identity="${KOPY_CODESIGN_IDENTITY:--}"
if [[ -n "$feed_url" || -n "$public_key" ]]; then
    if [[ "$feed_url" != https://* || ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
        echo 'Updates require an HTTPS KOPY_UPDATE_FEED and a base64 Ed25519 KOPY_UPDATE_PUBLIC_KEY.' >&2
        exit 2
    fi
fi

build_arguments=(-c "$configuration")
if [[ -n "${KOPY_BUILD_SCRATCH_PATH:-}" ]]; then
    build_arguments+=(--scratch-path "$KOPY_BUILD_SCRATCH_PATH")
fi
swift build "${build_arguments[@]}"
bin_dir="$(swift build "${build_arguments[@]}" --show-bin-path)"
bundle="$PWD/dist/Kopy.app"
contents="$bundle/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Frameworks"
install -m 755 "$bin_dir/Kopy" "$contents/MacOS/Kopy"
plist="$contents/Info.plist"
install -m 644 Scripts/Info.plist "$plist"
if [[ -n "$feed_url" ]]; then
    plutil -insert SUFeedURL -string "$feed_url" "$plist"
    plutil -insert SUPublicEDKey -string "$public_key" "$plist"
fi
if [[ -n "${KOPY_VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$KOPY_VERSION" "$plist"
fi
if [[ -n "${KOPY_BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$KOPY_BUILD_NUMBER" "$plist"
fi

framework="$contents/Frameworks/Sparkle.framework"
rm -rf "$framework"
ditto "$bin_dir/Sparkle.framework" "$framework"
Scripts/stage-app-resources.sh "$contents/Resources"
if [[ "$identity" == - ]]; then
    codesign --force --sign - "$bundle"
else
    while IFS= read -r -d '' component; do
        codesign --force --sign "$identity" --options runtime --timestamp \
            --preserve-metadata=identifier,entitlements "$component"
    done < <(find "$framework/Versions/Current/" -depth \( -name '*.xpc' -o -name '*.app' -o -name Autoupdate \) -print0)
    codesign --force --sign "$identity" --options runtime --timestamp "$framework"
    codesign --force --sign "$identity" --options runtime --timestamp "$bundle"
fi
codesign --verify --deep --strict "$bundle"
printf '%s\n' "$bundle"
