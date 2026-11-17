#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="${1:-$PWD/Store/screenshots/en-US}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/kopy-store-screenshots.XXXXXX")"
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
app="$work/Screenshots.app"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -swift-version 6 -target "$target" -parse-as-library -DKOPY_APP_STORE \
    -module-name KopyApp -I "$work" -L "$work" -lKopyCore -lsqlite3 \
    "${app_sources[@]}" Tests/StoreScreenshots/Render.swift -o "$app/Contents/MacOS/Kopy"
cp Scripts/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.kopy.store-screenshots "$app/Contents/Info.plist"
Scripts/stage-app-resources.sh "$app/Contents/Resources"
"$app/Contents/MacOS/Kopy" "$output"
python3 - "$output" <<'PY'
import pathlib
import subprocess
import sys
for path in pathlib.Path(sys.argv[1]).glob('*.png'):
    result = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)], capture_output=True, text=True, check=True)
    dimensions = dict(line.strip().split(': ', 1) for line in result.stdout.splitlines()[1:])
    width = int(dimensions['pixelWidth'])
    height = int(dimensions['pixelHeight'])
    assert (width, height) in {(1280,800), (1440,900), (2560,1600), (2880,1800)}, (path, width, height)
    print(f'Accepted Mac screenshot size: {path.name}, {width} x {height}')
PY
