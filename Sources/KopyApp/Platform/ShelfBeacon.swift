import AppKit
import KopyCore

@MainActor
final class ShelfBeacon {
    enum Cue: Equatable {
        case idle, intro, hint, drag(Int), copied(CopyIndicatorStyle)

        var symbol: String? {
            guard case .copied(let style) = self else { return nil }
            switch style {
            case .logo: return "rectangle.on.rectangle"
            case .check: return "checkmark"
            case .copy: return "doc.on.doc"
            case .sparkle: return "sparkles"
            }
        }

        var extraDepth: Double {
            switch self {
            case .idle: 0
            case .intro: 6
            case .hint: 4
            case .drag(let step): 3 + Double(step) * 3
            case .copied: 31
            }
        }

        var margin: Double {
            switch self {
            case .idle, .copied: 0
            case .intro: 11
            case .hint: 7
            case .drag(let step): 6 + Double(step) * 3
            }
        }
    }

    private let panel = ShelfPanel()
    private let content = NSView()
    private let shape = CAShapeLayer()
    private let glyph = NSImageView()
    private var lastCue: Cue?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.contentView = content
        content.wantsLayer = true
        content.layer?.addSublayer(shape)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.contentTintColor = .labelColor
        glyph.isHidden = true
        content.addSubview(glyph)
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        panel.collectionBehavior = behavior
    }

    func show(_ cue: Cue, at trigger: CGRect, in geometry: ShelfGeometry, animated: Bool) {
        let isTop = geometry.edge == .top
        let thickness = isTop ? trigger.height : trigger.width
        let canvas = geometry.approach(trigger, depth: thickness + 32, margin: 21).intersection(geometry.workArea)
        guard panel.frame != canvas || lastCue != cue || !panel.isVisible else { return }
        let oldPath = panel.frame == canvas && panel.isVisible ? (shape.presentation()?.path ?? shape.path) : nil
        panel.setFrame(canvas, display: true)

        // The thin bar stays visible while its copy-confirmation tab grows and retracts.
        let path = CGMutablePath()
        addRoundedRect(trigger.intersection(canvas), to: path, in: canvas, radius: thickness / 2)
        let highlight: CGRect
        if cue.symbol != nil {
            let tabWidth = max(1, min(47, isTop ? trigger.width : trigger.height))
            let tab = isTop
                ? CGRect(x: trigger.midX - tabWidth / 2, y: trigger.minY, width: tabWidth, height: trigger.height)
                : CGRect(x: trigger.minX, y: trigger.midY - tabWidth / 2, width: trigger.width, height: tabWidth)
            highlight = geometry.approach(tab, depth: thickness + cue.extraDepth).intersection(canvas)
        } else {
            highlight = geometry.approach(trigger, depth: thickness + cue.extraDepth, margin: cue.margin).intersection(canvas)
        }
        addRoundedRect(highlight, to: path, in: canvas, radius: cue.symbol != nil ? 12 : (thickness + cue.extraDepth) / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = content.bounds
        shape.fillColor = NSColor.labelColor.withAlphaComponent(cue == .idle ? 0.38 : 0.29).cgColor
        shape.path = path
        CATransaction.commit()
        shape.removeAnimation(forKey: "beacon")
        if animated, let oldPath {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = oldPath
            animation.toValue = path
            animation.duration = 0.17
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shape.add(animation, forKey: "beacon")
        }
        let iconCenter = CGPoint(x: highlight.midX - canvas.minX, y: highlight.midY - canvas.minY)
        glyph.frame = CGRect(x: iconCenter.x - 8, y: iconCenter.y - 8, width: 16, height: 16)
        glyph.image = cue.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        glyph.isHidden = glyph.image == nil
        if !panel.isVisible { panel.orderFrontRegardless() }
        lastCue = cue
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        shape.removeAnimation(forKey: "beacon")
        lastCue = nil
    }

    private func addRoundedRect(_ frame: CGRect, to path: CGMutablePath, in canvas: CGRect, radius: Double) {
        let local = frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
        path.addRoundedRect(in: local, cornerWidth: radius, cornerHeight: radius)
    }
}
