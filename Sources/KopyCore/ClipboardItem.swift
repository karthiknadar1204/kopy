import Foundation

public struct ClipboardText: Codable, Equatable, Sendable {
    public let value: String
    public let html: Data?
    public let rtf: Data?
    public let title: String?

    public init(_ value: String, html: Data? = nil, rtf: Data? = nil, title: String? = nil) {
        self.value = value
        self.html = html
        self.rtf = rtf
        self.title = title
    }
}

public struct ClipboardImage: Identifiable, Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case screenshot, image }

    public let id: UUID
    public let data: Data
    public let typeIdentifier: String
    public let name: String?
    public let width: Int
    public let height: Int
    public let source: Source?

    public init(
        id: UUID = UUID(), data: Data, typeIdentifier: String, name: String? = nil,
        width: Int = 0, height: Int = 0, source: Source? = nil
    ) {
        self.id = id
        self.data = data
        self.typeIdentifier = typeIdentifier
        self.name = name
        self.width = width
        self.height = height
        self.source = source
    }
}

public struct ClipboardFile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let size: Int?
    public let isDirectory: Bool
    public let bookmark: Data?
    public let attachment: Data?

    public init(
        id: UUID = UUID(), url: URL, size: Int? = nil, isDirectory: Bool = false,
        bookmark: Data? = nil, attachment: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.isDirectory = isDirectory
        self.bookmark = bookmark
        self.attachment = attachment
    }

    public var availableURL: URL? {
        guard attachment == nil else { return nil }
        if let bookmark {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), resolved.isFileURL, FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }
        return url.isFileURL && FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

public enum ClipboardMember: Identifiable, Codable, Equatable, Sendable {
    case file(ClipboardFile)
    case image(ClipboardImage)

    public var id: UUID {
        switch self {
        case .file(let file): file.id
        case .image(let image): image.id
        }
    }

    public var payload: ClipboardPayload {
        switch self {
        case .file: .files([self])
        case .image(let image): .image(image)
        }
    }
}

public enum ClipboardPayload: Codable, Equatable, Sendable {
    case text(ClipboardText)
    case image(ClipboardImage)
    case images([ClipboardImage])
    case files([ClipboardMember])

    public var members: [ClipboardMember] {
        switch self {
        case .text: []
        case .image(let image): [.image(image)]
        case .images(let images): images.map(ClipboardMember.image)
        case .files(let members): members
        }
    }

    public var isStack: Bool { members.count > 1 }

    public func selecting(_ ids: Set<UUID>) -> ClipboardPayload? {
        let picked = members.filter { ids.contains($0.id) }
        guard !picked.isEmpty, picked.count == ids.count else { return nil }
        if picked.count == 1 { return picked[0].payload }
        let images = picked.compactMap {
            if case .image(let image) = $0 { return image }
            return nil
        }
        return images.count == picked.count ? .images(images) : .files(picked)
    }
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var payload: ClipboardPayload
    public var activityAt: Date
    public var copyCount: Int
    public var pinned: Bool
    public var note: String?

    public init(
        id: UUID = UUID(), payload: ClipboardPayload, activityAt: Date = .now,
        copyCount: Int = 1, pinned: Bool = false, note: String? = nil
    ) {
        self.id = id
        self.payload = payload
        self.activityAt = activityAt
        self.copyCount = copyCount
        self.pinned = pinned
        self.note = note
    }

    public var isProtected: Bool { pinned || note?.isEmpty == false }
}

public enum ClipboardFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    case all, text, links, images, files, colors

    public var id: Self { self }
}
