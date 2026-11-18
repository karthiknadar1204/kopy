import CryptoKit
import Foundation
import Testing
@testable import KopyCore

struct ClipboardTimeRangeTests {
    @Test("Time ranges include their exact boundary and exclude older activity")
    func boundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (range, seconds) in [(ClipboardTimeRange.lastHour, 3_600.0), (.last6Hours, 21_600), (.last24Hours, 86_400)] {
            #expect(range.includes(now, at: now))
            #expect(range.includes(now.addingTimeInterval(-seconds), at: now))
            #expect(!range.includes(now.addingTimeInterval(-seconds - 1), at: now))
        }
        #expect(ClipboardTimeRange.allTime.includes(.distantPast, at: now))
    }

    @Test("Switching from 24 hours to All time restores older unpinned items without changing storage")
    func resetPreservesHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "History.sqlite3")
        let key = SymmetricKey(size: .bits256)
        let store = try HistoryStore(databaseURL: url, encryptionKey: key)
        let now = Date.now
        _ = try await store.capture(.text(ClipboardText("Older fixture")), preferences: .init(), at: now - 172_800)
        let all = try await store.capture(.text(ClipboardText("Recent fixture")), preferences: .init(), at: now)
        #expect(all.count == 2)
        #expect(all.allSatisfy { !$0.pinned })
        let recent = all.filter { ClipboardTimeRange.last24Hours.includes($0.activityAt, at: now) }
        #expect(recent.map(\.displayTitle) == ["Recent fixture"])
        #expect(all.filter { ClipboardTimeRange.allTime.includes($0.activityAt, at: now) } == all)
        #expect(await store.snapshot() == all)
        let reopened = try HistoryStore(databaseURL: url, encryptionKey: key)
        #expect(await reopened.snapshot() == all)
    }
}
