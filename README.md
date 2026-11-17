# Kopy

Kopy is a native macOS clipboard shelf. Move the pointer to the configured edge, use **Control–Option–V**, or open **Show Shelf** in the menu bar.

## Run locally

Kopy requires macOS 14 or later and Swift 6.1. Apple's Command Line Tools or Xcode can supply the compiler and macOS SDK.

```sh
Scripts/build-app.sh
open dist/Kopy.app
```

To open the shelf with fixture cards for a visual check, quit any running copy of Kopy first and pass the demo flag.

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
