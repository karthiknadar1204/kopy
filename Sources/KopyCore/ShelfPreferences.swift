import CoreGraphics
import Foundation

public enum ShelfEdge: String, CaseIterable, Codable, Identifiable, Sendable {
    case left, top, right

    public var id: Self { self }
}

public enum CopyIndicatorStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case logo, check, copy, sparkle

    public var id: Self { self }
}

public enum ShelfCardDensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case modern, compact

    public var id: Self { self }
}

public struct ShelfShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var display: String

    public init(keyCode: UInt32 = 9, modifiers: UInt32 = 6, display: String = "⌃⌥V") {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }
}

public struct ShelfPreferences: Codable, Equatable, Sendable {
    public var edge: ShelfEdge = .left
    public var displayID: UInt32?
    public var displayBounds: CGRect?
    public var edgeThickness = 3.0
    public var edgeSpan = 0.25
    public var edgeAlignment = 0.5
    public var offset = 0.5
    public var shelfHeight = 0.5
    public var openDelayMilliseconds = 0
    public var hoverEnabled = true
    public var suppressFullscreen = true
    public var incognito = false
    public var movePastedToTop = true
    public var historyLimit = 250
    public var autoDeleteHours = 0
    public var clearOnRestart = false
    public var soundEffects = true
    public var showCopyIndicator = true
    public var copyIndicatorStyle: CopyIndicatorStyle = .logo
    public var showEdgeLocationHint = false
    public var fontScale = 1.0
    public var reduceMotion = false
    public var language = "system"
    public var shortcut = ShelfShortcut()
    private var savedCardDensity: ShelfCardDensity?
    private var savedHorizontalOffset: Double?

    public var cardDensity: ShelfCardDensity {
        get { savedCardDensity ?? .modern }
        set { savedCardDensity = newValue == .modern ? nil : newValue }
    }

    public var horizontalOffset: Double {
        get { savedHorizontalOffset ?? 0.5 }
        set { savedHorizontalOffset = newValue == 0.5 ? nil : newValue }
    }

    public init() {}

    public func normalized() -> Self {
        var result = self
        result.edgeThickness = finite(edgeThickness, default: 3, range: 1...7)
        result.edgeSpan = finite(edgeSpan, default: 0.25, range: 0.2...0.6)
        result.edgeAlignment = finite(edgeAlignment, default: 0.5, range: 0...1)
        result.offset = finite(offset, default: 0.5, range: 0...1)
        result.horizontalOffset = finite(horizontalOffset, default: 0.5, range: 0...1)
        result.shelfHeight = finite(shelfHeight, default: 0.5, range: 0.3...0.9)
        let delay = min(max(openDelayMilliseconds, 0), 1_000)
        result.openDelayMilliseconds = ((delay + 25) / 50) * 50
        result.historyLimit = min(max(historyLimit, 50), 2_000)
        result.autoDeleteHours = [0, 1, 6, 24, 168].contains(autoDeleteHours) ? autoDeleteHours : 0
        result.fontScale = finite(fontScale, default: 1, range: 0.85...1.15)
        return result
    }

    private func finite(_ value: Double, default fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
