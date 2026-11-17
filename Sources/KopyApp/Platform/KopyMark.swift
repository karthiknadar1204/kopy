import AppKit

enum KopyMark {
    static func draw(in context: CGContext, bounds: CGRect, front: CGColor, back: CGColor) {
        context.saveGState()
        context.translateBy(x: bounds.minX, y: bounds.minY)
        context.scaleBy(x: bounds.width / 100, y: bounds.height / 100)

        let backSheet = CGRect(x: 8, y: 25, width: 61, height: 66)
        let frontSheet = CGRect(x: 30, y: 9, width: 62, height: 66)
        context.saveGState()
        context.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.addPath(CGPath(roundedRect: frontSheet.insetBy(dx: -6, dy: -6),
                               cornerWidth: 17, cornerHeight: 17, transform: nil))
        context.clip(using: .evenOdd)
        context.setFillColor(back)
        context.addPath(CGPath(roundedRect: backSheet, cornerWidth: 14, cornerHeight: 14, transform: nil))
        context.fillPath()
        context.restoreGState()

        let face = CGMutablePath()
        face.addRoundedRect(in: frontSheet, cornerWidth: 13, cornerHeight: 13)
        face.addRoundedRect(in: CGRect(x: 45, y: 45, width: 31, height: 5), cornerWidth: 2.5, cornerHeight: 2.5)
        face.addRoundedRect(in: CGRect(x: 45, y: 31, width: 22, height: 5), cornerWidth: 2.5, cornerHeight: 2.5)
        context.setFillColor(front)
        context.addPath(face)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    @MainActor static let template: NSImage = {
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            KopyMark.draw(in: context, bounds: bounds, front: CGColor(gray: 0, alpha: 1),
                          back: CGColor(gray: 0, alpha: 0.65))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kopy"
        return image
    }()
}
