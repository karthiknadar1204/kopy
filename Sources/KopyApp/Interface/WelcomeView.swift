import KopyCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    let model: KopyModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var step: TourStep = .welcome
    @State private var autoplay = false
    @State private var practiced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                KopyBadge()
                Text("Welcome Tour")
                    .font(.headline)
                Spacer()
                Button("Skip", action: model.finishTour)
                    .buttonStyle(ShelfSecondaryButtonStyle())
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.title)
                            .font(.system(size: 26, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        if step != .welcome || model.preferences.hoverEnabled {
                            Text(step.instruction)
                                .font(.subheadline)
                                .foregroundStyle(ShelfTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if step == .settings {
                        tourSettings
                    } else {
                        TourExample(step: step, practiced: $practiced, preferences: model.preferences)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .id(step)

            Rectangle().fill(ShelfTheme.line).frame(height: 1).accessibilityHidden(true)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ShelfTheme.background)
        .foregroundStyle(ShelfTheme.ink)
        .tint(ShelfTheme.accent)
        .task(id: AutoplayState(step: step, enabled: autoplay && scenePhase != .background)) {
            guard autoplay, step != .settings, scenePhase != .background else { return }
            do {
                try await Task.sleep(for: .seconds(9))
                move(by: 1)
            } catch {
                return
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Back") { move(by: -1) }
                .buttonStyle(ShelfSecondaryButtonStyle())
                .disabled(step == .welcome)
            Spacer(minLength: 4)
            ShelfIconButton(title: autoplay ? "Pause tour" : "Play tour", symbol: autoplay ? "pause" : "play") {
                autoplay.toggle()
            }
            .disabled(step == .settings)
            .opacity(step == .settings ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(step.rawValue + 1) / \(TourStep.allCases.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ShelfTheme.muted)
                    .accessibilityLabel("Step \(step.rawValue + 1) of \(TourStep.allCases.count)")
                ProgressView(value: Double(step.rawValue + 1), total: Double(TourStep.allCases.count))
                    .progressViewStyle(.linear)
                    .frame(width: 54)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            Button(step == .settings ? "Done" : "Next") { move(by: 1) }
                .buttonStyle(ShelfPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(ShelfTheme.toolbar)
    }

    private var tourSettings: some View {
        VStack(alignment: .leading, spacing: 11) {
            Picker("Shelf location", selection: Binding(
                get: { model.preferences.edge },
                set: { edge in model.updatePreferences { $0.edge = edge } }
            )) {
                ForEach(ShelfEdge.allCases) { edge in
                    Text(edge.title).tag(edge)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Play sounds", isOn: Binding(
                get: { model.preferences.soundEffects },
                set: { enabled in model.updatePreferences { $0.soundEffects = enabled } }
            ))
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
            ))
            Toggle("Pause automatic capture", isOn: Binding(
                get: { model.preferences.incognito },
                set: { enabled in model.updatePreferences { $0.incognito = enabled } }
            ))
            Text("Clipboard history stays on this Mac.")
                .font(.caption)
                .foregroundStyle(ShelfTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Link("Privacy Policy", destination: KopyLinks.privacy)
        }
        .toggleStyle(.switch)
        .padding(16)
        .background(ShelfTheme.surface, in: .rect(cornerRadius: ShelfTheme.radius))
        .overlay { RoundedRectangle(cornerRadius: ShelfTheme.radius).strokeBorder(ShelfTheme.line).allowsHitTesting(false) }
    }

    private func move(by delta: Int) {
        if step == .settings && delta > 0 {
            model.finishTour()
            return
        }
        guard let next = TourStep(rawValue: step.rawValue + delta) else { return }
        step = next
        practiced = false
        if next == .settings { autoplay = false }
    }
}

private struct AutoplayState: Equatable {
    let step: TourStep
    let enabled: Bool
}

private struct TourExample: View {
    let step: TourStep
    @Binding var practiced: Bool
    let preferences: ShelfPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch step {
            case .welcome:
                HStack(spacing: 12) {
                    ShelfEdgePreview(edge: preferences.edge)
                    Text("Open your shelf")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 6)
                    shortcutKeys
                }
            case .dropIn, .dragOut, .stacks:
                dragExercise
            case .preview:
                Button { practiced.toggle() } label: {
                    tile("Select a sample", symbol: practiced ? "checkmark.circle.fill" : "doc.text")
                }
                .buttonStyle(ShelfSecondaryButtonStyle())
                .accessibilityAddTraits(practiced ? .isSelected : [])
            case .find:
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .shelfField(isFocused: searchFocused)
                    .onChange(of: query) { _, term in
                        let search = term.trimmingCharacters(in: .whitespacesAndNewlines)
                        practiced = !search.isEmpty && "Park Café · studio notes".localizedStandardContains(search)
                    }
            default:
                tile(step.fixture, symbol: step.symbol)
            }
            if practiced {
                Label(step.outcome, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(ShelfTheme.accent)
            }
            if let action = step.practice {
                Button(practiced ? "Reset example" : action) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        if step == .find {
                            query = practiced ? "" : "studio notes"
                        } else {
                            practiced.toggle()
                        }
                    }
                }
                .buttonStyle(ShelfSecondaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(ShelfTheme.surface, in: .rect(cornerRadius: ShelfTheme.radius))
        .overlay { RoundedRectangle(cornerRadius: ShelfTheme.radius).strokeBorder(ShelfTheme.line).allowsHitTesting(false) }
    }

    private var shortcutKeys: some View {
        HStack(spacing: 4) {
            ForEach(Array(preferences.shortcut.display.enumerated()), id: \.offset) { _, key in
                Text(verbatim: String(key))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(width: 24, height: 24)
                    .background(ShelfTheme.inset, in: .rect(cornerRadius: 5))
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(ShelfTheme.line) }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: preferences.shortcut.display))
    }

    private var dragExercise: some View {
        HStack(spacing: 8) {
            tile(step.fixture, symbol: step.symbol)
                .onDrag {
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: Self.fixtureDrag.identifier, visibility: .ownProcess) { callback in
                        callback(Data([1]), nil)
                        return nil
                    }
                    return provider
                }
            Image(systemName: "arrow.right")
                .foregroundStyle(ShelfTheme.muted)
                .accessibilityHidden(true)
            tile(step == .stacks ? "Open stack" : "Drop sample here", symbol: "tray.and.arrow.down")
                .background(dropTargeted ? ShelfTheme.highlight : ShelfTheme.inset, in: .rect(cornerRadius: 7))
                .onDrop(of: [Self.fixtureDrag], isTargeted: $dropTargeted) { providers in
                    guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(Self.fixtureDrag.identifier) }) else {
                        return false
                    }
                    practiced = true
                    return true
                }
        }
    }

    private func tile(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }

    private static let fixtureDrag = UTType(exportedAs: "com.kopy.tour-sample")
}

