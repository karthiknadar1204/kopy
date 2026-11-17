import AppKit
import KopyCore
import SwiftUI

struct NativeDragGrip: NSViewRepresentable {
    let model: KopyModel
    let item: ClipboardItem
    var members: Set<UUID>? = nil
    var onPress: ((NSEvent.ModifierFlags) -> Void)? = nil

    func makeNSView(context: Context) -> GripView {
        GripView(showsGrip: onPress == nil)
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.items = { model.nativeDragItems(item, members: members) }
        view.completed = { model.finishExternalDrag(item, members: members) }
        view.ended = model.clipboard.finishDrag
        view.onPress = onPress
        if onPress == nil {
            let label = ShelfLanguage.string("Drag files", language: model.preferences.language)
            view.toolTip = label
            view.setAccessibilityLabel(label)
        }
    }

    final class GripView: NSView, NSDraggingSource {
        var items: (() -> [NSDraggingItem])?
        var completed: (() -> Void)?
        var ended: (() -> Void)?
        var onPress: ((NSEvent.ModifierFlags) -> Void)?
        private var start: CGPoint?
        private var sourceFrame: CGRect?

        init(showsGrip: Bool) {
            super.init(frame: .zero)
            setAccessibilityElement(showsGrip)
            guard showsGrip else { return }
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            icon.symbolConfiguration = .init(pointSize: 10, weight: .medium)
            icon.contentTintColor = .secondaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent,
               event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                return nil
            }
            return super.hitTest(point) == nil ? nil : self
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            start = event.locationInWindow
        }

        override func mouseUp(with event: NSEvent) {
            let wasPressed = start != nil
            start = nil
            if wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) {
                onPress?(event.modifierFlags)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            let location = event.locationInWindow
            guard let start, hypot(location.x - start.x, location.y - start.y) >= 4 else { return }
            self.start = nil
            guard let items = items?(), !items.isEmpty else { return }
            let point = convert(location, from: nil)
            for (index, item) in items.enumerated() {
                let offset = CGFloat(min(index, 4)) * 3
                item.draggingFrame.origin = CGPoint(x: point.x - 18 + offset, y: point.y - 18 - offset)
            }
            sourceFrame = window?.frame
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.draggingFormation = .none
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            defer {
                sourceFrame = nil
                ended?()
            }
            if operation.contains(.copy), sourceFrame?.contains(screenPoint) != true { completed?() }
        }
    }
}
