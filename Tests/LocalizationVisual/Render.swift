import AppKit
import SwiftUI
@testable import KopyApp

@main
struct LocalizationRender {
    enum CaptureError: Error {
        case missingOutputDirectory
        case missingLocalization(String)
        case invalidImage(URL)
    }

    @MainActor
    static func main() throws {
        guard let destination = CommandLine.arguments.dropFirst().first else {
            throw CaptureError.missingOutputDirectory
        }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.prohibited)

        let fixture = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let model = KopyModel(demo: true, isolatedProfile: fixture)
        for language in ShelfLanguage.available.map(\.identifier) {
            guard Bundle.main.url(forResource: language, withExtension: "lproj") != nil else {
                throw CaptureError.missingLocalization(language)
            }
            model.updatePreferences { $0.language = language }
            model.message = ShelfLanguage.errorMessage(
                ClipboardTransferError.missingFile("Fixture sample.txt"), language: language
            )
            try render(KopyLanguageRoot(model: model) { ShelfView(model: model) },
                       width: 362, height: 574, to: output.appending(path: "\(language)-shelf.png"))
            try render(KopyLanguageRoot(model: model) { SettingsView(model: model) },
                       width: 560, height: 540, to: output.appending(path: "\(language)-settings.png"))
        }
    }

    @MainActor
    private static func render(
        _ content: some View, width: CGFloat, height: CGFloat, to path: URL
    ) throws {
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let view = NSHostingView(rootView: content.frame(width: width, height: height))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: frame) else { throw CaptureError.invalidImage(path) }
        view.cacheDisplay(in: frame, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.invalidImage(path) }
        try png.write(to: path)
    }
}
