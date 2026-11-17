import AppKit
import KopyCore
import SwiftUI
import UniformTypeIdentifiers

struct ClipCard: View {
    let item: ClipboardItem
    let model: KopyModel
    let horizontal: Bool
    let expanded: Bool
    let toggleStack: () -> Void
    let preview: () -> Void
    let editNote: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var hovering = false
    @State private var mergeHovered = false
    private var compact: Bool { model.preferences.cardDensity == .compact }
    private var tile: Bool { horizontal && !compact && !expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tile { tileBar } else { cardBar }
            if expanded && item.payload.isStack {
                expandedMembers
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .background(
            mergeHovered ? ShelfTheme.highlight : hovering ? ShelfTheme.inset : horizontal || expanded ? ShelfTheme.surface : .clear,
            in: .rect(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(mergeHovered ? ShelfTheme.accent : horizontal ? ShelfTheme.line : .clear)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if !horizontal && !hovering && !expanded && !mergeHovered {
                Rectangle().fill(ShelfTheme.line.opacity(0.65))
                    .frame(height: 1)
                    .padding(.leading, compact ? 38 : 52)
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion || model.preferences.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onDrop(of: [ShelfTheme.internalDrag], isTargeted: $mergeHovered) { providers in
            model.acceptInternalDrop(providers, target: item.id)
        }
    }

    @ViewBuilder
    private var expandedMembers: some View {
        let members = ClipStackMembers(item: item, model: model, horizontal: horizontal)
        if horizontal && !item.payload.members.allSatisfy(\.isImage) {
            ScrollView { members }
                .frame(height: CGFloat(min(item.payload.members.count, 3)) * 34)
        } else {
            members
        }
    }

    private var cardBar: some View {
        HStack(spacing: 2) {
            mainButton
            itemControls
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 3 : 5)
        .frame(maxWidth: .infinity, minHeight: compact ? 34 : 51)
        .contextMenu { actions.labelStyle(.titleAndIcon) }
    }

    private var tileBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Image(systemName: item.shelfIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.shelfTint)
                    .frame(width: 24, height: 24)
                    .background(item.shelfTint.opacity(0.12), in: .rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                Spacer()
                itemControls
            }
            mainButton
        }
        .padding(10)
        .contextMenu { actions.labelStyle(.titleAndIcon) }
    }

    @ViewBuilder
    private var itemControls: some View {
        if item.payload.isStack {
            NativeDragGrip(model: model, item: item)
                .frame(width: 23, height: 24)
                .help("Drag the stack out of Kopy")
                .accessibilityLabel("Drag the stack out of Kopy")
        }
        if !compact {
            ShelfIconButton(title: "Preview", symbol: "arrow.up.left.and.arrow.down.right", size: 26, action: preview)
                .opacity(hovering || tile ? 1 : 0.48)
                .accessibilityValue(item.shelfTitle)
                .accessibilityIdentifier("preview-\(item.id)")
        }
        Menu {
            actions
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 25, height: 27)
                .background(hovering ? ShelfTheme.surface : .clear, in: .rect(cornerRadius: 7))
                .accessibilityLabel("Item actions")
        }
        .menuStyle(.borderlessButton)
        .labelStyle(.titleAndIcon)
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(ShelfTheme.muted)
        .opacity(hovering || tile ? 1 : 0.7)
        .accessibilityValue(item.shelfTitle)
        .accessibilityIdentifier("actions-\(item.id)")
        .help("Item actions")
    }

    @ViewBuilder
    private var mainButton: some View {
        if item.payload.members.isEmpty {
            pasteButton
        } else {
            pasteButton.overlay {
                NativeDragGrip(model: model, item: item, onPress: { activate($0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private var pasteButton: some View {
        Button {
            activate(NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
        } label: {
            if tile {
                VStack(alignment: .leading, spacing: 7) {
                    tileContent
                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            } else {
                rowLabel
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.payload.isStack ? (expanded ? "Collapse stack" : "Open stack") : ShelfClipboardAction.itemHint)
        .help(activationHelp)
    }

    private var activationHelp: Text {
        if item.payload.isStack { return expanded ? Text("Collapse stack") : Text("Open stack") }
        if !item.payload.members.isEmpty { return item.shelfTitle }
        return Text(ShelfClipboardAction.help)
    }

    private var rowLabel: some View {
        HStack(spacing: 10) {
            ClipBadge(item: item, size: compact ? 22 : 33)
            VStack(alignment: .leading, spacing: 2) {
                item.shelfTitle
                    .font(.system(size: 13 * model.preferences.fontScale, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(item.payload.members.isEmpty ? .tail : .middle)
                if !compact || item.note != nil || item.payload.isStack {
                    metadata
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.payload.isStack {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ShelfTheme.muted)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var tileContent: some View {
        if item.category == .images, let member = item.payload.members.first {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    switch member {
                    case .image(let image): ClipImageView(image: image, maxPixels: 360, contentMode: .fill)
                    case .file(let file): ClipImageView(file: file, maxPixels: 360, contentMode: .fill)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(ShelfTheme.inset, in: .rect(cornerRadius: 7))
                .clipShape(.rect(cornerRadius: 7))
                .accessibilityHidden(true)
                item.shelfTitle.font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            }
        } else if case .text(let text) = item.payload, let color = text.detectedColor {
            let swatch = Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
            item.shelfTitle
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ShelfTheme.surface, in: .rect(cornerRadius: 5))
                .frame(maxWidth: .infinity, minHeight: 66)
                .background(swatch, in: .rect(cornerRadius: 7))
        } else {
            HStack(alignment: .top, spacing: 5) {
                item.shelfTitle
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(3)
                    .truncationMode(item.payload.members.isEmpty ? .tail : .middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.payload.isStack {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ShelfTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 66, alignment: .topLeading)
        }
    }

    private func activate(_ flags: NSEvent.ModifierFlags) {
        if item.payload.isStack {
            toggleStack()
        } else {
            model.paste(item, plain: flags.contains(.shift))
        }
    }

    private var metadata: some View {
        HStack(spacing: 5) {
            if let note = item.note {
                Image(systemName: "note.text").accessibilityHidden(true)
                Text(note).lineLimit(1)
            } else if case .text(let text) = item.payload, let host = text.webURL?.host() {
                Text(verbatim: host).lineLimit(1).foregroundStyle(ShelfTheme.link)
            } else if !item.payload.isStack,
                      case .file(let file)? = item.payload.members.first, let size = file.size {
                Text(verbatim: size.formatted(.byteCount(style: .file, allowedUnits: .all).locale(locale)))
                    .lineLimit(1)
            } else if case .image(let image) = item.payload, image.width > 0, image.height > 0 {
                Text(verbatim: "\(image.width) × \(image.height)").monospacedDigit()
            } else {
                Text(item.activityAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
            }
            if item.copyCount > 1 {
                Text(verbatim: "×\(item.copyCount)").monospacedDigit()
                    .foregroundStyle(ShelfTheme.accent)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(ShelfTheme.muted)
    }

    @ViewBuilder
    private var actions: some View {
        Button(ShelfClipboardAction.title, systemImage: ShelfClipboardAction.symbol) { model.paste(item) }
        if case .text(let text) = item.payload, text.html != nil || text.rtf != nil {
            Button(ShelfClipboardAction.plainTitle, systemImage: "text.alignleft") { model.paste(item, plain: true) }
        }
#if !KOPY_APP_STORE
        Button("Copy", systemImage: "square.on.square") { model.copy(item) }
#endif
        Button("Preview", systemImage: "arrow.up.left.and.arrow.down.right", action: preview)
        Divider()
        Button(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin") { model.pin(item) }
        Button(item.note == nil ? "Add note" : "Edit note", systemImage: "note.text", action: editNote)
        if item.category == .links {
            Button("Open link", systemImage: "arrow.up.right") { model.openLink(item) }
            Button("Copy clean link", systemImage: "link") { model.copyCleanLink(item) }
        }
        if case .text(let text) = item.payload, let color = text.detectedColor {
            Menu("Copy color format") {
                Button("HEX") { model.copyText(color.hex) }
                Button("RGB") { model.copyText(color.rgb) }
                Button("HSL") { model.copyText(color.hsl) }
            }
        }
        let files = item.payload.members.compactMap { member -> ClipboardFile? in
            guard case .file(let file) = member else { return nil }
            return file
        }
        if let file = files.first {
            Button("Reveal in Finder", systemImage: "folder") { model.reveal(file) }
            Button(files.count == 1 ? "Copy path" : "Copy paths", systemImage: "doc.on.doc") {
                model.copyPaths(files)
            }
        }
        if item.payload.members.contains(where: { if case .image = $0 { true } else { false } }) {
            Button("Save images to Downloads", systemImage: "arrow.down.circle") { model.saveImages(item) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(item) }
    }
}

struct ClipBadge: View {
    let item: ClipboardItem
    let size: CGFloat

    var body: some View {
        Group {
            if case .text(let text) = item.payload, let color = text.detectedColor {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
            } else if let member = item.payload.members.first, case .image(let image) = member {
                ClipImageView(image: image, maxPixels: Int(size * 3), contentMode: .fill)
            } else if let member = item.payload.members.first, member.isImage, case .file(let file) = member {
                ClipImageView(file: file, maxPixels: Int(size * 3), contentMode: .fill)
            } else {
                Image(systemName: item.shelfIcon)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(item.shelfTint)
            }
        }
        .frame(width: size, height: size)
        .background(item.shelfTint.opacity(0.12), in: .rect(cornerRadius: 8))
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
