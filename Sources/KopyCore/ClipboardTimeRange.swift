import Foundation

public enum ClipboardTimeRange: String, CaseIterable, Identifiable, Sendable {
    case allTime, lastHour, last6Hours, last24Hours

    public var id: Self { self }

    public var title: String {
        switch self {
        case .allTime: "All time"
        case .lastHour: "Last hour"
        case .last6Hours: "Last 6 hours"
        case .last24Hours: "Last 24 hours"
        }
    }

    public func includes(_ activity: Date, at now: Date = .now) -> Bool {
        let duration: TimeInterval
        switch self {
        case .allTime: return true
        case .lastHour: duration = 3_600
        case .last6Hours: duration = 21_600
        case .last24Hours: duration = 86_400
        }
        return activity >= now.addingTimeInterval(-duration)
    }
}
