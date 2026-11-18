import AppKit
import CryptoKit
import KopyCore
import Testing
@testable import KopyApp

@MainActor
@Suite("Written snippets")
struct SnippetTests {
    @Test("Saving a multiline snippet pins it durably and leaves the clipboard untouched")
    func savesSnippet() async throws {
        try await withModel { model, profile, board in
            let value = "  First fixture line 👋\nSecond fixture line\n"
            let generation = board.changeCount
            model.beginSnippet()
            model.updateSnippetDraft(value)
            model.shelfClosed()
            #expect(model.snippetDraft?.text == value)
            model.saveSnippet()
            model.saveSnippet()
            model.cancelSnippet()
            try await wait { model.importRevision == 1 }

            let item = try #require(model.items.first)
            #expect(model.snippetDraft == nil)
            #expect(!model.isSavingSnippet)
            #expect(item.payload == .text(ClipboardText(value)))
            #expect(item.pinned)
            #expect(item.copyCount == 1)
            #expect(model.items.count == 1)
            #expect(model.importFilter == .text)
            #expect(model.expandedPinnedFilters.contains(ClipboardFilter.text.rawValue))
            #expect(model.preferences.incognito)
            #expect(board.changeCount == generation)
            #expect(board.string(forType: .string) == "Untouched clipboard fixture")

            let reopened = try store(at: profile)
            #expect(await reopened.snapshot() == model.items)
            #expect(try await reopened.clear([item.id]).count == 1)
        }
    }

    @Test("Editing replaces the original card and preserves its notes, pin choice, and copy count")
    func editsInPlace() async throws {
        try await withModel { model, profile, board in
            model.beginSnippet()
            model.updateSnippetDraft("Original editable fixture")
            model.saveSnippet()
            try await wait { model.importRevision == 1 }
            let original = try #require(model.items.first)
            model.pin(original)
            model.editNote(original)
            model.updateNoteDraft("Keep this note")
            model.finishNote(saving: true)
            model.copy(original)
            try await wait { model.items.first?.copyCount == 2 && model.items.first?.note == "Keep this note" }

            model.editSnippet(original)
            #expect(model.snippetDraft?.itemID == original.id)
            #expect(model.snippetDraft?.text == "Original editable fixture")
            let edited = "Updated fixture 👋\nwith a second line."
            model.updateSnippetDraft(edited)
            model.saveSnippet()
            model.saveSnippet()
            try await wait { model.importRevision == 2 }

            let item = try #require(model.items.first)
            #expect(model.items.count == 1)
            #expect(item.id == original.id)
            #expect(item.payload == .text(ClipboardText(edited)))
            #expect(!item.pinned)
            #expect(item.note == "Keep this note")
            #expect(item.copyCount == 2)
            #expect(!item.matches("Original editable", filter: .text))

            board.clearContents()
            try #require(board.setString(edited, forType: .string))
            model.pasteClipboard(into: .text)
            try await wait { model.importRevision == 3 }
            #expect(model.items.count == 1)
            #expect(model.items.first?.id == original.id)
            #expect(model.items.first?.copyCount == 3)
            let reopened = try store(at: profile)
            #expect(await reopened.snapshot() == model.items)
        }
    }

    @Test("An edit that matches another item keeps both originals and retains the draft")
    func duplicateEditKeepsOriginals() async throws {
        try await withModel { model, _, _ in
            model.beginSnippet()
            model.updateSnippetDraft("First fixture")
            model.saveSnippet()
            try await wait { model.importRevision == 1 }
            let first = try #require(model.items.first)
            model.beginSnippet()
            model.updateSnippetDraft("Second fixture")
            model.saveSnippet()
            try await wait { model.importRevision == 2 }
            let before = model.items

            model.editSnippet(first)
            model.updateSnippetDraft("Second fixture")
            model.saveSnippet()
            try await wait { !model.isSavingSnippet && model.message != nil }
            #expect(model.items == before)
            #expect(model.importRevision == 2)
            #expect(model.snippetDraft?.itemID == first.id)
            #expect(model.snippetDraft?.text == "Second fixture")
            model.cancelSnippet()
            #expect(model.snippetDraft == nil)
            #expect(model.items == before)
        }
    }

    @Test("Empty and oversized drafts cannot save, and Cancel creates no history item")
    func validationAndCancel() async throws {
        try await withModel { model, _, _ in
            model.beginSnippet()
            #expect(!model.canSaveSnippet)
            model.updateSnippetDraft(" \n\t ")
            model.saveSnippet()
            #expect(!model.isSavingSnippet)
            #expect(!model.canSaveSnippet)
            model.updateSnippetDraft(String(repeating: "x", count: 500_001))
            model.saveSnippet()
            #expect(!model.canSaveSnippet)
            model.updateSnippetDraft("A discarded fixture")
            #expect(model.canSaveSnippet)
            model.cancelSnippet()
            #expect(model.snippetDraft == nil)
            #expect(model.items.isEmpty)
            #expect(model.importRevision == 0)
        }
    }

    @Test("A failed database save keeps the complete draft available")
    func failedSaveRetainsDraft() async throws {
        try await withModel { model, profile, _ in
            let newerSession = try store(at: profile)
            _ = try await newerSession.capture(.text(ClipboardText("Newer session fixture")), preferences: .init())
            model.beginSnippet()
            model.updateSnippetDraft("Keep this unsaved fixture\nwith its second line.")
            let draft = model.snippetDraft
            model.saveSnippet()
            try await wait { !model.isSavingSnippet && model.message != nil }

            #expect(model.snippetDraft == draft)
            #expect(model.canSaveSnippet)
            #expect(model.importRevision == 0)
            #expect(model.items.isEmpty)
            #expect(await newerSession.snapshot().count == 1)
        }
    }

    private func withModel(_ check: @MainActor (KopyModel, URL, NSPasteboard) async throws -> Void) async throws {
        let profile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let board = NSPasteboard.withUniqueName()
        let model = KopyModel(isolatedProfile: profile, clipboard: ClipboardController(pasteboard: board))
        defer {
            model.stop()
            board.releaseGlobally()
            model.defaults.removePersistentDomain(forName: "Kopy.Test.\(profile.lastPathComponent)")
            try? FileManager.default.removeItem(at: profile)
        }
        try #require(board.setString("Untouched clipboard fixture", forType: .string))
        model.updatePreferences { $0.incognito = true }
        model.start()
        try await wait { !model.isLoadingHistory }
        try await check(model, profile, board)
    }

    private func store(at profile: URL) throws -> HistoryStore {
        let key = SymmetricKey(data: SHA256.hash(data: Data(profile.resolvingSymlinksInPath().path.utf8)))
        return try HistoryStore(databaseURL: profile.appending(path: "History.sqlite3"), encryptionKey: key)
    }

    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}
