import AppKit
import KopyCore
import SwiftUI

struct ShortcutRecorder: View {
    let shortcut: ShelfShortcut
    let onChange: (ShelfShortcut) -> Void

    @State private var monitor: Any?
    @State private var message: LocalizedStringKey?

    var body: some View {
        LabeledContent("Toggle shelf") {
            HStack(spacing: 7) {
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Button(action: toggle) {
                    if monitor == nil {
                        Text(verbatim: shortcut.display)
                    } else {
                        Text("Cancel")
                    }
                }
                .help("Record a keyboard shortcut")
                Button("Reset") { stop(); onChange(ShelfShortcut()) }
                    .disabled(shortcut == ShelfShortcut())
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        guard monitor == nil else { stop(); return }
        message = "Press a shortcut"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.rawValue
            let key = event.charactersIgnoringModifiers?.uppercased()
            MainActor.assumeIsolated {
                if keyCode == 53 {
                    stop()
                    return
                }
                let flags = NSEvent.ModifierFlags(rawValue: flags)
                let modifiers: [(NSEvent.ModifierFlags, String, UInt32)] = [
                    (.control, "⌃", 2), (.option, "⌥", 4), (.shift, "⇧", 8), (.command, "⌘", 1)
                ]
                let active = modifiers.filter { flags.contains($0.0) }
                guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option),
                      let key, key.count == 1,
                      key.allSatisfy({ $0.isLetter || $0.isNumber || $0.isPunctuation }) else {
                    message = "Use a modifier and a letter or number"
                    return
                }
                let mask = active.reduce(UInt32(0)) { $0 | $1.2 }
                stop()
                onChange(ShelfShortcut(
                    keyCode: UInt32(keyCode), modifiers: mask,
                    display: active.map(\.1).joined() + key
                ))
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        message = nil
    }
}
