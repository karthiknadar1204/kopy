import AppKit
import KopyCore
import ServiceManagement
import SwiftUI

@main
struct KopyApplication {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = KopyDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class KopyDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var model: KopyModel!
    private var shelf: EdgeShelfWindow!
    private let shortcut = GlobalShortcut()
    private var settingsWindow: NSWindow?
    private var tourWindow: NSWindow?
    private var tray: NSStatusItem?
    private var handoff: Task<Void, Never>?
    private var scheduledPrune: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var suspension = ShelfSuspension()
#if !KOPY_APP_STORE
    private var holdTestShelf = false
    private var licenseWindow: NSWindow?
    private var licenseRefresh: Task<Void, Never>?
    private var licenseRestored = false
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
#if KOPY_APP_STORE
        model = KopyModel()
#else
#if DEBUG
        let arguments = CommandLine.arguments
        let demo = arguments.contains("--demo")
        let isolated: URL?
        if let index = arguments.firstIndex(of: "--test-profile"), arguments.indices.contains(index + 1) {
            isolated = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            isolated = nil
        }
        holdTestShelf = isolated != nil && arguments.contains("--test-stay-open")
        model = KopyModel(demo: demo, isolatedProfile: isolated)
#else
        model = KopyModel()
#endif
        if !model.canUseProduct {
            let configuration = try? LicenseConfiguration()
            let license = LicenseController(
                configuration: configuration,
                client: configuration.map { DodoLicenseClient(configuration: $0) },
                store: KeychainLicenseStore(service: Bundle.main.bundleIdentifier ?? "com.karthiknadar.kopy")
            )
            model.license = license
            license.permissionChanged = { [weak self] enabled in self?.applyLicenseAccess(enabled) }
        }
#endif
        shelf = EdgeShelfWindow(content: KopyLanguageRoot(model: model) { [model = model!] in ShelfView(model: model) })
        bindModel()
        installApplicationMenu()
        installStatusItem()
        observeWorkspace()
        model.start()
#if !KOPY_APP_STORE
        model.updater.start()
#endif
        shelf.update(model.preferences)
        shelf.start()
        shelf.setSuspended(!model.canUseProduct)
        bindShortcut()
        let prune = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.prune()
#if !KOPY_APP_STORE
                self?.refreshLicense()
#endif
            }
        }
        RunLoop.main.add(prune, forMode: .common)
        scheduledPrune = prune

#if KOPY_APP_STORE
        if model.isTourDue, SMAppService.mainApp.status != .enabled { showTour() }
#else
#if DEBUG
        if demo || arguments.contains("--show") {
            showShelf()
        } else if model.isTourDue, !arguments.contains("--quiet"), isolated == nil,
                  SMAppService.mainApp.status != .enabled {
            showTour()
        }
#endif
        if model.license != nil { refreshLicense(); showLicense() }
#endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showShelf()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        shelf?.stop()
        shortcut.clear()
        model?.stop()
        scheduledPrune?.invalidate()
        handoff?.cancel()
#if !KOPY_APP_STORE
        licenseRefresh?.cancel()
        model?.license?.stop()
#endif
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func bindModel() {
        model.hideShelf = { [weak self] in self?.shelf.close() }
        model.showSettings = { [weak self] in self?.showSettings() }
        model.showTour = { [weak self] in self?.showTour() }
#if !KOPY_APP_STORE
        model.showLicense = { [weak self] in self?.showLicense() }
#endif
        model.tourCompleted = { [weak self] in
            guard let self, let window = tourWindow else { return }
            tourWindow = nil
            window.close()
        }
        model.captureFeedback = { [weak self] in self?.shelf.flashCopyIndicator() }
        model.detachedFeedback = { [weak self] message in self?.shelf.showNotice(message) }
        model.keepShelfOpen = { [weak self] duration in self?.shelf.holdOpen(for: duration) }
        model.preferencesChanged = { [weak self] next in
            guard let self else { return }
            shelf.update(next)
            settingsWindow?.title = localized("Kopy Settings")
            tourWindow?.title = localized("Welcome to Kopy")
            installApplicationMenu()
            if next.shortcut != attemptedShortcut { bindShortcut() }
        }
        model.keyboardEntryChanged = { [weak self] enabled in self?.shelf.setKeyboardEntry(enabled) }
        shelf.onOpen = { [weak self] in self?.model.recordTarget() }
        shelf.onClose = { [weak self] in self?.model.shelfClosed() }
        shelf.shouldStayOpen = { [weak self] in
            guard let self else { return false }
            return model.snippetDraft != nil || model.historyActionsOpen || model.clearConfirmationOpen
        }
        shelf.onDragChange = { [weak self] targeted in self?.model.isDropTargeted = targeted }
        shelf.onDrop = { [weak self] board in
            guard let self, model.canUseProduct, !model.isDemo else { return false }
            return model.clipboard.receiveDrop(board) { [weak self] payloads in
                self?.model.importPayloads(payloads)
            }
        }
        model.clipboard.reportDropError = { [weak self] message in self?.model.inform(message) }
    }

    private var attemptedShortcut: ShelfShortcut?

    private func bindShortcut() {
        guard model.canUseProduct else { shortcut.clear(); return }
        let keys = model.preferences.shortcut
        attemptedShortcut = keys
        if !shortcut.register(keys, action: { [weak self] in self?.shelf.toggle() }) {
            if let previous = shortcut.registeredShortcut {
                attemptedShortcut = previous
                model.updatePreferences { $0.shortcut = previous }
            }
            model.inform("Couldn’t register %@. Choose another shortcut in Settings.", keys.display)
        }
    }

    private func observeWorkspace() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in ShelfSuspension.notifications.keys {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applySuspension(name) }
            })
        }
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shelf.spaceChanged() }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shelf.refreshDisplays() }
        })
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shelf.refreshDisplays() }
        })
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshPermissions()
                self?.model.refreshLoginState()
