import KopyCore
import SwiftUI

struct ClipStackMembers: View {
    let item: ClipboardItem
    let model: KopyModel
    let horizontal: Bool
    var selection: Binding<Set<UUID>>?

    @Environment(\.locale) private var locale

    private var members: [ClipboardMember] { item.payload.members }
    private var imagesOnly: Bool { members.allSatisfy(\.isImage) }

    var body: some View {
        if imagesOnly {
            if horizontal {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(members) { member in
                            memberButton(member, imageTile: true)
                                .frame(width: 103)
                        }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                    ForEach(members) { memberButton($0, imageTile: true) }
                }
            }
        } else {
            LazyVStack(spacing: 5) {
                ForEach(members) { memberButton($0, imageTile: false) }
            }
        }
    }

    private func memberButton(_ member: ClipboardMember, imageTile: Bool) -> some View {
        let selected = selection?.wrappedValue.contains(member.id) ?? false
        return HStack(spacing: 2) {
            Button {
                activate(member, selected: selected)
            } label: {
                VStack(spacing: 5) {
                    if imageTile { thumbnail(member) }
                    HStack(spacing: 6) {
                        if !imageTile {
                            Image(systemName: member.shelfSymbol)
                                .foregroundStyle(ShelfTheme.accent)
                                .accessibilityHidden(true)
                        }
                        member.shelfTitle.lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if !imageTile, case .file(let file) = member, let bytes = file.size {
                            Text(verbatim: bytes.formatted(.byteCount(style: .file, allowedUnits: .all).locale(locale)))
                                .foregroundStyle(ShelfTheme.muted)
                        }
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ShelfTheme.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .overlay {
                NativeDragGrip(model: model, item: item, members: [member.id]) { _ in
                    activate(member, selected: selected)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }
            if selection == nil, !imageTile {
                NativeDragGrip(model: model, item: item, members: [member.id])
                    .frame(width: 20, height: 23)
                    .help("Drag item out of Kopy")
            }
        }
        .background(selected ? ShelfTheme.highlight : ShelfTheme.surface, in: .rect(cornerRadius: 7))
        .contextMenu { memberActions(member).labelStyle(.titleAndIcon) }
    }

    private func activate(_ member: ClipboardMember, selected: Bool) {
        guard let selection else {
            model.paste(item, members: [member.id])
            return
        }
        if selected {
            selection.wrappedValue.remove(member.id)
        } else {
            selection.wrappedValue.insert(member.id)
        }
        model.play(.click)
    }

    @ViewBuilder
    private func thumbnail(_ member: ClipboardMember) -> some View {
        Group {
            switch member {
            case .image(let image):
                ClipImageView(image: image, maxPixels: 280)
            case .file(let file):
                ClipImageView(file: file, maxPixels: 280)
            }
        }
        .frame(height: 64)
        .background(ShelfTheme.surface, in: .rect(cornerRadius: 5))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func memberActions(_ member: ClipboardMember) -> some View {
        Button("Paste item", systemImage: "document.on.clipboard") { model.paste(item, members: [member.id]) }
        Button("Copy item", systemImage: "square.on.square") { model.copy(item, members: [member.id]) }
        if case .file(let file) = member {
            Button("Reveal in Finder", systemImage: "folder") { model.reveal(file) }
        }
        if item.payload.isStack {
            Button("Separate from stack", systemImage: "rectangle.split.2x1") { model.split(item, member: member.id) }
        }
    }
}
