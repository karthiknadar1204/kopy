import Foundation

extension ClipboardLink {
    struct Page {
        let kind: String?
        let title: String?
        var service: String?

        init(_ kind: String?, _ title: String? = nil, service: String? = nil) {
            self.kind = kind
            self.title = title?.isEmpty == true ? nil : title
            self.service = service
        }
    }

    static func page(host: String, main: String, parts: [String], query: LinkQuery, fragment: String?) -> Page? {
        let route = LinkRoute(parts)
        let first = route.first
        let second = route[1]
        let third = route[2]
        if host == "github.com" { return gitHub(route, query: query) }
        if host == "gist.github.com" && !first.isEmpty { return Page("Gist", "@\(route[0])") }
        if host == "raw.githubusercontent.com" && !second.isEmpty {
            let path = parts.dropFirst(3).joined(separator: "/")
            return Page("Raw file", route.repository + (path.isEmpty ? "" : " · \(path)"))
        }
        if ["gitlab.com", "bitbucket.org", "codeberg.org"].contains(host) {
            guard !second.isEmpty else { return first.isEmpty ? nil : Page("Profile", "@\(route[0])") }
            if let index = parts.firstIndex(where: { ["merge_requests", "pull-requests", "pulls"].contains($0) }) {
                let number = route[index + 1]
                return Page(host == "gitlab.com" ? "Merge request" : "Pull request", route.repository + (number.isEmpty ? "" : " !\(number)"))
            }
            if let index = parts.firstIndex(of: "issues") {
                let number = route[index + 1]
                return Page("Issue", route.repository + (number.isEmpty ? "" : " #\(number)"))
            }
            return Page("Repository", route.repository)
        }
        if onHost(host, "youtube.com") || host == "youtu.be" { return youTube(route, host: host, query: query) }
        if onHost(host, "reddit.com") {
            if first == "r", third == "comments" { return Page("r/\(second)", humanize(route[4])) }
            if first == "r", !second.isEmpty { return Page(third == "wiki" ? "Wiki" : "Community", "r/\(second)") }
            if ["u", "user"].contains(first), !second.isEmpty { return Page("Profile", "u/\(second)") }
            return first == "search" ? Page("Search", query.search) : nil
        }
        if ["wikipedia.org", "wiktionary.org", "wikimedia.org"].contains(where: { onHost(host, $0) }) {
            if first == "wiki", !second.isEmpty {
                let name = parts.dropFirst().joined(separator: "/").replacingOccurrences(of: "_", with: " ")
                if name.lowercased().hasPrefix("special:search") { return Page("Search", query.search(using: ["search", "q"])) }
                let section = fragment?.replacingOccurrences(of: "_", with: " ")
                return Page("Article", name + (section.map { " § \($0)" } ?? ""))
            }
            return first == "w" && query["search"] != nil ? Page("Search", query["search"]) : nil
        }
        if let google = googlePage(host, route: route, query: query) { return google }
        if host == "perplexity.ai", first == "search" { return Page("Search", query.search ?? genericTitle(second)) }
        let isSearchEngine = host == "search.yahoo.com" || host == "startpage.com"
            || (host == "duckduckgo.com" && query["q"] != nil)
            || (["bing.com", "ecosia.org", "search.brave.com"].contains { onHost(host, $0) } && first == "search")
            || (onHost(host, "baidu.com") && first == "s") || (main == "yandex" && first == "search")
        if isSearchEngine { return Page("Search", query.search) }

        if let media = mediaPage(host, route: route, query: query) { return media }
        if let social = socialPage(host, route: route, query: query) { return social }
        if let work = workPage(host, route: route) { return work }
        if let software = softwarePage(host, route: route) { return software }

        if main == "amazon" || host.hasPrefix("amazon.") {
            if first == "s", let search = query["k"] ?? query["field-keywords"] { return Page("Search", search) }
            if let index = parts.firstIndex(where: { ["dp", "product", "d"].contains($0) }) {
                return Page("Product", genericTitle(route[index - 1]))
            }
            return first == "gp" ? Page("Product") : nil
        }
        if host == "flipkart.com" {
            if first == "search" { return Page("Search", query.search) }
            if let index = parts.firstIndex(of: "p"), index > 0 { return Page("Product", humanize(route[index - 1])) }
        }
        if onHost(host, "medium.com"), let last = parts.last {
            return last.hasPrefix("@") ? Page("Profile", last) : Page("Article", humanize(withoutSlugID(last)))
        }
        if onHost(host, "substack.com"), first == "p", !second.isEmpty { return Page("Post", humanize(second)) }
        if host == "dev.to", !second.isEmpty { return Page("Article", humanize(withoutSlugID(second))) }
        if ["stackoverflow.com", "superuser.com", "serverfault.com", "askubuntu.com", "mathoverflow.net"].contains(host)
            || onHost(host, "stackexchange.com") {
            switch first {
            case "questions", "q": return second.isEmpty ? nil : Page("Question", humanize(third))
            case "a": return Page("Answer")
            case "users": return third.isEmpty ? nil : Page("Profile", humanize(third))
            case "search": return Page("Search", query.search)
            default: return nil
            }
        }
        if host == "quora.com", !first.isEmpty { return Page("Question", humanize(route[0])) }
        if host == "news.ycombinator.com", first == "item" { return Page("Discussion") }
        return nil
    }

