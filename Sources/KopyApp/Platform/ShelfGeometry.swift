import AppKit
import KopyCore

struct ShelfDisplay: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let frame: CGRect
    let workArea: CGRect
    var safeTopInset: CGFloat = 0

    @MainActor static var connected: [Self] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return Self(id: number.uint32Value, name: screen.localizedName, frame: screen.frame,
                        workArea: screen.visibleFrame, safeTopInset: screen.safeAreaInsets.top)
        }
    }

    static func selected(in displays: [Self], for preferences: ShelfPreferences) -> Self? {
        preferred(in: displays, for: preferences) ?? displays.first
    }

    static func preferred(in displays: [Self], for preferences: ShelfPreferences) -> Self? {
        if let id = preferences.displayID, let match = displays.first(where: { $0.id == id }) { return match }
        guard let bounds = preferences.displayBounds else { return nil }
        return displays.first { Self.matches($0.frame, bounds, tolerance: 24) }
    }

    static func hasFullscreenWindow(in windows: [[String: Any]], displayBounds: CGRect,
                                    safeTopInset: CGFloat = 0, ignoring process: pid_t) -> Bool {
        windows.contains { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner != process,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            if Self.matches(frame, displayBounds, tolerance: 3) { return true }
            let topOffset = frame.minY - displayBounds.minY
            return safeTopInset > 0 && abs(topOffset - safeTopInset) <= 8
                && abs(frame.minX - displayBounds.minX) < 3
                && abs(frame.maxX - displayBounds.maxX) < 3
                && abs(frame.maxY - displayBounds.maxY) < 3
        }
    }

    private static func matches(_ frame: CGRect, _ bounds: CGRect, tolerance: CGFloat) -> Bool {
        abs(frame.minX - bounds.minX) < tolerance && abs(frame.minY - bounds.minY) < tolerance &&
            abs(frame.maxX - bounds.maxX) < tolerance && abs(frame.maxY - bounds.maxY) < tolerance
    }
}

struct ShelfGeometry {
    let edge: ShelfEdge
    let workArea: CGRect

    init(edge: ShelfEdge, workArea: CGRect) {
        self.edge = edge
        self.workArea = workArea
    }

    func trigger(_ preferences: ShelfPreferences) -> CGRect {
        let thickness = min(preferences.edgeThickness, min(workArea.width, workArea.height))
        let panel = shelf(preferences)
        if edge == .top {
            let preset = preferences.edgeSpan >= 0.55 ? 575.0 : preferences.edgeSpan >= 0.35 ? 400 : 275
            let length = min(panel.width, preset)
            return CGRect(
                x: panel.minX + (panel.width - length) * preferences.edgeAlignment,
                y: workArea.maxY - thickness, width: length, height: thickness
            )
        }
        let length = min(panel.height, workArea.height * preferences.edgeSpan)
        return CGRect(
            x: edge == .left ? workArea.minX : workArea.maxX - thickness,
            y: panel.minY + (panel.height - length) * preferences.edgeAlignment,
            width: thickness, height: length
        )
    }

    func shelf(_ preferences: ShelfPreferences) -> CGRect {
        if edge == .top {
            let width = min(860, max(1, workArea.width - 32))
            let height = min(296, workArea.height)
            return CGRect(
                x: workArea.minX + (workArea.width - width) * preferences.horizontalOffset,
                y: workArea.maxY - height, width: width, height: height
            )
        }
        let width = min(362, workArea.width)
        let height = min(workArea.height, max(360, workArea.height * preferences.shelfHeight))
        return CGRect(
            x: edge == .left ? workArea.minX : workArea.maxX - width,
            y: workArea.minY + (workArea.height - height) * (1 - preferences.offset),
            width: width, height: height
        )
    }

    func intoScreen(_ point: CGPoint) -> Double {
        switch edge {
        case .left: point.x - workArea.minX
        case .right: workArea.maxX - point.x
        case .top: workArea.maxY - point.y
        }
    }

    func approach(_ trigger: CGRect, depth: Double, margin: Double = 0) -> CGRect {
        switch edge {
        case .left:
            CGRect(x: trigger.minX, y: trigger.minY - margin, width: depth, height: trigger.height + 2 * margin)
        case .right:
            CGRect(x: trigger.maxX - depth, y: trigger.minY - margin, width: depth, height: trigger.height + 2 * margin)
        case .top:
            CGRect(x: trigger.minX - margin, y: trigger.maxY - depth, width: trigger.width + 2 * margin, height: depth)
        }
    }

    func dragCatch(_ trigger: CGRect) -> CGRect {
        approach(trigger, depth: edge == .top ? 40 : 48, margin: 24).intersection(workArea)
    }

    func dragPull(_ point: CGPoint, toward trigger: CGRect) -> Double {
        let along = edge == .top ? point.x : point.y
        let lower = edge == .top ? trigger.minX : trigger.minY
        let upper = edge == .top ? trigger.maxX : trigger.maxY
        let pastEnd = max(lower - along, along - upper, 0)
        let progress = max(0, 1 - hypot(max(0, intoScreen(point)), pastEnd) / 360)
        return progress * progress * (3 - 2 * progress)
    }

    func retractedFrame(for panel: CGRect, toward trigger: CGRect) -> CGRect {
        let edgeStrip = panel.intersection(trigger)
        if !edgeStrip.isEmpty { return edgeStrip }
        let nearest = edge == .top
            ? CGPoint(x: min(max(trigger.midX, panel.minX), panel.maxX - 1), y: panel.maxY - 1)
            : CGPoint(x: edge == .left ? panel.minX : panel.maxX - 1,
                      y: min(max(trigger.midY, panel.minY), panel.maxY - 1))
        return CGRect(origin: nearest, size: CGSize(width: 1, height: 1))
    }
}
