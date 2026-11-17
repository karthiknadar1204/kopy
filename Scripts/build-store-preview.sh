#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d "${TMPDIR:-/tmp}/kopy-store-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
bundle="${1:-$PWD/dist/KopyStorePreview.app}"
if [[ -e "$bundle" && -f "$bundle/Contents/Info.plist" ]]; then
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
    [[ "$identifier" == "com.karthiknadar.kopy.store-preview" ]] || {
        printf 'Choose a destination dedicated to the store preview.\n' >&2
        exit 1
    }
fi

target="$(uname -m)-apple-macosx14.0"
xcrun swiftc -swift-version 6 -target "$target" -parse-as-library \
    -module-name KopyCore -emit-module -emit-module-path "$work/KopyCore.swiftmodule" \
    -emit-library -static -o "$work/libKopyCore.a" Sources/KopyCore/*.swift
app_sources=()
while IFS= read -r -d '' source; do app_sources+=("$source"); done < <(
    find Sources/KopyApp -name '*.swift' ! -name KopyUpdater.swift ! -name KopyUpdateSection.swift -print0
)
xcrun swiftc -swift-version 6 -target "$target" -parse-as-library -DKOPY_APP_STORE \
    -module-name KopyApp -I "$work" -L "$work" -lKopyCore -lsqlite3 \
    -o "$work/Kopy" "${app_sources[@]}"

contents="$bundle/Contents"
mkdir -p "$contents/MacOS"
install -m 755 "$work/Kopy" "$contents/MacOS/Kopy"
install -m 644 Store/Info.plist "$contents/Info.plist"
for entry in 'CFBundleExecutable Kopy' 'CFBundleIdentifier com.karthiknadar.kopy.store-preview' \
    'CFBundleShortVersionString 0.1.0' 'CFBundleVersion 1' 'LSMinimumSystemVersion 14.0'; do
    read -r key value <<< "$entry"
    plutil -replace "$key" -string "$value" "$contents/Info.plist"
done
Scripts/stage-app-resources.sh "$contents/Resources"
codesign --force --sign - --entitlements Store/Kopy.entitlements "$bundle"
Scripts/check-store-bundle.sh "$bundle"