    private static func gitHub(_ route: LinkRoute, query: LinkQuery) -> Page? {
        let reserved = Set("settings features marketplace orgs topics explore notifications pulls issues sponsors about pricing login join new codespaces enterprise collections trending events search apps security customer-stories readme site team solutions resources contact organizations dashboard copilot premium-support".split(separator: " "))
        if route.first == "search" { return Page("Search", query.search) }
        if reserved.contains(Substring(route.first)) { return Page(nil, humanize(route.parts.last ?? route.first)) }
        guard !route[1].isEmpty else { return route.first.isEmpty ? nil : Page("Profile", "@\(route[0])") }
        let repo = route.repository
        let target = route[3]
        switch route[2] {
        case "pull" where !target.isEmpty: return Page("Pull request", "\(repo) #\(target)")
        case "issues": return target.isEmpty ? Page("Issues", repo) : Page("Issue", "\(repo) #\(target)")
        case "pulls": return Page("Pull requests", repo)
        case "discussions": return Page("Discussion", target.isEmpty ? repo : "\(repo) #\(target)")
        case "commit" where !target.isEmpty, "commits" where !target.isEmpty:
            return Page("Commit", "\(repo) @ \(target.prefix(7))")
        case "blob" where !target.isEmpty, "tree" where !target.isEmpty:
            let trail = route.parts.dropFirst(4).joined(separator: "/")
            return Page(route[2] == "blob" ? "File" : "Folder", "\(repo) · \(trail.isEmpty ? target : trail)")
        case "releases": return Page(route[4].isEmpty ? "Releases" : "Release \(route[4])", repo)
        case "actions": return Page("Actions", repo)
        case "wiki": return Page("Wiki", target.isEmpty ? repo : humanize(target))
        default: return Page("Repository", repo)
        }
    }