private enum TourStep: Int, CaseIterable {
    case welcome, collect, dropIn, dragOut, stacks, preview, find, settings

    var title: LocalizedStringKey {
        switch self {
        case .welcome: "Meet Kopy"
        case .collect: "Collect a copy"
        case .dropIn: "Drop files onto the shelf"
        case .dragOut: "Drag files back out"
        case .stacks: "Keep related items together"
        case .preview: "Inspect before pasting"
        case .find: "Find an earlier copy"
        case .settings: "Place your shelf"
        }
    }

    var instruction: LocalizedStringKey {
        switch self {
        case .welcome: "Move the pointer to a screen edge to open your clipboard shelf."
        case .collect: "Copied text, links, images, and files appear in Recent. Click an item to paste it."
        case .dropIn: "Drag a file from Finder to the edge. The shelf opens when it detects the drop."
        case .dragOut: "Drag a file or image from Kopy to Finder or another app."
        case .stacks: "Drop a file or image card onto another to make a stack. Open the stack to work with individual items."
        case .preview: "Use an item's menu to open a preview. Select the members you want to paste or copy."
        case .find: "Search copied text, filenames, and notes. Pin items to keep them through history cleanup."
        case .settings: "Choose an edge, then adjust your preferences whenever you like."
        }
    }

    var practice: LocalizedStringKey? {
        switch self {
        case .welcome: nil
        case .collect: "Copy sample"
        case .dropIn: "Simulate drop"
        case .dragOut: "Simulate export"
        case .stacks: "Combine sample items"
        case .preview: nil
        case .find: "Find sample note"
        case .settings: nil
        }
    }

    var outcome: LocalizedStringKey {
        switch self {
        case .welcome: "Shelf opened"
        case .collect: "Studio reference added to Recent"
        case .dropIn: "Budget.xlsx added to Files"
        case .dragOut: "Moodboard.png ready in Finder"
        case .stacks: "2 files in one stack"
        case .preview: "1 item selected"
        case .find: "Found Park Café by its note"
        case .settings: "Preferences saved"
        }
    }

    var fixture: LocalizedStringKey {
        switch self {
        case .welcome: "Open your shelf"
        case .collect: "Studio reference"
        case .dropIn: "Budget.xlsx"
        case .dragOut: "Moodboard.png"
        case .stacks: "Brief.pdf and Ideas.txt"
        case .preview: "Preview two items"
        case .find: "Park Café"
        case .settings: "Shelf preferences"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "rectangle.inset.filled.leadinghalf"
        case .collect: "doc.on.doc"
        case .dropIn: "arrow.down.to.line"
        case .dragOut: "hand.draw"
        case .stacks: "square.stack"
        case .preview: "eye"
        case .find: "magnifyingglass"
        case .settings: "slider.horizontal.3"
        }
    }
}
