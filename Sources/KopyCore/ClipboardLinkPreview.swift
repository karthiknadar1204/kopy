import Foundation

public struct ClipboardLinkPreview: Equatable, Sendable {
    public let service: String
    public let kind: String?
    public let title: String?
    public let address: String

    public var heading: String { [service, kind].compactMap { $0 }.joined(separator: " · ") }
}

extension ClipboardText {
    public var cleanedURL: URL? {
        guard let webURL else { return nil }
        return ClipboardLink.destination(of: webURL)
    }

    public var linkPreview: ClipboardLinkPreview? {
        guard let cleanedURL else { return nil }
        return ClipboardLink.preview(cleanedURL, copiedTitle: title)
    }
}

enum ClipboardLink {
    static func trimCopiedURL(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.firstMatch(of: #/^[<"'(\[]+(?=[a-zA-Z])/#) != nil {
            text = String(text.drop(while: { "<\"'([".contains($0) }))
        }
        let brackets: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        for _ in 0..<8 {
            guard text.count > 1, let last = text.last else { break }
            if ".,;:!?\'\">".contains(last) {
                text.removeLast()
            } else if let open = brackets[last], text.filter({ $0 == last }).count > text.filter({ $0 == open }).count {
                text.removeLast()
            } else {
                break
            }
        }
        return text
    }

    static func destination(of url: URL) -> URL {
        var result = url
        for _ in 0..<3 {
            guard let inner = redirectTarget(result) else { break }
            result = inner
        }
        return stripTracking(result)
    }

    private static func redirectTarget(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawHost = url.host()?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = components.path
        let query = LinkQuery(components)
        let target: String?
        switch host {
        case _ where isGoogle(host) && path == "/url": target = query["q"] ?? query["url"]
        case "l.facebook.com", "lm.facebook.com", "l.messenger.com":
            target = path.hasPrefix("/l.php") ? query["u"] : nil
        case "l.instagram.com": target = query["u"]
        case "youtube.com": target = path == "/redirect" ? query["q"] : nil
        case _ where onHost(host, "safelinks.protection.outlook.com"): target = query["url"]
        case "linkedin.com": target = path.hasPrefix("/redir/redirect") ? query["url"] : nil
        case "out.reddit.com": target = query["url"]
        case "t.umblr.com": target = path.hasPrefix("/redirect") ? query["z"] : nil
        case "steamcommunity.com": target = path.hasPrefix("/linkfilter") ? query["url"] ?? query["u"] : nil
        case "duckduckgo.com": target = path.hasPrefix("/l/") ? query["uddg"] : nil
        case "href.li": target = components.query
        case "slack-redir.net": target = path.hasPrefix("/link") ? query["url"] : nil
        default: target = nil
        }
        guard let target, let redirect = URL(string: target),
              ["http", "https"].contains(redirect.scheme?.lowercased() ?? ""), redirect.host() != nil else { return nil }
        return redirect
    }

    private static func stripTracking(_ url: URL) -> URL {
        let raw = url.absoluteString
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let question = raw.firstIndex(of: "?"), raw.firstIndex(of: "#").map({ question < $0 }) ?? true else { return url }
        let query = raw[raw.index(after: question)...]
        let fragment = query.firstIndex(of: "#") ?? raw.endIndex
        let fields = query[..<fragment].split(separator: "&", omittingEmptySubsequences: false)
        let kept = fields.filter { field in
            let name = field.prefix(while: { $0 != "=" })
            let key = name.removingPercentEncoding ?? String(name)
            return !isTracking(key)
        }
        guard kept.count != fields.count else { return url }
        let remaining = kept.filter { !$0.isEmpty }.joined(separator: "&")
        return URL(string: String(raw[..<question]) + (remaining.isEmpty ? "" : "?\(remaining)") + raw[fragment...]) ?? url
    }

    private static func isTracking(_ field: String) -> Bool {
        let name = field.lowercased()
        return ClipboardLinkDirectory.trackerKeys.contains(name) || ClipboardLinkDirectory.trackerPrefixes.contains(where: name.hasPrefix)
    }

