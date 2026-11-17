import AppKit
import KopyCore

@MainActor
final class TransferPromiseBatch {
    private let directory: URL
    private let onReceive: @MainActor ([ClipboardPayload]) -> Void
    private let onError: @MainActor (String) -> Void
    private var results: [[ClipboardMember]] = []
    private var remaining = 0
    private var failed = false
    private var finished = false
    private var timeout: Task<Void, Never>?

    init(directory: URL, onReceive: @escaping @MainActor ([ClipboardPayload]) -> Void,
         onError: @escaping @MainActor (String) -> Void) {
        self.directory = directory
        self.onReceive = onReceive
        self.onError = onError
    }

    func receive(_ promises: [NSFilePromiseReceiver], queue: OperationQueue) {
        results = Array(repeating: [], count: promises.count)
        for (index, promise) in promises.enumerated() {
            promise.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue, reader: reader(index, directory))
            remaining += max(promise.fileNames.isEmpty ? promise.fileTypes.count : promise.fileNames.count, 1)
        }
        timeout = Task { [self] in
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled {
                failed = true
                finish(cleanup: false)
            }
        }
    }

    nonisolated private func reader(_ index: Int, _ directory: URL) -> @Sendable (URL, (any Error)?) -> Void {
        { [self] url, error in
            let member = error == nil ? Self.read(url, in: directory) : nil
            Task { @MainActor in
                guard !finished else { return }
                if let member { results[index].append(member) } else { failed = true }
                remaining -= 1
                if remaining == 0 { finish(cleanup: true) }
            }
        }
    }

    private func finish(cleanup: Bool) {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        timeout = nil
        let members = results.flatMap { $0 }
        if !members.isEmpty { onReceive([.files(members)]) }
        if failed { onError("Kopy could not import one or more promised files.") }
        if cleanup { try? FileManager.default.removeItem(at: directory) }
    }

    nonisolated static func read(_ url: URL, in directory: URL) -> ClipboardMember? {
        let expectedParent = directory.standardizedFileURL.resolvingSymlinksInPath()
        let target = url.resolvingSymlinksInPath()
        let manager = FileManager.default
        guard url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() == expectedParent else { return nil }
        defer { try? manager.removeItem(at: url) }
        guard target.deletingLastPathComponent() == expectedParent,
              let attributes = try? manager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, (0...ClipboardPayloadCodec.imageByteLimit).contains(size),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data: Data
        if size == 0 {
            data = Data()
        } else {
            guard let read = try? handle.read(upToCount: size + 1), read.count == size else { return nil }
            data = read
        }
        if let image = ClipboardPayloadCodec.image(data, name: url.lastPathComponent) { return .image(image) }
        return .file(ClipboardFile(url: url, size: size, attachment: data))
    }
}
