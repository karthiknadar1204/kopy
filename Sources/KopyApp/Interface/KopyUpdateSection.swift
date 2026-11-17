import SwiftUI

struct KopyUpdateSection: View {
    let updater: KopyUpdater

    var body: some View {
        Section("Updates") {
            if !updater.currentVersion.isEmpty {
                LabeledContent("Version", value: updater.currentVersion)
            }
            if updater.isConfigured {
                Picker("Update mode", selection: Binding(get: { updater.mode }, set: { updater.setMode($0) })) {
                    Text("Automatic").tag(KopyUpdateMode.auto)
                    Text("Notify me").tag(KopyUpdateMode.notify)
                    Text("Off").tag(KopyUpdateMode.off)
                }
                updateStatus
            } else {
                Text("Updates are unavailable in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.state {
        case .idle:
            Button("Check for updates", action: updater.checkForUpdates)
        case .checking:
            ProgressView("Checking for updates…")
        case .upToDate:
            Label("Kopy is up to date", systemImage: "checkmark.circle")
            Button("Check again", action: updater.checkForUpdates)
        case .available(let version):
            Label("Version \(version) is available", systemImage: "arrow.down.circle")
            HStack {
                Button("Download & Update", action: updater.downloadOrInstall)
                Button("Skip", action: updater.skip)
            }
        case .downloading(let progress):
            if let progress {
                ProgressView("Downloading update…", value: progress)
            } else {
                ProgressView("Downloading update…")
            }
            Button("Cancel", action: updater.skip)
        case .preparing(let progress):
            if let progress {
                ProgressView("Preparing update…", value: progress)
            } else {
                ProgressView("Preparing update…")
            }
        case .ready(let version):
            Label("Version \(version) is ready to install", systemImage: "checkmark.circle")
            HStack {
                Button("Restart to update", action: updater.downloadOrInstall)
                Button("Skip", action: updater.skip)
            }
        case .installing:
            ProgressView("Installing update…")
        case .failed(let details):
            Label("Update check failed", systemImage: "exclamationmark.triangle")
            Text(details).font(.caption).foregroundStyle(.secondary)
            Button("Try again", action: updater.checkForUpdates)
        }
    }
}
