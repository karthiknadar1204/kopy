import AppKit
import Carbon.HIToolbox
import KopyCore
import Testing
@testable import KopyApp

@Suite("Mac lifecycle")
struct MacLifecycleTests {
    @Test("The shelf falls back when its selected display disconnects and returns when it reconnects")
    func displayReconnect() {
        let main = display(1, at: CGRect(x: 0, y: 0, width: 1_280, height: 832))
        let external = display(2, at: CGRect(x: -1_440, y: 350, width: 1_440, height: 900))
        let reconnected = display(3, at: external.frame)
        var preferences = ShelfPreferences()
        #expect(ShelfDisplay.selected(in: [main, external], for: preferences) == main)
        preferences.displayID = external.id
        preferences.displayBounds = external.frame
        #expect(ShelfDisplay.selected(in: [main, external], for: preferences) == external)
        #expect(ShelfDisplay.selected(in: [main], for: preferences) == main)
        #expect(ShelfDisplay.preferred(in: [main], for: preferences) == nil)
        #expect(ShelfDisplay.selected(in: [], for: preferences) == nil)
        #expect(ShelfDisplay.selected(in: [main, reconnected], for: preferences) == reconnected)
    }

    @MainActor
    @Test("AppKit display dimensions match the Quartz window coordinate space on this Mac")
    func connectedDisplayBounds() throws {
        let displays = ShelfDisplay.connected
        let primary = try #require(displays.first)
        for display in displays {
            let quartz = CGDisplayBounds(display.id)
            #expect(quartz.minX == display.frame.minX)
            #expect(quartz.minY == primary.frame.maxY - display.frame.maxY)
            #expect(quartz.size == display.frame.size)
        }
    }

    @Test("A fullscreen window suppresses its own display without blocking another display")
    func fullscreenUsesTheAssignedDisplay() {
        let main = CGRect(x: 0, y: 0, width: 1_280, height: 832)
        let external = CGRect(x: -1_440, y: -418, width: 1_440, height: 900)
        let maximized = CGRect(x: 0, y: 28, width: main.width, height: main.height - 28)
        let windows = [
            window(maximized, owner: 42), window(main, owner: 10),
            window(main, owner: 23, layer: 5), window(external, owner: 99)
        ]
        #expect(!ShelfDisplay.hasFullscreenWindow(in: windows, displayBounds: main, ignoring: 10))
        #expect(ShelfDisplay.hasFullscreenWindow(in: windows, displayBounds: external, ignoring: 10))
    }

    @Test("Fullscreen detection accounts for the camera housing while leaving room for the dock")
    func fullscreenInTheDisplaySafeArea() {
        let display = CGRect(x: 0, y: 0, width: 1_470, height: 956)
        let fullscreen = CGRect(x: 0, y: 37, width: 1_470, height: 919)
        let maximized = CGRect(x: 0, y: 38, width: 1_470, height: 833)
        #expect(ShelfDisplay.hasFullscreenWindow(in: [window(fullscreen, owner: 42)],
                                                displayBounds: display, safeTopInset: 32, ignoring: 10))
        #expect(!ShelfDisplay.hasFullscreenWindow(in: [window(maximized, owner: 42)],
                                                 displayBounds: display, safeTopInset: 32, ignoring: 10))
    }

    @Test("The shelf resumes only after computer, displays, and user session have all resumed")
    func nestedSuspension() {
        var state = ShelfSuspension()
        #expect(state.handle(NSWorkspace.screensDidWakeNotification) == nil)
        #expect(state.handle(NSWorkspace.screensDidSleepNotification) == true)
        #expect(state.handle(NSWorkspace.sessionDidResignActiveNotification) == nil)
        #expect(state.handle(NSWorkspace.willSleepNotification) == nil)
        #expect(state.handle(NSWorkspace.didWakeNotification) == nil)
        #expect(state.handle(NSWorkspace.screensDidWakeNotification) == nil)
        #expect(state.handle(NSWorkspace.sessionDidBecomeActiveNotification) == false)
        #expect(state.handle(NSWorkspace.sessionDidBecomeActiveNotification) == nil)
    }

    @MainActor
    @Test("Changing Incognito during suspension keeps clipboard capture paused")
    func combinedClipboardPause() {
        let model = KopyModel(demo: true)
        model.suspend(true)
        model.updatePreferences { $0.incognito = true }
        model.updatePreferences { $0.incognito = false }
        #expect(model.clipboard.isPaused)
        model.updatePreferences { $0.incognito = true }
        model.suspend(false)
        #expect(model.clipboard.isPaused)
        model.updatePreferences { $0.incognito = false }
        #expect(!model.clipboard.isPaused)
    }

    @MainActor
    @Test("Carbon retains the old hotkey after a conflict and frees it after a successful replacement")
    func shortcutRebinding() throws {
        _ = NSApplication.shared
        let first = ShelfShortcut(keyCode: UInt32(kVK_F16), modifiers: 14, display: "⌃⌥⇧F16")
        let second = ShelfShortcut(keyCode: UInt32(kVK_F17), modifiers: 14, display: "⌃⌥⇧F17")
        let registration = GlobalShortcut()
        defer { registration.clear() }
        var activations = 0
        try #require(registration.register(first) { activations += 1 })

        let modifiers = UInt32(controlKey | optionKey | shiftKey)
        let target = GetEventDispatcherTarget()
        let testID = EventHotKeyID(signature: 0x54455354, id: 1)
        var reserved: EventHotKeyRef?
        try #require(RegisterEventHotKey(second.keyCode, modifiers, testID, target, 0, &reserved) == noErr)
        defer { if let reserved { UnregisterEventHotKey(reserved) } }
        try postHotKey(testID, to: target)
        #expect(activations == 0)

        #expect(!registration.register(second, action: {}))
        #expect(registration.registeredShortcut == first)
        var probe: EventHotKeyRef?
        defer { if let probe { UnregisterEventHotKey(probe) } }
        #expect(RegisterEventHotKey(first.keyCode, modifiers, testID, target, 0, &probe) != noErr)
        if let reserved { UnregisterEventHotKey(reserved) }
        reserved = nil

        try #require(registration.register(second, action: {}))
        #expect(registration.registeredShortcut == second)
        #expect(RegisterEventHotKey(first.keyCode, modifiers, testID, target, 0, &probe) == noErr)
    }

    private func postHotKey(_ identifier: EventHotKeyID, to target: EventTargetRef?) throws {
        var reference: EventRef?
        try #require(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                 GetCurrentEventTime(), 0, &reference) == noErr)
        let event = try #require(reference)
        defer { ReleaseEvent(event) }
        var id = identifier
        try #require(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                      MemoryLayout<EventHotKeyID>.size, &id) == noErr)
        SendEventToEventTarget(event, target)
    }

    private func display(_ id: UInt32, at frame: CGRect) -> ShelfDisplay {
        ShelfDisplay(id: id, name: "Display \(id)", frame: frame, workArea: frame)
    }

    private func window(_ frame: CGRect, owner: pid_t, layer: Int = 0) -> [String: Any] {
        [kCGWindowOwnerPID as String: owner, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
}
