# Kopy

Kopy is a macOS clipboard shelf. It targets macOS 14 and later and builds with Swift 6.1 and the macOS SDK. Use the project skills in `.agents/skills/` for SwiftUI, concurrency, interface design, and verification. Check API availability against this project's deployment target and SDK.

- `Sources/KopyCore` owns clipboard data, presentation rules, and the encrypted history store.
- `Sources/KopyApp/Application` owns lifecycle, settings, and coordination across app operations.
- `Sources/KopyApp/Platform` owns AppKit, pasteboard, key posting, file handoffs, and windows.
- `Sources/KopyApp/Interface` owns SwiftUI views and transient presentation state.
- `Tests` covers history invariants and AppKit pasteboard behavior. Run `swift test`. Build the local bundle with `Scripts/build-app.sh`.

Use fixture content for tests. Keep real desktop history and source files outside test fixtures. Verify keyboard handoff and native drags on a Mac before making claims about those workflows.
