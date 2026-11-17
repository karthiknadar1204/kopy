#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 OUTPUT_DIRECTORY" >&2
    exit 1
fi

mkdir -p "$1"
output="$(cd "$1" && pwd)"
cd "$(dirname "$0")/../.."

staging="$(mktemp -d "${TMPDIR:-/tmp}/kopy-localization.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

swift build --scratch-path "$staging/build" --build-tests
build="$(swift build --scratch-path "$staging/build" --show-bin-path)"
bundle="$staging/LocalizationRender.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
cp -R Resources/Localizations/*.lproj "$bundle/Resources"

plutil -create xml1 "$bundle/Info.plist"
plutil -insert CFBundleIdentifier -string com.kopy.localization-render "$bundle/Info.plist"
plutil -insert CFBundleExecutable -string LocalizationRender "$bundle/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string en "$bundle/Info.plist"

objects=()
for object in "$build"/KopyApp.build/*.swift.o "$build"/KopyCore.build/*.swift.o; do
    if [[ "${object##*/}" != KopyApplication.swift.o ]]; then
        objects+=("$object")
    fi
done
swiftc -target "$(uname -m)-apple-macosx14.0" -swift-version 6 -parse-as-library \
    -I "$build/Modules" -F "$build" -framework Sparkle -lsqlite3 -Xlinker -rpath -Xlinker "$build" \
    -o "$bundle/MacOS/LocalizationRender" Tests/LocalizationVisual/Render.swift "${objects[@]}"
"$bundle/MacOS/LocalizationRender" "$output"
