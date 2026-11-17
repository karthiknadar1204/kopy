import Foundation
import Testing
@testable import KopyApp

@Suite("Application updates")
@MainActor
struct UpdaterTests {
    @Test("The chosen update mode survives a new updater instance")
    func modePersists() throws {
        let suite = "kopy.tests.updater.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = KopyUpdater(enabled: false, defaults: defaults)
        #expect(first.mode == .auto)
        first.setMode(.notify)
        let second = KopyUpdater(enabled: false, defaults: defaults)
        #expect(second.mode == .notify)
        second.setMode(.off)
        #expect(KopyUpdater(enabled: false, defaults: defaults).mode == .off)
    }

    @Test("Development builds require a signed HTTPS feed before checking")
    func configuration() throws {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let valid = try fixture(feed: "https://updates.example.test/appcast.xml", key: key)
        let insecure = try fixture(feed: "http://updates.example.test/appcast.xml", key: key)
        let malformed = try fixture(feed: "https://updates.example.test/appcast.xml", key: "bad key")
        defer {
            for item in [valid, insecure, malformed] { try? FileManager.default.removeItem(at: item.bundleURL) }
        }

        #expect(KopyUpdater(bundle: valid).isConfigured)
        #expect(!KopyUpdater(bundle: insecure).isConfigured)
        #expect(!KopyUpdater(bundle: malformed).isConfigured)
        let disabled = KopyUpdater(enabled: false, bundle: valid)
        #expect(!disabled.isConfigured)
        disabled.start()
        disabled.checkForUpdates()
        #expect(disabled.state == .idle)
    }

    private func fixture(feed: String, key: String) throws -> Bundle {
        let id = "com.kopy.tests.\(UUID().uuidString)"
        let url = FileManager.default.temporaryDirectory.appending(path: "\(id).app")
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL",
                                   "SUFeedURL": feed, "SUPublicEDKey": key]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return try #require(Bundle(url: url))
    }
}