    private static func youTube(_ route: LinkRoute, host: String, query: LinkQuery) -> Page? {
        let start = (query["t"] ?? query["start"]).flatMap { value -> String? in
            guard let match = value.wholeMatch(of: #/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?/#) else { return nil }
            let hours = min(Int(match.1 ?? "") ?? 0, 1_000_000)
            let minutes = min(Int(match.2 ?? "") ?? 0, 1_000_000)
            let seconds = min(Int(match.3 ?? "") ?? 0, 1_000_000)
            let total = hours * 3_600 + minutes * 60 + seconds
            guard total > 0 else { return nil }
            if total >= 3_600 { return "Starts at " + String(format: "%d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60) }
            return "Starts at " + String(format: "%d:%02d", total / 60, total % 60)
        }
        if host == "youtu.be", !route.first.isEmpty { return Page("Video", start) }
        switch route.first {
        case "watch" where query["v"] != nil: return Page(query["list"] == nil ? "Video" : "Playlist video", start)
        case "shorts": return Page("Short")
        case "live": return Page("Live", start)
        case "playlist": return Page("Playlist")
        case "results": return Page("Search", query.search(using: ["search_query", "q"]))
        case "channel": return Page("Channel")
        case "c", "user": return Page("Channel", route[1])
        case "embed", "v": return Page("Video")
        default: return route.first.hasPrefix("@") ? Page("Channel", route[0]) : nil
        }
    }

    private static func googlePage(_ host: String, route: LinkRoute, query: LinkQuery) -> Page? {
        let first = route.first
        if host == "docs.google.com" {
            let documents = ["document": ("Docs", "Document"), "spreadsheets": ("Sheets", "Spreadsheet"),
                             "presentation": ("Slides", "Presentation"), "forms": ("Forms", "Form"), "drawings": ("Drawings", "Drawing")]
            if let document = route.parts.lazy.compactMap({ documents[$0] }).first {
                return Page(document.1, service: "Google \(document.0)")
            }
        }
        if host == "drive.google.com" {
            if route.parts.contains("folders") { return Page("Folder") }
            return ["file", "open", "uc"].contains(first) ? Page("File") : nil
        }
        if host == "meet.google.com", first.wholeMatch(of: #/[a-z]{3,4}-[a-z]{4}-[a-z]{3,4}/#) != nil {
            return Page("Meeting", first)
        }
        if host == "maps.google.com" || (isGoogle(host) && first == "maps") {
            let maps = LinkRoute(first == "maps" ? Array(route.parts.dropFirst()) : route.parts)
            let service = "Google Maps"
            switch maps.first {
            case "place" where !maps[1].isEmpty, "search" where !maps[1].isEmpty:
                return Page(maps.first == "place" ? "Place" : "Search", maps[1].replacingOccurrences(of: "+", with: " "), service: service)
            case "dir":
                let stops = maps.parts.dropFirst().filter { !$0.hasPrefix("@") && !$0.hasPrefix("data=") }
                    .map { $0.replacingOccurrences(of: "+", with: " ") }.joined(separator: " → ")
                return Page("Directions", stops, service: service)
            default:
                let address = query["q"] ?? query["query"]
                return Page(address == nil ? "Map" : "Search", address, service: service)
            }
        }
        if isGoogle(host), ["search", "webhp"].contains(first) || (first.isEmpty && query["q"] != nil) {
            return Page(query["tbm"] == "isch" || query["udm"] == "2" ? "Image search" : "Search", query.search)
        }
        if host == "play.google.com", let id = query["id"]?.split(separator: ".").last {
            return Page("App", humanize(String(id), domain: true))
        }
        return nil
    }

    private static func mediaPage(_ host: String, route: LinkRoute, query: LinkQuery) -> Page? {
        let first = route.first
        let second = route[1]
        if onHost(host, "spotify.com") {
            let path = first.hasPrefix("intl-") ? LinkRoute(Array(route.parts.dropFirst())) : route
            let kinds = ["track": "Track", "album": "Album", "playlist": "Playlist", "artist": "Artist",
                         "episode": "Episode", "show": "Podcast", "user": "Profile", "search": "Search"]
            if let kind = kinds[path.first] { return Page(kind, path.first == "search" ? path[1] : nil) }
        }
        if ["music.apple.com", "podcasts.apple.com", "apps.apple.com"].contains(host) {
            let kinds = ["album": "Album", "playlist": "Playlist", "song": "Song", "artist": "Artist", "podcast": "Podcast", "app": "App"]
            if let index = route.parts.firstIndex(where: { kinds[$0.lowercased()] != nil }) {
                return Page(kinds[route[index].lowercased()], humanize(route[index + 1]))
            }
        }
        if host == "soundcloud.com", !first.isEmpty {
            if second == "sets" { return Page("Playlist", humanize(route[2])) }
            return second.isEmpty ? Page("Profile", route[0]) : Page("Track", humanize(second))
        }
        if onHost(host, "twitch.tv") {
            if first == "videos" { return Page("Video") }
            if host == "clips.twitch.tv" || second == "clip" { return Page("Clip") }
            if !first.isEmpty, !["directory", "settings", "search", "downloads", "jobs", "p"].contains(first) { return Page("Channel", route[0]) }
        }
        if onHost(host, "netflix.com") {
            let kind = first.wholeMatch(of: #/[a-z]{2}(?:-[a-z]{2})?/#) == nil ? first : second.lowercased()
            if kind == "search" { return Page("Search", query.search) }
            if ["title", "watch"].contains(kind) { return Page(kind.capitalized) }
        }
        if host == "vimeo.com", !first.isEmpty, first.allSatisfy(\.isNumber) { return Page("Video") }
        if onHost(host, "imdb.com") {
            switch first {
            case "title": return Page("Title")
            case "name": return Page("Person")
            case "find": return Page("Search", query.search)
            default: break
            }
        }
        return nil
    }

    private static func socialPage(_ host: String, route: LinkRoute, query: LinkQuery) -> Page? {
        let first = route.first
        let second = route[1]
        let third = route[2]
        if host == "x.com" || onHost(host, "twitter.com") {
            let reserved = ["home", "explore", "notifications", "messages", "settings", "i", "search", "compose", "login", "signup", "tos", "privacy"]
            if first == "search" { return Page("Search", query.search) }
            if second == "status", !third.isEmpty { return Page("Post", "@\(route[0])") }
            return !first.isEmpty && !reserved.contains(first) ? Page("Profile", "@\(route[0])") : nil
        }
        if onHost(host, "linkedin.com") {
            switch first {
            case "in" where !second.isEmpty: return Page("Profile", second)
            case "company" where !second.isEmpty, "school" where !second.isEmpty:
                return Page(first.capitalized, humanize(second))
            case "jobs": return Page(second == "view" ? "Job" : "Jobs", genericTitle(third))
            case "posts" where !second.isEmpty:
                let post = second.firstMatch(of: #/(?i)^([^_]+)_(.*?)-(?:activity|ugcpost|share)-\d+/#)
                let title = post.map { humanize(String($0.2)) }
                return Page("Post", title?.contains(" ") == true ? title : post.map { String($0.1) })
            case "feed" where second == "update": return Page("Post")
            case "pulse" where !second.isEmpty: return Page("Article", genericTitle(second))
            case "groups": return Page("Group")
            case "events": return Page("Event")
            default: return nil
            }
        }
        if onHost(host, "instagram.com") {
            if first == "p", !second.isEmpty { return Page("Post") }
            if ["reel", "reels"].contains(first), !second.isEmpty { return Page("Reel") }
            if first == "stories", !second.isEmpty { return Page("Story", "@\(second)") }
            if first == "explore", second == "tags", !third.isEmpty { return Page("Tag", "#\(third)") }
            if !first.isEmpty, !["explore", "accounts", "direct", "tv", "about", "developer", "legal"].contains(first) {
                return Page(["p": "Post", "reel": "Reel"][second] ?? "Profile", "@\(route[0])")
            }
        }
        if onHost(host, "facebook.com") || ["fb.com", "fb.watch"].contains(host) {
            if host == "fb.watch" { return Page("Video") }
            if first == "groups", !second.isEmpty {
                return Page(["posts", "permalink"].contains(third) ? "Group post" : "Group", second.allSatisfy(\.isNumber) ? nil : humanize(second))
            }
            if first == "watch" || second == "videos" || first == "reel" { return Page(first == "reel" ? "Reel" : "Video") }
            if first == "events" { return Page("Event") }
            if first == "marketplace" { return Page(second == "item" ? "Marketplace item" : "Marketplace") }
            if ["photo", "photo.php"].contains(first) || second == "photos" { return Page("Photo") }
            if ["story.php", "permalink.php"].contains(first) || second == "posts" { return Page("Post") }
            if first == "share" { return Page("Shared link") }
            if first == "profile.php" { return Page("Profile") }
            if !first.isEmpty, !["login", "help", "settings", "pages", "gaming", "business", "privacy", "policies"].contains(first) { return Page("Page", route[0]) }
        }
        if onHost(host, "tiktok.com") {
            if first.hasPrefix("@") { return Page(second == "video" ? "Video" : "Profile", route[0]) }
            if first == "search" { return Page("Search", query.search) }
        }
        if ["threads.net", "threads.com"].contains(host), first.hasPrefix("@") {
            return Page(second == "post" ? "Post" : "Profile", route[0])
        }
        if host == "bsky.app", first == "profile", !second.isEmpty {
            return Page(third == "post" ? "Post" : "Profile", "@\(second)")
        }
        if onHost(host, "pinterest.com") {
            if first == "pin" { return Page("Pin") }
            if first == "search" { return Page("Search", query.search) }
            if !second.isEmpty { return Page("Board", humanize(second)) }
        }
        if host == "discord.gg" || (host == "discord.com" && first == "invite") { return Page("Invite") }
        if host == "discord.com", first == "channels" { return Page("Channel") }
        if ["t.me", "telegram.me"].contains(host), !first.isEmpty {
            if first.hasPrefix("+") || first == "joinchat" { return Page("Invite") }
            return Page(!second.isEmpty && second.allSatisfy(\.isNumber) ? "Message" : "Chat", "@\(route[0])")
        }
        if host == "wa.me", !first.isEmpty { return Page("Chat", "+" + first.drop(while: { $0 == "+" })) }
        if host == "chat.whatsapp.com" { return Page("Group invite") }
        if host == "linktr.ee", !first.isEmpty { return Page("Profile", "@\(route[0])") }
        return nil
    }

    private static func workPage(_ host: String, route: LinkRoute) -> Page? {
        let first = route.first
        let second = route[1]
        let third = route[2]
        if onHost(host, "zoom.us") || onHost(host, "zoom.com") {
            if ["j", "w", "s"].contains(first), !second.isEmpty {
                let digits = second.filter(\.isNumber)
                let groups = [9: [3, 3], 10: [3, 3], 11: [3, 4]][digits.count]
                let name = groups.map { lengths in
                    [digits.prefix(lengths[0]), digits.dropFirst(lengths[0]).prefix(lengths[1]), digits.dropFirst(lengths[0] + lengths[1])].joined(separator: " ")
                } ?? digits
                return Page(first == "w" ? "Webinar" : "Meeting", name)
            }
            if first == "my", !second.isEmpty { return Page("Personal room", second) }
            if first == "rec" { return Page("Recording") }
        }
        if ["teams.microsoft.com", "teams.live.com"].contains(host) {
            let path = route.parts.joined(separator: "/").lowercased()
            if path.contains("meetup-join") || first == "meet" { return Page("Meeting") }
            if path.contains("channel") { return Page("Channel") }
            if path.contains("chat") { return Page("Chat") }
        }
        if onHost(host, "webex.com") {
            if first == "meet", !second.isEmpty { return Page("Meeting", second) }
            if route.parts.contains(where: { ["j.php", "join"].contains($0.lowercased()) }) { return Page("Meeting") }
        }
        if host == "chatgpt.com" || host == "chat.openai.com" {
            if first == "c" || (first == "g" && third == "c") { return Page("Conversation") }
            if first == "share" { return Page("Shared conversation") }
            if first == "g", !second.isEmpty {
                return Page("GPT", humanize(second.replacingOccurrences(of: #"(?i)^g-[a-z0-9]+-?"#, with: "", options: .regularExpression)))
            }
        }
        if host == "claude.ai", let kind = ["chat": "Chat", "share": "Shared chat", "project": "Project"][first] { return Page(kind) }
        if host == "gemini.google.com", let kind = ["app": "Chat", "share": "Shared chat", "gem": "Gem"][first] { return Page(kind) }
        if onHost(host, "figma.com") {
            let kinds = ["file": "Design", "design": "Design", "proto": "Prototype", "board": "FigJam board", "slides": "Slides", "community": "Community file"]
            if let kind = kinds[first] { return Page(kind, humanize(third)) }
        }
        if (onHost(host, "notion.so") || onHost(host, "notion.site")), let last = route.parts.last {
            return Page("Page", humanize(last.replacingOccurrences(of: #"(?i)-?[0-9a-f]{32}$"#, with: "", options: .regularExpression)))
        }
        if host == "linear.app", second == "issue", !third.isEmpty {
            let name = humanize(route[3])
            return Page("Issue", name.isEmpty ? third : "\(third) · \(name)")
        }
        if onHost(host, "atlassian.net") {
            if first == "browse", !second.isEmpty { return Page("Issue", second, service: "Jira") }
            if first == "wiki" {
                return Page("Page", route.parts.firstIndex(of: "pages").map { humanize(route[$0 + 2]) }, service: "Confluence")
            }
        }
        if host == "trello.com", ["b", "c"].contains(first), !second.isEmpty {
            return Page(first == "b" ? "Board" : "Card", humanize(third.replacingOccurrences(of: #"^\d+-"#, with: "", options: .regularExpression)))
        }
        if host == "miro.com", first == "app" { return Page("Board") }
        if host == "canva.com", first == "design" { return Page("Design") }
        if onHost(host, "dropbox.com"), ["s", "scl"].contains(first) { return Page("Shared file", route.parts.last.map { humanize($0) }) }
        return nil
    }

    private static func softwarePage(_ host: String, route: LinkRoute) -> Page? {
        let first = route.first
        let second = route[1]
        let third = route[2]
        switch host {
        case "npmjs.com" where first == "package" && !second.isEmpty:
            return Page("Package", route.parts.dropFirst().joined(separator: "/"))
        case "pypi.org" where first == "project" && !second.isEmpty: return Page("Python package", second)
        case "crates.io" where first == "crates" && !second.isEmpty: return Page("Rust crate", second)
        case "pkg.go.dev" where !first.isEmpty: return Page("Go package", route.parts.joined(separator: "/"))
        case "hub.docker.com" where ["r", "_"].contains(first) && !second.isEmpty:
            return Page("Image", first == "_" ? second : route.parts.dropFirst().prefix(2).joined(separator: "/"))
        case "arxiv.org" where ["abs", "pdf"].contains(first) && !second.isEmpty:
            return Page("Paper", second.replacingOccurrences(of: #"(?i)\.pdf$"#, with: "", options: .regularExpression))
        case "doi.org" where !first.isEmpty: return Page("Paper", route.parts.joined(separator: "/"))
        case "huggingface.co":
            if ["datasets", "spaces"].contains(first), !third.isEmpty {
                return Page(first == "datasets" ? "Dataset" : "Space", "\(second)/\(third)")
            }
            if !second.isEmpty, !["docs", "blog", "papers", "learn", "tasks", "models"].contains(first) { return Page("Model", route.repository) }
        case "leetcode.com" where first == "problems" && !second.isEmpty: return Page("Problem", humanize(second))
        case "store.steampowered.com" where first == "app" && !second.isEmpty,
             "steamcommunity.com" where first == "app" && !second.isEmpty: return Page("Game", humanize(third))
        default: break
        }
        return nil
    }
}

struct LinkRoute {
    let parts: [String]

    init(_ parts: [String]) { self.parts = parts }

    var first: String { self[0].lowercased() }
    var repository: String {
        "\(self[0])/\(self[1].replacingOccurrences(of: #"(?i)\.git$"#, with: "", options: .regularExpression))"
    }

    subscript(_ index: Int) -> String { parts.indices.contains(index) ? parts[index] : "" }
}
