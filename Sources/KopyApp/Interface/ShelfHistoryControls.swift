import KopyCore
import SwiftUI

struct ShelfHistoryControls: View {
    @Bindable var model: KopyModel
    @Binding var timeRange: ClipboardTimeRange
    let canClear: Bool
    let onClear: () -> Void

    var body: some View {
        ShelfIconButton(title: "History actions", symbol: "slider.horizontal.3",
                        tint: timeRange == .allTime ? ShelfTheme.muted : ShelfTheme.accent, size: 26) {
            model.historyActionsOpen.toggle()
        }
        .popover(isPresented: $model.historyActionsOpen, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Show history", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShelfTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                ForEach(ClipboardTimeRange.allCases) { range in
                    HistoryOption(title: LocalizedStringKey(range.title),
                                  symbol: range == .allTime ? "tray.full" : "clock",
                                  selected: range == timeRange) {
                        timeRange = range
                        model.keepShelfOpen?(.seconds(2))
                        model.historyActionsOpen = false
                    }
                }

                Divider().padding(.vertical, 6)
                if let action = model.undoAction {
                    HistoryOption(title: action.shelfTitle, symbol: "arrow.uturn.backward", shortcut: "⌘Z") {
                        model.historyActionsOpen = false
                        model.undoDeletion()
                    }
                    .disabled(model.isUndoingDeletion)
                }
                HistoryOption(title: "Clear shown history", symbol: "trash", tint: .red) {
                    model.historyActionsOpen = false
                    onClear()
                }
                .disabled(!canClear)
                Text("Pinned items and items with notes will be kept.")
                    .font(.caption2)
                    .foregroundStyle(ShelfTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
            }
            .padding(10)
            .frame(width: 248)
            .background(ShelfTheme.toolbar)
            .foregroundStyle(ShelfTheme.ink)
            .onExitCommand { model.historyActionsOpen = false }
        }
    }
}

private struct HistoryOption: View {
    let title: LocalizedStringKey
    let symbol: String
    var selected = false
    var tint: Color = ShelfTheme.ink
    var shortcut: String?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 17)
                Text(title).lineLimit(1)
                Spacer(minLength: 6)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                } else if let shortcut {
                    Text(verbatim: shortcut).font(.caption).foregroundStyle(ShelfTheme.muted)
                }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? ShelfTheme.accent : tint)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(selected ? ShelfTheme.highlight : hovering ? ShelfTheme.inset : .clear,
                        in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 && isEnabled }
    }
}

extension HistoryUndoAction {
    var shelfTitle: LocalizedStringKey {
        switch self {
        case .delete: "Undo delete"
        case .clear: "Undo clear history"
        }
    }

    var shelfNotice: LocalizedStringKey {
        switch self {
        case .delete: "Item deleted"
        case .clear: "History cleared"
        }
    }
}
