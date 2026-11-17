import SwiftUI

struct ShelfEmptyState<Action: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ShelfTheme.accent)
                .frame(width: 38, height: 38)
                .background(ShelfTheme.highlight, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(ShelfTheme.muted)
                }
            }
            action()
                .buttonStyle(ShelfSecondaryButtonStyle())
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
