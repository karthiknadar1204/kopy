# Kopy pre-account compliance review

Reviewed 2026-11-21. This is preparation, not approval or a distribution-signed release audit. Sources: the user-selected app-store-compliance playbook at d2156bab9d7189835631c0a99adcc2479d32138d and Apple's current Mac App Store review/privacy guidance.

## Baseline evidence

The full Xcode 27.2 toolchain passed all 79 existing tests (32 app tests and 47 core tests). Command Line Tools failed to load the SDK's SwiftUIMacros plugin; using the installed Xcode toolchain fixed that environment failure without source changes. Store listing metadata audit including URL checks reported zero findings.

## Findings and disposition

| Finding | Source | Disposition |
| --- | --- | --- |
| Scanner reports two critical risks in Sparkle's TestApplication/installer sources | Whole-checkout guard includes .build/checkouts | These are dependency sample sources, not Kopy's Store app. The Store build excludes Sparkle; verify the actual bundle with Scripts/check-store-bundle.sh. Do not modify a dependency or override the guard to hide this finding. |
| Scanner says Store has no policy link | Guard scopes to Store/ and misses shared Sources/ | KopyLinks and Settings/onboarding contain links. Verify their signed-out website destinations after deployment and inspect the actual app UI. |
| App Store age-rating questionnaire | Manual account check | Pending Apple account, as requested. Do not infer answers from a scanner. |
| Privacy, support and licensing disclosures | Source review | Update both app and website for direct-build Dodo licensing; Store binary has no custom licence flow. Persistent Undo means manual deletion is not immediate destruction of encrypted recovery records. |
| Distribution signing, notarization and Store upload | Manual release gates | Intentionally deferred. No public unsigned download or live checkout. |

## Scope controls

Kopy has no customer accounts, cloud clipboard sync, AI service, subscription, advertising SDK or developer usage analytics. Dodo purchases and licence validation add direct-build network processing; disclose it accurately. Do not add account deletion UI to an app that has no accounts. Mac Store purchases remain Apple's flow, with no Dodo activation requirement.

The whole-checkout guard's legal-deadline list is generic reference output. It does not establish applicability to a local clipboard utility or verify each underlying legal claim. Review applicable official requirements before release rather than adding unrelated age/AI/health controls.

## Final checks for this preparation pass

- [x] Direct licensing tests and app UI.
- [x] Store build excludes licence code, Dodo hosts and Sparkle.
- [x] Accurate privacy manifest and metadata URL audit.
- [x] Website legal/support links open without authentication.
- [x] Fixture screenshots and manual copy instructions match Store build.
- [x] Record remaining final-signed-build/physical-device checks honestly.

## Final preparation evidence

The full playbook release audit completed, including its own internal validation, and returned exit 2 / BLOCKED: 2 critical, 3 high and 2 medium findings. It was not overridden or represented as approval. The raw report was retained privately as /tmp/kopy-launch-evidence/RELEASE-READINESS-REPORT.md; the app's current, scoped dispositions are below.

| Full-audit finding | Actual artifact evidence and disposition |
| --- | --- |
| Staging backend | The whole checkout includes Sparkle samples, generated files and the direct TEST-licence channel. That direct binary is intentionally unsuitable for a live release. The actual Store preview has no Dodo host/licensing, Sparkle or development bypass flags, as verified by the bundle checker. Do not replace the test endpoint with a live endpoint in this preparation phase. |
| Missing privacy manifest | Store/PrivacyInfo.xcprivacy is copied into the actual sandboxed app and passes the playbook validator and plutil. Dependency sample headers are not Kopy's Store app. |
| Missing policy link | KopyLinks, Settings, onboarding and the empty state link the public website policy. Public URLs return 200 without authentication. The scanner's limited source scope is not a complete view of shared Swift sources. |
| Missing export declaration | The actual Store Info.plist contains ITSAppUsesNonExemptEncryption=false. Review the system CryptoKit/HTTPS exemption and final App Store Connect answers when the final distribution binary exists. |
| Missing Nutrition Labels | The actual Store privacy manifest explicitly includes NSPrivacyCollectedDataTypes as an empty array and NSPrivacyTracking=false. Store code excludes direct Dodo licensing. Local-only clipboard processing is not falsely declared as server collection to satisfy a regex. App Store Connect privacy answers still need the Apple account and final dependency review. |
| Button haptics | Reported files are project skill reference Markdown. This is an iOS-oriented advisory, not proof of a macOS accessibility defect. Do not add UIKit haptics to a Mac utility. |
| Age questionnaire | Real manual release gate: complete accurate answers in App Store Connect after the account is available. |

Latest local verification: 96 tests pass (32 core + 64 app), direct strict release builds, and sandboxed Store preview builds and passes Scripts/check-store-bundle.sh. This checks code-signature structure using ad hoc signing, sandbox, resources, privacy manifest, updater/event-posting/development-flag/direct-licence exclusion. It does not validate an Apple distribution signature or upload.

The final listing metadata audit, including the new website URLs, reports zero critical/high/medium/low findings. Privacy-manifest validation exits 0. Actual native licence UI activated an issued Dodo test key, restored it on relaunch, deactivated and reactivated it, and blocked access after explicit remote revocation. The isolated encrypted history file remained byte-identical after revocation. Native automated tests additionally cover recoverable deletion records surviving a licence lock. The Dodo refund request failed due to test-wallet funds, so successful refund processing and automatic revocation remain unverified.

Desktop website and 390px phone-width guide/purchase layouts were reviewed in Chrome. Semantic headings, skip navigation, alt text, labelled controls, keyboard focus styles and responsive content are present. This was not a complete VoiceOver or all-language release audit. The new direct-test licensing copy is English; its Store exclusion keeps it outside this Store preparation UI.

The app and website have no customer accounts or Google sign-in. Google OAuth brand approval and account-deletion flows are not applicable. GumCLI's operator reporting permission is a separate Search Console setup; it currently reports SCOPE_MISSING and final-domain verification is deferred.

The app's final distribution build must still be signed and exercised on real hardware, including sleep/wake, login launch, multiple displays, drag/cancel and permission denial. Existing development checks do not substitute for that final build. Apple has not reviewed or approved this app. No Google Play submission is planned for this macOS app.
