import AppKit
import Observation
import Sparkle

enum KopyUpdateMode: String, CaseIterable, Identifiable {
    case auto, notify, off

    var id: Self { self }
}

enum KopyUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case downloading(progress: Double?)
    case preparing(progress: Double?)
    case ready(version: String)
    case installing
    case failed(String)
}

@MainActor @Observable
final class KopyUpdater {
    private static let modeKey = "kopyUpdateMode"

    private let bundle: Bundle
    private let defaults: UserDefaults
    private let driver = KopyUpdateDriver()
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var rescheduledCheck: Task<Void, Never>?

    let isConfigured: Bool
    private(set) var mode: KopyUpdateMode

    var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var state: KopyUpdateState { driver.state }

    init(enabled: Bool = true, bundle: Bundle = .main, defaults: UserDefaults = .standard,
         allowLocalFeed: Bool = false) {
        self.bundle = bundle
        self.defaults = defaults
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = enabled && Self.canUseFeed(feed, publicKey: key, allowLocalFeed: allowLocalFeed)
        mode = defaults.string(forKey: Self.modeKey).flatMap(KopyUpdateMode.init(rawValue:)) ?? .auto
        driver.setMode(mode)
    }

    func start() {
        guard isConfigured, updater == nil else { return }
        let candidate = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        do {
            try candidate.start()
            updater = candidate
            applyMode(to: candidate)
            if candidate.automaticallyChecksForUpdates { candidate.checkForUpdatesInBackground() }
        } catch {
            driver.fail(error.localizedDescription)
        }
    }

    func setMode(_ mode: KopyUpdateMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        rescheduledCheck?.cancel()
        driver.setMode(mode)
        guard let updater else { return }
        applyMode(to: updater)
        if mode != .off {
            rescheduledCheck = Task { @MainActor [weak updater] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let updater, updater.automaticallyChecksForUpdates, !updater.sessionInProgress else { return }
                updater.checkForUpdatesInBackground()
            }
        }
    }

    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    func downloadOrInstall() { driver.downloadOrInstall() }

    func skip() { driver.skip() }

    private func applyMode(to updater: SPUUpdater) {
        let checks = mode != .off
        if updater.automaticallyChecksForUpdates != checks { updater.automaticallyChecksForUpdates = checks }
        if updater.automaticallyDownloadsUpdates { updater.automaticallyDownloadsUpdates = false }
    }

    private static func canUseFeed(_ value: String?, publicKey: String?, allowLocalFeed: Bool) -> Bool {
        guard let value, let feed = URLComponents(string: value),
              let host = feed.host, !host.isEmpty, feed.user == nil, feed.password == nil,
              let publicKey, Data(base64Encoded: publicKey)?.count == 32 else { return false }
        if feed.scheme == "https" { return true }
        return allowLocalFeed && feed.scheme == "http" && host == "127.0.0.1"
    }
}

@MainActor @Observable
private final class KopyUpdateDriver: NSObject, SPUUserDriver {
    private(set) var state: KopyUpdateState = .idle
    @ObservationIgnored private var mode: KopyUpdateMode = .auto
    @ObservationIgnored private var action: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var cancelDownload: (() -> Void)?
    @ObservationIgnored private var retryTermination: (() -> Void)?
    @ObservationIgnored private var version = ""
    @ObservationIgnored private var build = ""
    @ObservationIgnored private var skippedBuild: String?
    @ObservationIgnored private var backgroundOffer = false
    @ObservationIgnored private var automaticDownload = false
    @ObservationIgnored private var moreInformation: URL?
    @ObservationIgnored private var expectedLength: UInt64 = 0
    @ObservationIgnored private var receivedLength: Double = 0

    func setMode(_ mode: KopyUpdateMode) {
        self.mode = mode
        if mode == .auto, backgroundOffer, case .available = state, moreInformation == nil {
            beginDownload(automatically: true)
        }
        if mode != .auto, automaticDownload {
            if case .downloading = state { cancelDownload?() }
            if case .ready = state { reply(.skip) }
        }
        if mode == .off, backgroundOffer, case .available = state { reply(.dismiss) }
    }

    func downloadOrInstall() {
        switch state {
        case .available:
            if let moreInformation {
                NSWorkspace.shared.open(moreInformation)
                reply(.dismiss)
            } else {
                beginDownload(automatically: false)
            }
        case .ready:
            state = .installing
            reply(.install)
        case .installing:
            retryTermination?()
        default:
            break
        }
    }

    func skip() {
        switch state {
        case .available:
            skippedBuild = build
            reply(.dismiss)
        case .downloading:
            cancelDownload?()
        case .ready:
            skippedBuild = build
            reply(.skip)
        default:
            break
        }
    }

    func fail(_ reason: String) { state = .failed(reason) }

    private func beginDownload(automatically: Bool) {
        automaticDownload = automatically
        state = .downloading(progress: nil)
        reply(.install)
    }

    private func reply(_ choice: SPUUserUpdateChoice) {
        let handler = action
        action = nil
        if choice != .install { state = .idle }
        handler?(choice)
    }

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: mode != .off, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        state = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState,
                         reply handler: @escaping (SPUUserUpdateChoice) -> Void) {
        guard updateState.userInitiated || (mode != .off && skippedBuild != appcastItem.versionString) else {
            handler(.dismiss)
            return
        }
        action = handler
        version = appcastItem.displayVersionString
        build = appcastItem.versionString
        backgroundOffer = !updateState.userInitiated
        moreInformation = appcastItem.isInformationOnlyUpdate ? appcastItem.infoURL : nil
        if updateState.stage == .installing {
            state = .ready(version: version)
        } else {
            state = .available(version: version)
            if backgroundOffer, mode == .auto, moreInformation == nil { beginDownload(automatically: true) }
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let reasonValue = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
        let reason = reasonValue.flatMap { SPUNoUpdateFoundReason(rawValue: $0.int32Value) }
        switch reason {
        case .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64:
            fail(error.localizedDescription)
        default:
            state = .upToDate
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        fail(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelDownload = cancellation
        expectedLength = 0
        receivedLength = 0
        state = .downloading(progress: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += Double(length)
        if expectedLength > 0 {
            state = .downloading(progress: min(receivedLength / Double(expectedLength), 1))
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownload = nil
        state = .preparing(progress: nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        state = .preparing(progress: min(max(progress, 0), 1))
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if automaticDownload, mode != .auto {
            reply(.skip)
            return
        }
        action = reply
        state = .ready(version: version)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        state = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        state = .upToDate
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        action = nil
        cancelDownload = nil
        retryTermination = nil
        automaticDownload = false
        switch state {
        case .idle, .upToDate, .failed: break
        default: state = .idle
        }
    }
}
