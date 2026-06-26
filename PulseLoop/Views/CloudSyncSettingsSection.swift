import SwiftUI
import SwiftData

/// Settings UI to connect this iPhone to the PulseLoop web app so health data
/// is viewable on any device. Mirrors the "Connect to web" pairing flow:
/// user generates a code on the web dashboard, enters it here, then the device
/// uploads its measurements.
struct CloudSyncSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sync = CloudSyncService.shared
    @State private var code = ""
    @State private var working = false
    @State private var message: String?

    var body: some View {
        SectionHeader(title: "Connect to web", action: nil)

        HStack {
            ConnectorStatusPill(status: connectorStatus)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)

        if sync.isPaired {
            pairedState
        } else {
            unpairedState
        }

        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(PulseColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error = sync.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(PulseColors.heartRate)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Unified connector status, shared with `ConnectAccountsView` so the web-sync
    /// state reads identically everywhere.
    private var connectorStatus: ConnectorStatus {
        ConnectorStatus.forCloudSync(
            isConfigured: sync.isConfigured,
            hasConsent: sync.hasCloudConsent,
            isPaired: sync.isPaired,
            lastSync: sync.lastSyncAt
        )
    }

    private func refreshAccountIfPaired() async {
        if sync.isPaired { await sync.refreshLinkedAccount() }
    }

    private var unpairedState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in at the PulseLoop web dashboard, tap \u{201C}Generate pairing code\u{201D}, then enter it below.")
                .font(.caption)
                .foregroundStyle(PulseColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            consentRow

            TextField("Pairing code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .padding(12)
                .background(PulseColors.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            PrimaryButton(title: working ? "Connecting…" : "Connect", systemImage: "link") {
                Task { await connect() }
            }
            .disabled(working || !sync.hasCloudConsent || code.trimmingCharacters(in: .whitespaces).count < 4)
        }
        .padding(.horizontal, 4)
    }

    /// Explicit, revocable consent gate. No health data is uploaded until this is on
    /// (the service also enforces it, so the toggle can't be bypassed).
    private var consentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: consentBinding) {
                Text("Upload my health data to PulseLoop's cloud so I can view it on the web.")
                    .font(.system(size: 13))
                    .foregroundStyle(PulseColors.textPrimary)
            }
            .tint(PulseColors.accent)

            Link(destination: CloudSyncService.privacyPolicyURL) {
                Text("Read the privacy policy")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PulseColors.accent)
            }
        }
        .padding(12)
        .background(PulseColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
    }

    private var consentBinding: Binding<Bool> {
        Binding(get: { sync.hasCloudConsent }, set: { sync.hasCloudConsent = $0 })
    }

    private var pairedState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let account = sync.linkedAccount {
                StatusCopy(
                    title: "Signed in as",
                    body: account.email ?? "Connected account"
                )
            }
            StatusCopy(
                title: "Status",
                body: sync.lastSyncAt.map { "Last synced \(relative($0))" } ?? "Connected"
            )
            SecondaryButton(title: sync.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.clockwise") {
                Task {
                    let ok = await sync.sync(context: modelContext)
                    await DataSyncService.shared.sync(context: modelContext)
                    message = ok ? "Synced to web." : nil
                }
            }
            .disabled(sync.isSyncing)
            SecondaryButton(title: "Disconnect", systemImage: "xmark.circle") {
                sync.unpair()
                message = "Disconnected from web."
            }
            Link(destination: CloudSyncService.privacyPolicyURL) {
                Text("Privacy policy")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PulseColors.accent)
            }
        }
        .padding(.horizontal, 4)
        .task { await refreshAccountIfPaired() }
    }

    private func connect() async {
        working = true
        message = nil
        defer { working = false }
        do {
            try await sync.pair(code: code)
            code = ""
            message = "Connected. Syncing your data…"
            await sync.refreshLinkedAccount()
            let ok = await sync.sync(context: modelContext)
            await DataSyncService.shared.sync(context: modelContext)
            if ok { message = "Connected and synced to web." }
        } catch {
            sync.lastError = error.localizedDescription
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
