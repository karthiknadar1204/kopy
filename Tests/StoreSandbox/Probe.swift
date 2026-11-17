import AppKit
import KopyCore
import SwiftUI

@main
struct StoreSandboxProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var status: NSTextField?
    private var recordURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "KopyStoreProbe").appending(path: "Fixture.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Kopy Sandbox File Check"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let choose = NSButton(title: "Choose fixture file", target: self, action: #selector(chooseFixture))
        let reopen = NSButton(title: "Reopen stored reference", target: self, action: #selector(reopenFixture))
        let status = NSTextField(wrappingLabelWithString: "Choose the sandbox fixture. Relaunch, then reopen its stored reference.")
        stack.addArrangedSubview(choose)
        stack.addArrangedSubview(reopen)
        stack.addArrangedSubview(status)
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor)
        ])
        self.status = status
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        appActivate()
    }

    private func appActivate() { NSApp.activate() }

    @objc private func chooseFixture() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let board = NSPasteboard(name: NSPasteboard.Name("com.kopy.sandbox.fixture"))
        board.clearContents()
        board.writeObjects([url as NSURL])
        guard case .file(let file) = ClipboardPayloadCodec.files(from: board).first,
              file.bookmarkIsSecurityScoped == true else {
            status?.stringValue = "FAIL: no scoped bookmark was created."
            return
        }
        do {
            try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: recordURL)
            try verify(file)
            status?.stringValue = "PASS: scoped bookmark saved and fixture read. Relaunch to verify persistence."
        } catch { status?.stringValue = "FAIL: \(error.localizedDescription)" }
    }

    @objc private func reopenFixture() {
        do {
            let file = try JSONDecoder().decode(ClipboardFile.self, from: Data(contentsOf: recordURL))
            try verify(file)
            status?.stringValue = "PASS: stored security-scoped reference reopened after relaunch."
        } catch { status?.stringValue = "FAIL: \(error.localizedDescription)" }
    }

    private func verify(_ file: ClipboardFile) throws {
        guard let access = file.openFileAccess() else { throw CocoaError(.fileReadNoPermission) }
        try withExtendedLifetime(access) {
            guard try String(contentsOf: access.url, encoding: .utf8) == "Kopy sandbox fixture\n" else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
}
