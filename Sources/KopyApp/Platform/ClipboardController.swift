import AppKit
import CoreGraphics
import KopyCore
import UniformTypeIdentifiers

enum PasteOutcome: Sendable, Equatable {
    case posted
    case copiedForManualPaste
    case clipboardChanged
}

enum ClipboardTransferError: LocalizedError {
    case unsupportedPayload
    case missingFile(String)
    case clipboardWriteFailed
    case clipboardChanged
    case nameUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedPayload: "There is no transferable content in this selection."
        case .missingFile(let name): "The original file “\(name)” is no longer available."
        case .clipboardWriteFailed: "Kopy could not write to the clipboard."
        case .clipboardChanged: "The clipboard changed while Kopy was writing."
        case .nameUnavailable: "Kopy could not find an unused name for the image."
        }
    }
}

@MainActor
final class ClipboardController {
    private let pasteboard: NSPasteboard
    private let files = TransferFiles()
    private var polling: Task<Void, Never>?
    private var settledGeneration: Int?
    private var pendingGeneration: Int?
    private var pendingAttempts = 0
    private var lastWrite: Int?
    private var pasteboardAccess: [ClipboardFileAccess] = []
    private var dragAccess: [ClipboardFileAccess] = []
    private var nextTransferCleanup: ContinuousClock.Instant?
    private let promiseQueue = OperationQueue()

    var isPaused = false {
        didSet {
            if oldValue != isPaused { reseed() }
        }
    }

