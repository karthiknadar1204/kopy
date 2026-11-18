# Kopy privacy policy

Effective November 17, 2026.

Kopy is a clipboard history and file shelf for macOS, developed by Karthik Nadar.

## Clipboard history

When you enable automatic capture, Kopy saves supported text, links, images, and file references copied on this Mac. It also saves notes, pins, preferences, and recent emoji that you choose in the app. The Mac App Store build starts with automatic capture paused. You can enable history or pause it in Settings. Manual clipboard imports and file drops are explicit actions and continue to work while capture is paused.

Kopy skips clipboard formats marked as concealed, transient, or sensitive by their source app. Apps must supply these markers for Kopy to recognize them. Ordinary clipboard text can contain passwords or other private information, so use Pause automatic capture before copying anything you do not want to keep.

Kopy saves clipboard history in an encrypted local SQLite database. It stores the history key in your Mac's Keychain. Preferences, recent emoji, and file-transfer metadata are stored locally. Original files remain in their original locations. Kopy may retain encrypted file contents for files delivered by another app through a file promise.

## Network activity

Kopy has no account system, analytics SDK, advertising SDK, tracking identifier, or cloud sync. Clipboard history and search terms are processed on your Mac.

If you drop a supported image URL onto Kopy, Kopy requests the image from that address. The image host receives the request URL and ordinary connection information, including your IP address. Kopy uses an ephemeral session, disables cookies and stored credentials, rejects redirects, and limits the response size. The image host has its own privacy practices.

Opening a saved link, this policy, or a support page opens your browser. Those websites have their own privacy practices. GitHub hosts this policy and the support pages.

The Mac App Store build receives updates through the Mac App Store. The separately distributed build can use Sparkle to request a configured update feed and download an update you select or enable. The update server receives normal connection metadata. Kopy disables Sparkle system profiling. The developer must publish the production update host before enabling that feed.

## Retention and deletion

Settings lets you choose a history limit and automatic cleanup interval. Pinned items and items with notes are protected from automatic cleanup and bulk history clearing. You can delete a protected item from its individual menu. Remove every item you want erased, including protected items.

Kopy creates readable temporary files when another app needs a file or image through copy, paste, drag, or Finder reveal. It cleans up expired transfer sessions after 24 hours when Kopy runs. A temporary file still referenced by Kopy's current clipboard transfer remains available until the clipboard changes and the cleanup runs again. Files explicitly exported to Downloads remain until you delete them. Copies you paste or drop into another app belong to that destination and must be deleted there.

Deletion removes an item from Kopy's active history. Kopy does not promise forensic erasure from backups, storage snapshots, or storage media. macOS backups may contain local app data. Removing Kopy does not delete files you exported or copied elsewhere.

Kopy keeps the last 20 manual delete or clear actions in memory for Undo during the current app session. Quitting Kopy discards this recovery history. Undo does not use a separate recovery database or upload deleted content.

## Permissions and choices

Automatic clipboard reading follows your macOS clipboard permission. The direct build offers click-to-paste and asks for event-posting access through macOS when you select Allow automatic paste. Without that access, Kopy leaves the item ready for manual paste. The Mac App Store build copies a selected item to the clipboard. Press Command-V in the destination app to paste it. The store build does not request Accessibility access.

File access comes from files you choose, copy, or drop, and the app can export images to Downloads. Launch at login is optional and can be disabled in Kopy or System Settings.

## Support and changes

For privacy questions, email **karthiknadar1204@gmail.com**. Do not include clipboard contents, passwords, or private files in a public GitHub issue.

We update this policy when Kopy's data handling changes. The effective date at the top records the latest revision.
