import AppKit
import KopyCore
import SwiftUI
import UniformTypeIdentifiers

enum ShelfTheme {
    static let background = adaptive(light: 0xF5F3F0, dark: 0x191A1D)
    static let toolbar = adaptive(light: 0xFBFAF8, dark: 0x222327)
    static let surface = adaptive(light: 0xFFFDFB, dark: 0x24262A)
    static let inset = adaptive(light: 0xEAE7E2, dark: 0x2D2E33)
    static let line = adaptive(light: 0xDCD7D0, dark: 0x3C3D43)
    static let ink = adaptive(light: 0x232321, dark: 0xF7F3ED)
    static let muted = adaptive(light: 0x66635F, dark: 0xACA9A5)
    static let accent = adaptive(light: 0xA1442B, dark: 0xFFAB8C)
    static let highlight = adaptive(light: 0xF6E3DB, dark: 0x48302C)
    static let action = Color(.sRGB, red: 0.63, green: 0.27, blue: 0.17)
    static let link = adaptive(light: 0x365D8C, dark: 0xA4C4F3)
    static let media = adaptive(light: 0x386F62, dark: 0x9DCEBD)
    static let radius: CGFloat = 16
    static let internalDrag = UTType(exportedAs: "com.kopy.clipboard-item")

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct ShelfIconButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color = ShelfTheme.muted
    var size: CGFloat = 30
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .frame(width: size, height: size)
                .contentShape(.rect)
                .background(hovering ? ShelfTheme.inset : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? ShelfTheme.ink : tint)
        .accessibilityLabel(Text(title))
        .help(Text(title))
        .onHover { hovering = $0 }
    }
}

struct KopyBadge: View {
    var size: CGFloat = 29

    var body: some View {
        Image(nsImage: KopyMark.template)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.58, height: size * 0.58)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ShelfTheme.action, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct ShelfPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(minHeight: 28)
            .background(ShelfTheme.action.opacity(configuration.isPressed ? 0.78 : 1), in: .rect(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct ShelfSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ShelfTheme.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 28)
            .background(configuration.isPressed ? ShelfTheme.line : ShelfTheme.inset, in: .rect(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension View {
    func shelfField(isFocused: Bool) -> some View {
        self
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(ShelfTheme.background, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isFocused ? ShelfTheme.accent.opacity(0.75) : ShelfTheme.line)
                    .allowsHitTesting(false)
            }
    }
}

extension ClipboardFilter {
    var shelfTitle: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .links: "Links"
        case .images: "Images"
        case .files: "Files"
        case .colors: "Colors"
        }
    }

    var shelfSymbol: String {
        switch self {
        case .all: "tray"
        case .text: "text.alignleft"
        case .links: "link"
        case .images: "photo"
        case .files: "folder"
        case .colors: "paintpalette"
        }
    }
}

extension ClipboardItem {
    var shelfIcon: String {
        if payload.isStack { return "square.stack.3d.up" }
        if let member = payload.members.first { return member.shelfSymbol }
        return category.shelfSymbol
    }

    var shelfTint: Color {
        switch category {
        case .links: ShelfTheme.link
        case .images: ShelfTheme.media
        case .files: payload.isStack ? ShelfTheme.accent : ShelfTheme.muted
        default: ShelfTheme.muted
        }
    }

    var shelfTitle: Text {
        switch payload {
        case .image(let image) where image.name == nil:
            Text("Clipboard image")
        case .images(let images):
            Text("\(images.count) images")
        case .files(let members) where members.count != 1:
            Text("\(members.count) items")
        default:
            Text(verbatim: displayTitle)
        }
    }
}

extension ClipboardMember {
    var shelfTitle: Text {
        switch self {
        case .image(let image) where image.name == nil: Text("Clipboard image")
        default: Text(verbatim: name)
        }
    }

    var shelfSymbol: String {
        switch self {
        case .file(let file): file.isDirectory ? "folder" : isImage ? "photo" : "doc"
        case .image: "photo"
        }
    }
}
