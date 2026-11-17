import Foundation

public struct ClipboardColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public var hex: String {
        let rgb = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha == 1 ? rgb : rgb + String(format: "%02X", byte(alpha))
    }

    public var rgb: String {
        let channels = "\(byte(red)), \(byte(green)), \(byte(blue))"
        return alpha == 1 ? "rgb(\(channels))" : "rgba(\(channels), \(alphaText))"
    }

    public var hsl: String {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        let light = (high + low) / 2
        var hue = 0.0
        var saturation = 0.0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * light - 1))
            if high == red {
                hue = (green - blue) / delta
            } else if high == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
        }
        let degrees = (Int((hue * 60).rounded()) + 360) % 360
        let channels = "\(degrees), \(Int((saturation * 100).rounded()))%, \(Int((light * 100).rounded()))%"
        return alpha == 1 ? "hsl(\(channels))" : "hsla(\(channels), \(alphaText))"
    }

    private func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
    private var alphaText: String { String((alpha * 100).rounded() / 100) }

    public init?(_ value: String) {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.utf8.count <= 100 else { return nil }
        if input.hasPrefix("#") {
            let digits = input.dropFirst()
            guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit),
                  let number = UInt32(digits, radix: 16) else {
                return nil
            }
            let short = digits.count <= 4
            let bits = short ? 4 : 8
            let scale = short ? 15.0 : 255.0
            let mask: UInt32 = short ? 0xF : 0xFF
            let hasAlpha = digits.count.isMultiple(of: 4)
            let rgb = hasAlpha ? number >> bits : number
            self.init(
                red: Double((rgb >> (bits * 2)) & mask) / scale,
                green: Double((rgb >> bits) & mask) / scale,
                blue: Double(rgb & mask) / scale,
                alpha: hasAlpha ? Double(number & mask) / scale : 1
            )
            return
        }

        guard input.hasSuffix(")"), let opening = input.firstIndex(of: "(") else { return nil }
        let kind = input[..<opening].lowercased()
        let body = input[input.index(after: opening)..<input.index(before: input.endIndex)]
        let components: [String]
        if body.contains(",") {
            components = body.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            let groups = body.split(separator: "/", omittingEmptySubsequences: false)
            guard groups.count <= 2, let first = groups.first else { return nil }
            let channels = first.split(whereSeparator: \.isWhitespace)
            guard channels.count == 3 else { return nil }
            components = channels.map(String.init) + groups.dropFirst().map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard (3...4).contains(components.count),
              let alpha = components.count == 4 ? Self.number(components[3], scale: 1) : 1 else { return nil }
        switch kind {
        case "rgb", "rgba":
            guard let red = Self.number(components[0], scale: 255),
                  let green = Self.number(components[1], scale: 255),
                  let blue = Self.number(components[2], scale: 255) else { return nil }
            self.init(red: red, green: green, blue: blue, alpha: alpha)
        case "hsl", "hsla":
            let hue = components[0].lowercased()
            let degrees = hue.hasSuffix("deg") ? String(hue.dropLast(3)) : hue
            guard let angle = Double(degrees), angle.isFinite,
                  components[1].hasSuffix("%"), let s = Self.number(components[1], scale: 100),
                  components[2].hasSuffix("%"), let l = Self.number(components[2], scale: 100) else { return nil }
            let h = (angle.truncatingRemainder(dividingBy: 360) + 360) / 30
            func channel(_ offset: Double) -> Double {
                let k = (offset + h).truncatingRemainder(dividingBy: 12)
                return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
            }
            self.init(red: channel(0), green: channel(8), blue: channel(4), alpha: alpha)
        default:
            return nil
        }
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    private static func number(_ text: String, scale: Double) -> Double? {
        let percent = text.hasSuffix("%")
        let value = percent ? String(text.dropLast()) : text
        guard let raw = Double(value), raw.isFinite else { return nil }
        return min(max(raw / (percent ? 100 : scale), 0), 1)
    }
}

extension ClipboardText {
    public var detectedColor: ClipboardColor? { ClipboardColor(value) }
}
