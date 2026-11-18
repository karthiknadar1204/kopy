import AppKit
import Foundation
import KopyCore
import Testing
@testable import KopyApp

@MainActor
@Suite("Paste into shelf sections")
struct ShelfPasteTests {
    @Test("Pasting into a section reveals the matching item while capture is paused", arguments: [
        ("https://x.com/i/history", ClipboardFilter.links, ClipboardFilter.links),
        ("A paragraph saved directly in Kopy.", .text, .text),
        ("#FF5733", .colors, .colors),
        ("rgb(255, 87, 51)", .links, .colors),
        ("https://example.com/kopy-paste", .all, .all)
    ])
    func sectionPaste(value: String, section: ClipboardFilter, destination: ClipboardFilter) async throws {
        let board = NSPasteboard.withUniqueName()
        let profile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "Kopy.Test.\(profile.lastPathComponent)"
        let model = KopyModel(isolatedProfile: profile, clipboard: ClipboardController(pasteboard: board))
        defer {
            model.stop()
            board.releaseGlobally()
            model.defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: profile)
        }
        model.updatePreferences { $0.incognito = true }
        model.start()
        try #require(board.setString(value, forType: .string))
        model.pasteClipboard(into: section)
        try await waitForImport(1, in: model)

        let item = try #require(model.items.first)
        #expect(model.preferences.incognito)
        #expect(model.importFilter == destination)
        #expect(item.matches("", filter: destination))
        guard case .text(let text) = item.payload else {
            Issue.record("Pasted text changed its payload type")
            return
        }
        #expect(text.value == value)

        model.pasteClipboard(into: section)
        try await waitForImport(2, in: model)
        #expect(model.items.count == 1)
        #expect(model.items.first?.id == item.id)
        #expect(model.importFilter == destination)
    }

    private func waitForImport(_ revision: Int, in model: KopyModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.importRevision < revision && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(model.importRevision == revision)
    }
}
