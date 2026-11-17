import AppKit
import KopyCore
import UniformTypeIdentifiers

@MainActor
struct TransferFiles {
    private let manager = FileManager.default
    private let root = FileManager.default.temporaryDirectory.appending(path: "Kopy-Transfers", directoryHint: .isDirectory)

    func sessionDirectory() throws -> URL {
        try manager.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let session = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try manager.createDirectory(at: session, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return session
    }

    func stage(_ image: ClipboardImage, capturedAt: Date, index: Int = 1) throws -> URL {
        let session = try sessionDirectory()
        do {
            return try writeImage(image, note: nil, capturedAt: capturedAt, index: index, directory: session)
        } catch {
            try? manager.removeItem(at: session)
            throw error
        }
    }

    func isStaged(_ url: URL) -> Bool {
        let session = url.deletingLastPathComponent().standardizedFileURL
        guard UUID(uuidString: session.lastPathComponent) != nil else { return false }
        let parent = session.deletingLastPathComponent()
        if parent.path == root.standardizedFileURL.path { return true }
        return parent.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path
    }

    func resolve(_ file: ClipboardFile) throws -> URL {
        if let attachment = file.attachment {
            let name = file.url.lastPathComponent
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { throw ClipboardTransferError.nameUnavailable }
            let directory = try sessionDirectory()
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            do {
                try attachment.write(to: url, options: .withoutOverwriting)
                return url
            } catch {
                try? manager.removeItem(at: directory)
                throw error
            }
        }
        guard let original = file.availableURL else {
            throw ClipboardTransferError.missingFile(file.url.lastPathComponent)
        }
        return original
    }

    func export(_ images: [ClipboardImage], note: String?, capturedAt: Date) throws -> [URL] {
        guard !images.isEmpty else { throw ClipboardTransferError.unsupportedPayload }
        let downloads = try manager.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try images.enumerated().map { index, image in
            try writeImage(image, note: note, capturedAt: capturedAt, index: index + 1, directory: downloads)
        }
    }

    private struct ClipboardLease: Codable {
        let generation: Int
        let sessions: Set<String>
    }

    private var leaseURL: URL { root.appending(path: "ClipboardLease.json") }

    func recordClipboardItems(_ items: [NSPasteboardItem], generation: Int) {
        let roots = items.compactMap { item -> String? in
            guard let value = item.string(forType: .fileURL), let file = URL(string: value) else { return nil }
            guard isStaged(file) else { return nil }
            return file.deletingLastPathComponent().lastPathComponent
        }
        guard !roots.isEmpty,
              let data = try? JSONEncoder().encode(ClipboardLease(generation: generation, sessions: Set(roots)))
        else { return }
        try? data.write(to: leaseURL, options: .atomic)
    }

    func removeOldSessions(clipboardGeneration: Int, now: Date = .now) {
        let expiration = now.addingTimeInterval(-24 * 60 * 60)
        let lease = (try? Data(contentsOf: leaseURL)).flatMap { try? JSONDecoder().decode(ClipboardLease.self, from: $0) }
        let activeSessions = lease?.generation == clipboardGeneration ? lease?.sessions ?? [] : []
        let entries = (try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        for entry in entries {
            guard UUID(uuidString: entry.lastPathComponent) != nil,
                  !activeSessions.contains(entry.lastPathComponent),
                  let values = try? entry.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let created = values.creationDate, created < expiration else { continue }
            try? manager.removeItem(at: entry)
        }
    }

    private func writeImage(
        _ image: ClipboardImage, note: String?, capturedAt: Date, index: Int, directory: URL
    ) throws -> URL {
        let filename = image.name.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        let stamp = capturedAt.formatted(Date.ISO8601FormatStyle(dateTimeSeparator: .space, timeZone: .current)
            .year().month().day().time(includingFractionalSeconds: false).timeSeparator(.colon))
            .replacingOccurrences(of: ":", with: ".")
        let label = image.source == .screenshot ? "Screenshot" : "Image"
        let prefix = safeName(note) ?? safeName(filename) ?? "\(label) \(stamp)"
        let name = index > 1 ? "\(prefix) (\(index))" : prefix
        let ext = UTType(image.typeIdentifier)?.preferredFilenameExtension ?? "image"
        for version in 1...10_000 {
            let leaf = version == 1 ? "\(name).\(ext)" : "\(name) \(version).\(ext)"
            let target = directory.appending(path: leaf, directoryHint: .notDirectory)
            do {
                try image.data.write(to: target, options: .withoutOverwriting)
                return target
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw ClipboardTransferError.nameUnavailable
    }

    private func safeName(_ name: String?) -> String? {
        guard let name else { return nil }
        let forbidden = CharacterSet(charactersIn: "/\\:\u{0000}").union(.controlCharacters)
        let safe = name.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let trimmed = String(safe.unicodeScalars.prefix(45))
        return trimmed.isEmpty ? nil : trimmed
    }
}
