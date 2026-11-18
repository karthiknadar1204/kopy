# Kopy support

Kopy is a macOS clipboard shelf. For help or privacy questions, email **karthiknadar1204@gmail.com**.

To report a reproducible issue, open [a GitHub issue](https://github.com/karthiknadar1204/kopy/issues). Public issues can be read by anyone. Remove private clipboard contents, file paths, passwords, and account information before attaching a screenshot or log.

## Open the shelf

Move your pointer to Kopy's configured screen edge. You can also choose Show Shelf from Kopy's menu bar icon or use the shortcut shown in Settings. The default shortcut is Control-Option-V.

## Enable or pause history

The Mac App Store build starts with automatic capture paused. Choose Enable clipboard history on the empty shelf or change Pause automatic capture under Settings and Behavior. You can still use Import clipboard and drop files while capture is paused.

If macOS blocks automatic clipboard access, review Kopy's clipboard permission in System Settings. In the Mac App Store build, select a card and press Command-V in the destination app. The direct build offers Allow automatic paste under Settings and System. If that permission is unavailable, paste manually with Command-V.

## Manage saved items

Delete an item from its menu. Pins and notes protect items from automatic cleanup and bulk clearing. Delete protected items individually when you want to remove them. Review history limits and cleanup under Settings and Behavior.

After deleting or clearing, click Undo in the recovery bar. You can also press Command-Z while the history area has focus or use the Undo action in the history controls. Kopy keeps the last 20 manual delete or clear actions until you quit. Text fields keep their own typing undo. Undo restores the saved items without replacing your current clipboard or removing newer history.

The history controls filter by All time, Last hour, Last 6 hours, or Last 24 hours. Click Show all time to remove a time filter. Clear shown history is a separate action that asks for confirmation.

An original file must remain available to be transferred. If a referenced file moved, was deleted, or is no longer authorized by macOS, drop it onto Kopy again. Kopy retains encrypted contents for supported files supplied through a file promise.

## Include these details in a bug report

- Kopy's version, shown under Settings and System.
- Your macOS version and whether you use the Mac App Store or the direct build.
- Steps that reproduce the issue and what you expected.
- A screenshot with fixture content if it helps explain the issue.

See the [privacy policy](PRIVACY.md) for storage, permissions, network activity, and deletion.
