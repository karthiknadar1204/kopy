import AppKit

@main
struct UpdaterProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let values = ProcessInfo.processInfo.environment
        Task { @MainActor in
            let updater = KopyUpdater(allowLocalFeed: true)
            if updater.currentVersion == "0.2.0" {
                let receipt = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "relaunched")
                try Data().write(to: receipt)
                app.terminate(nil)
                return
            }

            guard let group = values["KOPY_UPDATE_TEST"], updater.isConfigured else {
                fatalError("Missing update fixture configuration")
            }
            let mode = KopyUpdateMode(rawValue: group) ?? .off
            updater.setMode(mode)
            updater.start()
            if mode == .off {
                try await Task.sleep(for: .milliseconds(1500))
                precondition(updater.state == .idle, "Off started a background session")
                updater.checkForUpdates()
            }

            var last: KopyUpdateState?
            var skipped = false
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while ContinuousClock.now < deadline {
                let state = updater.state
                if state != last {
                    print(state)
                    fflush(nil)
                    last = state
                }
                switch state {
                case .available(version: "0.2.0"):
                    precondition(mode != .auto, "Auto waited for a click before downloading")
                    if mode == .notify && !skipped {
                        try await Task.sleep(for: .milliseconds(650))
                        precondition(updater.state == state, "Notify downloaded before a click")
                        updater.skip()
                        skipped = true
                        try await Task.sleep(for: .milliseconds(650))
                        precondition(updater.state == .idle, "Skip did not dismiss the offer")
                        updater.checkForUpdates()
                    } else {
                        updater.downloadOrInstall()
                    }
                case .ready(version: "0.2.0"):
                    if mode == .auto {
                        updater.downloadOrInstall()
                    } else {
                        updater.skip()
                        try await Task.sleep(for: .milliseconds(350))
                        precondition(updater.state == .idle, "Skip did not cancel installation")
                        app.terminate(nil)
                    }
                case .upToDate:
                    precondition(group == "up-to-date", "A newer fixture should be available")
                    app.terminate(nil)
                case .failed(let reason):
                    precondition(group.hasPrefix("reject-"), reason)
                    app.terminate(nil)
                default:
                    break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            fatalError("Updater did not finish")
        }
        app.run()
    }
}
