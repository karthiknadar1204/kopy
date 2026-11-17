import AppKit
import CryptoKit
import KopyCore
import Observation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
@Observable
final class KopyModel {
    private static let tourVersion = 2
    private(set) var items: [ClipboardItem] = []
    private(set) var preferences = ShelfPreferences()
    private(set) var hasPastePermission = false
    private(set) var automaticCaptureDenied = false
    private(set) var launchAtLogin = false
    private(set) var isLoginApprovalRequired = false
    private(set) var hasStoredHistory = true
    private(set) var isLoadingHistory = false
    private(set) var isShelfOpen = false
    private(set) var noteDraft: NoteDraft?
    private(set) var importRevision = 0
    private(set) var expandedPinnedFilters: Set<String> = []
    var isDropTargeted = false
    var message: String?
    let isDemo: Bool
#if !KOPY_APP_STORE
    let updater: KopyUpdater
#endif
    private let isolatedProfile: URL?

    @ObservationIgnored let clipboard = ClipboardController()
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var history: HistoryStore?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var messageTimer: Task<Void, Never>?
    @ObservationIgnored private var target: NSRunningApplication?
    @ObservationIgnored private var borrowedFocus = false
    @ObservationIgnored private var lastPaste: ContinuousClock.Instant?
    @ObservationIgnored private var lastCopiedItem: (id: UUID, generation: Int)?
    @ObservationIgnored private var activeDrag: DragSelection?
    @ObservationIgnored var preferencesChanged: ((ShelfPreferences) -> Void)?
    @ObservationIgnored var keyboardEntryChanged: ((Bool) -> Void)?
    @ObservationIgnored var showSettings: (() -> Void)?
    @ObservationIgnored var showTour: (() -> Void)?
    @ObservationIgnored var tourCompleted: (() -> Void)?
    @ObservationIgnored var hideShelf: (() -> Void)?
    @ObservationIgnored var captureFeedback: (() -> Void)?
    @ObservationIgnored var detachedFeedback: ((String) -> Void)?
    @ObservationIgnored var keepShelfOpen: ((Duration) -> Void)?

    init(demo: Bool = false, isolatedProfile: URL? = nil) {
        isDemo = demo
        self.isolatedProfile = isolatedProfile
        defaults = isolatedProfile.map { UserDefaults(suiteName: "Kopy.Test.\($0.lastPathComponent)") ?? .standard } ?? .standard
#if !KOPY_APP_STORE
        updater = KopyUpdater(enabled: !demo && isolatedProfile == nil, defaults: defaults)
#endif
        if demo {
            items = Self.examples
            expandedPinnedFilters = Set(ClipboardFilter.allCases.map(\.rawValue))
            return
        }
        expandedPinnedFilters = Set(defaults.stringArray(forKey: "expandedPinnedFilters") ?? [])
        if let data = defaults.data(forKey: "shelfPreferences"),
           let decoded = try? JSONDecoder().decode(ShelfPreferences.self, from: data) {
            preferences = decoded.normalized()
        }
#if KOPY_APP_STORE
        if !defaults.bool(forKey: "clipboardCaptureConsented") { preferences.incognito = true }
#endif
        refreshPermissions()
        refreshLoginState()
    }

