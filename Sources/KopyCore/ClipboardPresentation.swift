import Foundation
import UniformTypeIdentifiers

extension ClipboardItem {
    public var category: ClipboardFilter {
        switch payload {
        case .text(let text):
            if text.detectedColor != nil { return .colors }
            return text.webURL == nil ? .text : .links
        case .image, .images:
            return .images
        case .files(let members):
            return !members.isEmpty && members.allSatisfy(\.isImage) ? .images : .files
        }
    }

    public var displayTitle: String {
        switch payload {
        case .text(let text):
            if let title = text.title, !title.isEmpty { return title }
            if let host = text.webURL?.host(), !host.isEmpty { return host }
            return String(text.value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        case .image(let image):
            return image.name ?? "Image"
        case .images(let images):
            return "\(images.count) images"
        case .files(let members):
            return members.count == 1 ? members[0].name : "\(members.count) items"
        }
    }

    public func matches(_ query: String, filter: ClipboardFilter) -> Bool {
        if filter != .all && filter != category { return false }
        let terms = Self.fold(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let searchable: String
        switch payload {
        case .text(let text):
            searchable = [String(text.value.prefix(300)), text.title, note].compactMap { $0 }.joined(separator: "\n")
        case .image, .images:
            searchable = note ?? ""
        case .files(let members):
            searchable = (members.map(\.name) + [note ?? ""]).joined(separator: "\n")
        }
        let folded = Self.fold(searchable)
        let compact = Self.compact(folded)
        return terms.allSatisfy { term in
            if folded.contains(term) { return true }
            let packed = Self.compact(String(term))
            return !packed.isEmpty && compact.contains(packed)
        }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }

    private static func compact(_ value: String) -> String {
        String(value.filter { $0.isLetter || $0.isNumber })
    }
}

extension ClipboardMember {
    public var name: String {
        switch self {
        case .file(let file): file.url.lastPathComponent
        case .image(let image): image.name ?? "Image"
        }
    }

    public var isImage: Bool {
        switch self {
        case .image: true
        case .file(let file):
            !file.isDirectory && UTType(filenameExtension: file.url.pathExtension)?.conforms(to: .image) == true
        }
    }
}

extension ClipboardText {
    public var webURL: URL? {
        let text = ClipboardLink.trimCopiedURL(value)
        guard !text.isEmpty, text.utf8.count <= 8_192 else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("mailto:"), text.wholeMatch(of: #/(?i)mailto:[^\s@]+@[^\s@]+\.[^\s@]+/#) != nil {
            return URL(string: text)
        }
        if lower.hasPrefix("tel:"), text.wholeMatch(of: #/(?i)tel:\+?[0-9 .()\-]{5,}/#) != nil {
            return URL(string: text.replacingOccurrences(of: " ", with: ""))
        }
        guard !text.contains(where: \.isWhitespace) else { return nil }
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("www.") {
            let url = URL(string: lower.hasPrefix("www.") ? "https://\(text)" : text)
            guard let host = url?.host(), !host.isEmpty else { return nil }
            return url
        }
        guard let url = URL(string: "https://\(text)"), url.user() == nil, let host = url.host(),
              host.wholeMatch(of: #/(?i)([a-z0-9]([a-z0-9\-]*[a-z0-9])?\.)+[a-z]{2,24}/#) != nil,
              let suffix = host.lowercased().split(separator: ".").last,
              Self.webSuffixes.contains(suffix) else { return nil }
        if Self.ambiguousSuffixes.contains(suffix), url.path.isEmpty, url.query == nil, url.fragment == nil {
            return nil
        }
        return url
    }

    private static let webSuffixes = Set("""
        com net org edu gov mil int info biz io co ai app dev me tv in uk us ca au de fr jp cn ru br it es nl se no fi dk pl
        ch at be ie nz za sg hk tw kr id my ph vn th tr ae sa il eg ng ke pk bd lk np mx ar cl pe eu asia xyz online site tech
        store shop blog news live link page cloud email so gg ly to fm sh md py rs cc ws one zip mov design studio art wiki top icu pro gl gd is
        """.split(whereSeparator: \.isWhitespace))

    private static let ambiguousSuffixes = Set("md py rs sh pl cc zip mov ai so app is to gd".split(separator: " "))
}
