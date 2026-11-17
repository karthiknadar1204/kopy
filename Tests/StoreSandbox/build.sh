#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
destination="${1:?Pass a disposable output directory}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/kopy-sandbox-probe.XXXXXX")"
trap 'rm -rf "$work"' EXIT
target="$(uname -m)-apple-macosx14.0"
xcrun swiftc -swift-version 6 -target "$target" -parse-as-library -module-name KopyCore \
    -emit-module -emit-module-path "$work/KopyCore.swiftmodule" \
    -emit-library -static -o "$work/libKopyCore.a" Sources/KopyCore/*.swift
app_sources=()
while IFS= read -r -d '' source; do app_sources+=("$source"); done < <(
    find Sources/KopyApp -name '*.swift' ! -name KopyUpdater.swift ! -name KopyUpdateSection.swift \
        ! -name KopyApplication.swift -print0
)
app="$destination/Kopy Sandbox Check.app"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -swift-version 6 -target "$target" -parse-as-library -DKOPY_APP_STORE \
    -module-name KopyApp -I "$work" -L "$work" -lKopyCore -lsqlite3 \
    "${app_sources[@]}" Tests/StoreSandbox/Probe.swift -o "$app/Contents/MacOS/Kopy"
cp Store/Info.plist "$app/Contents/Info.plist"
for entry in 'CFBundleExecutable Kopy' 'CFBundleIdentifier com.karthiknadar.kopy.sandbox-check' \
    'CFBundleShortVersionString 0.1.0' 'CFBundleVersion 1' 'LSMinimumSystemVersion 14.0'; do
    read -r key value <<< "$entry"
    plutil -replace "$key" -string "$value" "$app/Contents/Info.plist"
done
Scripts/stage-app-resources.sh "$app/Contents/Resources"
cp Store/PrivacyInfo.xcprivacy "$app/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --force --sign - --entitlements Store/Kopy.entitlements "$app"
Scripts/check-store-bundle.sh "$app"
printf 'Kopy sandbox fixture\n' > "$destination/Sandbox fixture.txt"
printf 'Open %s and choose %s\n' "$app" "$destination/Sandbox fixture.txt"
