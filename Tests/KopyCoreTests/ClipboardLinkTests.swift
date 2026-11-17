import Foundation
import KopyCore
import Testing

@Suite("Offline link presentation")
struct ClipboardLinkTests {
    @Test(arguments: [
        ("https://github.com/apple/swift/issues/42", "GitHub · Issue", "apple/swift #42"),
        ("https://github.com/vercel/next.js/blob/canary/packages/next/src/server/next.ts", "GitHub · File",
         "vercel/next.js · packages/next/src/server/next.ts"),
        ("https://youtu.be/dQw4w9WgXcQ?t=1h2m3s", "YouTube · Video", "Starts at 1:02:03"),
        ("https://www.reddit.com/r/reactjs/comments/12345/awesome_new_state_manager/", "Reddit · r/reactjs",
         "Awesome New State Manager"),
        ("https://en.m.wikipedia.org/wiki/Mount_Everest#History", "Wikipedia · Article", "Mount Everest § History"),
        ("https://www.google.com/maps/dir/Home/Office/@12.9,77.6,13z", "Google Maps · Directions", "Home → Office"),
        ("https://us02web.zoom.us/j/1234567890?pwd=abc", "Zoom · Meeting", "123 456 7890"),
        ("https://www.figma.com/design/AbC123/Edge-Drop-UI?node-id=1-2", "Figma · Design", "Edge Drop UI"),
        ("https://www.notion.so/myteam/Project-Roadmap-0123456789abcdef0123456789abcdef", "Notion · Page", "Project Roadmap"),
        ("https://www.npmjs.com/package/@types/react", "npm · Package", "@types/react"),
        ("http://localhost:3000/dashboard", "This computer · Port 3000", "Dashboard"),
        ("https://www.google.co.uk/search?q=running+swift", "Google · Search", "running swift")
    ])
    func identifiesOfflinePageTypes(_ url: String, _ heading: String, _ title: String) throws {
        let preview = try #require(ClipboardText(url).linkPreview)
        #expect(preview.heading == heading)
        #expect(preview.title == title)
    }

    @Test(arguments: [
        ("https://www.google.com/url?q=https://example.com/page&sa=D", "https://example.com/page"),
        ("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fa%3Fx%3D1%26utm_source%3Dfb&h=AT0", "https://example.com/a?x=1"),
        ("https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.org%2Fdoc&data=05", "https://example.org/doc"),
        ("https://example.com/url?q=https://example.org&UTM_source=test&value=%2f+%20#top", "https://example.com/url?q=https://example.org&value=%2f+%20#top"),
        ("(https://example.com/a_(b))", "https://example.com/a_(b)"),
        ("https://example.com/page?utm_source=x&id=5)", "https://example.com/page?id=5")
    ])
    func preservesFunctionalParameters(_ original: String, _ clean: String) {
        let text = ClipboardText(original)
        #expect(text.cleanedURL?.absoluteString == clean)
        #expect(text.value == original)
    }

    @Test
    func displaysReadableAddressesWithoutExposingCredentialsOrSpoofingHosts() throws {
        let address = try #require(ClipboardText("https://user:pass@example.com/path").linkPreview?.address)
        #expect(address == "example.com/path")
        let unicode = try #require(ClipboardText("https://例子.测试/路径").linkPreview?.address)
        #expect(unicode == "例子.测试/路径")
        let spoof = try #require(ClipboardText("https://xn--80ak6aa92e.com/").linkPreview?.address)
        #expect(spoof == "xn--80ak6aa92e.com")
    }
}