#if !KOPY_APP_STORE
                self?.refreshLicense()
#endif
            }
        })
    }

    private func applySuspension(_ name: Notification.Name) {
        guard let suspended = suspension.handle(name) else { return }
        handoff?.cancel()
        shelf.setSuspended(suspended || !model.canUseProduct)
        if suspended {
            model.suspend(true)
        } else {
            handoff = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled else { return }
                self?.model.suspend(false)
            }
        }
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let application = NSMenu(title: "Kopy")
        application.addItem(makeItem("Settings", action: #selector(showSettings), key: ","))
        application.addItem(.separator())
        application.addItem(makeItem("Quit Kopy", action: #selector(quit), key: "q"))
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        menu.addItem(applicationItem)

        let file = NSMenu(title: localized("File"))
        file.addItem(NSMenuItem(title: localized("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem(title: file.title, action: nil, keyEquivalent: "")
        fileItem.submenu = file
        menu.addItem(fileItem)

        let edit = NSMenu(title: localized("Edit"))
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select all", #selector(NSText.selectAll(_:)), "a")
        ] {
            if key == "x" || key == "a" { edit.addItem(.separator()) }
            edit.addItem(NSMenuItem(title: localized(title), action: action, keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: edit.title, action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func installStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = KopyMark.template
        status.button?.toolTip = "Kopy"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        tray = status
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(makeItem("Show Shelf", action: #selector(showShelf)))
        menu.addItem(makeItem("Import Clipboard", action: #selector(importClipboard)))
        menu.addItem(makeItem("Settings", action: #selector(showSettings), key: ","))
        menu.addItem(makeItem("Welcome Tour", action: #selector(showTour)))
#if !KOPY_APP_STORE
        if model.updater.isConfigured {
            menu.addItem(makeItem("Check for updates", action: #selector(checkForUpdates)))
        }
#endif
        menu.addItem(.separator())

        let pause = makeItem("Incognito", action: #selector(toggleIncognito))
        pause.state = model.preferences.incognito ? .on : .off
        menu.addItem(pause)
        let hover = makeItem("Open on Hover", action: #selector(toggleHover))
        hover.state = model.preferences.hoverEnabled ? .on : .off
        menu.addItem(hover)

        let edgeItem = makeItem("Screen Edge", action: nil)
        menu.addItem(edgeItem)
        let edges = NSMenu()
        for edge in ShelfEdge.allCases {
            let item = makeItem(edge.rawValue.capitalized, action: #selector(setEdge(_:)))
            item.representedObject = edge.rawValue
            item.state = model.preferences.edge == edge ? .on : .off
            edges.addItem(item)
        }
        edgeItem.submenu = edges

        let screens = ShelfDisplay.connected
        if screens.count > 1 {
            let displayItem = makeItem("Display", action: nil)
            menu.addItem(displayItem)
            let displays = NSMenu()
            let selected = ShelfDisplay.selected(in: screens, for: model.preferences)
            for display in screens {
                let item = makeItem(display.name, action: #selector(setDisplay(_:)))
                item.representedObject = NSNumber(value: display.id)
                item.state = selected?.id == display.id ? .on : .off
                displays.addItem(item)
            }
            displayItem.submenu = displays
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Kopy", action: #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: localized(title), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func localized(_ key: String) -> String {
        ShelfLanguage.string(key, language: model.preferences.language)
    }

    @objc private func showShelf() {
#if !KOPY_APP_STORE
        guard model.canUseProduct else { showLicense(); return }
#endif
        shelf.show(waitForPointerEntry: true)
#if !KOPY_APP_STORE
        if holdTestShelf { shelf.holdOpen(for: .seconds(60)) }
#endif
    }

#if !KOPY_APP_STORE
    @objc private func checkForUpdates() {
        showSettings()
        model.updater.checkForUpdates()
    }
#endif

    @objc private func importClipboard() {
#if !KOPY_APP_STORE
        guard model.canUseProduct else { showLicense(); return }
#endif
        model.importClipboard()
        shelf.show()
    }

    @objc private func toggleIncognito() { model.updatePreferences { $0.incognito.toggle() } }
    @objc private func toggleHover() { model.updatePreferences { $0.hoverEnabled.toggle() } }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func setEdge(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let edge = ShelfEdge(rawValue: raw) else { return }
        model.updatePreferences { $0.edge = edge }
    }

    @objc private func setDisplay(_ item: NSMenuItem) {
        guard let id = (item.representedObject as? NSNumber)?.uint32Value,
              let display = ShelfDisplay.connected.first(where: { $0.id == id }) else { return }
        model.updatePreferences {
            $0.displayID = id
            $0.displayBounds = display.frame
        }
    }

    @objc private func showSettings() {
        shelf.close()
        model.refreshPermissions()
        model.refreshLoginState()
        if let settingsWindow {
            present(settingsWindow)
            return
        }
        let window = makeWindow(
            title: localized("Kopy Settings"),
            size: NSSize(width: 560, height: 480),
            minimumSize: NSSize(width: 480, height: 350),
            content: KopyLanguageRoot(model: model) { [model = model!] in SettingsView(model: model) }
        )
        settingsWindow = window
        present(window)
    }

    @objc private func showTour() {
#if !KOPY_APP_STORE
        guard model.canUseProduct else { showLicense(); return }
#endif
        shelf.close()
        if let tourWindow { present(tourWindow); return }
        let window = makeWindow(
            title: localized("Welcome to Kopy"),
            size: NSSize(width: 540, height: 365),
            minimumSize: NSSize(width: 420, height: 340),
            content: KopyLanguageRoot(model: model) { [model = model!] in WelcomeView(model: model) }
        )
        window.delegate = self
        tourWindow = window
        present(window)
    }

#if !KOPY_APP_STORE
    private func refreshLicense() {
        guard let license = model.license, licenseRefresh == nil else { return }
        licenseRefresh = Task { @MainActor [weak self] in
            guard let self else { return }
            if !licenseRestored {
                licenseRestored = true
                await license.restore()
            } else {
                await license.refresh()
            }
            self.licenseRefresh = nil
        }
    }

    private func applyLicenseAccess(_ enabled: Bool) {
        if !enabled { shelf.close() }
        model.setLicenseAccess(enabled)
        shelf.setSuspended(!enabled || !suspension.isEmpty)
        bindShortcut()
        if enabled {
            licenseWindow?.close()
            licenseWindow = nil
            if model.isTourDue { showTour() } else { showShelf() }
        } else {
            tourWindow?.close()
            settingsWindow?.close()
            showLicense()
        }
    }

    @objc private func showLicense() {
        guard let license = model.license else { return }
        shelf.close()
        if let licenseWindow { present(licenseWindow); return }
        let window = makeWindow(title: "Kopy Licence", size: NSSize(width: 460, height: 540),
                                minimumSize: NSSize(width: 420, height: 480), content: LicenseView(license: license))
        licenseWindow = window
        present(window)
    }
#endif

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === tourWindow else { return }
        tourWindow = nil
        model.finishTour()
    }

    private func makeWindow(title: String, size: NSSize, minimumSize: NSSize, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.contentMinSize = minimumSize
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct ShelfSuspension: OptionSet {
    let rawValue: UInt8

    private static let computer = Self(rawValue: 1 << 0)
    private static let screens = Self(rawValue: 1 << 1)
    private static let session = Self(rawValue: 1 << 2)

    static let notifications: [Notification.Name: (reason: Self, suspending: Bool)] = [
        NSWorkspace.willSleepNotification: (.computer, true),
        NSWorkspace.didWakeNotification: (.computer, false),
        NSWorkspace.screensDidSleepNotification: (.screens, true),
        NSWorkspace.screensDidWakeNotification: (.screens, false),
        NSWorkspace.sessionDidResignActiveNotification: (.session, true),
        NSWorkspace.sessionDidBecomeActiveNotification: (.session, false)
    ]

    mutating func handle(_ notification: Notification.Name) -> Bool? {
        guard let change = Self.notifications[notification] else { return nil }
        let wasSuspended = !isEmpty
        if change.suspending {
            insert(change.reason)
        } else {
            remove(change.reason)
        }
        return wasSuspended == !isEmpty ? nil : !isEmpty
    }
}
