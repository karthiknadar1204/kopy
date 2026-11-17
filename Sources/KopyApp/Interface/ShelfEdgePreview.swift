import KopyCore
import SwiftUI

struct ShelfEdgePreview: View {
    let edge: ShelfEdge

    private var alignment: Alignment {
        switch edge {
        case .left: .leading
        case .top: .top
        case .right: .trailing
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(ShelfTheme.inset)
            .strokeBorder(ShelfTheme.line)
            .frame(width: 50, height: 32)
            .overlay(alignment: alignment) {
                Capsule()
                    .fill(ShelfTheme.accent)
                    .frame(width: edge == .top ? 21 : 4, height: edge == .top ? 4 : 16)
                    .padding(3)
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }
}
