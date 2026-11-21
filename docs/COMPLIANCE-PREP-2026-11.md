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

- [ ] Direct licensing tests and app UI.
- [ ] Store build excludes licence code, Dodo hosts and Sparkle.
- [ ] Accurate privacy manifest and metadata URL audit.
- [ ] Website legal/support links open without authentication.
- [ ] Fixture screenshots and manual copy instructions match Store build.
- [ ] Record remaining final-signed-build/physical-device checks honestly.
