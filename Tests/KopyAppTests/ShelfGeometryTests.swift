import AppKit
import KopyCore
import Testing
@testable import KopyApp

@Suite("Shelf geometry")
struct ShelfGeometryTests {
    @MainActor
    @Test("An edge panel can take keyboard focus only during explicit text entry")
    func optInKeyboardFocus() {
        _ = NSApplication.shared
        let panel = ShelfPanel()
        #expect(!panel.canBecomeKey)
        panel.keyboardEntryEnabled = true
        #expect(panel.canBecomeKey)
        panel.keyboardEntryEnabled = false
        #expect(!panel.canBecomeKey)
    }

    @Test("The configured side trigger stays on its assigned display")
    func sideTriggerOnNegativeDisplay() {
        var preferences = ShelfPreferences()
        preferences.edgeThickness = 7
        preferences.edgeSpan = 0.4
        let area = CGRect(x: -1_440, y: 40, width: 1_440, height: 860)
        let geometry = ShelfGeometry(edge: .left, workArea: area)
        let trigger = geometry.trigger(preferences)
        #expect(trigger.minX == area.minX)
        #expect(trigger.width == 7)
        #expect(trigger.midY == area.midY)
        #expect(geometry.intoScreen(CGPoint(x: -1_441, y: area.midY)) < 0)
        #expect(geometry.shelf(preferences).minX == area.minX)
    }

    @Test("The top trigger and panel align below reserved screen space")
    func topTriggerRespectsWorkArea() {
        var preferences = ShelfPreferences()
        preferences.edge = .top
        preferences.edgeAlignment = 1
        let area = CGRect(x: 0, y: 52, width: 1_280, height: 710)
        let geometry = ShelfGeometry(edge: .top, workArea: area)
        let trigger = geometry.trigger(preferences)
        #expect(trigger.maxX == geometry.shelf(preferences).maxX)
        #expect(trigger.maxY == area.maxY)
        #expect(trigger.width == 275)
        #expect(geometry.shelf(preferences).maxY == area.maxY)
        #expect(geometry.intoScreen(CGPoint(x: 1_200, y: 780)) < 0)
    }

    @Test("An adjusted side trigger follows its shelf and the chosen alignment")
    func triggerFollowsPanel() {
        var preferences = ShelfPreferences()
        preferences.offset = 0.85
        let geometry = ShelfGeometry(edge: .right, workArea: CGRect(x: 500, y: 40, width: 1_440, height: 860))
        let panel = geometry.shelf(preferences)
        preferences.edgeAlignment = 0
        #expect(geometry.trigger(preferences).minY == panel.minY)
        preferences.edgeAlignment = 1
        #expect(geometry.trigger(preferences).maxY == panel.maxY)
        #expect(geometry.trigger(preferences).height == 215)
        let trigger = geometry.trigger(preferences)
        #expect(geometry.retractedFrame(for: panel, toward: trigger) == trigger)
    }

    @Test("Closed shelf accepts a drag inside its wider catch on its own display")
    func dragCatchOnAssignedScreen() {
        let area = CGRect(x: -1_440, y: 40, width: 1_440, height: 860)
        let side = ShelfGeometry(edge: .left, workArea: area)
        let sideTrigger = side.trigger(ShelfPreferences())
        let catchFrame = side.dragCatch(sideTrigger)
        #expect(catchFrame.width == 48)
        #expect(catchFrame.minY == sideTrigger.minY - 24)
        #expect(catchFrame.maxY == sideTrigger.maxY + 24)
        #expect(!catchFrame.contains(CGPoint(x: area.minX - 1, y: sideTrigger.midY)))
        let top = ShelfGeometry(edge: .top, workArea: area)
        #expect(top.dragCatch(top.trigger(ShelfPreferences())).height == 40)
    }

    @Test("Hover adds the configured delay and a click resets the dwell")
    func userDelayAndClickReset() {
        var intent = ShelfPointerIntent()
        let geometry = ShelfGeometry(edge: .left, workArea: CGRect(x: 0, y: 0, width: 1_200, height: 800))
        let trigger = geometry.trigger(ShelfPreferences())
        let atEdge = CGPoint(x: 1, y: trigger.midY)
        let origin = ContinuousClock.now

        func open(_ milliseconds: Int, pressed: Bool = false) -> Bool {
            intent.shouldOpen(at: atEdge, now: origin.advanced(by: .milliseconds(milliseconds)),
                              geometry: geometry, trigger: trigger, buttonPressed: pressed, delay: .milliseconds(50))
        }

        #expect(!open(0))
        #expect(!open(89))
        #expect(open(90))
        #expect(!open(93, pressed: true))
        #expect(!open(100))
        #expect(open(190))
    }

    @Test("A fast display crossing arms only after three parked samples and a full dwell")
    func monitorSeamRest() {
        var intent = ShelfPointerIntent()
        let geometry = ShelfGeometry(edge: .left, workArea: CGRect(x: 0, y: 0, width: 1_200, height: 800))
        let trigger = geometry.trigger(ShelfPreferences())
        let origin = ContinuousClock.now

        func open(_ x: Double, _ milliseconds: Int) -> Bool {
            intent.shouldOpen(at: CGPoint(x: x, y: trigger.midY), now: origin.advanced(by: .milliseconds(milliseconds)),
                              geometry: geometry, trigger: trigger, buttonPressed: false, delay: .zero)
        }

        #expect(!open(-50, 0))
        #expect(!open(1, 16))
        #expect(!open(1, 32))
        #expect(!open(1, 48))
        #expect(!open(1, 64))
        #expect(!open(1, 103))
        #expect(open(1, 104))
    }

    @Test("The drag swell changes in three steps and settles without flicker near a boundary")
    func dragPullHysteresis() {
        var intent = ShelfPointerIntent()
        #expect(intent.dragCueStep(pull: 0.27) == 0)
        #expect(intent.dragCueStep(pull: 0.35) == 1)
        #expect(intent.dragCueStep(pull: 0.59) == 1)
        #expect(intent.dragCueStep(pull: 0.62) == 2)
        #expect(intent.dragCueStep(pull: 0.92) == 3)
        #expect(intent.dragCueStep(pull: 0) == 0)
    }

    @Test("Existing preferences keep Modern cards and independent top placement")
    func preferencesCompatibility() throws {
        var preferences = ShelfPreferences()
        preferences.offset = 0.8
        let previous = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(ShelfPreferences.self, from: previous)
        #expect(decoded.cardDensity == .modern)
        #expect(decoded.horizontalOffset == 0.5)
        #expect(decoded.offset == 0.8)
        preferences.cardDensity = .compact
        preferences.horizontalOffset = 0.2
        let saved = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(ShelfPreferences.self, from: saved)
        #expect(restored.cardDensity == .compact)
        #expect(restored.horizontalOffset == 0.2)
        #expect(restored.offset == 0.8)
    }

    @Test("Every interaction cue decodes as a distinct, short macOS sound")
    @MainActor func soundsDecode() throws {
        var clips: Set<Data> = []
        for cue in ShelfSound.allCases {
            let data = cue.wave
            #expect(clips.insert(data).inserted)
            let sound = try #require(NSSound(data: data))
            #expect(sound.duration > 0)
            #expect(sound.duration < 0.3)
        }
    }

    @Test("The four copy-indicator settings use distinguishable glyphs")
    @MainActor func copyIndicatorSymbols() throws {
        var symbols: Set<String> = []
        for style in CopyIndicatorStyle.allCases {
            let symbol = try #require(ShelfBeacon.Cue.copied(style).symbol)
            #expect(symbols.insert(symbol).inserted)
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }
    }
}
