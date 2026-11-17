import Foundation
import KopyCore
import Testing
@testable import KopyApp

@Suite("Kopy language resources")
struct LocalizationTests {
    private let catalogs = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Resources/Localizations")

    @Test("Each selectable language has the same keys and preserves format arguments")
    func completeCatalogs() throws {
        let english = try propertyList("Localizable.strings", language: "en", as: [String: String].self)
        let englishPlurals = try propertyList("Localizable.stringsdict", language: "en", as: [String: [String: Any]].self)
        let formatting = /%(?:[1-9][0-9]*\$)?(@|lld|ld|d)/
        let names = ShelfLanguage.available.map(\.identifier)
        let directories = try FileManager.default.contentsOfDirectory(at: catalogs, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
        #expect(Set(names) == Set(directories))

        for language in names {
            let strings = try propertyList("Localizable.strings", language: language, as: [String: String].self)
            let plurals = try propertyList("Localizable.stringsdict", language: language, as: [String: [String: Any]].self)
            #expect(Set(strings.keys) == Set(english.keys), "Keys differ for \(language)")
            #expect(Set(plurals.keys) == Set(englishPlurals.keys), "Plural keys differ for \(language)")

            for (key, value) in strings {
                let expected = english[key]?.matches(of: formatting).map { String($0.1) }.sorted()
                let actual = value.matches(of: formatting).map { String($0.1) }.sorted()
                #expect(actual == expected, "Format arguments differ for \(language) / \(key)")
            }
            for (key, plural) in plurals {
                let rule = try #require(plural["count"] as? [String: String])
                #expect(rule["NSStringFormatSpecTypeKey"] == "NSStringPluralRuleType")
                #expect(rule["NSStringFormatValueTypeKey"] == "lld")
                #expect(rule["other"]?.matches(of: formatting).map { String($0.1) } == ["lld"],
                        "Missing count argument for \(language) / \(key)")
            }
        }
    }

    @Test("Explicit language lookup formats shortcuts, image counts, and literal fallback")
    func bundleLookup() throws {
        let bundleRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".bundle")
        let contents = bundleRoot.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        let info: [String: String] = ["CFBundleIdentifier": "com.kopy.test-localizations", "CFBundlePackageType": "BNDL"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
        try FileManager.default.copyItem(at: catalogs, to: contents.appending(path: "Resources"))
        let bundle = try #require(Bundle(url: bundleRoot))

        #expect(ShelfLanguage.string("Clear shown history", language: "fr", in: bundle) == "Effacer l’historique affiché")
        #expect(ShelfLanguage.string("Allow automatic paste", language: "ja", in: bundle) == "自動ペーストを許可")
        #expect(ShelfLanguage.string("Couldn’t register %@. Choose another shortcut in Settings.", language: "fr",
                                     arguments: ["⌘K"], in: bundle).contains("⌘K"))
        #expect(ShelfLanguage.string("%lld images", language: "pl", arguments: [1], in: bundle) == "1 obraz")
        #expect(ShelfLanguage.string("%lld images", language: "pl", arguments: [2], in: bundle) == "2 obrazy")
        #expect(ShelfLanguage.string("%lld images", language: "pl", arguments: [5], in: bundle) == "5 obrazów")
        #expect(ShelfLanguage.string("Link type: Repository", language: "fr", in: bundle) == "Dépôt")
        #expect(ShelfLanguage.string("Link type: Example.com", language: "ar", fallback: "Example.com", in: bundle) == "Example.com")
        #expect(ShelfLanguage.locale(for: "ar").language.characterDirection == .rightToLeft)
        #expect(ShelfLanguage.locale(for: "fr").language.characterDirection == .leftToRight)

        for language in ShelfLanguage.available.map(\.identifier) {
            let count = ShelfLanguage.string("%lld images", language: language, arguments: [Int64(2)], in: bundle)
            #expect(!count.contains("%"), "Unresolved plural format for \(language)")
        }
        #expect(ShelfLanguage.string("%lld items", language: "en", arguments: [Int64(1)], in: bundle) == "1 item")
        #expect(ShelfLanguage.string("%lld items", language: "pl", arguments: [Int64(2)], in: bundle) == "2 elementy")
        #expect(ShelfLanguage.string("%lld items", language: "pl", arguments: [Int64(5)], in: bundle) == "5 elementów")
        #expect(ShelfLanguage.string("%lld items", language: "ar", arguments: [Int64(2)], in: bundle) == "عنصران")

        let missingFile = ClipboardTransferError.missingFile("Sample.txt")
        #expect(ShelfLanguage.errorMessage(missingFile, language: "de", in: bundle)
                == "Die Originaldatei „Sample.txt“ ist nicht mehr verfügbar.")
        let keychain = LocalHistoryKey.AccessError(status: -50)
        #expect(ShelfLanguage.errorMessage(keychain, language: "it", in: bundle)
                == "Kopy non ha potuto leggere o creare la chiave della cronologia nel portachiavi (-50).")
        #expect(ShelfLanguage.errorMessage(HistoryError.changed, language: "fr", in: bundle)
                == "L’historique a changé dans une autre session de Kopy. Rouvrez Kopy pour continuer.")
        #expect(ShelfLanguage.errorMessage(CocoaError(.fileWriteOutOfSpace), language: "fi", in: bundle)
                == "Levytila ei riitä tiedoston tallentamiseen.")
    }

    private func propertyList<Value>(_ filename: String, language: String, as: Value.Type) throws -> Value {
        let url = catalogs.appending(path: "\(language).lproj").appending(path: filename)
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? Value)
    }
}
