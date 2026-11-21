# Kopy launch preparation

Started 2026-11-21. Scope: account-free website and Dodo test licensing, app compliance, organic search preparation. Apple membership, distribution signing, notarization, App Store submission and live payments are excluded.

## Work list

- [x] Ground existing app and compare two licence designs.
- [x] Choose architecture and record boundaries.
- [ ] Implement and test direct-only licensing.
- [ ] Build and verify the Next.js public website.
- [ ] Verify Dodo test checkout, delivery, activation and refunds where available.
- [ ] Audit app, metadata, privacy and accessibility.
- [ ] Deploy a preview and verify public routes.
- [ ] Prepare SEO, reporting, alerts and launch drafts.
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
