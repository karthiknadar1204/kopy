import CryptoKit
import Foundation
import SQLite3

final class HistoryDatabase {
    private static let applicationID: Int64 = 0x4B4F5059
    private static let orderContext = Data("kopy-history-v1-order".utf8)
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let handle: OpaquePointer
    private let key: SymmetricKey

    init(url: URL, key: SymmetricKey) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path(percentEncoded: false), &connection, flags, nil)
        guard result == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw HistoryError.unreadable
        }
        self.handle = connection
        self.key = key
        try check(sqlite3_busy_timeout(connection, 3_000))
        try initialize()
    }

    deinit {
        sqlite3_close(handle)
    }

    func load() throws -> (generation: Int64, items: [ClipboardItem], unreadableCount: Int) {
        let snapshot = try transaction { try readSnapshot() }
        guard !snapshot.unreadable.isEmpty else { return (snapshot.generation, snapshot.items, 0) }
        return try transaction(write: true) {
            // Re-read under the write lock in case another process repaired the same history.
            let current = try readSnapshot()
            guard !current.unreadable.isEmpty else { return (current.generation, current.items, 0) }
            try preserveUnreadableRows(current.unreadable, generation: current.generation)
            let nextGeneration = current.generation + 1
            try writeOrder(current.items.map(\.id), generation: nextGeneration)
            return (nextGeneration, current.items, current.unreadable.count)
        }
    }

    private struct Snapshot {
        let generation: Int64
        let items: [ClipboardItem]
        let unreadable: [UUID]
    }

    private func readSnapshot() throws -> Snapshot {
        let (generation, order) = try readOrder()
        let indexedIDs = Set(order)
        guard indexedIDs.count == order.count else { throw HistoryError.unreadable }
        var itemsByID: [UUID: ClipboardItem] = [:]
        var seen = Set<UUID>()
        try statement("SELECT id, content FROM items") { query in
            while try step(query) {
                guard let text = sqlite3_column_text(query, 0) else { throw HistoryError.unreadable }
                let rowID = String(cString: text)
                guard let id = UUID(uuidString: rowID), id.uuidString == rowID,
                      indexedIDs.contains(id), seen.insert(id).inserted else {
                    throw HistoryError.unreadable
                }
                if let item = try? decode(ClipboardItem.self, from: blob(query, column: 1), context: itemContext(id)),
                   item.id == id, item.copyCount > 0 {
                    itemsByID[id] = item
                }
            }
        }
        return Snapshot(
            generation: generation,
            items: order.compactMap { itemsByID[$0] },
            unreadable: order.filter { itemsByID[$0] == nil }
        )
    }

    private func preserveUnreadableRows(_ ids: [UUID], generation: Int64) throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS unreadable_items (
                id TEXT NOT NULL,
                content BLOB NOT NULL,
                generation INTEGER NOT NULL
            )
            """)
        try statement("""
            INSERT INTO unreadable_items (id, content, generation)
            SELECT id, content, ? FROM items WHERE id = ?
            """) { query in
            for id in ids {
                try check(sqlite3_bind_int64(query, 1, generation))
                try bind(id.uuidString, at: 2, to: query)
                try execute(query)
            }
        }
        try statement("DELETE FROM items WHERE id = ?") { query in
            for id in ids {
                try bind(id.uuidString, at: 1, to: query)
                try execute(query)
            }
        }
    }

    func commit(from previous: [ClipboardItem], to items: [ClipboardItem], generation: Int64) throws -> Int64 {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let nextIDs = Set(items.map(\.id))
        let removed = previous.filter { !nextIDs.contains($0.id) }
        let changed = items.filter { previousByID[$0.id] != $0 }
        let nextGeneration = generation + 1

        return try transaction(write: true) {
            guard try scalar("SELECT generation FROM state WHERE singleton = 1") == generation else {
                throw HistoryError.changed
            }
            try statement("DELETE FROM items WHERE id = ?") { query in
                for item in removed {
                    try bind(item.id.uuidString, at: 1, to: query)
                    try execute(query)
                }
            }
            try statement("""
                INSERT INTO items (id, content) VALUES (?, ?)
                ON CONFLICT(id) DO UPDATE SET content = excluded.content
                """) { query in
                for item in changed {
                    try bind(item.id.uuidString, at: 1, to: query)
                    try bind(encode(item, context: itemContext(item.id)), at: 2, to: query)
                    try execute(query)
                }
            }
            try writeOrder(items.map(\.id), generation: nextGeneration)
            return nextGeneration
        }
    }

    private func initialize() throws {
        let applicationID = try scalar("PRAGMA application_id")
        let version = try scalar("PRAGMA user_version")
        if applicationID == Self.applicationID && version == 1 { return }
        guard applicationID == 0, version == 0 else { throw HistoryError.unreadable }

        try transaction(write: true) {
            // Another instance may have won initialization while we waited for the write lock.
            let applicationID = try scalar("PRAGMA application_id")
            let version = try scalar("PRAGMA user_version")
            if applicationID == Self.applicationID && version == 1 { return }
            guard applicationID == 0, version == 0,
                  try scalar("SELECT COUNT(*) FROM sqlite_schema WHERE substr(name, 1, 7) <> 'sqlite_'") == 0 else {
                throw HistoryError.unreadable
            }
            try execute("""
                CREATE TABLE items (id TEXT PRIMARY KEY NOT NULL, content BLOB NOT NULL);
                CREATE TABLE state (
                    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                    generation INTEGER NOT NULL,
                    item_order BLOB NOT NULL
                );
                PRAGMA application_id = \(Self.applicationID);
                PRAGMA user_version = 1;
                """)
            try writeOrder([], generation: 0)
        }
    }

    private func readOrder() throws -> (Int64, [UUID]) {
        try statement("SELECT generation, item_order FROM state WHERE singleton = 1") { query in
            guard try step(query) else { throw HistoryError.unreadable }
            let generation = sqlite3_column_int64(query, 0)
            guard generation >= 0, generation < Int64.max else { throw HistoryError.unreadable }
            return (generation, try decode([UUID].self, from: blob(query, column: 1), context: Self.orderContext))
        }
    }

    private func writeOrder(_ ids: [UUID], generation: Int64) throws {
        try statement("""
            INSERT INTO state (singleton, generation, item_order) VALUES (1, ?, ?)
            ON CONFLICT(singleton) DO UPDATE
                SET generation = excluded.generation, item_order = excluded.item_order
            """) { query in
            try check(sqlite3_bind_int64(query, 1, generation))
            try bind(encode(ids, context: Self.orderContext), at: 2, to: query)
            try execute(query)
        }
    }

    private func itemContext(_ id: UUID) -> Data {
        Data("kopy-history-v1-item-\(id.uuidString)".utf8)
    }

    private func encode(_ item: some Encodable, context: Data) throws -> Data {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let sealed = try AES.GCM.seal(encoder.encode(item), using: key, authenticating: context)
            guard let combined = sealed.combined else { throw HistoryError.unreadable }
            return combined
        } catch {
            throw HistoryError.unreadable
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, context: Data) throws -> T {
        do {
            let sealed = try AES.GCM.SealedBox(combined: data)
            let open = try AES.GCM.open(sealed, using: key, authenticating: context)
            return try PropertyListDecoder().decode(type, from: open)
        } catch {
            throw HistoryError.unreadable
        }
    }

    private func transaction<T>(write: Bool = false, _ operation: () throws -> T) throws -> T {
        try execute(write ? "BEGIN IMMEDIATE" : "BEGIN")
        do {
            let result = try operation()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw HistoryError.unreadable }
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    private func execute(_ query: OpaquePointer) throws {
        guard try !step(query) else { throw HistoryError.unreadable }
        try check(sqlite3_reset(query))
        try check(sqlite3_clear_bindings(query))
    }

    private func step(_ query: OpaquePointer) throws -> Bool {
        switch sqlite3_step(query) {
        case SQLITE_ROW: true
        case SQLITE_DONE: false
        default: throw HistoryError.unreadable
        }
    }

    private func statement<T>(_ sql: String, _ use: (OpaquePointer) throws -> T) throws -> T {
        var query: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &query, nil))
        guard let query else { throw HistoryError.unreadable }
        defer { sqlite3_finalize(query) }
        return try use(query)
    }

    private func scalar(_ sql: String) throws -> Int64 {
        try statement(sql) { query in
            guard try step(query) else { throw HistoryError.unreadable }
            return sqlite3_column_int64(query, 0)
        }
    }

    private func bind(_ value: String, at index: Int32, to query: OpaquePointer) throws {
        try check(sqlite3_bind_text(query, index, value, -1, Self.transient))
    }

    private func bind(_ data: Data, at index: Int32, to query: OpaquePointer) throws {
        try check(data.withUnsafeBytes {
            sqlite3_bind_blob64(query, index, $0.baseAddress, UInt64($0.count), Self.transient)
        })
    }

    private func blob(_ query: OpaquePointer, column: Int32) throws -> Data {
        let bytes = sqlite3_column_bytes(query, column)
        guard bytes > 0, let pointer = sqlite3_column_blob(query, column) else {
            throw HistoryError.unreadable
        }
        return Data(bytes: pointer, count: Int(bytes))
    }
}
