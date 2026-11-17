import SwiftUI

@MainActor
enum ShelfClipboardAction {
#if KOPY_APP_STORE
    static let title: LocalizedStringKey = "Copy"
    static let selectionTitle: LocalizedStringKey = "Copy selection"
    static let itemTitle: LocalizedStringKey = "Copy item"
    static let itemHint: LocalizedStringKey = "Copy item"
    static let help: LocalizedStringKey = "Copy item"
    static let plainTitle: LocalizedStringKey = "Copy as plain text"
    static let symbol = "square.on.square"
#else
    static let title: LocalizedStringKey = "Paste"
    static let selectionTitle: LocalizedStringKey = "Paste selection"
    static let itemTitle: LocalizedStringKey = "Paste item"
    static let itemHint: LocalizedStringKey = "Pastes this item"
    static let help: LocalizedStringKey = "Paste into the current app"
    static let plainTitle: LocalizedStringKey = "Paste as plain text"
    static let symbol = "document.on.clipboard"
#endif
}
