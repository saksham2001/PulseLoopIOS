import SwiftUI
import SwiftData
import UIKit

/// "Privacy & data" controls (roadmap E2): export the user's data — both the
/// on-device copy and, when connected, the server-held copy — and delete data.
///
/// - Local export always works (reads SwiftData) and presents a share sheet.
/// - Server export / delete only appear when the device is paired to the web app.
/// - Account deletion is destructive and confirmation-gated.
struct PrivacyDataSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sync = CloudSyncService.shared

    @State private var working = false
    @State private var message: String?
    @State private var errorMessage: String?

    @State private var diagnosticsEnabled = DiagnosticsConsent.isEnabled

    @State private var exportFileURL: URL?
    @State private var showShareSheet = false
    @State private var pendingDelete: CloudSyncService.DeleteScope?

    var body: some View {
        SectionHeader(title: "Privacy & data", action: nil)

        VStack(alignment: .leading, spacing: 10) {
            Text("Export a copy of your data or remove it. Your on-device data can always be exported; cloud options appear when you're connected to the web app.")
                .font(.caption)
                .foregroundStyle(PulseColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            SecondaryButton(title: "Export my data (this device)", systemImage: "square.and.arrow.up") {
                exportLocal()
            }

            if sync.isPaired {
                SecondaryButton(title: working ? "Preparing…" : "Download my web data", systemImage: "icloud.and.arrow.down") {
                    Task { await exportServer() }
                }
                .disabled(working)

                SecondaryButton(title: "Disconnect this device from web", systemImage: "xmark.icloud") {
                    pendingDelete = .device
                }
                Button {
                    pendingDelete = .account
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("Delete all my web data")
                    }
                    .font(PulseFont.bodySemibold(15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(PulseColors.danger)
                    .background(PulseColors.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PulseColors.danger.opacity(0.4), lineWidth: 1)
                    }
                }
            }

            Link(destination: CloudSyncService.privacyPolicyURL) {
                Text("Privacy policy")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PulseColors.accent)
            }

            diagnosticsRow

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(PulseColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showShareSheet) {
            if let exportFileURL {
                ShareSheet(items: [exportFileURL])
            }
        }
        .alert(item: $pendingDelete) { scope in
            switch scope {
            case .device:
                return Alert(
                    title: Text("Disconnect from web?"),
                    message: Text("This device will stop uploading and lose its connection. Your data already in the cloud and other devices are kept."),
                    primaryButton: .destructive(Text("Disconnect")) {
                        Task { await delete(scope: .device) }
                    },
                    secondaryButton: .cancel()
                )
            case .account:
                return Alert(
                    title: Text("Delete all web data?"),
                    message: Text("This permanently erases everything PulseLoop stores for you in the cloud — health samples, AI credits, and paired devices. This can't be undone. Your data on this iPhone is not affected."),
                    primaryButton: .destructive(Text("Delete everything")) {
                        Task { await delete(scope: .account) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    /// Opt-in, content-free crash diagnostics + anonymous usage telemetry (F1).
    /// Off by default; flipping it on starts the MetricKit subscriber immediately.
    private var diagnosticsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: diagnosticsBinding) {
                Text("Share crash diagnostics & anonymous usage to help improve PulseLoop.")
                    .font(.system(size: 13))
                    .foregroundStyle(PulseColors.textPrimary)
            }
            .tint(PulseColors.accent)
            Text("No health data or personal content is ever included.")
                .font(.caption)
                .foregroundStyle(PulseColors.textMuted)
        }
        .padding(12)
        .background(PulseColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
    }

    private var diagnosticsBinding: Binding<Bool> {
        Binding(
            get: { diagnosticsEnabled },
            set: { newValue in
                diagnosticsEnabled = newValue
                DiagnosticsConsent.isEnabled = newValue
                if newValue {
                    DiagnosticsService.shared.startIfEnabled()
                } else {
                    DiagnosticsService.shared.stop()
                }
            }
        )
    }

    private func exportLocal() {
        message = nil
        errorMessage = nil
        do {
            let url = try LocalDataExport.makeExportFile(context: modelContext)
            exportFileURL = url
            showShareSheet = true
            Analytics.track("export_local")
        } catch {
            errorMessage = "Couldn't build export: \(error.localizedDescription)"
        }
    }

    private func exportServer() async {
        working = true
        message = nil
        errorMessage = nil
        defer { working = false }
        do {
            let data = try await sync.exportServerData()
            let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PulseLoop-Web-Export-\(stamp).json")
            try data.write(to: url, options: .atomic)
            exportFileURL = url
            showShareSheet = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(scope: CloudSyncService.DeleteScope) async {
        working = true
        message = nil
        errorMessage = nil
        defer { working = false }
        do {
            try await sync.deleteServerData(scope: scope)
            message = scope == .account ? "All web data deleted." : "Disconnected from web."
            Analytics.track("account_delete", ["scope": scope.rawValue])
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

extension CloudSyncService.DeleteScope: Identifiable {
    public var id: String { rawValue }
}
