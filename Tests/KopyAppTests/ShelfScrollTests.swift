import AppKit
import Testing
@testable import KopyApp

@MainActor
struct ShelfScrollTests {
    @Test("The saved anchor tracks a partially visible row after it moves")
    func captureOffset() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 250, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let document = FlippedView(frame: CGRect(x: 0, y: 0, width: 250, height: 1_000))
        let marker = ShelfScrollMarker.Marker(frame: CGRect(x: 0, y: 425, width: 200, height: 48))
        let marks = ShelfScrollMarks()
        let id = UUID()
        marker.id = id
        marker.marks = marks
        document.addSubview(marker)
        scroll.documentView = document
        window.contentView = scroll
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 441))
        let saved = marks.capture(id: id, edge: .top)
        let anchor = try #require(saved.anchor)
        #expect(anchor.y == -16 / (scroll.contentView.bounds.height - marker.bounds.height))

        marker.frame.origin.y += 51
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 492))
        #expect(marks.capture(id: id, edge: .top) == saved)
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
