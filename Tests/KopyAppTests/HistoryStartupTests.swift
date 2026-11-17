import CryptoKit
import Foundation
import KopyCore
import Testing
@testable import KopyApp

@MainActor
@Suite("History startup")
struct HistoryStartupTests {
    @Test("A drop during startup persists after clear-on-restart")
    func importDuringStartup() async throws {
        let profile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "Kopy.Test.\(profile.lastPathComponent)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: profile)
        }
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let database = profile.appending(path: "History.sqlite3")
        let key = SymmetricKey(data: SHA256.hash(data: Data(profile.resolvingSymlinksInPath().path.utf8)))
        let seeded = try HistoryStore(databaseURL: database, encryptionKey: key)
        _ = try await seeded.capture(.text(.init("Previous session")), preferences: .init())

        let model = KopyModel(isolatedProfile: profile)
        defer { model.stop() }
        model.updatePreferences {
            $0.clearOnRestart = true
            $0.incognito = true
        }
        model.start()
        #expect(model.isLoadingHistory)
        model.importPayloads([.text(.init("Dropped during startup"))])

        let deadline = ContinuousClock.now + .seconds(3)
        while model.importRevision == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.importRevision == 1)
        #expect(!model.isLoadingHistory)
        #expect(model.items.map(\.displayTitle) == ["Dropped during startup"])
        let reopened = try HistoryStore(databaseURL: database, encryptionKey: key)
        #expect(await reopened.snapshot() == model.items)
    }
}
