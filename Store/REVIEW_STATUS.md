# Mac App Store readiness

Reviewed November 18, 2026.

## Implemented and checked

| Item | Evidence |
| --- | --- |
| Separate store build | KopyStore native Xcode target shares the app and core sources. GitHub Actions successfully archived the target. |
| Sandbox | Store/Kopy.entitlements is embedded in the local preview. Scripts/check-store-bundle.sh verifies the signed entitlement. |
| Store updates | The store target excludes Sparkle, its UI, and its helpers. The bundle checker inspects linked libraries and bundle contents. |
| First-run capture consent | The store preview launched paused. Clipboard history is enabled through an explicit user action. |
| Manual clipboard workflow | A fixture imported while capture was paused, survived relaunch, and copied into a disposable TextEdit document through manual Command-V. |
| Event posting | The temporary Accessibility grant was unavailable to the sandbox preview's event-posting API. The store build uses manual paste and compiles out event posting and its permission request. The temporary grant was switched off after the test. |
| Persistent file scope | Tests/StoreSandbox created a read-only security-scoped bookmark through a user-selected fixture, quit, relaunched, and successfully read the stored reference. |
| Existing file history | A regression test verifies decoding and opening a legacy record without the new scope flag. Another verifies scope metadata round trips. |
| Privacy disclosure | PRIVACY.md and SUPPORT.md are public repository pages. The app links them from Settings, and onboarding links the policy. |
| Privacy manifest | The store bundle includes Store/PrivacyInfo.xcprivacy. The reference repository's manifest validation completed successfully. |
| Listing | The reference repository's metadata audit, including URL checks, reported zero findings for Store/metadata. |
| Screenshots | Four fixture screenshots in Store/screenshots/en-US are 2560 by 1600 pixels. They use the actual SwiftUI views with store build conditions. |
| Local test suite | All 54 tests passed on macOS 27.2.1. The tests include encrypted history, clipboard transfers, localization completeness, legacy file record compatibility, and domain display across Unicode, percent-encoded, and punycode URLs. |
| Updated macOS | The sandbox preview launched and opened Settings on macOS 27.2.1. The scoped-file probe successfully read its fixture before and after relaunch. |
| GitHub verification | Commit 7310f58 passed tests, the Xcode store archive, and the archive inspection. [Build results](https://github.com/karthiknadar1204/kopy/actions/runs/44240070726). |
| Languages | All 31 selectable languages contain the new privacy and copy-action labels. |
| Account features | Kopy has no user accounts, social login, subscriptions, in-app payments, AI integration, advertising, or analytics SDK. |

The support and privacy contact uses karthiknadar1204@gmail.com, the repository author's configured Git email. Confirm that this is the address you want to support publicly before submission.

## Remaining release gates

| Gate | Current state |
| --- | --- |
| Distribution signing | This Mac has Command Line Tools and no valid signing identities. The local preview is ad hoc signed. Add Xcode and the Apple developer team, then create and validate the distribution-signed archive. |
| App Store Connect | App record, bundle registration, age-rating answers, App Privacy answers, review contact, encryption declaration, price, availability, agreements, and trader status require verification in the developer account. |
| Final distribution build | Repeat Finder drops, drag-out to a sandboxed destination, managed images and stack selection, restart, sleep/wake, full-screen behavior, physical shortcut input, and multiple displays on the signed release. |
| Review outcome | Apple has not reviewed or approved this build. |

## Release steps

Follow Store/README.md to build, test, archive, and submit the store version. Re-run Scripts/check-store-bundle.sh on the final exported app. Update this record with the archive version, test OS versions, upload validation, and Apple review outcome.
