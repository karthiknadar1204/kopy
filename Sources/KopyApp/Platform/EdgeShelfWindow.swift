import AppKit
import KopyCore
import SwiftUI

@MainActor
final class EdgeShelfWindow {
    private let shelf = ShelfPanel()
    private let sensor = ShelfPanel()
    private let notice = ShelfPanel()
    private let sensorView = ShelfDropView()
    private let bodyView = ShelfDropView()
    private let beacon = ShelfBeacon()
    private var polling: Task<Void, Never>?
    private var intent = ShelfPointerIntent()
    private var outside: ContinuousClock.Instant?
    private var keepOpenUntil: ContinuousClock.Instant?
    private var waitsForPointerEntry = false
    private weak var dropTarget: ShelfDropView?
    private var isSuspended = false
    private var isOpen = false
    private var isRunning = false
    private var fullscreenCheck: (until: ContinuousClock.Instant, value: Bool)?
    private var preferences = ShelfPreferences()
    private var displays: [ShelfDisplay] = []
    private var currentCue: ShelfBeacon.Cue = .idle
    private var cueTimer: Task<Void, Never>?
    private var edgeHintFired = false
    private var panelMotion: Task<Void, Never>?
    private var relocation: Task<Void, Never>?
    private var fastUntil: ContinuousClock.Instant?
    private var trackedMenus: Set<ObjectIdentifier> = []
    private var menuObservers: [NSObjectProtocol] = []
    private var noticeTimer: Task<Void, Never>?

    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onDragChange: ((Bool) -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var shouldStayOpen: (() -> Bool)?

    init(content: some View) {
        let hosting = NSHostingView(rootView: content)
        shelf.title = "Kopy Shelf"
        shelf.contentView = bodyView
        shelf.isMovable = false
        shelf.level = .floating
        shelf.hasShadow = true
        bodyView.wantsLayer = true
        bodyView.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: bodyView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor)
        ])

        sensor.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        sensor.contentView = sensorView
        sensor.ignoresMouseEvents = true
        // A fully transparent window surface can fall through WindowServer hit testing.
        sensor.backgroundColor = NSColor.black.withAlphaComponent(0.012)
        sensorView.onClick = { [weak self] in self?.show() }
        notice.level = .floating
        notice.ignoresMouseEvents = true

        for view in [sensorView, bodyView] {
            view.onEnter = { [weak self, weak view] in
                guard let view else { return }
                self?.enteredDrop(on: view)
            }
            view.onExit = { [weak self, weak view] in
                guard let view else { return }
                self?.exitedDrop(on: view)
            }
            view.onDrop = { [weak self, weak view] board in
                guard let self, !isSuspended, !shouldAvoidFullscreen() else { return false }
                let accepted = onDrop?(board) ?? false
                if accepted {
                    if view === sensorView { show() }
                    holdOpen(for: .seconds(2))
                }
                return accepted
            }
        }
    }

    func update(_ preferences: ShelfPreferences) {
        let previous = self.preferences
        let oldGeometry = geometry
        self.preferences = preferences
        let moving = previous.edge != preferences.edge || previous.displayID != preferences.displayID
            || previous.displayBounds != preferences.displayBounds
        let adjustingPosition = previous.offset != preferences.offset || previous.horizontalOffset != preferences.horizontalOffset
            || previous.shelfHeight != preferences.shelfHeight || previous.edgeAlignment != preferences.edgeAlignment
            || previous.edgeSpan != preferences.edgeSpan || previous.edgeThickness != preferences.edgeThickness
        if moving || adjustingPosition {
            intent = ShelfPointerIntent()
            outside = nil
            if isOpen { keepOpenUntil = .now.advanced(by: .milliseconds(1_750)) }
        }
        if moving {
            edgeHintFired = false
            if isOpen, !reduceMotion, let oldGeometry {
                relocate(from: oldGeometry, oldPreferences: previous)
                return
            }
        }
        guard relocation == nil else { return }
        refreshDisplays()
        if isRunning, moving, !isOpen, !isSuspended {
            ShelfSound.play(.edgeBeacon, enabled: preferences.soundEffects)
        }
        if isRunning, !isOpen, !isSuspended, preferences.showEdgeLocationHint,
           moving || adjustingPosition || !previous.showEdgeLocationHint {
            flash(.hint, for: .milliseconds(450))
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeMenuTracking()
        refreshDisplays()
        beginPolling()
        flash(.intro, for: .milliseconds(1_300))
    }

    private func beginPolling() {
        guard isRunning, !isSuspended, polling == nil else { return }
        fastUntil = .now.advanced(by: .seconds(8))
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.sample() else { return }
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    func stop() {
        isRunning = false
        polling?.cancel()
        polling = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers.removeAll()
        cueTimer?.cancel()
        noticeTimer?.cancel()
        notice.orderOut(nil)
        close()
        sensor.orderOut(nil)
        beacon.hide()
    }

    func setSuspended(_ value: Bool) {
        guard isSuspended != value else { return }
        isSuspended = value
        intent = ShelfPointerIntent()
        if value {
            polling?.cancel()
            polling = nil
            cueTimer?.cancel()
            currentCue = .idle
            close()
            notice.orderOut(nil)
            sensor.orderOut(nil)
            beacon.hide()
        } else {
            refreshDisplays()
            beginPolling()
        }
    }

    func refreshDisplays() {
        cancelRelocation()
        let previous = display
        displays = ShelfDisplay.connected
        fullscreenCheck = nil
        if previous != display {
            intent = ShelfPointerIntent()
            outside = nil
            edgeHintFired = false
            if dropTarget != nil { close() }
        }
        guard isRunning, !isSuspended, let geometry else {
            hideForCurrentSpace()
            return
        }
        let behavior: NSWindow.CollectionBehavior = preferences.suppressFullscreen
            ? [.moveToActiveSpace, .ignoresCycle, .fullScreenNone]
            : [.moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]
        if shelf.collectionBehavior != behavior {
            shelf.collectionBehavior = behavior
            sensor.collectionBehavior = behavior
            notice.collectionBehavior = behavior
            beacon.setCollectionBehavior(behavior)
        }
        guard !shouldAvoidFullscreen() else {
            hideForCurrentSpace()
            return
        }
        let frame = geometry.shelf(preferences)
        if shelf.frame != frame {
            if frame.size != shelf.frame.size { bodyView.layer?.mask = nil }
            shelf.setFrame(frame, display: isOpen)
        }
        if isOpen {
            orderShelfForCurrentDrag(using: geometry)
        }
        refreshBeacon()
    }

    func spaceChanged() {
        close()
        notice.orderOut(nil)
        refreshDisplays()
    }

    func show(waitForPointerEntry: Bool = false) {
        guard !isOpen, !isSuspended, let geometry, !shouldAvoidFullscreen() else { return }
        panelMotion?.cancel()
        panelMotion = nil
        notice.orderOut(nil)
        cueTimer?.cancel()
        currentCue = .idle
        onOpen?()
        isOpen = true
        waitsForPointerEntry = waitForPointerEntry
        keepOpenUntil = .now.advanced(by: .milliseconds(480))
        outside = nil
        shelf.setFrame(geometry.shelf(preferences), display: true)
        shelf.ignoresMouseEvents = false
        beacon.hide()
        orderShelfForCurrentDrag(using: geometry)
        animateShelf(using: geometry, preferences: preferences, expanding: true, duration: 0.19)
    }

    private func orderShelfForCurrentDrag(using geometry: ShelfGeometry) {
        if dropTarget === sensorView {
            let dropArea = shelf.frame.union(geometry.dragCatch(geometry.trigger(preferences)))
            // Keep the same AppKit destination while revealing the shelf beneath it.
            if sensor.frame != dropArea { sensor.setFrame(dropArea, display: false) }
        } else {
            disarmSensor()
        }
        shelf.orderFrontRegardless()
    }

    func showNotice(_ text: String) {
        guard !isOpen, !isSuspended, let geometry, !shouldAvoidFullscreen() else { return }
        noticeTimer?.cancel()
        let host = NSHostingView(rootView: Text(text)
            .font(.callout)
            .foregroundStyle(ShelfTheme.ink)
            .lineLimit(3)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(width: 280, alignment: .leading)
            .background(ShelfTheme.background, in: .rect(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(ShelfTheme.line) })
        notice.contentView = host
        let height = max(host.fittingSize.height, 42)
        let area = geometry.shelf(preferences)
        let x = preferences.edge == .right ? area.maxX - 290 : area.minX + 10
        let y = preferences.edge == .top ? area.maxY - height - 10 : area.midY - height / 2
        notice.setFrame(CGRect(x: x, y: y, width: 280, height: height), display: true)
        notice.orderFrontRegardless()
        noticeTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.notice.orderOut(nil) }
        }
    }

    func toggle() {
        isOpen ? close(animated: true) : show(waitForPointerEntry: true)
    }

    func close() {
        close(animated: false)
    }

    private func close(animated: Bool) {
        panelMotion?.cancel()
        panelMotion = nil
        cancelRelocation()
        if let dropTarget { exitedDrop(on: dropTarget) }
        guard isOpen else {
            shelf.orderOut(nil)
            bodyView.layer?.mask = nil
            return
        }
        isOpen = false
        intent = ShelfPointerIntent()
        keepOpenUntil = nil
        waitsForPointerEntry = false
        outside = nil
        trackedMenus.removeAll()
        shelf.ignoresMouseEvents = true
        setKeyboardEntry(false)
        disarmSensor()
        onClose?()
        if animated, !reduceMotion, let geometry {
            let duration = 0.17
            animateShelf(using: geometry, preferences: preferences, expanding: false, duration: duration)
            panelMotion = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.finishClose()
            }
        } else {
            finishClose()
        }
    }

    private func finishClose() {
        panelMotion = nil
        shelf.orderOut(nil)
        bodyView.layer?.mask = nil
        refreshBeacon()
    }

    func setKeyboardEntry(_ enabled: Bool) {
        guard isOpen || !enabled else { return }
        shelf.keyboardEntryEnabled = enabled
        if enabled, !shelf.isKeyWindow {
            shelf.makeKey()
        } else if !enabled, shelf.isKeyWindow {
            shelf.makeFirstResponder(nil)
            shelf.resignKey()
        }
    }

    func holdOpen(for duration: Duration) {
        guard isOpen else { return }
        let deadline = ContinuousClock.now.advanced(by: duration)
        keepOpenUntil = max(keepOpenUntil ?? deadline, deadline)
    }

    func flashCopyIndicator() {
        guard preferences.showCopyIndicator, !isOpen, dropTarget == nil else { return }
        flash(.copied(preferences.copyIndicatorStyle), for: .milliseconds(780))
    }

    private var display: ShelfDisplay? {
        ShelfDisplay.selected(in: displays, for: preferences)
    }

    private var geometry: ShelfGeometry? {
        display.map { ShelfGeometry(edge: preferences.edge, workArea: $0.workArea) }
    }

    private func enteredDrop(on view: ShelfDropView) {
        dropTarget = view
        outside = nil
        if isOpen {
            onDragChange?(true)
            if view === bodyView { disarmSensor() }
        } else if view === sensorView, preferences.hoverEnabled {
            show()
            if isOpen { onDragChange?(true) }
        }
    }

    private func exitedDrop(on view: ShelfDropView) {
        guard view === dropTarget else { return }
        dropTarget = nil
        outside = nil
        onDragChange?(false)
        if isOpen { disarmSensor() }
    }

    private func sample() -> Int {
        guard !isSuspended, let geometry else { return 120 }
        let now = ContinuousClock.now
        let point = NSEvent.mouseLocation
        let trigger = geometry.trigger(preferences)
        let distance = geometry.intoScreen(point)
        let near = (-30...450).contains(distance)
        let edgeApproach = (-30...28).contains(distance)

        if (near || isOpen || beacon.isVisible || notice.isVisible), shouldAvoidFullscreen() {
            hideForCurrentSpace()
            intent = ShelfPointerIntent()
            return 90
        }

        if isOpen {
            let pressed = NSEvent.pressedMouseButtons != 0
            if shelf.frame.contains(point) { waitsForPointerEntry = false }
            if waitsForPointerEntry || keepOpenUntil.map({ now < $0 }) == true || !trackedMenus.isEmpty || dropTarget != nil
                || shouldStayOpen?() == true
                || pressed || relocation != nil {
                outside = nil
            } else if shelf.frame.insetBy(dx: -8, dy: -8).contains(point) || trigger.contains(point) {
                outside = nil
            } else if !shelf.frame.insetBy(dx: -24, dy: -20).contains(point) {
                if let outside, outside.duration(to: now) >= .milliseconds(250) {
                    close(animated: true)
                } else if outside == nil {
                    outside = now
                }
            }
            return 16
        }
        refreshBeacon()
        guard preferences.hoverEnabled else {
            disarmSensor()
            return 120
        }
        let pressed = NSEvent.pressedMouseButtons != 0
        updateExternalDrag(at: point, pressed: pressed, geometry: geometry, trigger: trigger)
        if !isOpen, intent.shouldOpen(at: point, now: now, geometry: geometry, trigger: trigger,
                                      buttonPressed: pressed, delay: .milliseconds(preferences.openDelayMilliseconds)) {
            show()
        }
        if !edgeApproach {
            edgeHintFired = false
        } else if !pressed, !edgeHintFired, !trigger.contains(point), !isOpen, preferences.showEdgeLocationHint {
            edgeHintFired = true
            flash(.hint, for: .milliseconds(450))
        }
        if near || isOpen || pressed { fastUntil = now.advanced(by: .milliseconds(1_500)) }
        return fastUntil.map { now < $0 } == true ? 16 : 95
    }

    private func updateExternalDrag(at point: CGPoint, pressed: Bool,
                                    geometry: ShelfGeometry, trigger: CGRect) {
        let isMovingDrag = pressed && (Self.recentDrag(dragged: .leftMouseDragged, down: .leftMouseDown, buttonMask: 1)
            || Self.recentDrag(dragged: .rightMouseDragged, down: .rightMouseDown, buttonMask: 2))
        let catchFrame = geometry.dragCatch(trigger)
        let nearing = geometry.approach(trigger, depth: 108, margin: 48).contains(point)
        let entered = dropTarget === sensorView
        let frame = entered || (isMovingDrag && nearing) ? catchFrame : trigger
        if sensor.frame != frame { sensor.setFrame(frame, display: false) }
        if !sensor.isVisible {
            sensor.ignoresMouseEvents = false
            sensor.orderFrontRegardless()
        }

        if isMovingDrag {
            let step = intent.dragCueStep(pull: geometry.dragPull(point, toward: trigger))
            if currentCue != .drag(step) {
                cueTimer?.cancel()
                currentCue = .drag(step)
                refreshBeacon()
            }
        } else if case .drag = currentCue {
            _ = intent.dragCueStep(pull: 0)
            currentCue = .idle
            refreshBeacon()
        }
    }

    private static func recentDrag(dragged: CGEventType, down: CGEventType, buttonMask: Int) -> Bool {
        guard NSEvent.pressedMouseButtons & buttonMask != 0 else { return false }
        let lastDrag = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: dragged)
        let lastDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: down)
        return lastDrag.isFinite && lastDrag <= lastDown
    }

    private func disarmSensor() {
        sensor.ignoresMouseEvents = true
        sensor.orderOut(nil)
    }

    private func hideForCurrentSpace() {
        close()
        disarmSensor()
        notice.orderOut(nil)
        beacon.hide()
    }

    private var reduceMotion: Bool {
        preferences.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func animateShelf(using geometry: ShelfGeometry, preferences: ShelfPreferences,
                              expanding: Bool, duration: TimeInterval) {
        guard let layer = bodyView.layer else { return }
        guard !reduceMotion else {
            layer.mask = nil
            return
        }
        bodyView.layoutSubtreeIfNeeded()
        let full = CGPath(rect: bodyView.bounds, transform: nil)
        let collapsedFrame = geometry.retractedFrame(for: shelf.frame, toward: geometry.trigger(preferences))
        let collapsed = CGPath(rect: collapsedFrame.offsetBy(dx: -shelf.frame.minX, dy: -shelf.frame.minY), transform: nil)
        let oldMask = layer.mask as? CAShapeLayer
        let startPath = oldMask?.presentation()?.path ?? (expanding ? collapsed : full)
        let endPath = expanding ? full : collapsed

        let mask = CAShapeLayer()
        mask.frame = bodyView.bounds
        mask.path = endPath
        layer.mask = mask
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = startPath
        animation.toValue = endPath
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: expanding ? .easeOut : .easeIn)
        mask.add(animation, forKey: "shelf")
    }

    private func relocate(from oldGeometry: ShelfGeometry, oldPreferences: ShelfPreferences) {
        guard relocation == nil else { return }
        shelf.ignoresMouseEvents = true
        ShelfSound.play(.edgeRetract, enabled: preferences.soundEffects)
        animateShelf(using: oldGeometry, preferences: oldPreferences, expanding: false, duration: 0.26)
        relocation = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, let self else { return }
            shelf.orderOut(nil)
            bodyView.layer?.mask = nil
            // Move only after the shelf has retracted, avoiding a visible jump across the desktop.
            relocation = nil
            refreshDisplays()
            guard isOpen, let geometry else { return }
            keepOpenUntil = .now.advanced(by: .milliseconds(1_750))
            shelf.ignoresMouseEvents = false
            ShelfSound.play(.edgeBeacon, enabled: preferences.soundEffects)
            ShelfSound.play(.edgeExpand, enabled: preferences.soundEffects)
            animateShelf(using: geometry, preferences: preferences, expanding: true, duration: 0.30)
        }
    }

    private func cancelRelocation() {
        guard let relocation else { return }
        relocation.cancel()
        self.relocation = nil
        shelf.ignoresMouseEvents = !isOpen
        bodyView.layer?.mask = nil
    }

    private func flash(_ cue: ShelfBeacon.Cue, for duration: Duration) {
        cueTimer?.cancel()
        currentCue = cue
        refreshBeacon()
        cueTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            currentCue = .idle
            refreshBeacon()
        }
    }

    private func refreshBeacon() {
        guard isRunning, !isOpen, panelMotion == nil, !isSuspended, let geometry,
              !shouldAvoidFullscreen() else {
            beacon.hide()
            return
        }
        beacon.show(currentCue, at: geometry.trigger(preferences), in: geometry, animated: !reduceMotion)
    }

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) {
            [weak self] note in
            guard let object = note.object as? NSMenu else { return }
            let menu = ObjectIdentifier(object)
            MainActor.assumeIsolated {
                if let self, self.isOpen { self.trackedMenus.insert(menu) }
            }
        })
        menuObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) {
            [weak self] note in
            guard let object = note.object as? NSMenu else { return }
            let menu = ObjectIdentifier(object)
            MainActor.assumeIsolated {
                guard let self, self.trackedMenus.remove(menu) != nil else { return }
                self.holdOpen(for: .milliseconds(1_500))
            }
        })
    }

    private func shouldAvoidFullscreen() -> Bool {
        guard preferences.suppressFullscreen, let display else { return false }
        let now = ContinuousClock.now
        if let fullscreenCheck, now < fullscreenCheck.until { return fullscreenCheck.value }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let value = ShelfDisplay.hasFullscreenWindow(in: windows, displayBounds: CGDisplayBounds(display.id),
                                                     safeTopInset: display.safeTopInset,
                                                     ignoring: ProcessInfo.processInfo.processIdentifier)
        fullscreenCheck = (now.advanced(by: .milliseconds(500)), value)
        return value
    }

}


@MainActor
final class ShelfPanel: NSPanel {
    var keyboardEntryEnabled = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { keyboardEntryEnabled }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
private final class ShelfDropView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var onClick: (() -> Void)?

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes(ClipboardController.supportedDropTypes)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        if let onClick {
            onClick()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(ClipboardController.localDragType) == true {
            return []
        }
        onEnter?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onExit?() }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onExit?() }
        return onDrop?(sender.draggingPasteboard) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) { onExit?() }
}
