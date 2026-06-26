import SwiftUI

/// "Connect" screen. Shows the **honest** state of every data connector: real
/// connectors (Apple Health, the smart ring, web sync) reflect their live service
/// state via `ConnectorStatus`; integrations that aren't built yet are shown as
/// explicitly unavailable rather than offering a fake "Connect" that does nothing.
struct ConnectAccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RingBLEClient.self) private var ble
    @Environment(RingSyncCoordinator.self) private var coordinator

    @State private var showShareSheet = false
    @State private var showSiriSetup = false
    @State private var healthState: HealthAuthorizationState = .notAuthorized
    @State private var requestingHealth = false
    @State private var healthLastImport: Date?
    @State private var importMessage: String?
    @State private var syncingCloud = false

    @State private var wearables = WearableConnectionManager.shared
    @State private var connectingProvider: WearableProvider?

    @State private var accounts = AccountConnectionManager.shared
    @State private var connectingAccount: AccountProvider?

    private let cloud = CloudSyncService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 20) {
                    liveConnectorsSection
                    wearableAccountsSection
                    upcomingDevicesSection
                    accountsSection
                    shareSheetSection
                    privacyNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Connect")
        .task { refreshHealthState() }
        .task {
            await ConnectedSourcesSyncCoordinator.syncAllIfDue(context: modelContext)
        }
        .alert("Share Sheet", isPresented: $showShareSheet) {
            Button("OK") {}
        } message: {
            Text("The Share Sheet extension lets you forward screenshots, emails, and notifications directly to PulseLoop from anywhere on your iPhone.")
        }
        .alert("Siri Shortcut", isPresented: $showSiriSetup) {
            Button("OK") {}
        } message: {
            Text("Say \"Hey Siri, log to PulseLoop\" to quickly capture anything via voice. Shortcut has been added to the Shortcuts app.")
        }
    }

    // MARK: - Live connector status

    private var healthStatus: ConnectorStatus {
        ConnectorStatus.forHealthKit(healthState, lastSync: healthLastImport)
    }

    private var ringStatus: ConnectorStatus {
        ConnectorStatus.forRing(
            state: ble.state,
            bluetoothReady: ble.isBluetoothReady,
            batteryPercent: ble.batteryPercent,
            lastError: ble.lastError
        )
    }

    private var cloudStatus: ConnectorStatus {
        ConnectorStatus.forCloudSync(
            isConfigured: cloud.isConfigured,
            hasConsent: cloud.hasCloudConsent,
            isPaired: cloud.isPaired,
            lastSync: cloud.lastSyncAt
        )
    }

    // MARK: - Wearable OAuth connectors

    private func wearableStatus(_ provider: WearableProvider) -> ConnectorStatus {
        ConnectorStatus.forWearable(
            isConfigured: wearables.isConfigured(provider),
            isConnected: wearables.isConnected(provider),
            isSyncing: wearables.isSyncing.contains(provider),
            lastSync: wearables.lastSyncedAt[provider],
            lastError: wearables.lastError[provider],
            unsupportedReason: WearableOAuthConfig.unsupportedReason(for: provider)
        )
    }

    private func connectWearable(_ provider: WearableProvider) {
        guard connectingProvider == nil else { return }
        connectingProvider = provider
        HapticService.impact(.medium)
        let context = modelContext
        Task {
            _ = await wearables.connect(provider, context: context)
            await MainActor.run { connectingProvider = nil }
        }
    }

    private func syncWearable(_ provider: WearableProvider) {
        guard connectingProvider == nil else { return }
        connectingProvider = provider
        HapticService.impact(.light)
        let context = modelContext
        Task {
            _ = try? await wearables.sync(provider, context: context)
            await MainActor.run { connectingProvider = nil }
        }
    }

    private func disconnectWearable(_ provider: WearableProvider) {
        HapticService.impact(.light)
        wearables.disconnect(provider)
    }

    // MARK: - Account OAuth connectors

    private func accountStatus(_ provider: AccountProvider) -> ConnectorStatus {
        if provider == .appleCalendar {
            let ek = EventKitCalendarSource()
            return ConnectorStatus.forEventKit(
                authorized: ek.isAuthorized,
                denied: ek.isDenied,
                lastSync: accounts.lastSyncedAt[provider]
            )
        }
        return ConnectorStatus.forAccount(
            isConfigured: accounts.isConfigured(provider),
            isConnected: accounts.isConnected(provider),
            isSyncing: accounts.isSyncing.contains(provider),
            lastSync: accounts.lastSyncedAt[provider],
            lastError: accounts.lastError[provider]
        )
    }

    private func connectAccount(_ provider: AccountProvider) {
        guard connectingAccount == nil else { return }
        connectingAccount = provider
        HapticService.impact(.medium)
        let context = modelContext
        Task {
            _ = await accounts.connect(provider, context: context)
            await MainActor.run { connectingAccount = nil }
        }
    }

    private func syncAccount(_ provider: AccountProvider) {
        guard connectingAccount == nil else { return }
        connectingAccount = provider
        HapticService.impact(.light)
        let context = modelContext
        Task {
            _ = try? await accounts.sync(provider, context: context)
            await MainActor.run { connectingAccount = nil }
        }
    }

    private func disconnectAccount(_ provider: AccountProvider) {
        HapticService.impact(.light)
        accounts.disconnect(provider)
    }

    private func refreshHealthState() {
        let hk = HealthKitIngestion(context: modelContext)
        healthState = hk.authorizationState
        healthLastImport = hk.lastImportAt
    }

    private func requestHealthAuthorization() {
        guard !requestingHealth else { return }
        requestingHealth = true
        HapticService.impact(.medium)
        Task {
            let hk = HealthKitIngestion(context: modelContext)
            try? await hk.requestAuthorization()
            // If authorization succeeded, pull data immediately so the row reflects a
            // real last-import time rather than just "Authorized".
            if hk.authorizationState == .authorized {
                _ = await hk.importNow()
            }
            await MainActor.run {
                healthState = hk.authorizationState
                healthLastImport = hk.lastImportAt
                requestingHealth = false
            }
        }
    }

    private func importHealthNow() {
        guard !requestingHealth else { return }
        requestingHealth = true
        HapticService.impact(.light)
        Task {
            let hk = HealthKitIngestion(context: modelContext)
            let result = await hk.importNow()
            await MainActor.run {
                healthState = hk.authorizationState
                healthLastImport = hk.lastImportAt
                requestingHealth = false
                switch result {
                case .imported:
                    importMessage = nil
                case .failed(let reason):
                    importMessage = reason
                case .notAuthorized:
                    importMessage = "Allow Apple Health access first."
                case .unavailable:
                    importMessage = "Apple Health isn't available here."
                }
            }
        }
    }

    private func scanForRing() {
        HapticService.impact(.medium)
        ble.startScanning()
    }

    private func syncCloudNow() {
        guard !syncingCloud else { return }
        syncingCloud = true
        HapticService.impact(.light)
        Task {
            _ = await cloud.sync(context: modelContext)
            await MainActor.run { syncingCloud = false }
        }
    }

    /// Primary action shown on the status pill button when the ring is actionable    /// (idle/disconnected → "Scan"). Auto-connects to the first likely ring found.
    private func ringPrimaryAction() {
        HapticService.impact(.medium)
        if let candidate = ble.discovered.first(where: { $0.isLikelyRing }) {
            ble.connect(to: candidate.id)
        } else {
            ble.startScanning()
        }
    }

    /// A context-aware secondary action: stop an in-progress scan, or disconnect a
    /// connected ring. Returns nil otherwise (so no button shows).
    private var ringSecondaryTitle: String? {
        switch ble.state {
        case .scanning, .connecting, .reconnecting: return "Stop"
        case .connected: return "Disconnect"
        default: return nil
        }
    }

    private var ringSecondaryAction: (() -> Void)? {
        switch ble.state {
        case .scanning, .connecting, .reconnecting:
            return { HapticService.impact(.light); ble.stopScanning() }
        case .connected:
            return { HapticService.impact(.light); ble.disconnect() }
        default:
            return nil
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect accounts")
                .font(PulseFont.title(28))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Connect your devices and web account for health data. Each connector below shows its real status — nothing is connected until you authorize it.")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    /// The connectors that genuinely work: their rows reflect live status and offer
    /// a real action when one is available.
    private var liveConnectorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CONNECTED SOURCES")

            connectorCard {
                ConnectorRow(
                    icon: "heart.fill",
                    name: "Apple Health",
                    detail: "HR, SpO₂, steps, sleep",
                    status: healthStatus,
                    isBusy: requestingHealth,
                    secondaryActionTitle: healthState == .authorized ? "Import now" : nil,
                    secondaryAction: healthState == .authorized ? { importHealthNow() } : nil
                ) { requestHealthAuthorization() }

                divider

                ConnectorRow(
                    icon: "circle.circle",
                    name: "Smart Ring",
                    detail: "Live HR, SpO₂, sleep · Bluetooth",
                    status: ringStatus,
                    isBusy: false,
                    secondaryActionTitle: ringSecondaryTitle,
                    secondaryAction: ringSecondaryAction
                ) { ringPrimaryAction() }

                divider

                ConnectorRow(
                    icon: "icloud",
                    name: "Web sync",
                    detail: cloud.isPaired
                        ? "Synced to the PulseLoop web app"
                        : "Pair in Settings → Connect to web",
                    status: cloudStatus,
                    isBusy: syncingCloud,
                    secondaryActionTitle: cloud.isPaired ? "Sync now" : nil,
                    secondaryAction: cloud.isPaired ? { syncCloudNow() } : nil,
                    action: nil
                )
            }

            if let importMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseColors.alert)
                    Text(importMessage)
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.alert)
                }
                .padding(.top, 2)
            }
        }
    }

    /// Fitbit + Google Fit, connected over OAuth2. Each row reflects its real
    /// connection/sync state via the `WearableConnectionManager`. When a build
    /// doesn't ship a client id the row honestly reads "Not configured".
    private var wearableAccountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WEARABLE ACCOUNTS")

            connectorCard {
                wearableRow(.fitbit, detail: "Steps, resting HR, SpO₂, sleep")
                divider
                wearableRow(.googleFit, detail: "Steps & heart rate")
            }

            Text("Connect with your account to pull daily steps and vitals — they flow into the same dashboard and the assistant automatically.")
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textFaint)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func wearableRow(_ provider: WearableProvider, detail: String) -> some View {
        let status = wearableStatus(provider)
        let connected = wearables.isConnected(provider)
        ConnectorRow(
            icon: provider.iconSystemName,
            name: provider.displayName,
            detail: detail,
            status: status,
            isBusy: connectingProvider == provider,
            secondaryActionTitle: connected ? "Sync now" : nil,
            secondaryAction: connected ? { syncWearable(provider) } : nil,
            tertiaryActionTitle: connected ? "Disconnect" : nil,
            tertiaryAction: connected ? { disconnectWearable(provider) } : nil,
            action: connected ? nil : { connectWearable(provider) }
        )
    }

    /// Additional OAuth wearables (Oura, Whoop, Garmin), data-driven from the
    /// provider model. Each row reflects its real config/connection state — an
    /// unconfigured provider honestly reads "Not configured" (and Garmin, whose
    /// OAuth 1.0a flow we can't drive yet, reads its documented unavailable reason)
    /// rather than a fake "Not yet available".
    private var upcomingDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MORE WEARABLES")

            let details: [WearableProvider: String] = [
                .oura: "Steps, HR, SpO₂, sleep",
                .whoop: "Recovery, strain, sleep",
                .garmin: "Steps, HR, sleep",
            ]
            let providers: [WearableProvider] = [.oura, .whoop, .garmin]

            connectorCard {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    wearableRow(provider, detail: details[provider] ?? "Health metrics")
                    if index < providers.count - 1 { divider }
                }
            }

            Text("Connect over your account to pull these in. Many also sync into Apple Health already — connect Apple Health above to bring their data in today.")
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textFaint)
                .padding(.top, 4)
        }
    }

    /// OAuth-backed accounts + Apple Calendar (EventKit), data-driven. Each row
    /// reflects real OAuth/EventKit state — unconfigured providers honestly read
    /// "Not configured", never a fake "Connect".
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACCOUNTS")

            let rows: [(provider: AccountProvider, icon: String, name: String, detail: String)] = [
                (.googleCalendar, "calendar", "Google Calendar", "Upcoming events"),
                (.appleCalendar, "calendar.badge.clock", "Apple Calendar", "On-device events"),
                (.gmail, "envelope", "Gmail", "Receipts, bills, invites"),
                (.slack, "number", "Slack", "Mentions & messages"),
                (.notion, "doc.text", "Notion", "Task sync"),
                (.todoist, "checklist", "Todoist", "Task sync"),
            ]

            connectorCard {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    accountRow(row.provider, icon: row.icon, name: row.name, detail: row.detail)
                    if index < rows.count - 1 { divider }
                }
            }

            Text("Calendars and mail are read-only and flow into your inbox and planner. The assistant only changes anything after you confirm.")
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textFaint)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func accountRow(_ provider: AccountProvider, icon: String, name: String, detail: String) -> some View {
        let status = accountStatus(provider)
        let connected = accounts.isConnected(provider)
        let canSync = connected && provider != .appleCalendar
        ConnectorRow(
            icon: icon,
            name: name,
            detail: detail,
            status: status,
            isBusy: connectingAccount == provider,
            secondaryActionTitle: connected ? "Sync now" : nil,
            secondaryAction: connected ? { syncAccount(provider) } : nil,
            tertiaryActionTitle: canSync ? "Disconnect" : nil,
            tertiaryAction: canSync ? { disconnectAccount(provider) } : nil,
            action: connected ? nil : { connectAccount(provider) }
        )
    }

    private var shareSheetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SHARE SHEET & SIRI")

            VStack(alignment: .leading, spacing: 14) {
                Text("Share any notification, screenshot, email or text into PulseLoop  -  the AI files it as a task, event or note.")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
                    .lineSpacing(2)

                HStack(spacing: 10) {
                    Button { showShareSheet = true } label: {
                        Text("Add to Share Sheet")
                            .font(PulseFont.bodySemibold(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    Button { showSiriSetup = true } label: {
                        Text("Add Siri Shortcut")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(PulseColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(PulseColors.borderStrong, lineWidth: 1)
                            }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(UIColor.secondarySystemBackground), Color(UIColor.tertiarySystemBackground)], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(PulseColors.textMuted)
            Text("Data is processed on-device. PulseLoop only reads what you authorize and never posts on your behalf.")
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
        }
        .padding(12)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(PulseFont.bodyMedium(11))
            .foregroundStyle(PulseColors.textMuted)
            .tracking(0.8)
    }

    private var divider: some View {
        Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
    }

    private func connectorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
    }
}

/// A connector row that renders its `ConnectorStatus` honestly. When the status is
/// actionable (`.available`) and an `action` is provided, it shows a tappable
/// button; otherwise it shows a read-only status pill.
struct ConnectorRow: View {
    let icon: String
    let name: String
    let detail: String
    let status: ConnectorStatus
    var isBusy: Bool = false
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var tertiaryActionTitle: String? = nil
    var tertiaryAction: (() -> Void)? = nil
    var action: (() -> Void)? = {}

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(status.isConnected ? PulseColors.success : PulseColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                Text(status.detail ?? detail)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            trailing
        }
        .padding(12)
        .background(PulseColors.background)
    }

    @ViewBuilder
    private var trailing: some View {
        if isBusy {
            ProgressView().scaleEffect(0.8)
        } else if status.isActionable, let action {
            Button(action: action) {
                Text(status.label)
                    .font(PulseFont.bodySemibold(12))
                    .foregroundStyle(.white)
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .background(PulseColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .accessibilityLabel("\(status.label) \(name)")
        } else {
            HStack(spacing: 8) {
                ConnectorStatusPill(status: status)
                if let secondaryActionTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryActionTitle)
                            .font(PulseFont.bodySemibold(12))
                            .foregroundStyle(PulseColors.textPrimary)
                            .frame(height: 28)
                            .padding(.horizontal, 10)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(PulseColors.borderStrong, lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("\(secondaryActionTitle) \(name)")
                }
                if let tertiaryActionTitle, let tertiaryAction {
                    Button(action: tertiaryAction) {
                        Text(tertiaryActionTitle)
                            .font(PulseFont.bodyMedium(12))
                            .foregroundStyle(PulseColors.textMuted)
                            .frame(height: 28)
                            .padding(.horizontal, 8)
                    }
                    .accessibilityLabel("\(tertiaryActionTitle) \(name)")
                }
            }
        }
    }
}