    nonisolated private static func openHistory(profile: URL?, service: String) throws -> HistoryStore {
        let root: URL
        if let profile {
            root = profile
        } else {
            root = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appending(path: "Kopy", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let database = root.appending(path: "History.sqlite3")
        let key = if profile != nil {
            SymmetricKey(data: SHA256.hash(data: Data(root.resolvingSymlinksInPath().path.utf8)))
        } else {
            try LocalHistoryKey.load(service: service, createIfMissing: !FileManager.default.fileExists(atPath: database.path))
        }
        return try HistoryStore(databaseURL: database, encryptionKey: key)
    }

    func start() {
        guard !isDemo, !isLoadingHistory, history == nil else { return }
        isLoadingHistory = true
        let profile = isolatedProfile
        let service = Bundle.main.bundleIdentifier ?? "com.karthiknadar.kopy"
        let loading = Task.detached(priority: .userInitiated) {
            try Self.openHistory(profile: profile, service: service)
        }
        mutation = Task { @MainActor [weak self] in
            let result = await loading.result
            guard let self else { return }
            defer { self.isLoadingHistory = false }
            switch result {
            case .success(let store):
                self.history = store
                if store.unreadableItemCount > 0 {
                    self.message = ShelfLanguage.string(
                        "Some history items could not be read. Kopy kept the readable items and preserved any damaged data.",
                        language: self.preferences.language
                    )
                }
                do {
                    let settings = self.preferences
                    let existing = try await store.prune(preferences: settings)
                    self.items = settings.clearOnRestart ? try await store.clear(Set(existing.map(\.id))) : existing
                } catch {
                    self.inform(error)
                }
                self.startCapture()
            case .failure(let error):
                self.hasStoredHistory = false
                self.message = ShelfLanguage.errorMessage(error, language: self.preferences.language)
            }
        }
    }

    private func startCapture() {
        clipboard.isPaused = isSuspended || preferences.incognito
        clipboard.start { [weak self] payload in
            guard let self else { return }
            let settings = self.preferences
            self.mutate { store in
                try await store.capture(payload, preferences: settings)
            }
            self.captureFeedback?()
            self.play(.capture)
        }
    }

    func stop() { clipboard.stop() }

    func suspend(_ value: Bool) {
        isSuspended = value
        clipboard.isPaused = value || preferences.incognito
    }

    func prune() {
        guard !isDemo else { return }
        let settings = preferences
        mutate { try await $0.prune(preferences: settings) }
    }

    func recordTarget() {
        isShelfOpen = true
        refreshPermissions()
        let foreground = NSWorkspace.shared.frontmostApplication
        target = foreground?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : foreground
        borrowedFocus = false
    }

    func shelfClosed() {
        finishNote(saving: true)
        isShelfOpen = false
    }

    func updatePreferences(_ change: (inout ShelfPreferences) -> Void) {
        var next = preferences
        change(&next)
        next = next.normalized()
        guard next != preferences else { return }
        let retentionChanged = next.historyLimit != preferences.historyLimit || next.autoDeleteHours != preferences.autoDeleteHours
        let captureChanged = next.incognito != preferences.incognito
        preferences = next
#if KOPY_APP_STORE
        if !next.incognito { defaults.set(true, forKey: "clipboardCaptureConsented") }
#endif
        if !isDemo, let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: "shelfPreferences")
        }
        if captureChanged { clipboard.isPaused = isSuspended || next.incognito }
        if retentionChanged { prune() }
        preferencesChanged?(next)
    }

    func refreshPermissions() {
        hasPastePermission = CGPreflightPostEventAccess()
        automaticCaptureDenied = clipboard.automaticCaptureDenied
    }

    func requestPastePermission() {
        hasPastePermission = clipboard.requestPastePermission()
        if !hasPastePermission {
            inform("Kopy can copy the item for manual paste. Allow Accessibility access in System Settings for click-to-paste.")
        }
    }

    func setKeyboardEntry(_ enabled: Bool) {
        if enabled { borrowedFocus = true }
        keyboardEntryChanged?(enabled)
    }

    func openSettings() { showSettings?() }
    func openTour() { showTour?() }

    var isTourDue: Bool {
        max(defaults.integer(forKey: "welcomeTourVersion"), defaults.bool(forKey: "welcomeTourV1") ? 1 : 0)
            < Self.tourVersion
    }

    func finishTour() {
        if !isDemo { defaults.set(Self.tourVersion, forKey: "welcomeTourVersion") }
        tourCompleted?()
    }

    func enableClipboardHistory() {
        updatePreferences { $0.incognito = false }
    }

