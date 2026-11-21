# Kopy

Kopy is a native macOS clipboard shelf. Move the pointer to the configured edge, use **Control–Option–V**, or open **Show Shelf** in the menu bar.

## Run locally

Kopy targets macOS 14 or later. The verified toolchain is Xcode 27.2 (Swift 6.4.2). On this Mac, use the full Xcode developer directory: Command Line Tools alone could not load the SDK's SwiftUI macro plugin.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-app.sh
open dist/Kopy.app
```

The default debug build supports fixture cards for a visual check. Quit any running copy of Kopy first and pass the demo flag. Release builds compile out these development switches and require Dodo test activation.

```sh
open dist/Kopy.app --args --demo
```

Run the history, pasteboard, geometry, and update settings tests with `swift test`. Run `python3 Tests/Integration/test_updates.py` after building to exercise signed updates with temporary app bundles and a local feed.

## Use the shelf

- Search by content, file name, or note. Filter by kind. Pin items or add a note to protect them from automatic clearing.
- Click a card to paste. To let Kopy send Command–V, open **Settings**, select **System**, and click **Allow automatic paste**. If the permission or target is unavailable, Kopy leaves the item ready for manual paste and shows a message.
- Drag Finder files to the shelf. Drop cards together to make a stack, click to expand it, or detach a member to make its own card. Drag a file or stack card to another app. In a preview, select individual members and use the drag grip to transfer just that selection.
- Use **Incognito** to pause automatic capture. The app skips recognized concealed and transient content and suppresses its own clipboard writes.
- Use **Import Clipboard** for an explicit import. macOS can separately control automatic pasteboard reads.

Encrypted history is local to the Mac. Kopy stores its encryption key in the login Keychain. Ordinary file cards reference their originals. Regular files supplied through an app's file promise are encrypted in history, with a 32 MiB limit per promised file. Transferring a managed file creates a temporary readable copy. A supported web-image drop may fetch that image.

## Project layout

| Location | Responsibility |
| --- | --- |
| `Sources/KopyCore` | Item types, search and classification, and authenticated SQLite history |
| `Sources/KopyApp/Application` | Lifecycle, preferences, menu, and user actions |
| `Sources/KopyApp/Platform` | AppKit shelf, native drag, pasteboard, focus, and Keychain |
| `Sources/KopyApp/Interface` | SwiftUI cards, filters, settings, and onboarding |
| `Tests` | Core and macOS transfer behavior |
| [`.agents/SOURCES.md`](.agents/SOURCES.md) | Pinned project skill sources |

The build script creates an ad hoc signed development bundle by default. See [Build and publish a Kopy update](Scripts/UPDATES.md) for Developer ID signing, notarization, and the Sparkle feed.

## Mac App Store build

[Prepare the sandboxed Mac App Store build](Store/README.md) for the store target, local preview, signing, and submission steps. [Privacy policy](PRIVACY.md). [Support](SUPPORT.md).

## Prelaunch website and direct test licensing

The [website preview](https://kopy-website.vercel.app) is built in [kopy-website](https://github.com/karthiknadar1204/kopy-website). It has public privacy/support pages and a clearly labelled Dodo TEST checkout. No live payment or signed public installer is offered yet.

The strict direct release uses the configured test product. Buy only with Dodo's documented test details, use the emailed test licence in the activation screen, and manage the single active Mac under Settings → System → Licence. No customer account or private merchant API key belongs in the app. Credentials use a separate Keychain item; licence changes preserve local history and Undo. Store builds have no Dodo activation flow.

[Launch evidence and remaining gates](docs/LAUNCH-PREP.md) records the verified tests and the test-wallet restriction that prevented a successful refund check. [Compliance preparation](docs/COMPLIANCE-PREP-2026-11.md) distinguishes source scanner findings from actual bundle checks. Apple account setup, final distribution signing, the final domain and live commerce are deferred.
