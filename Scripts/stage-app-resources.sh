#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:?Pass the Contents/Resources directory of the app}"
mkdir -p "$destination"
install -m 644 "$root/Resources/Kopy.icns" "$destination/Kopy.icns"
for localization in "$root"/Resources/Localizations/*.lproj; do
    ditto "$localization" "$destination/$(basename "$localization")"
done
ditto "$root/Resources/Emoji" "$destination/Emoji"
for notice in LICENSE NOTICE; do
    install -m 644 "$root/Resources/Localizations/$notice" "$destination/Localizations-$notice"
done
