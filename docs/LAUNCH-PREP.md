# Kopy launch preparation

Started 2026-11-21. Scope: account-free website and Dodo test licensing, app compliance, organic search preparation. Apple membership, distribution signing, notarization, App Store submission and live payments are excluded.

## Work list

- [x] Ground existing app and compare two licence designs.
- [x] Choose architecture and record boundaries.
- [x] Implement and test direct-only licensing.
- [x] Build and verify the Next.js public website.
- [x] Verify Dodo test checkout, delivery, activation and revocation; record the provider-blocked refund test.
- [x] Audit app, metadata, privacy and accessibility; document scanner scope and deferred release gates.
- [x] Deploy a preview and verify public routes.
- [x] Prepare SEO, reporting, daily site checks and unpublished launch drafts.
- [ ] Final evidence review and clean pushed repositories.

## Architecture decision

Two independent sketches compared an app-owned licence coordinator and a pure core access policy with one effect owner. Both found that a licence window alone leaves capture, shortcuts and edge drops running. Choose the app-owned coordinator with a small pure access policy and a central model capture gate. Score: ownership 5/5, Store separation 5/5, offline/revocation safety 5/5, testability 5/5. The alternative's pure policy is retained; its generic entitlement abstraction is unnecessary.

The configured architecture runner families were unavailable in this harness, so two inherited-model candidates ran. No different-vendor judge was available; the parent compared both candidates and synthesized the design.

One owner persists licence credentials in a separate Keychain item. No change to history encryption keys or deletion/Undo. Only a prior valid licence can receive bounded offline grace after a connection failure. Explicit invalidation denies access. Avoid overlapping activation/deactivation/refresh writes. Compile all licensing out of the Store target and inspect its final binary.

The public Next.js website lives in karthiknadar1204/kopy-website. Dodo owns checkout, receipts and key issuance. No customer login, Better Auth or customer database. Test API credentials never enter Git, browser bundles or the native app. No live checkout is enabled. The user chose a preview URL; custom-domain and Search Console verification remain pending until a production host is selected.

## Tooling

Dodo plugin marketplace was already present; plugin installation succeeded. Its MCP server is enabled but not signed in. Use the authorized test API for account work where possible, without widening permissions. Compliance source: karthiknadar1204/app-store-compliance, commit d2156bab9d7189835631c0a99adcc2479d32138d. Its scanner output is evidence to review, not proof of App Store approval.

## Baseline

Working tree was clean at 3ddd543. The first command-line-tools test attempt failed while loading SwiftUI macros; diagnose the toolchain before attributing this to app changes. No app source was modified before this baseline.

## Verified preparation results

- Public preview: https://kopy-website.vercel.app . All 24 HTML, Markdown, discovery, checkout-information and share-image checks pass. HTML returns `noindex` in headers and metadata. The Vercel production alias is used as a prelaunch preview, not an indexed launch or live payment release.
- Native tests: 93 passing (32 core, 61 app). Direct release and sandboxed Store preview build. GitHub macOS build/archive inspection passed for native licensing milestone 3243a50.
- Dodo TEST: USD 2.99, one non-expiring personal licence, one active Mac. Hosted failed-card and successful-card outcomes verified against API status. The user confirmed both receipt and licence emails arrived. Public licence activation, validation, activation-limit denial and deactivation were exercised.
- Actual native strict release: activated using the issued test key in an isolated bundle/home/Keychain identity, quit and reopened activated, deactivated through UI and returned to the activation gate, then reactivated. A saved disposable snippet remained in the same encrypted history file after manual remote revocation; the app denied access on reopening. No normal Kopy history or history encryption key was changed by the fixture.
- Refund attempted in TEST: Dodo returned HTTP 409 `INSUFFICIENT_WALLET_FUNDS`. No refund succeeded. Manual grant revocation succeeded and tested the explicit-invalid path; this does not establish automatic refund-to-revocation behaviour. Re-run the complete refund path when the test wallet supports it.
- Store bundle inspection excludes Dodo licensing, Sparkle and cross-app event posting. No Apple distribution signing or review approval is implied.
- Privacy/support links now point to the public website. The repository policy/support files remain source copies. No Google customer login exists, so Google app-brand verification and account deletion are not applicable. GumCLI operator OAuth is separate from a customer-facing Google sign-in feature.
- A daily website check is configured for 03:17 UTC (08:47 India time), plus on-demand runs. A real GitHub hosted run passed: https://github.com/karthiknadar1204/kopy-website/actions/runs/44870589904 . GitHub failure email depends on the owner's notification settings and was not simulated or verified.

## Remaining external gates

1. Choose the final domain; replace preview origins in app links, Store metadata, website and Dodo return URLs. Keep noindex until the public-launch decision.
2. Repair GumCLI's missing Search Console scope, verify the final property, submit the sitemap and inspect priority URLs. This new noindex preview has no claimed search impressions or indexed pages.
3. Resolve the Dodo test refund wallet restriction and verify successful refund, automatic entitlement revocation and native access removal. Only then configure a separate live product/build, consumer terms and live checkout at release time.
4. Add Apple membership/team and distribution identities. Sign/notarize the direct download and validate the App Store archive; repeat final release UI/permission/physical-device checks and complete App Store Connect declarations.
5. Publish a signed installer and decide when to enable indexing/live sales. No public unsigned installer, live charge, App Store submission or social post was made in this preparation pass.

Commands and search/distribution handoff are in the website repository's docs/SEO-OPERATIONS.md. The compliance finding dispositions are in docs/COMPLIANCE-PREP-2026-11.md.
