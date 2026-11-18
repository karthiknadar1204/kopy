import AppKit
import KopyCore
import SwiftUI
import Testing
@testable import KopyApp

@MainActor
@Suite("Shelf input")
struct ShelfInputTests {
    @Test("The edge handle and drop sensor are available on every desktop")
    func edgeWindowsFollowDesktopSwitches() throws {
        _ = NSApplication.shared
        let previous = Set(NSApp.windows.map(ObjectIdentifier.init))
        let shelf = EdgeShelfWindow(content: EmptyView())
        var preferences = ShelfPreferences()
        preferences.suppressFullscreen = false
        preferences.soundEffects = false
        shelf.update(preferences)
        shelf.start()
        defer { shelf.stop() }

        let windows = NSApp.windows.filter { !previous.contains(ObjectIdentifier($0)) }
        let handle = try #require(windows.first { $0.title == "Kopy Edge Handle" })
        let sensor = try #require(windows.first { $0.title == "Kopy Edge Sensor" })
        for window in [handle, sensor] {
            #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
            #expect(!window.collectionBehavior.contains(.moveToActiveSpace))
            #expect(!window.hidesOnDeactivate)
        }
        let panel = try #require(windows.first { $0.title == "Kopy Shelf" })
        #expect(panel.collectionBehavior.contains(.moveToActiveSpace))
    }

    @Test("An incoming drag cannot give the shelf keyboard focus")
    func incomingDragKeepsSourceKeyboardControl() {
        _ = NSApplication.shared
        let panel = ShelfPanel()
        let model = KopyModel(demo: true)
        model.keyboardEntryChanged = { panel.keyboardEntryEnabled = $0 }

        model.setKeyboardEntry(true)
        #expect(panel.canBecomeKey)

        model.isDropTargeted = true
        #expect(!panel.canBecomeKey)
        model.setKeyboardEntry(true)
        #expect(!panel.canBecomeKey)

        model.isDropTargeted = false
        #expect(!panel.canBecomeKey)
        model.setKeyboardEntry(true)
        #expect(panel.canBecomeKey)
    }
}
