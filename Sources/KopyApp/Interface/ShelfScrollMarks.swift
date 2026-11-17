import AppKit
import SwiftUI

@MainActor
final class ShelfScrollMarks {
    struct Location: Equatable {
        let id: UUID
        let edge: Edge
        let anchor: UnitPoint?
    }

    @MainActor
    enum Edge: Equatable {
        case top, left, right

        func offset(of row: CGRect, in clip: NSClipView) -> CGFloat {
            switch self {
            case .top:
                clip.isFlipped ? row.minY - clip.bounds.minY : clip.bounds.maxY - row.maxY
            case .left:
                row.minX - clip.bounds.minX
            case .right:
                clip.bounds.maxX - row.maxX
            }
        }

        func anchor(for row: CGRect, in clip: NSClipView) -> UnitPoint? {
            let remaining: CGFloat
            switch self {
            case .top: remaining = clip.bounds.height - row.height
            case .left, .right: remaining = clip.bounds.width - row.width
            }
            guard remaining > 0 else { return nil }
            let fraction = offset(of: row, in: clip) / remaining
            return self == .top ? UnitPoint(x: 0.5, y: fraction) : UnitPoint(x: fraction, y: 0.5)
        }
    }

    private let rows = NSMapTable<NSUUID, NSView>.strongToWeakObjects()

    func capture(id: UUID, edge: Edge) -> Location {
        let anchor = rows.object(forKey: id as NSUUID).flatMap { view in
            view.enclosingScrollView.flatMap { scroll in
                let clip = scroll.contentView
                return edge.anchor(for: view.convert(view.bounds, to: clip), in: clip)
            }
        }
        return Location(id: id, edge: edge, anchor: anchor)
    }

    fileprivate func attach(_ view: NSView, id: UUID) {
        rows.setObject(view, forKey: id as NSUUID)
    }
}

struct ShelfScrollMarker: NSViewRepresentable {
    let id: UUID
    let marks: ShelfScrollMarks

    func makeNSView(context: Context) -> Marker { Marker() }

    func updateNSView(_ view: Marker, context: Context) {
        view.id = id
        view.marks = marks
        view.register()
    }

    final class Marker: NSView {
        var id: UUID?
        weak var marks: ShelfScrollMarks?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            register()
        }

        override func layout() {
            super.layout()
            register()
        }

        func register() {
            guard let id, window != nil else { return }
            marks?.attach(self, id: id)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
