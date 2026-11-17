import KopyCore
import SwiftUI

struct ClipPreview: View {
    let item: ClipboardItem
    let model: KopyModel
    let horizontal: Bool
    let onClose: () -> Void

    @State private var selected: Set<UUID> = []
    @State private var mergeHovered = false

    private var visibleSelection: Set<UUID>? { selected.isEmpty ? nil : selected }
    private var members: [ClipboardMember] { item.payload.members }
    private var title: Text { item.category == .text ? Text("Text") : item.shelfTitle }
    private var hasSelectedImages: Bool {
        members.contains { member in
            guard selected.isEmpty || selected.contains(member.id) else { return false }
            if case .image = member { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ClipBadge(item: item, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    title
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.activityAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(ShelfTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if let note = item.note {
                        Label(note, systemImage: "note.text")
                            .font(.subheadline)
                            .foregroundStyle(ShelfTheme.muted)
                    }
                    detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            actions
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(ShelfTheme.toolbar)
                .overlay(alignment: .top) {
                    Rectangle().fill(ShelfTheme.line).frame(height: 1).allowsHitTesting(false)
                }
        }
        .onExitCommand(perform: onClose)
        .onChange(of: members.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .onDrop(of: [ShelfTheme.internalDrag], isTargeted: $mergeHovered) { providers in
            model.acceptInternalDrop(providers, target: item.id)
        }
        .overlay {
            if mergeHovered {
                RoundedRectangle(cornerRadius: ShelfTheme.radius)
                    .strokeBorder(ShelfTheme.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch item.payload {
        case .text(let text):
            if let color = text.detectedColor {
                HStack(spacing: 10) {
                    ClipBadge(item: item, size: horizontal ? 38 : 54)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach([color.hex, color.rgb, color.hsl], id: \.self) { value in
                            Button {
                                model.copyText(value)
                            } label: {
                                Text(value).font(.subheadline.monospaced()).textSelection(.disabled)
                            }
                            .buttonStyle(.plain)
                            .help("Copy \(value)")
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShelfTheme.surface, in: .rect(cornerRadius: 10))
            } else if let link = text.linkPreview {
                VStack(alignment: .leading, spacing: 8) {
                    Label(localizedHeading(for: link), systemImage: "link")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ShelfTheme.link)
                    Text(link.address)
                        .font(.caption)
                        .foregroundStyle(ShelfTheme.muted)
                        .textSelection(.enabled)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { linkActions }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) { linkActions }
                    }
                    .buttonStyle(ShelfSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ShelfTheme.surface, in: .rect(cornerRadius: 10))
            } else {
                Text(textPreview(text.value))
                    .font(looksLikeCode(text.value) ? .subheadline.monospaced() : .subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ShelfTheme.surface, in: .rect(cornerRadius: 10))
            }
        case .image(let image):
            ClipImageView(image: image, maxPixels: 1200)
                .frame(maxWidth: .infinity, minHeight: 95, maxHeight: horizontal ? 140 : 290)
                .background(ShelfTheme.inset, in: .rect(cornerRadius: 10))
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityLabel(image.name.map { Text(verbatim: $0) } ?? Text("Clipboard image"))
        case .images, .files:
            ClipStackMembers(item: item, model: model, horizontal: horizontal, selection: $selected)
        }
    }

    private func localizedHeading(for link: ClipboardLinkPreview) -> String {
        let language = model.preferences.language
        let service = ShelfLanguage.string("Link type: \(link.service)", language: language, fallback: link.service)
        let kind = link.kind.map { ShelfLanguage.string("Link type: \($0)", language: language, fallback: $0) }
        return [service, kind].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var linkActions: some View {
        Button("Open link", systemImage: "arrow.up.right") { model.openLink(item) }
        Button("Copy clean link", systemImage: "link") { model.copyCleanLink(item) }
    }

    private var actions: some View {
        HStack(spacing: 7) {
            Button(selected.isEmpty ? ShelfClipboardAction.title : ShelfClipboardAction.selectionTitle, systemImage: ShelfClipboardAction.symbol) {
                model.paste(item, members: visibleSelection)
            }
            .lineLimit(1)
            .layoutPriority(1)
            .buttonStyle(ShelfPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)

#if !KOPY_APP_STORE
            ShelfIconButton(title: selected.isEmpty ? "Copy" : "Copy selection", symbol: "square.on.square") {
                model.copy(item, members: visibleSelection)
            }
#endif

            if !members.isEmpty {
                NativeDragGrip(model: model, item: item, members: visibleSelection)
                    .frame(width: 28, height: 24)
                    .help("Drag selection out of Kopy")
                    .accessibilityLabel("Drag selection out of Kopy")
            }
            if item.payload.isStack {
                Menu("Selection", systemImage: "checklist") {
                    Button("Select all", systemImage: "checkmark.circle") { selected = Set(members.map(\.id)) }
                    Button("Deselect all", systemImage: "circle") { selected.removeAll() }
                        .disabled(selected.isEmpty)
                }
                .menuStyle(.borderlessButton)
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .help("Selection")
                .fixedSize()
            }
            Spacer(minLength: 0)
            if hasSelectedImages {
                ShelfIconButton(title: "Save images to Downloads", symbol: "arrow.down.circle", size: 27) {
                    model.saveImages(item, members: visibleSelection)
                }
            }
        }
        .controlSize(.small)
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let snippet = String(text.prefix(400))
        return snippet.hasPrefix("#!") || snippet.hasPrefix("import ") || snippet.hasPrefix("func ")
            || snippet.hasPrefix("const ") || snippet.hasPrefix("class ") || snippet.contains("\n    ")
    }

    private func textPreview(_ text: String) -> AttributedString {
        let value = String(text.prefix(20_000))
        var result = AttributedString(value)
        guard looksLikeCode(value) else { return result }

        let words = /\b(?:import|func|return|let|var|const|class|struct|enum|if|else|for|while|async|await|public|private|def)\b/
        for match in value.matches(of: words) {
            if let range = Range(match.range, in: result) {
                result[range].foregroundColor = ShelfTheme.accent
            }
        }
        return result
    }
}
