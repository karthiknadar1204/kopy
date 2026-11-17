# Prepare the Mac App Store build

The store target shares Kopy's app and core source. It compiles with KOPY_APP_STORE, excludes Sparkle and development launch switches, enables App Sandbox, and starts clipboard capture paused. The direct SwiftPM build uses its existing update mechanism.

## Test on this Mac

Run the core and AppKit tests, then create a sandboxed preview.

```sh
swift test
Scripts/build-store-preview.sh
open dist/KopyStorePreview.app
```

The preview uses com.karthiknadar.kopy.store-preview, with a separate container and Keychain identity. It is ad hoc signed for local testing. It cannot be uploaded as a store release.

Run the persistent file-access probe with a disposable fixture.

```sh
Tests/StoreSandbox/build.sh /tmp/KopySandboxFixture
open "/tmp/KopySandboxFixture/Kopy Sandbox Check.app"
```

Choose Sandbox fixture.txt from that folder, quit the probe, reopen it, and choose Reopen stored reference. Both reads must report PASS. The probe uses the same scoped bookmark codec and file-access implementation as the store build.

Test Finder drops and dragging files out, screenshots, stack selections, note search, rich text and plain copy, manual paste, clipboard permission denial, relaunch, sleep and wake, and multiple displays in the store build. Keep actual clipboard contents out of screenshots and reports.

## Archive with Xcode

Install Xcode and add your Apple developer account in its settings. Open Store/KopyStore.xcodeproj. Select KopyStore, set your signing team, and confirm that com.karthiknadar.kopy is registered to that team. Set the release version and a new build number in Store.xcconfig. Archive for a generic Mac destination.

```sh
xcodebuild archive -project Store/KopyStore.xcodeproj -scheme KopyStore \
    -destination 'generic/platform=macOS' \
    -archivePath dist/Kopy.xcarchive \
    DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

In Xcode Organizer, validate and distribute the archive to App Store Connect using the App Store Connect distribution method. Xcode supplies the distribution signing and provisioning workflow. Use the credentials for your own developer team.

GitHub Actions archives an unsigned store target and checks an ad hoc signed copy on each push. That proves buildability and bundle structure. Distribution signing and upload validation require your developer account.

## Check the final bundle

```sh
Scripts/check-store-bundle.sh dist/Kopy.xcarchive/Products/Applications/Kopy.app
```

The checker verifies the code signature, sandbox entitlement, updater exclusion, privacy manifest, and bundled resources. Re-run it on the exported distribution app before upload.

The store build copies selected items and uses manual Command-V in the destination app. It does not request Accessibility access or post keyboard events across apps. The direct build retains its optional click-to-paste feature.

The store entitlements allow read-only user-selected files, persistent app-scoped bookmarks, exports to Downloads, and outgoing requests for explicitly dropped image URLs. No camera, microphone, location, incoming network server, or Apple Events automation entitlement is requested.

Store/PrivacyInfo.xcprivacy declares no tracking and no developer-side collection. It documents app-owned preferences and file metadata used within the container or on user-authorized files. Apple documents required-reason API enforcement for its mobile and spatial platforms. The Mac build includes an accurate manifest as an explicit disclosure.

ITSAppUsesNonExemptEncryption is false for the store build because it uses Apple's CryptoKit and system HTTPS encryption. It contains no separately implemented encryption library. Review this declaration whenever dependencies or encryption behavior change, and complete App Store Connect's encryption questions for the final binary. [Apple encryption guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)

## Complete App Store Connect

The English draft listing and review notes are in Store/metadata/en-US. The support and privacy pages are public files in this repository.

Before submitting, complete these items in App Store Connect.

- Choose the app category, availability, price, and release method.
- Fill the age-rating questionnaire for a clipboard utility. Kopy opens saved links in the browser and has no embedded web browser, user account, generative AI service, or social publishing feature.
- Complete App Privacy from the final store build. Kopy has no developer analytics, advertising, or clipboard backend. Explain user-requested image downloads and browser links in the privacy policy.
- Supply your review contact details and the review notes.
- Confirm your developer membership, required agreements, and trader status. Apple displays verified trader details for applicable EU distribution.
- Upload Mac screenshots in an accepted 16:10 size. Generate fixture screenshots with Tests/StoreScreenshots/run.sh.
- Run the full store build on the current shipping macOS and any older macOS release that the listing supports.
- Validate and upload a distribution-signed archive. Confirm that App Store Connect finishes processing it without unresolved errors.

Apple reviews the submitted binary, metadata, account declarations, and app behavior. Record that review outcome alongside the release version.

## References

- [Mac App Store requirements](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)
- [App Sandbox configuration](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Mac screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
