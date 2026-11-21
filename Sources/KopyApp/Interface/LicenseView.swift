#if !KOPY_APP_STORE
import AppKit
import SwiftUI

struct LicenseView: View {
    let license: LicenseController
    @State private var key = ""
    @State private var confirmDeactivation = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(license.status.permitsUse ? "Kopy is activated" : "Activate Kopy")
                    .font(.system(size: 27, weight: .semibold))
                Text(license.status.permitsUse ? "Your licence is ready on this Mac." : "Paste the licence key from your purchase email.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if license.status.permitsUse {
                if case .offline(let until) = license.status {
                    Label("Offline access until \(until.formatted(date: .abbreviated, time: .omitted))", systemImage: "wifi.slash")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Deactivate this Mac") { confirmDeactivation = true }
                    .disabled(license.isBusy)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Licence key").font(.callout.weight(.medium))
                    HStack {
                        SecureField("Enter your licence key", text: $key)
                            .textFieldStyle(.plain)
                            .focused($keyFocused)
                            .privacySensitive()
                            .onSubmit(activate)
                            .accessibilityIdentifier("license-key")
                        Button("Paste") {
                            if let value = NSPasteboard.general.string(forType: .string) { key = value }
                            keyFocused = true
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary) }
                    .disabled(license.isBusy)
                    Button(action: activate) {
                        HStack(spacing: 8) {
                            if license.isBusy { ProgressView().controlSize(.small) }
                            Text(license.isBusy ? "Checking licence…" : "Activate Kopy")
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(license.isBusy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("activate-license")
                }
            }
            if let issue = license.issue {
                Text(issue.localizedDescription)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("license-message")
            }
            if !license.status.permitsUse, license.hasCredential {
                HStack {
                    Button("Retry verification") { Task { await license.refresh(force: true) } }
                    Button("Deactivate this Mac") { confirmDeactivation = true }
                }
                .disabled(license.isBusy)
            }
            HStack(spacing: 18) {
                Link("Buy Kopy ↗", destination: URL(string: "https://kopy-website.vercel.app/buy")!)
                Link("Get help ↗", destination: KopyLinks.support)
            }
            .font(.callout)
            Text("Test licensing · No real payments\nNo account required. Your clipboard history stays on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(ShelfTheme.accent)
        .confirmationDialog("Deactivate Kopy on this Mac?", isPresented: $confirmDeactivation, titleVisibility: .visible) {
            Button("Deactivate this Mac", role: .destructive) { Task { await license.deactivate() } }
        } message: {
            Text("This frees the activation for another Mac. Your saved history will remain on this Mac.")
        }
        .onChange(of: license.status) { if license.status.permitsUse { key = "" } }
    }

    private func activate() {
        let input = key
        Task { await license.activate(input) }
    }
}
#endif
