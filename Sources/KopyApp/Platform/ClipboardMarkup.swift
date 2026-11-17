import Foundation
import KopyCore

enum ClipboardMarkup {
    static let htmlLimit = 32_768

    static func isLargeTable(_ text: String) -> Bool {
        guard text.contains("\t") else { return false }
        return text.utf16.count > 8_192 || text.utf8.lazy.filter { $0 == 10 }.prefix(40).count >= 40
    }

    static func normalizeRows(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
    }

    static func tableHTML(_ text: String, existing: Data?) -> Data? {
        if let existing, existing.count <= htmlLimit,
           String(data: existing, encoding: .utf8)?.firstMatch(of: #/(?i)<table\b[^>]*>/#) != nil {
            return existing
        }
        guard !isLargeTable(text) else { return nil }
        let rows = text.components(separatedBy: "\r\n").map { row in
            let cells = row.components(separatedBy: "\t").map { "<td>\(escape($0))</td>" }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()
        let html = Data("<table border=\"0\" cellpadding=\"0\" cellspacing=\"0\"><tbody>\(rows)</tbody></table>".utf8)
        return html.count <= htmlLimit ? html : nil
    }

    // The AppKit HTML importer can load remote resources. Clipboard previews only inspect text.
    static func plainText(_ html: String) -> String {
        let body = html.replacingOccurrences(of: #"(?is)<!--.*?-->|<(script|style|head)\b[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
        let markup = body.replacingOccurrences(of: #"(?i)</(?:td|th)\s*>\s*<(?:td|th)\b[^>]*>"#, with: "\t", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<br\b[^>]*>|</(?:p|div|tr|li)\s*>"#, with: "\n", options: .regularExpression)
        return decodeEntities(markup.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression))
    }

    static func linkTitle(in html: String, for pastedValue: String) -> String? {
        guard let target = ClipboardText(pastedValue).webURL else { return nil }
        for anchor in html.matches(of: #/(?is)<a\b[^>]*?\s+href\s*=\s*(["'])(.*?)\1[^>]*>(.*?)<\/a\s*>/#).prefix(50) {
            let href = decodeEntities(String(anchor.output.2))
            guard let link = ClipboardText(href).webURL, sameLink(link, target) else { continue }
            let title = plainText(String(anchor.output.3)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !title.isEmpty, ClipboardText(title).webURL == nil else { continue }
            return title.unicodeScalars.count > 200 ? String(title.unicodeScalars.prefix(199)) + "…" : title
        }
        return nil
    }

    private static func sameLink(_ lhs: URL, _ rhs: URL) -> Bool {
        // Host and scheme often differ between a copied address and the accompanying HTML anchor.
        func comparableHost(_ url: URL) -> String? {
            url.host()?.lowercased().replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        }
        return comparableHost(lhs) == comparableHost(rhs)
            && lhs.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")) == rhs.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            && lhs.port == rhs.port && lhs.query() == rhs.query() && lhs.fragment() == rhs.fragment()
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func decodeEntities(_ value: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        var decoded = ""
        var start = value.startIndex
        for match in value.matches(of: #/(?i)&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/#) {
            decoded += value[start..<match.range.lowerBound]
            let token = match.output.1.lowercased()
            let codePoint = token.hasPrefix("#x") ? UInt32(token.dropFirst(2), radix: 16) : UInt32(token.dropFirst())
            decoded += named[token] ?? codePoint.flatMap(UnicodeScalar.init).map(String.init) ?? String(match.output.0)
            start = match.range.upperBound
        }
        decoded += value[start...]
        return decoded
    }
}