    static func onHost(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    static func isGoogle(_ host: String) -> Bool {
        let root = domainParts(host).root
        return host == root && root.hasPrefix("google.")
    }

    static func preview(_ url: URL, copiedTitle: String?) -> ClipboardLinkPreview? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = LinkQuery(components)
        switch components.scheme?.lowercased() {
        case "mailto":
            return ClipboardLinkPreview(service: "Email", kind: nil, title: copiedTitle ?? query["subject"], address: components.path)
        case "tel":
            return ClipboardLinkPreview(service: "Phone", kind: "Call", title: copiedTitle, address: components.path)
        default:
            break
        }

        guard let ascii = url.host()?.lowercased() else { return nil }
        let withoutWWW = ascii.replacingOccurrences(of: #"^www[0-9]?\."#, with: "", options: .regularExpression)
        let host = withoutWWW.replacingOccurrences(of: #"^m\.(?=[^.]+\.[^.]+)"#, with: "", options: .regularExpression)
        let displayHost = displayDomain(withoutWWW)
        let port = components.port.map { ":\($0)" } ?? ""
        let path = components.path == "/" ? "" : components.path
        let address = displayHost + port + path + (components.query.map { "?\($0)" } ?? "") + (components.fragment.map { "#\($0)" } ?? "")
        let parts = components.percentEncodedPath.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let fallbackTitle = parts.reversed().lazy.compactMap(genericTitle).first

        let comparableHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if comparableHost == "localhost" || comparableHost.hasSuffix(".localhost") || comparableHost.hasPrefix("127.")
            || comparableHost == "::1" || comparableHost == "0.0.0.0" {
            return ClipboardLinkPreview(service: "This computer", kind: components.port.map { "Port \($0)" }, title: copiedTitle ?? fallbackTitle, address: address)
        }
        if [".local", ".lan", ".internal", ".home.arpa"].contains(where: comparableHost.hasSuffix)
            || comparableHost.wholeMatch(of: #/(?:10\.[0-9.]+|192\.168\.[0-9.]+|172\.(?:1[6-9]|2[0-9]|3[01])\.[0-9.]+|169\.254\.[0-9.]+)/#) != nil {
            return ClipboardLinkPreview(service: "Local network", kind: nil, title: copiedTitle ?? fallbackTitle, address: address)
        }
        if comparableHost.contains(":") || comparableHost.wholeMatch(of: #/(?:[0-9]+\.){3}[0-9]+/#) != nil {
            return ClipboardLinkPreview(service: displayHost, kind: nil, title: copiedTitle ?? fallbackTitle, address: address)
        }

        let (root, main) = domainParts(host)
        let hostService = brand(for: host)
        let hosted = ClipboardLinkDirectory.hostedPlatforms.first { host.hasSuffix(".\($0)") }
        let subdomain = hosted.flatMap { platform in
            host.dropLast(platform.count + 1).split(separator: ".").last.map(String.init)
        }
        let service = subdomain.map { humanize(displayDomain($0)) }
            ?? hostService ?? (main.hasPrefix("xn--") ? displayDomain(root) : humanize(main, domain: true))
        let hostedOn = hosted.map { brand(for: $0) ?? humanize(String($0.prefix(while: { $0 != "." })), domain: true) }

        if ClipboardLinkDirectory.shorteners.contains(host) {
            return ClipboardLinkPreview(service: service, kind: "Short link", title: copiedTitle, address: address)
        }
        if let page = page(host: host, main: main, parts: parts, query: query, fragment: components.fragment) {
            return ClipboardLinkPreview(service: page.service ?? service, kind: page.kind ?? hostedOn, title: copiedTitle ?? page.title, address: address)
        }
        let search = fallbackTitle == nil ? query.search : nil
        let named = ["title", "name", "page", "topic"].lazy.compactMap { query[$0].flatMap(genericTitle) }.first
        return ClipboardLinkPreview(service: service, kind: search == nil ? hostedOn : "Search",
                                    title: copiedTitle ?? fallbackTitle ?? search ?? named, address: address)
    }

    private static func domainParts(_ host: String) -> (root: String, main: String) {
        let parts = host.split(separator: ".")
        if parts.count < 2 { return (host, host) }
        let lastThree = parts.suffix(3).joined(separator: ".")
        let lastTwo = parts.suffix(2).joined(separator: ".")
        let suffixCount = ClipboardLinkDirectory.suffixes.contains(lastThree) ? 3
            : ClipboardLinkDirectory.suffixes.contains(lastTwo) ? 2 : 1
        let root = parts.suffix(suffixCount + 1)
        return (root.joined(separator: "."), String(root.first ?? Substring(host)))
    }

    private static func brand(for host: String) -> String? {
        var current = host
        while let dot = current.firstIndex(of: ".") {
            if let brand = ClipboardLinkDirectory.brands[current] { return brand }
            current = String(current[current.index(after: dot)...])
        }
        return nil
    }

    static func humanize(_ raw: String, domain: Bool = false) -> String {
        if domain {
            let words = raw.replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
                .replacingOccurrences(of: #"[-_.]+"#, with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace)
            return words.map { word in
                let lower = word.lowercased()
                let upper = word.uppercased()
                if ClipboardLinkDirectory.acronyms.contains(upper)
                    || (lower.wholeMatch(of: #/[a-z]{2,6}/#) != nil && !lower.contains(where: { "aeiouy".contains($0) })) {
                    return upper
                }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }.joined(separator: " ")
        }
        let wordString = raw.replacingOccurrences(of: #"[-_+]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\.(html?|php|aspx?|jsp|json|md|txt|cms|shtml|cfm)$"#, with: "", options: .regularExpression)
        let words = wordString.split(whereSeparator: \.isWhitespace)
        return words.enumerated().map { index, word in
            let low = word.lowercased()
            let upper = word.uppercased()
            if let idiomatic = ClipboardLinkDirectory.casedWords[low] { return idiomatic }
            if ClipboardLinkDirectory.acronyms.contains(upper) { return upper }
            if index > 0, ClipboardLinkDirectory.smallWords.contains(low) { return low }
            if (word != low && word != upper) || (word == upper && word.count <= 4) { return String(word) }
            return low.prefix(1).uppercased() + low.dropFirst()
        }.joined(separator: " ")
    }

    static func withoutSlugID(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)[-_](?:[a-f0-9]{8,}|[0-9]{5,}|[0-9a-z]*\d[0-9a-z]*\d[0-9a-z]{6,})$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\d{4,}[-_](?=[a-z])"#, with: "", options: .regularExpression)
    }

    static func genericTitle(_ raw: String) -> String? {
        let value = withoutSlugID(raw.replacingOccurrences(of: #"(?i)\.(html?|php|aspx?|jsp|cms|shtml|cfm|asp)$"#, with: "", options: .regularExpression))
        guard value.count > 1, value.contains(where: \.isLetter),
              !ClipboardLinkDirectory.fillerSegments.contains(value.lowercased()),
              value.firstMatch(of: #/[=;&]/#) == nil,
              value.wholeMatch(of: #/(?i)[0-9a-f]{8,}|[0-9a-f]{8}-[0-9a-f]{4}-.*|v?\d+(?:\.\d+)*|[a-z]{2}[-_][a-z]{2,4}|intl-[a-z]{2}/#) == nil else {
            return nil
        }
        if value.count >= 6, value.contains(where: \.isNumber),
           !value.contains(where: { "-_.~+ ".contains($0) }) { return nil }
        return humanize(value)
    }

    private static func displayDomain(_ host: String) -> String {
        let lookalikes = Set("аеорсухіјӏԁѕԛԝһкмпвтгьзΑΒΕΖΗΙΚΜΝΟΡΤΥΧαβεικνορτυχοаАВЕКМНОРСТХѵѡԑɡ")
        guard host.contains("xn--"),
              let url = URL(string: "https://\(host)", encodingInvalidCharacters: false),
              let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host else { return host }
        return zip(host.split(separator: "."), decoded.split(separator: ".")).map { ascii, unicode in
            let letters = unicode.filter(\.isLetter)
            let latin = letters.filter { String($0).wholeMatch(of: #/\p{Script=Latin}/#) != nil }
            guard ascii.hasPrefix("xn--"), unicode.contains(where: { !$0.isASCII }),
                  latin.isEmpty || latin.count == letters.count,
                  !latin.isEmpty || letters.isEmpty || !letters.allSatisfy(lookalikes.contains) else { return String(ascii) }
            return String(unicode)
        }.joined(separator: ".")
    }
}

struct LinkQuery {
    let fields: [URLQueryItem]

    init(_ components: URLComponents) {
        var form = components
        form.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        fields = form.queryItems ?? []
    }

    subscript(_ name: String) -> String? {
        fields.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    var search: String? {
        search(using: ["q", "query", "search_query", "search", "k", "keywords", "keyword", "term", "text", "p", "wd", "searchTerm", "st"])
    }

    func search(using keys: [String]) -> String? {
        keys.lazy.compactMap { self[$0] }.map {
            $0.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.first { !$0.isEmpty && !$0.lowercased().hasPrefix("http://") && !$0.lowercased().hasPrefix("https://") }
    }
}
