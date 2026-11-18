import Foundation

public enum HistoryUndoAction: Codable, Sendable, Equatable {
    case delete, clear
}

struct HistoryDeletion: Codable, Equatable, Sendable {
    let id: UUID
    let action: HistoryUndoAction
    let removed: [ClipboardItem]
    let order: [UUID]

    init(id: UUID = UUID(), action: HistoryUndoAction, removed: [ClipboardItem], order: [UUID]) {
        self.id = id
        self.action = action
        self.removed = removed
        self.order = order
    }

    var isValid: Bool {
        let removedIDs = Set(removed.map(\.id))
        let orderedIDs = Set(order)
        return !removed.isEmpty && removedIDs.count == removed.count && orderedIDs.count == order.count
            && removedIDs.isSubset(of: orderedIDs) && removed.allSatisfy { $0.copyCount > 0 }
            && (action != .delete || removed.count == 1)
    }
}

public struct HistoryUndoState: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let action: HistoryUndoAction
}
