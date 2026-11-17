import AppKit
import KopyCore
import SwiftUI

@main
struct StoreScreenshots {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = KopyModel(demo: true)
        let item = model.items.first { $0.category == .text }!
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            try await render(title: "Clipboard history", appearance: appearance, to: output.appending(path: "history-\(name).png")) {
                ShelfView(model: model).frame(width: 362, height: 580)
                WelcomeView(model: model).frame(width: 540, height: 365)
                    .background(ShelfTheme.surface, in: .rect(cornerRadius: 16))
            }
            try await render(title: "Preview before pasting", appearance: appearance, to: output.appending(path: "preview-\(name).png")) {
                ShelfView(model: model).frame(width: 362, height: 580)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Preview").font(.headline).padding(16)
                    ClipPreview(item: item, model: model, horizontal: false, onClose: {})
                }
                .frame(width: 420, height: 480)
                .background(ShelfTheme.surface, in: .rect(cornerRadius: 16))
            }
        }
    }

    @MainActor private static func render(
        title: String, appearance: NSAppearance.Name, to url: URL, @ViewBuilder content: () -> some View
    ) async throws {
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let root = VStack(spacing: 28) {
            HStack(spacing: 10) {
                KopyBadge(size: 36)
                Text(verbatim: "Kopy").font(.system(size: 28, weight: .semibold))
                Spacer()
                Text(verbatim: title).font(.system(size: 22, weight: .medium))
            }
            .padding(.horizontal, 100)
            HStack(spacing: 36) { content() }
            Spacer(minLength: 0)
        }
        .padding(.top, 38)
        .frame(width: frame.width, height: frame.height)
        .background(ShelfTheme.background)
        .foregroundStyle(ShelfTheme.ink)
        .tint(ShelfTheme.accent)
        .kopyLanguage("en")
        let view = NSHostingView(rootView: root)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: frame) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: frame, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
