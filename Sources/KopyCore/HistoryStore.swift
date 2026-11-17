import CryptoKit
import Foundation

public enum HistoryError: LocalizedError, Equatable {
    case unreadable
    case changed
    case invalidItem
    case missingItem
    case incompatibleStack
    case stackFull

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Kopy couldn’t read or save its history."
        case .changed: "History changed in another Kopy session. Reopen Kopy to continue."
        case .invalidItem: "This clipboard item has no supported content."
        case .missingItem: "This clipboard item is no longer available."
        case .incompatibleStack: "Only files and images can be combined."
        case .stackFull: "A stack can contain up to 10 items."
        }
    }
}

public actor HistoryStore {
    private static let stackLimit = 10
    private let database: HistoryDatabase
    private let identityKey: SymmetricKey
    public nonisolated let unreadableItemCount: Int
    private var generation: Int64
    private var entries: [Entry]

    public init(databaseURL: URL, encryptionKey: SymmetricKey) throws {
        let database = try HistoryDatabase(url: databaseURL, key: encryptionKey)
        let (generation, items, unreadableItemCount) = try database.load()
        let identityKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: encryptionKey,
            info: Data("kopy-history-identity-v1".utf8),
            outputByteCount: 32
        )
        self.database = database
        self.identityKey = identityKey
        self.unreadableItemCount = unreadableItemCount
        self.generation = generation
        self.entries = items.map { Entry(item: $0, identity: Self.identity($0.payload, key: identityKey)) }
    }

    public func snapshot() -> [ClipboardItem] {
        entries.map(\.item)
    }

    @discardableResult
    public func capture(
        _ payload: ClipboardPayload, preferences: ShelfPreferences, at: Date = .now
    ) throws -> [ClipboardItem] {
        let payload = try Self.normalized(payload)
        var next = entries
        add(payload, at: at, to: &next)
        Self.prune(&next, preferences: preferences, at: at)
        return try save(next)
    }

    @discardableResult
    public func importPayloads(
        _ payloads: [ClipboardPayload], preferences: ShelfPreferences, at: Date = .now
    ) throws -> [ClipboardItem] {
        let payloads = try payloads.flatMap { payload -> [ClipboardPayload] in
            let payload = try Self.normalized(payload)
            let members = payload.members
            guard members.count > Self.stackLimit else { return [payload] }
            return stride(from: 0, to: members.count, by: Self.stackLimit).map { start in
                Self.payload(for: Array(members[start..<min(start + Self.stackLimit, members.count)]))
            }
        }
        var next = entries
        for payload in payloads.reversed() { add(payload, at: at, to: &next) }
        Self.prune(&next, preferences: preferences, at: at)
        return try save(next)
    }

    @discardableResult
    public func prune(preferences: ShelfPreferences, at: Date = .now) throws -> [ClipboardItem] {
        var next = entries
        Self.prune(&next, preferences: preferences, at: at)
        return try save(next)
    }

    @discardableResult
    public func touch(_ id: UUID, at: Date = .now) throws -> [ClipboardItem] {
        guard let index = entries.firstIndex(where: { $0.item.id == id }) else { throw HistoryError.missingItem }
        var next = entries
        next[index].item.activityAt = at
        if next[index].item.copyCount < Int.max { next[index].item.copyCount += 1 }
        if !next[index].item.pinned {
            let entry = next.remove(at: index)
            next.insert(entry, at: 0)
        }
        return try save(next)
    }

    @discardableResult
    public func setPinned(_ pinned: Bool, for id: UUID) throws -> [ClipboardItem] {
        guard let index = entries.firstIndex(where: { $0.item.id == id }) else { throw HistoryError.missingItem }
        var next = entries
        next[index].item.pinned = pinned
        return try save(next)
    }

    @discardableResult
    public func setNote(_ note: String?, for id: UUID) throws -> [ClipboardItem] {
        guard let index = entries.firstIndex(where: { $0.item.id == id }) else { throw HistoryError.missingItem }
        var next = entries
        next[index].item.note = Self.normalizedNote(note)
        return try save(next)
    }

    @discardableResult
    public func delete(_ id: UUID) throws -> [ClipboardItem] {
        try save(entries.filter { $0.item.id != id })
    }

    @discardableResult
    public func clear(_ ids: Set<UUID>, since: Date? = nil) throws -> [ClipboardItem] {
        try save(entries.filter { entry in
            let item = entry.item
            if item.isProtected || !ids.contains(item.id) { return true }
            return since.map { item.activityAt < $0 } ?? false
        })
    }

    @discardableResult
    public func merge(
        _ source: UUID, into target: UUID, members selectedIDs: Set<UUID>? = nil
    ) throws -> [ClipboardItem] {
        guard source != target else { throw HistoryError.incompatibleStack }
        guard let sourceIndex = entries.firstIndex(where: { $0.item.id == source }),
              let targetIndex = entries.firstIndex(where: { $0.item.id == target }) else {
            throw HistoryError.missingItem
        }
        let sourceItem = entries[sourceIndex].item
        var targetItem = entries[targetIndex].item
        let sourceMembers = sourceItem.payload.members
        let targetMembers = targetItem.payload.members
        guard !sourceMembers.isEmpty, !targetMembers.isEmpty else { throw HistoryError.incompatibleStack }

        let selected = sourceMembers.filter { selectedIDs?.contains($0.id) ?? true }
        guard !selected.isEmpty, selectedIDs.map({ selected.count == $0.count }) ?? true else {
            throw HistoryError.missingItem
        }
        let moved = Set(selected.map(\.id))
        let remaining = sourceMembers.filter { !moved.contains($0.id) }
        let combined = Self.unique(targetMembers + selected)
        guard combined.count <= Self.stackLimit else { throw HistoryError.stackFull }

        targetItem.payload = Self.payload(for: combined)
        targetItem.activityAt = .now
        if remaining.isEmpty {
            targetItem.pinned = targetItem.pinned || sourceItem.pinned
            if let sourceNote = sourceItem.note, sourceNote != targetItem.note {
                targetItem.note = Self.normalizedNote([targetItem.note, sourceNote].compactMap { $0 }.joined(separator: " · "))
            }
        }

        var next = entries
        next[targetIndex] = makeEntry(targetItem)
        if remaining.isEmpty {
            next.remove(at: sourceIndex)
        } else {
            var remainder = sourceItem
            remainder.payload = Self.payload(for: remaining)
            next[sourceIndex] = makeEntry(remainder)
        }
        return try save(next)
    }

    @discardableResult
    public func split(_ source: UUID, member id: UUID) throws -> [ClipboardItem] {
        guard let index = entries.firstIndex(where: { $0.item.id == source }) else { throw HistoryError.missingItem }
        var original = entries[index].item
        let members = original.payload.members
        guard members.count > 1 else { throw HistoryError.incompatibleStack }
        guard let member = members.first(where: { $0.id == id }) else { throw HistoryError.missingItem }
        original.payload = Self.payload(for: members.filter { $0.id != id })
        var next = entries
        next[index] = makeEntry(original)
        next.insert(makeEntry(ClipboardItem(payload: member.payload)), at: index)
        return try save(next)
    }

    private struct Entry: Equatable {
        var item: ClipboardItem
        let identity: Data
    }

    private func makeEntry(_ item: ClipboardItem) -> Entry {
        Entry(item: item, identity: Self.identity(item.payload, key: identityKey))
    }

    private func add(_ payload: ClipboardPayload, at date: Date, to entries: inout [Entry]) {
        let signature = Self.identity(payload, key: identityKey)
        if let index = entries.firstIndex(where: { $0.identity == signature }) {
            var existing = entries.remove(at: index)
            existing.item.activityAt = date
            if existing.item.copyCount < Int.max { existing.item.copyCount += 1 }
            if case .text(let previous) = existing.item.payload, case .text(let incoming) = payload {
                existing.item.payload = .text(ClipboardText(
                    previous.value,
                    html: incoming.html ?? previous.html,
                    rtf: incoming.rtf ?? previous.rtf,
                    title: incoming.title ?? previous.title
                ))
            }
            entries.insert(existing, at: 0)
        } else {
            entries.insert(Entry(item: ClipboardItem(payload: payload, activityAt: date), identity: signature), at: 0)
        }
    }

    private func save(_ next: [Entry]) throws -> [ClipboardItem] {
        let items = next.map(\.item)
        if next != entries {
            generation = try database.commit(from: entries.map(\.item), to: items, generation: generation)
            entries = next
        }
        return items
    }

    private static func prune(_ entries: inout [Entry], preferences: ShelfPreferences, at: Date) {
        let preferences = preferences.normalized()
        if preferences.autoDeleteHours > 0 {
            let cutoff = at.addingTimeInterval(-Double(preferences.autoDeleteHours) * 3_600)
            entries.removeAll { !$0.item.isProtected && $0.item.activityAt < cutoff }
        }
        var excess = entries.count - preferences.historyLimit
        guard excess > 0 else { return }
        entries = entries.reversed().filter { entry in
            if excess > 0 && !entry.item.isProtected {
                excess -= 1
                return false
            }
            return true
        }.reversed()
    }

    private static func normalized(_ payload: ClipboardPayload) throws -> ClipboardPayload {
        switch payload {
        case .text(let text):
            let value = String(text.value.prefix(500_000))
            guard !value.isEmpty else { throw HistoryError.invalidItem }
            return .text(ClipboardText(
                value,
                html: text.html.flatMap { $0.count <= 32_768 ? $0 : nil },
                rtf: text.rtf,
                title: text.title.map { String($0.prefix(200)) }
            ))
        case .image(let image):
            guard !image.data.isEmpty else { throw HistoryError.invalidItem }
            return payload
        case .images, .files:
            let members = unique(payload.members)
            guard !members.isEmpty, members.allSatisfy(isValidMember) else { throw HistoryError.invalidItem }
            return Self.payload(for: members)
        }
    }

    private static func isValidMember(_ member: ClipboardMember) -> Bool {
        switch member {
        case .file(let file): file.url.isFileURL && !file.url.path.isEmpty
        case .image(let image): !image.data.isEmpty
        }
    }

    private static func payload(for members: [ClipboardMember]) -> ClipboardPayload {
        if members.count == 1 { return members[0].payload }
        let images = members.compactMap {
            if case .image(let image) = $0 { return image }
            return nil
        }
        return images.count == members.count ? .images(images) : .files(members)
    }

    private static func normalizedNote(_ input: String?) -> String? {
        guard let input else { return nil }
        let words = input.split { $0.isWhitespace || $0.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) }
        let note = String(String.UnicodeScalarView(words.joined(separator: " ").unicodeScalars.prefix(120)))
        return note.isEmpty ? nil : note
    }

    private enum MemberIdentity: Hashable {
        case file(String)
        case image(Data)
        case attachment(name: String, fingerprint: Data)

        init(_ member: ClipboardMember) {
            switch member {
            case .file(let file):
                if let data = file.attachment {
                    self = .attachment(name: file.url.lastPathComponent, fingerprint: Data(SHA256.hash(data: data)))
                } else {
                    self = .file(file.url.standardizedFileURL.path(percentEncoded: false))
                }
            case .image(let image):
                self = .image(Data(SHA256.hash(data: image.data)))
            }
        }
    }

    private static func unique(_ members: [ClipboardMember]) -> [ClipboardMember] {
        var seen = Set<MemberIdentity>()
        return members.filter { seen.insert(MemberIdentity($0)).inserted }
    }

    private static func identity(_ payload: ClipboardPayload, key: SymmetricKey) -> Data {
        var digest = HMAC<SHA256>(key: key)
        switch payload {
        case .text(let text):
            digest.update(data: [0])
            digest.update(data: Data(text.value.utf8))
        case .image, .images, .files:
            digest.update(data: [1])
            for member in payload.members {
                switch MemberIdentity(member) {
                case .file(let path):
                    digest.update(data: [0])
                    let pathBytes = Data(path.utf8)
                    var length = UInt64(pathBytes.count).bigEndian
                    withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
                    digest.update(data: pathBytes)
                case .image(let fingerprint):
                    digest.update(data: [1])
                    digest.update(data: fingerprint)
                case .attachment(let name, let fingerprint):
                    digest.update(data: [2])
                    let nameBytes = Data(name.utf8)
                    var length = UInt64(nameBytes.count).bigEndian
                    withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
                    digest.update(data: nameBytes)
                    digest.update(data: fingerprint)
                }
            }
        }
        return Data(digest.finalize())
    }
}
