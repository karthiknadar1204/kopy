# Mac verification record

Checked on November 18, 2026, on macOS 27.2.1. These checks used disposable content, an isolated direct-build history, and a separate sandbox container. The normal Store Preview history was not used for destructive tests. Both builds were ad hoc signed.

## Checks through the app

| Check | Observed result |
| --- | --- |
| Write and edit a snippet | A multiline snippet retained Unicode text. Editing kept the same card ID and pin without creating a duplicate. |
| Editor shortcuts | Command-A replaced the selected text. Command-Z restored the previous draft without invoking history recovery. |
| Direct link entry | Command-V in Links added a URL without Import clipboard. |
| Link actions | Open link opened the original URL, including its tracking parameters. Copy clean link removed tracking parameters and kept an unrelated query parameter. |
| Notes and search | A saved note matched search. An unmatched search exposed Clear search, which restored the results. |
| Time filters | Last 24 hours hid the two-day-old fixture. Show all time restored it without deleting it. |
| Pause and explicit import | A new copy was ignored while capture was paused. Import clipboard still added it. |
| Resume capture | A new fixture appeared after capture resumed. Capture was paused again after the check. |
| Colors | A hex value appeared in Colors. Its preview copied the expected RGB string. |
| Large images | Six synthetic 6000 by 4000 images appeared in history. The shelf scrolled and opened their previews. This was not a sustained performance benchmark. |
| Several pending deletions | Two deletions survived a normal quit and relaunch. Undo restored the newest deletion, and Command-Z restored the earlier deletion. Their original IDs returned. |
| Clear history | The confirmation appeared. Pinned snippets and the noted link survived clearing. Undo restored cleared content while keeping a stack imported afterward. |
| Recovery after relaunch | The separate same-day native checks verified delete recovery and clear-history recovery after quitting and reopening. |
| Finder file import | Copying two real Finder files and importing them produced a two-member stack. Both members appeared when expanded. |
| Selected stack transfer | Copy selection transferred only the cobalt fixture to Finder. Its contents matched the source bytes. |
| Rich and plain text | Manual paste into TextEdit preserved the fixture's bold 24-point formatting. Shift-click produced only plain text, which pasted using the destination's regular 12-point style. |
| Appearance and placement | Top-edge layout displayed the image cards horizontally. Left and right placement controls responded. Compact rows and large text persisted across relaunch. |
| Shortcut settings | Recording Control-Option-B changed the shortcut. Reset restored Control-Option-V. A physical global-key check remains pending. |
| Permission navigation | In the rebuilt direct app, Allow automatic paste opened Device Control and Data Access in System Settings from another settings pane. |
| Store consent | The fresh sandbox instance started paused with Enable clipboard history and a Privacy Policy link. Enabling history captured a subsequent fixture. Capture was then paused again. |
| Store manual paste | Clicking a Store card copied its exact text. Command-V pasted that text into the disposable TextEdit document. Store settings explained manual paste and exposed no automatic-paste permission request. |
| Welcome tour | All eight Store tour pages and Done worked. The corrected collect and preview pages described copy followed by manual Command-V. Direct-build practice examples also responded. |
| Emoji | An unmatched query exposed Clear search. Searching for rocket found the emoji and copied the correct glyph. |

## Automated and rendered checks

- `swift test` passed all 77 tests after the fixes. This includes history persistence, recovery transactions, file transfers, lifecycle state, shortcut registration, and localization resources.
- `Scripts/build-app.sh release` built and verified the direct bundle.
- `Scripts/build-store-preview.sh` built the sandbox bundle and passed its signature, entitlement, and resource checks.
- `Tests/LocalizationVisual/run.sh OUTPUT_DIRECTORY` rendered shelf and Behavior settings views for all 31 languages. The render review included right-to-left layouts.
- The two new Store tour instructions exist in all 31 language catalogs. Every catalog passed property-list validation and the localization tests. The corrected tour was exercised in English in the sandbox app.

The commands used `DEVELOPER_DIR=/Library/Developer/CommandLineTools` on this Mac.

## Issues corrected

Allow automatic paste previously left its explanatory message on the hidden shelf when permission remained denied. The direct build now opens the relevant System Settings pane.

The Store tour previously described automatic cross-app paste. Its collect and preview instructions now explain copying and manual Command-V. The direct-build instructions retain their automatic-paste behavior.

## Checks that still need physical input

| Check | Required observation |
| --- | --- |
| Finder drops onto the closed shelf | Hold a real file drag at the middle of the configured edge. The shelf opens and accepts the released file. Repeat with the shelf already open. |
| Native drag-out | Transfer a managed image, a file, and an individual stack selection into Finder or another app. Verify the received contents. |
| File promises and cancellation | Drop a promised file from an app that produces one. Press Escape while holding a drag and verify that Kopy retains the source item. |
| Direct automatic paste | After macOS grants event-posting access to the signed direct build, verify ordinary click-to-paste and paste after search in TextEdit. Repeat with Shift-click. |
| Physical shortcut | With another app focused, verify that the old shortcut stops working after rebinding and the new shortcut opens the shelf. |
| Fullscreen and Spaces | With fullscreen suppression enabled, enter and leave a fullscreen app and switch Spaces. Verify suppression and subsequent recovery. |
| Sleep and wake | Sleep, wake, unlock, and verify capture, opening the shelf, and the shortcut. |
| Launch after login | Enable Launch at login and sign out and back into macOS. Verify automatic launch. |
| Physical display changes | Connect a second display, place Kopy there, disconnect it, and reconnect it. Verify fallback and return. |

The native drag tool returned `noWindowsAvailable` even in a Finder-only control test, so its drag attempts do not establish a Kopy failure or a pass. During the automatic-paste check, macOS still reported event-posting access denied despite an enabled permission entry. No permission check was bypassed. Both Kopy permission switches were off at cleanup.

These checks do not establish App Store approval or replace testing the final distribution-signed build.

## App-switch and drag follow-up

The user reported completing most manual checks, with launch after login still untested. Two failures remained: Escape did not cancel a drag, and the small gray edge handle disappeared after browser switches.

The input regression reproduced the shelf accepting keyboard focus during an incoming drag. The model now releases its keyboard focus when a drag enters and rejects new keyboard-focus requests until the drag leaves or ends.

The edge-window regression caught the handle and sensor using `moveToActiveSpace`. Both now use `canJoinAllSpaces`. The shelf panel retains `moveToActiveSpace` and its existing auto-hide behavior. App activation refreshes the edge windows, and that refresh restores handle ordering even when its drawing has not changed.

All 79 tests passed after these changes. The direct release bundle and sandbox preview both built successfully.

The user physically dragged a promised file to the shelf, pressed Escape while holding the drag, and released the mouse. They confirmed cancellation without an added item. The source recorded drag operation `0` and never received a file-write request. A read of the isolated profile's persisted history also confirmed that the uniquely named canceled file was absent.

The handle remained discoverable as a native window after Chrome and Safari app switches during the live session. Confirmation of its visible appearance across the user's browser windows is pending. Launch after a fresh macOS login remains untested.
