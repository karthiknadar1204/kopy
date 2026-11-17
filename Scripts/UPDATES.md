# Build and publish a Kopy update

Kopy uses Sparkle to verify its update feed and archives. The app checks on launch and periodically in Automatic and Notify Me modes. Automatic prepares updates in the background. Notify Me waits for the user to choose Download. Off stops background checks, and Check for Updates remains available.

Updates require an HTTPS appcast URL and a public Ed25519 key in the bundled property list. A local build without those settings can run with updates unavailable. Keep the production private signing key in the release Keychain. Use the same feed URL, app bundle identifier, and public key in each release.

## Build

After a SwiftPM build, Sparkle's signing tools are in `.build/artifacts/sparkle/Sparkle/bin`. Generate the production key once with `generate_keys --account kopy`, then get its public key with `generate_keys --account kopy -p`.

Run this from the repository root with your actual version, feed address, and signing identity. Increment the build number for each public release.

```sh
sparkle_tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
KOPY_UPDATE_PUBLIC_KEY="$("$sparkle_tools/generate_keys" --account kopy -p)" \
KOPY_UPDATE_FEED="https://updates.example.com/kopy/appcast.xml" \
KOPY_VERSION="0.2.0" \
KOPY_BUILD_NUMBER="2" \
KOPY_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
Scripts/build-app.sh release
```

## Package

Use your Apple notary profile to notarize the app and staple the ticket. Build the Sparkle archive from the stapled app, then generate the signed appcast. Keep the previous appcast and any update archives you want to retain in the working directory used to generate the feed.

```sh
ditto -c -k --keepParent dist/Kopy.app dist/Kopy-notary.zip
xcrun notarytool submit dist/Kopy-notary.zip --keychain-profile kopy-notary --wait
xcrun stapler staple dist/Kopy.app
xcrun stapler validate dist/Kopy.app
spctl --assess --type execute --verbose dist/Kopy.app
mkdir -p dist/updates
ditto -c -k --keepParent dist/Kopy.app dist/updates/Kopy-0.2.0.zip
"$sparkle_tools/generate_appcast" --account kopy --download-url-prefix "https://updates.example.com/kopy/" dist/updates
```

Publish the update archives and deltas before replacing the appcast. Verify that a previous signed build can find and install the update. The current build should report that it is up to date. [Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/)

## Test locally

Run `swift build` followed by `python3 Tests/Integration/test_updates.py`. The integration test uses temporary Ed25519 keys, a loopback feed, and disposable signed Mac apps. It exercises both background modes, Off with a manual check, Skip, download, install, relaunch, and rejection of a changed feed or archive.
