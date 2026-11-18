import KopyCore
import SwiftUI

struct ShelfUndoBar: View {
    let action: HistoryUndoAction
    let isUndoing: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(ShelfTheme.accent)
                .accessibilityHidden(true)
            Text(action.shelfNotice)
                .font(.caption)
                .foregroundStyle(ShelfTheme.muted)
            Spacer(minLength: 4)
            Button("Undo", action: undo)
                .buttonStyle(ShelfSecondaryButtonStyle())
                .help(Text(verbatim: "⌘Z"))
                .disabled(isUndoing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(ShelfTheme.toolbar)
        .overlay(alignment: .top) {
            Rectangle().fill(ShelfTheme.line).frame(height: 1).allowsHitTesting(false)
        }
        .accessibilityIdentifier("history-undo")
    }
}
