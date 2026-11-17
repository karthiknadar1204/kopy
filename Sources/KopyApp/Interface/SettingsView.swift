import KopyCore
import SwiftUI

struct SettingsView: View {
    let model: KopyModel
    @State private var displays = ShelfDisplay.connected

    private var selectedDisplayID: UInt32? {
        ShelfDisplay.preferred(in: displays, for: model.preferences)?.id ?? model.preferences.displayID
    }

    var body: some View {
        TabView {
            behavior.tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
            position.tabItem { Label("Position", systemImage: "rectangle.inset.filled") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            system.tabItem { Label("System", systemImage: "gearshape") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(ShelfTheme.accent)
        .onAppear { displays = ShelfDisplay.connected }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = ShelfDisplay.connected
        }
    }

    private var behavior: some View {
        Form {
            Section {
                ShortcutRecorder(shortcut: model.preferences.shortcut) { shortcut in
                    model.updatePreferences { $0.shortcut = shortcut }
                }
            }
            Section("Capture") {
                Toggle("Pause automatic capture", isOn: setting(\.incognito))
                Text("Clipboard history stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.automaticCaptureDenied {
                    Label("macOS has blocked automatic clipboard capture.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Move pasted items to Recent", isOn: setting(\.movePastedToTop))
                Picker("History limit", selection: setting(\.historyLimit)) {
                    ForEach([100, 250, 500, 1_000], id: \.self) { limit in
                        Text(limit, format: .number).tag(limit)
                    }
                }
                Picker("Delete old items", selection: setting(\.autoDeleteHours)) {
                    Text("Never").tag(0)
                    Text("After 1 hour").tag(1)
                    Text("After 6 hours").tag(6)
                    Text("After 24 hours").tag(24)
                    Text("After 7 days").tag(168)
                }
                Toggle("Clear unpinned, unnoted items on restart", isOn: setting(\.clearOnRestart))
            }
        }
        .formStyle(.grouped)
    }

    private var system: some View {
        Form {
            Section("System") {
                Picker("Language", selection: setting(\.language)) {
                    Text("System default").tag(ShelfLanguage.system)
                    ForEach(ShelfLanguage.available, id: \.identifier) { language in
                        Text(verbatim: language.name).tag(language.identifier)
                    }
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
                ))
                if model.isLoginApprovalRequired {
                    Text("Allow Kopy under Login Items in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Paste into other apps") {
                    if model.hasPastePermission {
                        Label("Allowed", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Allow automatic paste", action: model.requestPastePermission)
                    }
                }
                Button("Replay welcome tour", systemImage: "play.circle", action: model.openTour)
                Link("Privacy Policy", destination: KopyLinks.privacy)
                Link("Support", destination: KopyLinks.support)
            }
#if KOPY_APP_STORE
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
#else
            KopyUpdateSection(updater: model.updater)
#endif
        }
        .formStyle(.grouped)
    }

    private var position: some View {
        Form {
            Section("Placement") {
                HStack(spacing: 12) {
                    ShelfEdgePreview(edge: model.preferences.edge)
                    Picker("Screen edge", selection: setting(\.edge)) {
                        ForEach(ShelfEdge.allCases) { edge in
                            Text(edge.title).tag(edge)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Picker("Display", selection: Binding(get: { selectedDisplayID }, set: { id in
                    model.updatePreferences {
                        $0.displayID = id
                        $0.displayBounds = displays.first { $0.id == id }?.frame
                    }
                })) {
                    Text("Automatic").tag(Optional<UInt32>.none)
                    ForEach(displays, id: \.id) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                    if let id = selectedDisplayID, !displays.contains(where: { $0.id == id }) {
                        Text("Disconnected display").tag(Optional(id))
                    }
                }
                if model.preferences.edge != .top {
                    Picker("Shelf height", selection: setting(\.shelfHeight)) {
                        Text(0.5, format: .percent).tag(0.5)
                        Text(0.65, format: .percent).tag(0.65)
                        Text(0.8, format: .percent).tag(0.8)
                    }
                }
                Slider(value: setting(model.preferences.edge == .top ? \.horizontalOffset : \.offset), in: 0...1, step: 0.05) {
                    Text(model.preferences.edge == .top ? "Horizontal position" : "Shelf position")
                }
                Toggle("Show where the shelf is docked", isOn: setting(\.showEdgeLocationHint))
                Toggle("Keep shelf out of full screen", isOn: setting(\.suppressFullscreen))
            }
            Section("Hover") {
                Toggle("Open when the pointer reaches the edge", isOn: setting(\.hoverEnabled))
                Stepper(
                    "Hover delay · \(model.preferences.openDelayMilliseconds) ms",
                    value: setting(\.openDelayMilliseconds), in: 0...1_000, step: 50
                )
                .disabled(!model.preferences.hoverEnabled)
            }
            Section {
                Picker("Trigger length", selection: setting(\.edgeSpan)) {
                    Text(0.25, format: .percent).tag(0.25)
                    Text(0.4, format: .percent).tag(0.4)
                    Text(0.6, format: .percent).tag(0.6)
                }
                Picker("Align trigger", selection: setting(\.edgeAlignment)) {
                    Text(model.preferences.edge == .top ? ShelfEdge.left.title : LocalizedStringKey("Bottom")).tag(0.0)
                    Text("Center").tag(0.5)
                    Text(model.preferences.edge == .top ? ShelfEdge.right.title : ShelfEdge.top.title).tag(1.0)
                }
                LabeledContent("Trigger thickness") {
                    Stepper(
                        "\(Int(model.preferences.edgeThickness)) points",
                        value: setting(\.edgeThickness), in: 1...7, step: 1
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section("Text and motion") {
                Picker("Card layout", selection: setting(\.cardDensity)) {
                    Text("Modern").tag(ShelfCardDensity.modern)
                    Text("Compact rows").tag(ShelfCardDensity.compact)
                }
                Picker("Shelf text size", selection: setting(\.fontScale)) {
                    Text("Small").tag(0.85)
                    Text("Medium").tag(1.0)
                    Text("Large").tag(1.15)
                }
                Toggle("Reduce shelf motion", isOn: setting(\.reduceMotion))
                Toggle("Play sounds", isOn: setting(\.soundEffects))
            }
            Section("Feedback") {
                Toggle("Flash the edge when an item is copied", isOn: setting(\.showCopyIndicator))
                Picker("Copy indicator", selection: setting(\.copyIndicatorStyle)) {
                    Text("Kopy mark").tag(CopyIndicatorStyle.logo)
                    Text("Checkmark").tag(CopyIndicatorStyle.check)
                    Text("Copy").tag(CopyIndicatorStyle.copy)
                    Text("Sparkle").tag(CopyIndicatorStyle.sparkle)
                }
                .disabled(!model.preferences.showCopyIndicator)
            }
        }
        .formStyle(.grouped)
    }

    private func setting<Value>(_ key: WritableKeyPath<ShelfPreferences, Value>) -> Binding<Value> {
        Binding(get: { model.preferences[keyPath: key] }) { value in
            model.updatePreferences { $0[keyPath: key] = value }
        }
    }
}

extension ShelfEdge {
    var title: LocalizedStringKey {
        switch self {
        case .left: "Left"
        case .top: "Top"
        case .right: "Right"
        }
    }
}
