import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import KopyCore
import SQLite3
import Testing
import UniformTypeIdentifiers

struct HistoryTests {
    @Test
    func aFullHistoryReopensAndStillAcceptsANewCopy() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        var preferences = ShelfPreferences()
        preferences.historyLimit = 1_000
        let store = try fixture.open()
        let inputs: [ClipboardPayload] = try (0..<1_000).map { index in
            if index % 10 == 0 { return .text(ClipboardText("Kopy fixture row \(index)")) }
            if index % 10 == 1 { return .files([testFile(index)]) }
            return .image(try pngFixture(index))
        }
        let before = try await store.importPayloads(inputs, preferences: preferences)
        try #require(before.count == 1_000)
        let restarted = try fixture.open()
        #expect(await restarted.snapshot() == before)
        let after = try await restarted.capture(.text(.init("Latest launch fixture")), preferences: preferences)
        #expect(after.count == 1_000)
        #expect(after.first?.payload == .text(.init("Latest launch fixture")))
        #expect(after.last?.id == before[998].id)
    }

    @Test
    func failureAfterRowChangesRollsBackAndTheSameStoreCanRetry() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let store = try fixture.open()
        var preferences = ShelfPreferences()
        preferences.historyLimit = 50
        let inputs = (0..<50).map { ClipboardPayload.text(.init("Retained item \($0)")) }
        let before = try await store.importPayloads(inputs, preferences: preferences)
        try fixture.sql("""
            CREATE TRIGGER interrupt_commit BEFORE UPDATE ON state
            BEGIN
                SELECT RAISE(ABORT, 'fixture failed before the updated index was committed');
            END;
            """)

        let payload = ClipboardPayload.text(.init("Replacement for the oldest item"))
        await #expect(throws: HistoryError.unreadable) {
            _ = try await store.capture(payload, preferences: preferences)
        }
        #expect(await store.snapshot() == before)
        let interrupted = try fixture.open()
        #expect(await interrupted.snapshot() == before)

        try fixture.sql("DROP TRIGGER interrupt_commit")
        let after = try await store.capture(payload, preferences: preferences)
        #expect(after.count == before.count)
        #expect(after.first?.payload == payload)
        #expect(Array(after.dropFirst()) == Array(before.dropLast()))
        let reopened = try fixture.open()
        #expect(await reopened.snapshot() == after)
    }

    @Test
    func authenticRowsAndNewCopiesSurviveACorruptRecord() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let before = try await fixture.open().importPayloads(
            [.text(.init("First valid fixture")), .text(.init("Damaged fixture")), .text(.init("Last valid fixture"))],
            preferences: .init()
        )
        let removed = before[1].id.uuidString
        try fixture.sql("UPDATE items SET content = X'AABBCC' WHERE id = '\(removed)'")
        let recovered = try fixture.open()
        #expect(recovered.unreadableItemCount == 1)
        #expect(await recovered.snapshot() == [before[0], before[2]])

        _ = try await recovered.capture(.text(.init("New copy after recovery")), preferences: .init())
        let reopened = try fixture.open()
        #expect(reopened.unreadableItemCount == 0)
        #expect(await reopened.snapshot().map(\.displayTitle) == [
            "New copy after recovery", "First valid fixture", "Last valid fixture"
        ])
        #expect(try fixture.scalar("""
            SELECT COUNT(*) FROM unreadable_items WHERE id = '\(removed)' AND content = X'AABBCC'
            """) == 1)
    }

    @Test
    func anUnreadableIndexIsPreservedInsteadOfStartingAnEmptyHistory() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        _ = try await fixture.open().capture(.text(.init("Saved fixture")), preferences: .init())
        try fixture.sql("UPDATE state SET item_order = X'AABBCC' WHERE singleton = 1")
        let damaged = try Data(contentsOf: fixture.url)
        #expect(throws: HistoryError.unreadable) { _ = try fixture.open() }
        #expect(try Data(contentsOf: fixture.url) == damaged)
    }

    @Test
    func sqliteRecoversCommittedHistoryAfterAWriterIsKilled() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let inputs = (0..<50).map { ClipboardPayload.text(.init("Committed item \($0)")) }
        let before = try await fixture.open().importPayloads(inputs, preferences: .init())
        let committedBytes = try Data(contentsOf: fixture.url)
        let ready = fixture.url.deletingLastPathComponent().appending(path: "writer-ready")
        let input = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-batch", "-bail", fixture.url.path]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        let transaction = """
            PRAGMA cache_size = 4;
            PRAGMA cache_spill = 1;
            PRAGMA synchronous = FULL;
            BEGIN IMMEDIATE;
            UPDATE items SET content = randomblob(2048);
            .once "\(ready.path)"
            SELECT 1;

            """
        try input.fileHandleForWriting.write(contentsOf: Data(transaction.utf8))

        let deadline = ContinuousClock.now + .seconds(4)
        while process.isRunning, !FileManager.default.fileExists(atPath: ready.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(process.isRunning)
        try #require(FileManager.default.fileExists(atPath: ready.path))
        try #require(FileManager.default.fileExists(atPath: fixture.url.path + "-journal"))
        try #require(Data(contentsOf: fixture.url) != committedBytes)
        try #require(kill(process.processIdentifier, SIGKILL) == 0)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)

        let reopened = try fixture.open()
        #expect(await reopened.snapshot() == before)
    }

    @Test
    func authenticatedHistoryReopensWithTheSameIdentity() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let marker = "sample fixture signal 72EA no plaintext persistence"
        let store = try fixture.open()
        let before = try await store.capture(.text(.init(marker)), preferences: .init())
        let item = try #require(before.first)
        _ = try await store.setPinned(true, for: item.id)
        _ = try await store.setNote("  Résumé \n office   Wi-Fi ", for: item.id)
        _ = try await store.capture(.text(.init(marker, rtf: Data("sample RTF".utf8))), preferences: .init())
        _ = try await store.touch(item.id)

        let reader = try fixture.open()
        let restored = try #require(await reader.snapshot().first)
        #expect(restored.id == item.id)
        #expect(restored.pinned)
        #expect(restored.note == "Résumé office Wi-Fi")
        #expect(restored.copyCount == 3)
        #expect(restored.payload == .text(.init(marker, rtf: Data("sample RTF".utf8))))
        #expect(restored.matches("WIFI resume", filter: .text))
        #expect(try Data(contentsOf: fixture.url).range(of: Data(marker.utf8)) == nil)
        #expect(throws: HistoryError.unreadable) {
            _ = try HistoryStore(databaseURL: fixture.url, encryptionKey: SymmetricKey(size: .bits256))
        }
        let finalReader = try fixture.open()
        #expect(await finalReader.snapshot() == [restored])
    }

    @Test
    func olderOpenSessionCannotOverwriteHistory() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let first = try fixture.open()
        let second = try fixture.open()
        let records = try await first.capture(.text(.init("first copy")), preferences: .init())
        await #expect(throws: HistoryError.changed) {
            _ = try await second.capture(.text(.init("stale copy")), preferences: .init())
        }
        let fresh = try fixture.open()
        #expect(await fresh.snapshot() == records)
    }

    @Test
    func mergesTargetFirstAndSplitsStableMembers() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let store = try fixture.open()
        let files = (0..<3).map { testFile($0) }
        let original = try await store.importPayloads([.files([files[0]]), .files(Array(files[1...]))], preferences: .init())
        let target = try #require(original.first)
        let source = try #require(original.last)
        _ = try await store.setPinned(true, for: source.id)
        _ = try await store.setNote("invoice", for: source.id)

        let partial = try await store.merge(source.id, into: target.id, members: [files[1].id])
        #expect(partial.first?.payload.members.map(\.id) == [files[0].id, files[1].id])
        #expect(partial.last?.payload.members.map(\.id) == [files[2].id])
        #expect(partial.last?.note == "invoice")
        let merged = try await store.merge(source.id, into: target.id)
        #expect(merged.count == 1)
        #expect(merged.first?.id == target.id)
        #expect(merged.first?.pinned == true)
        #expect(merged.first?.note == "invoice")
        #expect(merged.first?.payload.members.map(\.id) == files.map(\.id))

        let split = try await store.split(target.id, member: files[1].id)
        #expect(split.first?.payload.members.map(\.id) == [files[1].id])
        #expect(split.last?.payload.members.map(\.id) == [files[0].id, files[2].id])
        let reloaded = try fixture.open()
        #expect(await reloaded.snapshot() == split)
    }

    @Test
    func manualImportsChunkWhileCopiedFileCollectionsStayTogether() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let store = try fixture.open()
        let files = (0..<23).map(testFile)
        let imported = try await store.importPayloads([.files(files)], preferences: .init())
        #expect(imported.map { $0.payload.members.count } == [10, 10, 3])
        #expect(imported.flatMap(\.payload.members).map(\.id) == files.map(\.id))
        let copied = try await store.capture(.files(files), preferences: .init())
        #expect(copied.first?.payload.members.count == 23)

        let first = try #require(imported.first)
        let last = try #require(imported.last)
        await #expect(throws: HistoryError.stackFull) {
            _ = try await store.merge(last.id, into: first.id)
        }
        #expect(await store.snapshot() == copied)
    }

    @Test
    func expiryAndScopedClearRespectPinsAndNotes() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.remove() }
        let store = try fixture.open()
        let now = Date(timeIntervalSince1970: 100_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let start = try await store.importPayloads(
            [.text(.init("pin")), .text(.init("note")), .text(.init("old"))],
            preferences: .init(),
            at: yesterday
        )
        let pinned = try #require(start.first)
        let noted = try #require(start.dropFirst().first)
        _ = try await store.setPinned(true, for: pinned.id)
        _ = try await store.setNote("keep", for: noted.id)
        _ = try await store.capture(.text(.init("recent")), preferences: .init(), at: now)
        let active = try await store.capture(.text(.init("newer")), preferences: .init(), at: now)
        var preferences = ShelfPreferences()
        preferences.autoDeleteHours = 6
        let survivors = try await store.prune(preferences: preferences, at: now)
        #expect(survivors.map(\.displayTitle) == ["newer", "recent", "pin", "note"])
        let recent = try #require(active.dropFirst().first)
        let remaining = try await store.clear([recent.id, pinned.id, noted.id], since: now)
        #expect(remaining.map(\.displayTitle) == ["newer", "pin", "note"])
    }

    @Test
    func filtersColorsAndLinksWithoutClassifyingOrdinaryFilenamesAsLinks() throws {
        let swatch = ClipboardItem(payload: .text(.init("hsl(0 100% 50% / 50%)")))
        #expect(swatch.category == .colors)
        #expect(!swatch.matches("#FF000080", filter: .text))
        let color = try #require(ClipboardColor("hsl(0 100% 50% / 50%)"))
        #expect(color.hex == "#FF000080")
        #expect(ClipboardColor("rgb()") == nil)
        #expect(ClipboardText("notes.md").webURL == nil)
        #expect(ClipboardText("test@example.com").webURL == nil)
        #expect(ClipboardText("www.example.com").webURL?.host() == "www.example.com")
        #expect(ClipboardText("example.com/settings").webURL?.path() == "/settings")
    }

    private func testFile(_ index: Int) -> ClipboardMember {
        .file(ClipboardFile(url: URL(fileURLWithPath: "/fixture/document-\(index).txt")))
    }

    private func pngFixture(_ seed: Int) throws -> ClipboardImage {
        let width = 160
        let height = 120
        let pixels = Data((0..<(width * height * 4)).map { index -> UInt8 in
            let channel = index % 4
            if channel == 3 { return 255 }
            let x = index / 4 % width
            let y = index / (4 * width)
            let horizontal = x * (23 + seed % 31)
            let vertical = y * (7 + seed % 17)
            return UInt8(truncatingIfNeeded: horizontal ^ vertical ^ (seed >> (channel * 4)))
        })
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let bitmap = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, bitmap, nil)
        try #require(CGImageDestinationFinalize(destination))
        return ClipboardImage(data: bytes as Data, typeIdentifier: UTType.png.identifier, width: width, height: height)
    }
}

private struct HistoryFixture {
    let url: URL
    let key = SymmetricKey(size: .bits256)

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kopy-history-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        url = directory.appending(path: "history.sqlite")
    }

    func open() throws -> HistoryStore {
        try HistoryStore(databaseURL: url, encryptionKey: key)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func sql(_ statement: String) throws {
        try withConnection { connection in
            try #require(sqlite3_exec(connection, statement, nil, nil, nil) == SQLITE_OK)
        }
    }

    func scalar(_ statement: String) throws -> Int64 {
        try withConnection { connection in
            var query: OpaquePointer?
            try #require(sqlite3_prepare_v2(connection, statement, -1, &query, nil) == SQLITE_OK)
            defer { sqlite3_finalize(query) }
            try #require(sqlite3_step(query) == SQLITE_ROW)
            return sqlite3_column_int64(query, 0)
        }
    }

    private func withConnection<T>(_ use: (OpaquePointer) throws -> T) throws -> T {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        try #require(sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        return try use(try #require(connection))
    }
}