    var reportDropError: (@MainActor (String) -> Void)?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        promiseQueue.maxConcurrentOperationCount = 2
    }

    var generation: Int { pasteboard.changeCount }
    var ownsLastWrite: Bool { generation == lastWrite }

    static var supportedDropTypes: [NSPasteboard.PasteboardType] {
        let promises = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return ClipboardPayloadCodec.supportedDropTypes + promises
    }

    static var localDragType: NSPasteboard.PasteboardType { ClipboardPayloadCodec.ownDrag }

    var automaticCaptureDenied: Bool {
        if #available(macOS 15.4, *) { return pasteboard.accessBehavior == .alwaysDeny }
        return false
    }

    func start(onCapture: @escaping @MainActor (ClipboardPayload) -> Void) {
        stop()
        pruneTransfersIfDue()
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(160))
                } catch {
                    return
                }
                guard let self else { return }
                if let payload = self.poll() { onCapture(payload) }
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
        reseed()
    }

    func importCurrent() -> ClipboardPayload? {
        let current = generation
        let payload = readPayload()
        guard generation == current else { return nil }
        settledGeneration = current
        pendingGeneration = nil
        pendingAttempts = 0
        return payload
    }

    func copy(_ payload: ClipboardPayload, plain: Bool = false, capturedAt: Date = .now) throws -> Int {
        try write(items(for: payload, plain: plain, capturedAt: capturedAt))
    }

    func clearIfOwned(generation expected: Int) {
        guard generation == expected, lastWrite == expected else { return }
        markOwnWrite(pasteboard.clearContents())
    }

    func paste(
        _ payload: ClipboardPayload,
        target: NSRunningApplication?,
        expectedGeneration: Int,
        mayRestoreFocus: Bool,
        plain: Bool = false,
        capturedAt: Date = .now
    ) async throws -> PasteOutcome {
        guard generation == expectedGeneration else { return .clipboardChanged }
        let objects = try items(for: payload, plain: plain, capturedAt: capturedAt)
        guard generation == expectedGeneration else { return .clipboardChanged }
        let written: Int
        do {
            written = try write(objects)
        } catch ClipboardTransferError.clipboardChanged {
            return .clipboardChanged
        }

        let selfPID = NSRunningApplication.current.processIdentifier
        guard let target, target.processIdentifier != selfPID,
              !target.isTerminated, CGPreflightPostEventAccess() else {
            return manualPasteOutcome(written)
        }

        if !isFrontmost(target) {
            guard mayRestoreFocus,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID else {
                return manualPasteOutcome(written)
            }
            NSApp.yieldActivation(to: target)
            guard target.activate() else { return manualPasteOutcome(written) }
            for _ in 0..<12 {
                if isFrontmost(target) { break }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID else {
                    return manualPasteOutcome(written)
                }
                do {
                    try await Task.sleep(for: .milliseconds(15))
                } catch {
                    return manualPasteOutcome(written)
                }
            }
        }

        guard generation == written else { return .clipboardChanged }
        guard !Task.isCancelled, !target.isTerminated, isFrontmost(target),
              CGPreflightPostEventAccess(),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            return .copiedForManualPaste
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(target.processIdentifier)
        up.postToPid(target.processIdentifier)
        return .posted
    }

    func requestPastePermission() -> Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }

    func receiveDrop(
        _ pasteboard: NSPasteboard,
        onReceive: @escaping @MainActor ([ClipboardPayload]) -> Void
    ) -> Bool {
        guard pasteboard.types?.contains(Self.localDragType) != true,
              !ClipboardPayloadCodec.isPrivate(pasteboard) else { return false }

        let originalFiles = originalFiles(from: pasteboard)
        if !originalFiles.isEmpty {
            onReceive([.files(originalFiles)])
            return true
        }

        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)?
            .compactMap { $0 as? NSFilePromiseReceiver } ?? []
        if !promises.isEmpty {
            do {
                let batch = TransferPromiseBatch(directory: try files.sessionDirectory(), onReceive: onReceive,
                                                 onError: { [weak self] in self?.reportDropError?($0) })
                batch.receive(promises, queue: promiseQueue)
                return true
            } catch {
                reportDropError?("Kopy could not import one or more promised files.")
                return false
            }
        }

        let droppedAddress = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string)
        if let droppedAddress, droppedAddress.prefix(11).lowercased() == "data:image/" {
            if let image = TransferRemoteImage.embeddedImage(droppedAddress) {
                onReceive([.image(image)])
                return true
            }
            reportDropError?("The dropped image could not be imported.")
            return false
        }

        guard let payload = ClipboardPayloadCodec.nonFilePayload(from: pasteboard) else { return false }
        if case .text(let text) = payload,
           let imageURL = URL(string: text.value), ClipboardPayloadCodec.isWebImageURL(imageURL) {
            Task { @MainActor [weak self] in
                do {
                    let image = try await TransferRemoteImage.load(imageURL)
                    onReceive([.image(image)])
                } catch {
                    self?.reportDropError?("The dropped image could not be imported.")
                }
            }
        } else {
            onReceive([payload])
        }
        return true
    }

    func dragItems(
        _ payload: ClipboardPayload, capturedAt: Date = .now, internalToken: Data? = nil
    ) throws -> [NSDraggingItem] {
        guard !payload.members.isEmpty else { throw ClipboardTransferError.unsupportedPayload }
        let transfers = try payload.members.enumerated().map { index, member in
            try prepare(member, capturedAt: capturedAt, index: index + 1)
        }
        dragAccess = transfers.compactMap(\.access)
        return transfers.map { file in
            let item = ClipboardPayloadCodec.item(fileURL: file.url)
            item.setData(Data(), forType: Self.localDragType)
            if let internalToken { item.setData(internalToken, forType: ClipboardPayloadCodec.internalDrag) }
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 36, height: 36),
                                          contents: NSWorkspace.shared.icon(forFile: file.url.path))
            return draggingItem
        }
    }

    func exportImages(_ payload: ClipboardPayload, note: String?, capturedAt: Date = .now) throws -> [URL] {
        let images = payload.members.compactMap { member -> ClipboardImage? in
            if case .image(let image) = member { return image }
            return nil
        }
        return try files.export(images, note: note, capturedAt: capturedAt)
    }

    func finishDrag() { dragAccess.removeAll() }

    func prepareTransfer(for file: ClipboardFile) throws -> TransferFiles.PreparedFile {
        try files.resolve(file)
    }

    private func poll() -> ClipboardPayload? {
        let current = generation
        if current != lastWrite { pasteboardAccess.removeAll() }
        guard !isPaused, current != settledGeneration else {
            pendingGeneration = nil
            return nil
        }
        if pendingGeneration != current {
            pendingGeneration = current
            pendingAttempts = 0
            return nil
        }

        if automaticCaptureDenied {
            finishCapture(current)
            return nil
        }
        if ClipboardPayloadCodec.isPrivate(pasteboard) {
            finishCapture(current)
            return nil
        }
        let payload = readAvailablePayload()
        guard generation == current else { return nil }
        pendingAttempts += 1
        if payload != nil || pendingAttempts >= 5 { finishCapture(current) }
        return payload
    }

    private func readPayload() -> ClipboardPayload? {
        guard !ClipboardPayloadCodec.isPrivate(pasteboard) else { return nil }
        return readAvailablePayload()
    }

    private func readAvailablePayload() -> ClipboardPayload? {
        let references = originalFiles(from: pasteboard)
        return references.isEmpty ? ClipboardPayloadCodec.nonFilePayload(from: pasteboard) : .files(references)
    }

    private func originalFiles(from pasteboard: NSPasteboard) -> [ClipboardMember] {
        ClipboardPayloadCodec.files(from: pasteboard).filter {
            guard case .file(let file) = $0 else { return true }
            return !files.isStaged(file.url)
        }
    }

    private func reseed() {
        finishCapture(generation)
    }

    private func finishCapture(_ current: Int) {
        settledGeneration = current
        pendingGeneration = nil
        pendingAttempts = 0
    }

    private func write(_ prepared: [PreparedItem]) throws -> Int {
        let items = prepared.map(\.item)
        guard !items.isEmpty else { throw ClipboardTransferError.unsupportedPayload }
        let written = pasteboard.clearContents()
        markOwnWrite(written)
        guard generation == written else { throw ClipboardTransferError.clipboardChanged }
        guard pasteboard.writeObjects(items) else { throw ClipboardTransferError.clipboardWriteFailed }
        guard generation == written else { throw ClipboardTransferError.clipboardChanged }
        pasteboardAccess = prepared.compactMap(\.access)
        if pasteboard.name == .general {
            files.recordClipboardItems(items, generation: written)
            pruneTransfersIfDue()
        }
        return written
    }

    private func markOwnWrite(_ written: Int) {
        pasteboardAccess.removeAll()
        finishCapture(written)
        lastWrite = written
    }

    private func pruneTransfersIfDue() {
        guard pasteboard.name == .general else { return }
        let now = ContinuousClock.now
        if let nextTransferCleanup, now < nextTransferCleanup { return }
        files.removeOldSessions(clipboardGeneration: generation)
        nextTransferCleanup = now.advanced(by: .seconds(3_600))
    }

    private func manualPasteOutcome(_ written: Int) -> PasteOutcome {
        generation == written ? .copiedForManualPaste : .clipboardChanged
    }

    private struct PreparedItem {
        let item: NSPasteboardItem
        var access: ClipboardFileAccess?
    }

    private func items(for payload: ClipboardPayload, plain: Bool, capturedAt: Date) throws -> [PreparedItem] {
        if case .text(let text) = payload {
            return [PreparedItem(item: ClipboardPayloadCodec.textItem(text, plain: plain))]
        }
        if case .image(let image) = payload {
            let url = try? files.stage(image, capturedAt: capturedAt)
            return [PreparedItem(item: ClipboardPayloadCodec.item(fileURL: url, image: image))]
        }
        return try payload.members.enumerated().map { index, member in
            switch member {
            case .file(let file):
                let transfer = try files.resolve(file)
                return PreparedItem(item: ClipboardPayloadCodec.item(fileURL: transfer.url), access: transfer.access)
            case .image(let image):
                let url = try files.stage(image, capturedAt: capturedAt, index: index + 1)
                return PreparedItem(item: ClipboardPayloadCodec.item(fileURL: url, image: image))
            }
        }
    }

    private func prepare(_ member: ClipboardMember, capturedAt: Date, index: Int) throws -> TransferFiles.PreparedFile {
        switch member {
        case .file(let file): try files.resolve(file)
        case .image(let image): TransferFiles.PreparedFile(url: try files.stage(image, capturedAt: capturedAt, index: index))
        }
    }

    private func isFrontmost(_ target: NSRunningApplication) -> Bool {
        let current = NSWorkspace.shared.frontmostApplication
        return current?.processIdentifier == target.processIdentifier && current?.launchDate == target.launchDate
    }
}
