#!/bin/bash
set -euo pipefail

bundle="${1:?Pass the signed Mac App Store build or sandbox preview}"
contents="$bundle/Contents"
info="$contents/Info.plist"
entitlements="$(mktemp)"
trap 'rm -f "$entitlements"' EXIT

codesign --verify --deep --strict "$bundle"
codesign -d --xml --entitlements - "$bundle" > "$entitlements" 2>/dev/null
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements")" != true ]]; then
    printf 'App Sandbox is missing.\n' >&2
    exit 1
fi

executable="$(plutil -extract CFBundleExecutable raw "$info")"
libraries="$(otool -L "$contents/MacOS/$executable")"
symbols="$(nm -u "$contents/MacOS/$executable")"
bundle_listing="$(find "$contents" \( -iname '*sparkle*' -o -name Autoupdate -o -name Updater.app \) -print)"
plist="$(plutil -p "$info")"
if [[ "$libraries" == *Sparkle* || -n "$bundle_listing" ]] || grep -Eq '"SU[A-Z][A-Za-z]+"' <<< "$plist"; then
    printf 'A separate updater is present in the store build.\n' >&2
    exit 1
fi

if grep -Eq 'CGEventPost(ToPid)?$|CGRequestPostEventAccess$' <<< "$symbols"; then
    printf 'The store build contains cross-app event posting.\n' >&2
    exit 1
fi
if [[ "$(plutil -extract LSApplicationCategoryType raw "$info")" != public.app-category.productivity ]]; then
    printf 'The Productivity category is missing.\n' >&2
    exit 1
fi
if strings "$contents/MacOS/$executable" | grep -E -- '^--(test-profile|test-stay-open|demo)$'; then
    printf 'Development launch options are present in the store build.\n' >&2
    exit 1
fi

test -f "$contents/Resources/en.lproj/Localizable.strings"
test -f "$contents/Resources/Emoji/emoji-16.json"
test -f "$contents/Resources/Localizations-NOTICE"
plutil -lint "$contents/Resources/PrivacyInfo.xcprivacy"
printf 'Checked sandbox signature and resources for %s\n' "$bundle"
