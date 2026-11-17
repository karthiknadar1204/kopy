import AppKit
import CryptoKit
import Foundation
import KopyCore
import Testing
@testable import KopyApp

@MainActor
@Suite("Clipboard transfers")
struct ClipboardTransferTests {
    @Test("Formatted copy retains HTML and plain copy omits it")
    func textRepresentations() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let controller = ClipboardController(pasteboard: board)
        let html = Data("<p><b>rich text</b></p>".utf8)
        let payload = ClipboardPayload.text(ClipboardText("rich text", html: html))

        _ = try controller.copy(payload)
        #expect(board.string(forType: .string) == "rich text")
        #expect(board.data(forType: .html) == html)
        #expect(controller.ownsLastWrite)

        _ = try controller.copy(payload, plain: true)
        #expect(board.string(forType: .string) == "rich text")
        #expect(board.data(forType: .html) == nil)
    }

    @Test("A newer copy survives an obsolete delete or paste request")
    func newerClipboardContent() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let controller = ClipboardController(pasteboard: board)
        let payload = ClipboardPayload.text(ClipboardText("original text"))
        let previous = try controller.copy(payload)
        try externalCopy("new external copy", to: board)

        controller.clearIfOwned(generation: previous)
        let outcome = try await controller.paste(
            payload, target: nil, expectedGeneration: previous, mayRestoreFocus: false
        )
        #expect(outcome == .clipboardChanged)
        #expect(board.string(forType: .string) == "new external copy")
        #expect(!controller.ownsLastWrite)
    }

    @Test("Spreadsheet cells retain empty columns and ordinary and plain paste stay distinguishable")
    func tableRoundTrip() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        let cells = "\t<Tom & Jerry>\n100\t"
        try #require(item.setString(cells + "\n", forType: .tabularText))
        try #require(item.setString("<div>Other apps use their own wrapper</div>", forType: .html))
        try #require(board.writeObjects([item]))
        let controller = ClipboardController(pasteboard: board)
        let captured = try #require(controller.importCurrent())
        guard case .text(let text) = captured else { Issue.record("Spreadsheet captured as a bitmap"); return }
        #expect(text.value == cells)

        _ = try controller.copy(captured)
        #expect(board.string(forType: .string) == "\t<Tom & Jerry>\r\n100\t")
        #expect(board.string(forType: .tabularText) == board.string(forType: .string))
        #expect(board.string(forType: .html)?.contains("<tr><td></td><td>&lt;Tom &amp; Jerry&gt;</td></tr>") == true)
        #expect(board.string(forType: .html)?.contains("<tr><td>100</td><td></td></tr>") == true)
        _ = try controller.copy(captured, plain: true)
        #expect(board.data(forType: .rtf) == nil)
        #expect(board.data(forType: .html) == nil)
        #expect(board.data(forType: .tabularText) == nil)
        #expect(board.string(forType: .string) == "\t<Tom & Jerry>\r\n100\t")
        let large = ClipboardPayload.text(ClipboardText(Array(repeating: "A\tB", count: 42).joined(separator: "\n")))
        _ = try controller.copy(large)
        #expect(board.data(forType: .html) == nil)
    }

    @Test("A copied HTML anchor gives the matching link a searchable title")
    func titleFromBrowserAnchor() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        try #require(item.setString("https://github.com/apple/swift/issues/500", forType: .string))
        try #require(item.setString("""
            <a href="https://different.example/another">Different link</a>
            <a class="link" href="https://github.com/apple/swift/issues/500"><b>Fast</b> &amp; safe</a>
            """, forType: .html))
        try #require(board.writeObjects([item]))
        let controller = ClipboardController(pasteboard: board)
        let captured = try #require(controller.importCurrent())
        guard case .text(let text) = captured else { Issue.record("Link captured with the wrong format"); return }
        #expect(text.title == "Fast & safe")
        #expect(ClipboardItem(payload: captured).matches("fast safe", filter: .links))
    }

    @Test("Dropped embedded image bytes become an image and malformed image URLs create no card")
    func embeddedImageDrop() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/nroAAAAASUVORK5CYII="
        try externalCopy("data:image/png;base64,\(base64)", to: board)
        let controller = ClipboardController(pasteboard: board)
        var received: [ClipboardPayload] = []
        #expect(controller.receiveDrop(board) { received.append(contentsOf: $0) })
        let payload = try #require(received.first)
        guard case .image(let image) = payload else { Issue.record("Didn't retain original image data"); return }
        #expect(image.data == Data(base64Encoded: base64))
        #expect(image.width == 1 && image.height == 1)
        try externalCopy("data:image/png;base64,invalid", to: board)
        #expect(!controller.receiveDrop(board) { received.append(contentsOf: $0) })
        #expect(received.count == 1)
    }

    @Test("A clipboard screenshot keeps native pixels and a friendly named file across copy and drag")
    func screenshotRepresentations() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/nroAAAAASUVORK5CYII="))
        let item = NSPasteboardItem()
        try #require(item.setData(png, forType: .png))
        try #require(board.writeObjects([item]))
        let controller = ClipboardController(pasteboard: board)
        let payload = try #require(controller.importCurrent())
        guard case .image(let image) = payload else { Issue.record("Clipboard PNG was not an image"); return }
        #expect(image.source == .screenshot)
        #expect(image.data == png)
        let date = Date(timeIntervalSince1970: 1_731_234_567)
        _ = try controller.copy(payload, capturedAt: date)
        let copyPath = try #require(board.string(forType: .fileURL).flatMap(URL.init(string:)))
        defer { try? FileManager.default.removeItem(at: copyPath.deletingLastPathComponent()) }
        #expect(copyPath.lastPathComponent.hasPrefix("Screenshot "))
        #expect(copyPath.pathExtension == "png")
        #expect(board.data(forType: .png) == png)
        #expect(try Data(contentsOf: copyPath) == png)

        let dragging = try #require(controller.dragItems(payload, capturedAt: date).first?.item as? NSPasteboardItem)
        let dragPath = try #require(dragging.string(forType: .fileURL).flatMap(URL.init(string:)))
        defer { try? FileManager.default.removeItem(at: dragPath.deletingLastPathComponent()) }
        #expect(dragPath.lastPathComponent == copyPath.lastPathComponent)
        #expect(try Data(contentsOf: dragPath) == png)
    }

    @Test("Promised documents remain readable after the receiver's temporary files are removed")
    func promisingFiles() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appending(path: "Promised notes.txt")
        let contents = Data("check the exact original bytes of this promised file".utf8)
        try contents.write(to: document)
        let file = try #require(TransferPromiseBatch.read(document, in: root))
        #expect(!FileManager.default.fileExists(atPath: document.path))
        guard case .file(let promised) = file else { Issue.record("Generic document dropped as an image"); return }
        #expect(promised.attachment == contents)
        let key = SymmetricKey(size: .bits256)
        let path = root.appending(path: "History.sqlite")
        let store = try HistoryStore(databaseURL: path, encryptionKey: key)
        _ = try await store.importPayloads([file.payload], preferences: .init())
        #expect(try Data(contentsOf: path).range(of: contents) == nil)
        let restored = try HistoryStore(databaseURL: path, encryptionKey: key)
        let payload = try #require(await restored.snapshot().first?.payload)
        let controller = ClipboardController(pasteboard: board)
        _ = try controller.copy(payload)
        let pathOnBoard = try #require(board.string(forType: .fileURL).flatMap(URL.init(string:)))
        defer { try? FileManager.default.removeItem(at: pathOnBoard.deletingLastPathComponent()) }
        #expect(pathOnBoard.lastPathComponent == "Promised notes.txt")
        #expect(try Data(contentsOf: pathOnBoard) == contents)
    }

    @Test("A valid owned generation can be cleared")
    func clearOwnedWrite() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let controller = ClipboardController(pasteboard: board)
        let written = try controller.copy(.text(ClipboardText("selected text")))
        controller.clearIfOwned(generation: written)

        #expect(board.string(forType: .string) == nil)
    }

    @Test("Paste without a destination leaves the selected text ready to paste")
    func manualPasteFallback() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let controller = ClipboardController(pasteboard: board)
        let outcome = try await controller.paste(
            .text(ClipboardText("selected text")), target: nil, expectedGeneration: controller.generation,
            mayRestoreFocus: false
        )
        #expect(outcome == .copiedForManualPaste)
        #expect(board.string(forType: .string) == "selected text")
    }

    @Test("Concealed pasteboard content is excluded")
    func excludesConcealedContent() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let item = NSPasteboardItem()
        try #require(item.setString("test private text", forType: .string))
        try #require(item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")))
        try #require(board.writeObjects([item]))

        let controller = ClipboardController(pasteboard: board)
        #expect(controller.importCurrent() == nil)
    }

    @Test("File pasteboard and native stack drag preserve original file references")
    func preservesOriginalFiles() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let testFolder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: testFolder) }

        let files = [testFolder.appending(path: "First.txt"), testFolder.appending(path: "Second.txt")]
        try Data("first file".utf8).write(to: files[0])
        try Data("second file".utf8).write(to: files[1])
        let controller = ClipboardController(pasteboard: board)
        let payload = ClipboardPayload.files(files.map { .file(ClipboardFile(url: $0)) })
        let expected = files.map { $0.resolvingSymlinksInPath() }

        _ = try controller.copy(payload)
        let imported = try #require(controller.importCurrent())
        let importedURLs = imported.members.compactMap {
            if case .file(let file) = $0 { return file.url.resolvingSymlinksInPath() }
            return nil
        }
        #expect(importedURLs == expected)

        let token = Data("individual native drag session 38AE".utf8)
        let dragItems = try controller.dragItems(payload, internalToken: token)
        let draggingURLs = dragItems.compactMap { item in
            (item.item as? NSPasteboardItem)?.string(forType: .fileURL)
                .flatMap { URL(string: $0)?.resolvingSymlinksInPath() }
        }
        #expect(draggingURLs == expected)
        let dragWriters = dragItems.compactMap { $0.item as? NSPasteboardItem }
        #expect(dragWriters.allSatisfy { $0.data(forType: ClipboardPayloadCodec.internalDrag) == token })
        let dragBoard = NSPasteboard.withUniqueName()
        defer { dragBoard.releaseGlobally() }
        try #require(dragBoard.writeObjects(dragWriters))
        #expect(dragBoard.data(forType: ClipboardPayloadCodec.internalDrag) == token)
        #expect(!controller.receiveDrop(dragBoard) { _ in Issue.record("Native drag reimported the app's own files") })
        #expect(try String(contentsOf: files[0], encoding: .utf8) == "first file")
    }

    @Test("A renamed original stays available to Finder paste")
    func resolvesRenamedOriginal() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "Original.txt")
        let renamed = folder.appending(path: "Renamed.txt")
        try Data("same file".utf8).write(to: original)
        let controller = ClipboardController(pasteboard: board)
        _ = try controller.copy(.files([.file(ClipboardFile(url: original))]))
        let captured = try #require(controller.importCurrent())

        try FileManager.default.moveItem(at: original, to: renamed)
        _ = try controller.copy(captured)
        let newLocation = board.string(forType: .fileURL).flatMap(URL.init(string:))
        #expect(newLocation?.resolvingSymlinksInPath() == renamed.resolvingSymlinksInPath())
    }

    @Test("Capture ignores the app's writes and resumes after incognito")
    func captureOwnershipAndIncognito() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let controller = ClipboardController(pasteboard: board)
        var captured: [ClipboardPayload] = []
        controller.start { captured.append($0) }
        defer { controller.stop() }

        _ = try controller.copy(.text(ClipboardText("Kopy wrote this")))
        try await Task.sleep(for: .milliseconds(500))
        #expect(captured.isEmpty)

        try externalCopy("captured external text", to: board)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while captured.isEmpty, .now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(captured == [.text(ClipboardText("captured external text"))])

        controller.isPaused = true
        try externalCopy("incognito text", to: board)
        try await Task.sleep(for: .milliseconds(500))
        controller.isPaused = false
        try await Task.sleep(for: .milliseconds(500))
        #expect(captured.count == 1)
    }

    private func externalCopy(_ value: String, to board: NSPasteboard) throws {
        let fresh = NSPasteboardItem()
        try #require(fresh.setString(value, forType: .string))
        board.clearContents()
        try #require(board.writeObjects([fresh]))
    }
}