    func refreshLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        isLoginApprovalRequired = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDemo else { launchAtLogin = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            inform("macOS couldn’t update the login item. Check Login Items in System Settings.")
        }
        refreshLoginState()
    }

    func importClipboard() {
        guard !isDemo else { return }
        guard let payload = clipboard.importCurrent() else {
            inform("There’s no supported item to import from the clipboard.")
            return
        }
        importPayloads([payload])
    }

    func importPayloads(_ payloads: [ClipboardPayload]) {
        guard !isDemo, !payloads.isEmpty else { return }
        let settings = preferences
        mutate({ try await $0.importPayloads(payloads, preferences: settings) }) { [weak self] _ in
            self?.importRevision &+= 1
        }
    }

    func paste(_ item: ClipboardItem, members: Set<UUID>? = nil, plain: Bool = false) {
        guard let payload = payload(for: item, members: members) else { return }
        deliver(payload, itemID: item.id, promotes: members == nil, plain: plain, capturedAt: item.activityAt)
    }

    func pasteEmoji(_ emoji: String) {
        guard !emoji.isEmpty, emoji.utf16.count <= 64 else { return }
        deliver(.text(ClipboardText(emoji)))
    }

    private func deliver(
        _ payload: ClipboardPayload, itemID: UUID? = nil, promotes: Bool = false, plain: Bool = false,
        capturedAt: Date = .now
    ) {
        guard !isDemo else { inform("Demo item"); return }
        let now = ContinuousClock.now
        if let lastPaste, lastPaste.duration(to: now) < .milliseconds(600) { return }
        lastPaste = now
        let expected = clipboard.generation
        let target = self.target
        let shouldRestore = borrowedFocus
        hideShelf?()
        Task { @MainActor in
            do {
                let result = try await clipboard.paste(
                    payload, target: target, expectedGeneration: expected,
                    mayRestoreFocus: shouldRestore, plain: plain, capturedAt: capturedAt
                )
                switch result {
                case .posted, .copiedForManualPaste:
                    if let itemID, promotes, preferences.movePastedToTop { mutate { try await $0.touch(itemID) } }
                    if clipboard.ownsLastWrite, let itemID {
                        lastCopiedItem = (itemID, clipboard.generation)
                    }
                    if case .copiedForManualPaste = result { inform("Copied. Press ⌘V where you want to paste.") }
                case .clipboardChanged:
                    inform("The clipboard changed. Select the item again to paste it.")
                }
            } catch {
                inform(error)
            }
        }
    }

    func copy(_ item: ClipboardItem, members: Set<UUID>? = nil) {
        guard let payload = payload(for: item, members: members), !isDemo else { return }
        do {
            lastCopiedItem = (item.id, try clipboard.copy(payload, capturedAt: item.activityAt))
            mutate { try await $0.touch(item.id) }
            inform("Copied")
        } catch {
            inform(error)
        }
    }

    func copyText(_ text: String) {
        guard !isDemo else { return }
        do {
            _ = try clipboard.copy(.text(ClipboardText(text)))
            lastCopiedItem = nil
            inform("Copied")
        } catch {
            inform(error)
        }
    }

    func pin(_ item: ClipboardItem) {
        mutate({ try await $0.setPinned(!item.pinned, for: item.id) }) { [weak self] _ in
            self?.play(item.pinned ? .off : .on)
        }
    }

    func editNote(_ item: ClipboardItem) {
        noteDraft = NoteDraft(itemID: item.id, text: item.note ?? "")
    }

    func updateNoteDraft(_ text: String) {
        noteDraft?.text = String(text.unicodeScalars.prefix(120))
    }

    func finishNote(saving: Bool) {
        guard let draft = noteDraft else { return }
        noteDraft = nil
        if saving {
            mutate { try await $0.setNote(draft.text, for: draft.itemID) }
        }
    }

    func play(_ cue: ShelfSound) {
        ShelfSound.play(cue, enabled: preferences.soundEffects)
    }

    func togglePinnedSection(_ filter: ClipboardFilter) {
        if expandedPinnedFilters.remove(filter.rawValue) != nil {
            play(.collapse)
        } else {
            expandedPinnedFilters.insert(filter.rawValue)
            play(.expand)
        }
        if !isDemo {
            defaults.set(expandedPinnedFilters.sorted(), forKey: "expandedPinnedFilters")
        }
    }

    func delete(_ item: ClipboardItem) {
        mutate({ try await $0.delete(item.id) }) { [weak self] _ in
            self?.clearOwnedClipboard(in: [item.id])
            self?.play(.delete)
        }
    }

    func clear(_ items: [ClipboardItem], since: Date? = nil) {
        let ids = Set(items.filter { item in
            !item.isProtected && (since.map { item.activityAt >= $0 } ?? true)
        }.map(\.id))
        mutate({ try await $0.clear(ids, since: since) }) { [weak self] remaining in
            self?.clearOwnedClipboard(in: ids.subtracting(remaining.map(\.id)))
        }
    }

    private func clearOwnedClipboard(in ids: Set<UUID>) {
        if let lastCopiedItem, ids.contains(lastCopiedItem.id) {
            clipboard.clearIfOwned(generation: lastCopiedItem.generation)
            self.lastCopiedItem = nil
        }
    }

    func merge(_ source: UUID, into target: UUID, members: Set<UUID>? = nil) {
        mutate { try await $0.merge(source, into: target, members: members) }
    }

    func split(_ item: ClipboardItem, member: UUID) {
        mutate { try await $0.split(item.id, member: member) }
    }

    func openLink(_ item: ClipboardItem) {
        guard !isDemo, case .text(let text) = item.payload, let url = text.webURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyCleanLink(_ item: ClipboardItem) {
        guard case .text(let text) = item.payload, let url = text.cleanedURL else { return }
        copyText(url.absoluteString)
    }

    func reveal(_ file: ClipboardFile) {
        guard !isDemo else { return }
        do {
            let transfer = try clipboard.prepareTransfer(for: file)
            withExtendedLifetime(transfer) {
                NSWorkspace.shared.activateFileViewerSelecting([transfer.url])
            }
        } catch {
            inform(error)
        }
    }

    func copyPaths(_ files: [ClipboardFile]) {
        guard !isDemo else { return }
        do {
            let paths = try files.map { try clipboard.prepareTransfer(for: $0).url.path }
            copyText(paths.joined(separator: "\n"))
        } catch {
            inform(error)
        }
    }

    func saveImages(_ item: ClipboardItem, members: Set<UUID>? = nil) {
        guard !isDemo, let payload = payload(for: item, members: members) else { return }
        do {
            let files = try clipboard.exportImages(payload, note: item.note, capturedAt: item.activityAt)
            if !files.isEmpty {
                if files.count == 1 {
                    inform("Saved to Downloads")
                } else {
                    inform("Saved %lld images to Downloads", files.count)
                }
            }
        } catch {
            inform(error)
        }
    }

    func nativeDragItems(_ item: ClipboardItem, members: Set<UUID>?) -> [NSDraggingItem] {
        guard !isDemo, let payload = payload(for: item, members: members) else { return [] }
        let selection = DragSelection(source: item.id, members: members, token: UUID())
        do {
            let items = try clipboard.dragItems(
                payload, capturedAt: item.activityAt, internalToken: Data(selection.token.uuidString.utf8)
            )
            activeDrag = selection
            return items
        } catch {
            inform(error)
            return []
        }
    }

    func finishExternalDrag(_ item: ClipboardItem, members: Set<UUID>?) {
        if members == nil, preferences.movePastedToTop { mutate { try await $0.touch(item.id) } }
    }

    func acceptInternalDrop(_ providers: [NSItemProvider], target: UUID? = nil) -> Bool {
        guard let selection = activeDrag,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("com.kopy.clipboard-item") }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: "com.kopy.clipboard-item") { [weak self] data, _ in
            guard data == Data(selection.token.uuidString.utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activeDrag?.token == selection.token else { return }
                self.activeDrag = nil
                if let target, target != selection.source {
                    self.merge(selection.source, into: target, members: selection.members)
                } else if target == nil, let members = selection.members, members.count == 1,
                          let member = members.first, let item = self.items.first(where: { $0.id == selection.source }) {
                    self.split(item, member: member)
                }
            }
        }
        return true
    }

    func inform(_ key: String, _ arguments: CVarArg...) {
        showMessage(ShelfLanguage.string(key, language: preferences.language, arguments: arguments))
    }

    private func inform(_ error: any Error) {
        showMessage(ShelfLanguage.errorMessage(error, language: preferences.language))
    }

    private func showMessage(_ text: String) {
        message = text
        detachedFeedback?(text)
        messageTimer?.cancel()
        messageTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.message = nil }
        }
    }

    private func payload(for item: ClipboardItem, members: Set<UUID>?) -> ClipboardPayload? {
        guard let current = items.first(where: { $0.id == item.id }) else { return nil }
        if let members { return current.payload.selecting(members) }
        return current.payload
    }

    private func mutate(
        _ action: @escaping @Sendable (HistoryStore) async throws -> [ClipboardItem],
        onSuccess: (([ClipboardItem]) -> Void)? = nil
    ) {
        guard !isDemo, history != nil || isLoadingHistory else { return }
        let previous = mutation
        mutation = Task { @MainActor [weak self] in
            await previous?.value
            guard let history = self?.history else { return }
            do {
                let updated = try await action(history)
                self?.items = updated
                onSuccess?(updated)
            } catch {
                self?.inform(error)
            }
        }
    }

    private static var examples: [ClipboardItem] {
        let directory = FileManager.default.homeDirectoryForCurrentUser
        let sample = directory.appending(path: "Documents/Reference")
        return [
            ClipboardItem(payload: .text(ClipboardText("The details are the design.")), pinned: true, note: "Studio notes"),
            ClipboardItem(payload: .text(ClipboardText("https://developer.apple.com/design/", title: "Apple Design")), activityAt: .now - 43),
            ClipboardItem(payload: .text(ClipboardText("#D68B71")), activityAt: .now - 118),
            ClipboardItem(payload: .files([
                .file(ClipboardFile(url: sample.appending(path: "Brief.pdf"), size: 83_250)),
                .file(ClipboardFile(url: sample.appending(path: "Layout.sketch"), size: 216_000))
            ]), activityAt: .now - 700),
            ClipboardItem(payload: .text(ClipboardText("Polish the handoff, then test with a real file.")), activityAt: .now - 1500)
        ]
    }
}

private struct DragSelection: Sendable {
    let source: UUID
    let members: Set<UUID>?
    let token: UUID
}

struct NoteDraft: Sendable {
    let itemID: UUID
    var text: String
}
