import Foundation
import KopyCore
import Testing

struct ClipboardFileAccessTests {
    @Test("Existing file records without a scoped flag still open")
    func legacyFileRecord() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("Legacy file fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let bookmark = try file.bookmarkData(options: .minimalBookmark)
        let record = ClipboardFile(url: file, bookmark: bookmark)
        let encoded = try JSONEncoder().encode(record)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("bookmarkIsSecurityScoped"))
        let restored = try JSONDecoder().decode(ClipboardFile.self, from: encoded)
        let access = try #require(restored.openFileAccess())
        let contents = try withExtendedLifetime(access) {
            try String(contentsOf: access.url, encoding: .utf8)
        }
        #expect(contents == "Legacy file fixture")
    }

    @Test("A persisted security scope flag round trips with its bookmark")
    func scopedFileRecord() throws {
        let file = ClipboardFile(url: URL(fileURLWithPath: "/tmp/ScopedFixture.txt"),
                                 bookmark: Data([1, 2, 3]), bookmarkIsSecurityScoped: true)
        let restored = try JSONDecoder().decode(ClipboardFile.self, from: JSONEncoder().encode(file))
        #expect(restored.bookmarkIsSecurityScoped == true)
        #expect(restored.bookmark == file.bookmark)
    }
}
