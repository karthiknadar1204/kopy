import Foundation
import SwiftUI

enum ShelfLanguage {
    struct Option {
        let identifier: String
        let name: String
    }

    static let system = "system"
    static let available = [
        Option(identifier: "en", name: "English"),
        Option(identifier: "es", name: "Español"),
        Option(identifier: "fr", name: "Français"),
        Option(identifier: "de", name: "Deutsch"),
        Option(identifier: "it", name: "Italiano"),
        Option(identifier: "pt", name: "Português"),
        Option(identifier: "ru", name: "Русский"),
        Option(identifier: "ja", name: "日本語"),
        Option(identifier: "ko", name: "한국어"),
        Option(identifier: "zh-Hans", name: "简体中文"),
        Option(identifier: "zh-Hant", name: "繁體中文"),
        Option(identifier: "hi", name: "हिन्दी"),
        Option(identifier: "ar", name: "العربية"),
        Option(identifier: "fa", name: "فارسی"),
        Option(identifier: "bn", name: "বাংলা"),
        Option(identifier: "tr", name: "Türkçe"),
        Option(identifier: "vi", name: "Tiếng Việt"),
        Option(identifier: "pl", name: "Polski"),
        Option(identifier: "nl", name: "Nederlands"),
        Option(identifier: "sv", name: "Svenska"),
        Option(identifier: "id", name: "Bahasa Indonesia"),
        Option(identifier: "uk", name: "Українська"),
        Option(identifier: "el", name: "Ελληνικά"),
        Option(identifier: "cs", name: "Čeština"),
        Option(identifier: "ro", name: "Română"),
        Option(identifier: "hu", name: "Magyar"),
        Option(identifier: "da", name: "Dansk"),
        Option(identifier: "fi", name: "Suomi"),
        Option(identifier: "th", name: "ไทย"),
        Option(identifier: "he", name: "עברית"),
        Option(identifier: "nb", name: "Norsk"),
    ]

    static func locale(for identifier: String) -> Locale {
        if available.contains(where: { $0.identifier == identifier }) {
            return Locale(identifier: identifier)
        }
        let preferred = Bundle.preferredLocalizations(from: available.map(\.identifier))
        return Locale(identifier: preferred.first ?? "en")
    }

    static func string(
        _ key: String,
        language: String,
        arguments: [CVarArg] = [],
        fallback: String? = nil,
        in resources: Bundle = .main
    ) -> String {
        let locale = locale(for: language)
        let bundle = resources.url(forResource: locale.identifier, withExtension: "lproj").flatMap(Bundle.init(url:))
        let defaultValue = fallback ?? key
        let format = bundle?.localizedString(forKey: key, value: defaultValue, table: nil) ?? defaultValue
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    static func errorMessage(_ error: any Error, language: String, in resources: Bundle = .main) -> String {
        if case .missingFile(let name) = error as? ClipboardTransferError {
            return string("The original file “%@” is no longer available.", language: language, arguments: [name], in: resources)
        }
        if let keyError = error as? LocalHistoryKey.AccessError {
            return string("Kopy couldn’t read or create the history key in Keychain (%d).",
                          language: language, arguments: [keyError.status], in: resources)
        }
        let key: String
        switch (error as? CocoaError)?.code {
        case .fileReadNoPermission, .fileWriteNoPermission:
            key = "Kopy doesn’t have permission to access this file or folder."
        case .fileWriteOutOfSpace:
            key = "There isn’t enough disk space to save the file."
        default:
            key = error.localizedDescription
        }
        return string(key, language: language, in: resources)
    }
}

struct KopyLanguageRoot<Content: View>: View {
    let model: KopyModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().kopyLanguage(model.preferences.language)
            .defaultAppStorage(model.defaults)
    }
}

extension View {
    func kopyLanguage(_ identifier: String) -> some View {
        let locale = ShelfLanguage.locale(for: identifier)
        return environment(\.locale, locale)
            .environment(\.layoutDirection, locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
    }
}
