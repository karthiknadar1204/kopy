import AppKit
import Foundation
import KopyCore
import Testing
@testable import KopyApp

@MainActor
struct DeletionUndoTests {
    @Test("Delete and clear publish recoverable actions and Undo leaves a newer clipboard untouched")
    func modelRecovery() async throws {
        let profile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let board = NSPasteboard.withUniqueName()
        let model = KopyModel(isolatedProfile: profile, clipboard: ClipboardController(pasteboard: board))
        defer {
            model.stop()
            board.releaseGlobally()
            model.defaults.removePersistentDomain(forName: "Kopy.Test.\(profile.lastPathComponent)")
            try? FileManager.default.removeItem(at: profile)
        }
        model.updatePreferences { $0.incognito = true }
        model.start()
        model.importPayloads([.text(.init("First undo fixture")), .text(.init("Second undo fixture"))])
        try await wait { model.importRevision == 1 }
        let before = model.items
        model.delete(before[0])
        try await wait { model.items.count == 1 && model.undoAction == .delete }
        model.clear(model.items)
        try await wait { model.items.isEmpty && model.undoAction == .clear }
        try #require(board.setString("Newer clipboard fixture", forType: .string))
        let generation = board.changeCount

        model.undoDeletion()
        model.undoDeletion()
        try await wait { model.items.count == 1 && model.importRevision == 2 }
        #expect(model.undoAction == .delete)
        #expect(model.importFocusID == before[1].id)
        model.undoDeletion()
        try await wait { model.importRevision == 3 && model.undoAction == nil }
        #expect(model.items == before)
        #expect(model.importFocusID == before[0].id)
        #expect(board.changeCount == generation)
        #expect(board.string(forType: .string) == "Newer clipboard fixture")
        #expect(model.importFilter == .all)
        #expect(!model.isUndoingDeletion)
    }

    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
}
