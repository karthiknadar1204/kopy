import Foundation

public enum HistoryUndoAction: Sendable, Equatable {
    case delete, clear
}

public struct HistoryUndoState: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let action: HistoryUndoAction
}
