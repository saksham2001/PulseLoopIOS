import SwiftUI

// MARK: - Module Detail View (Experience loop Track P / P1)
//
// A rich, design-system-correct detail screen for a single module / sub-app,
// reachable from the catalog (`ModulePickerView`) and the Coach's navigate flow.
// Shows what the module is, who made it, where it came from, what it can touch
// (permissions), how many AI tools it adds, and its version — with honest
// install / uninstall / update actions. Versions + changelog get richer in P2/P4;
// this view already surfaces installed vs. available version and an update badge.
//
// Honest UX: the action button reflects the real installed state from
// `SubAppRegistry`, and "Update available" only shows when one genuinely exists.

struct ModuleDetailView: View {
    let app: any SubApp

    @Environment(\.modelContext) private var modelContext
    @State private var registryTick = 0          // forces recompute after install changes
    @State private var showUpdateConfirm = false

    private var registry: SubAppRegistry { SubAppRegistry.shared }
    private var isInstalled: Bool { _ = registryTick; return registry.isInstalled(app.id) }

    private var accent: Color {
        AppModule(rawValue: app.id.rawValue)?.color ?? PulseColors.accent
    }

    private var installedVersion: SemanticVersion? {
        _ = registryTick
        return registry.installedVersion(of: app.id)
    }

    private var availableUpdate: SemanticVersion? {
        _ = registryTick
        return registry.availableUpdate(for: app.id)
    }

    /// AI tools this module contributes under the user's current coach settings.
    private var aiToolLabels: [String] {
        let settings = CoachSettingsStore.shared.settings
        let flags = CoachFeatureFlags(settings: settings, hasAPIKey: true)
        return app.aiTools(flags: flags).map(\.publicLabel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                actionButton
                if availableUpdate != nil { updateBanner }
                aboutSection
                metaSection
                if !app.permissions.isEmpty { permissionsSection }
                if !aiToolLabels.isEmpty { aiToolsSection }
                versionHistorySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(PulseColors.background)
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .installedModulesChanged)) { _ in
            registryTick += 1
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: app.iconSystemName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(PulseFont.title(22))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(app.summary)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Primary action

    private var actionButton: some View {
        Button {
            if isInstalled {
                registry.uninstall(app.id)
            } else {
                registry.install(app.id)
            }
            registry.registerAllRoutes()
            NotificationCenter.default.post(name: .installedModulesChanged, object: nil)
            HapticService.impact(.medium)
            registryTick += 1
        } label: {
            Text(isInstalled ? "Uninstall" : "Install")
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(isInstalled ? PulseColors.textPrimary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isInstalled ? PulseColors.fillSubtle : PulseColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if isInstalled {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PulseColors.borderSubtle, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Update banner

    private var updateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(PulseColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                if let installed = installedVersion, let available = availableUpdate {
                    Text("v\(installed) → v\(available)")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
            Spacer()
            Button {
                performUpdate()
            } label: {
                Text("Update")
                    .font(PulseFont.bodySemibold(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(PulseColors.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(PulseColors.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .confirmationDialog(
            "Update \(app.displayName)?",
            isPresented: $showUpdateConfirm,
            titleVisibility: .visible
        ) {
            Button("Update", role: .destructive) { applyUpdateNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This update changes how \(app.displayName) stores your data. Your existing records are preserved, but the change can't be undone.")
        }
    }

    /// Routes the update through a confirmation prompt when the migration is risky
    /// (data-rewriting), and applies it silently otherwise. Mirrors the policy the
    /// assistant's `update_module` tool uses, so both surfaces behave identically.
    private func performUpdate() {
        if registry.updateNeedsConfirmation(app.id) {
            showUpdateConfirm = true
        } else {
            applyUpdateNow()
        }
    }

    private func applyUpdateNow() {
        registry.applyUpdate(app.id, context: modelContext)
        HapticService.success()
        registryTick += 1
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("About")
            Text(longDescription)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Built-ins carry a longer marketing description on `AppModule`; spec/installed
    /// sub-apps fall back to their one-line summary.
    private var longDescription: String {
        AppModule(rawValue: app.id.rawValue)?.description ?? app.summary
    }

    // MARK: Meta (version / author / origin)

    private var metaSection: some View {
        VStack(spacing: 0) {
            metaRow(label: "Version", value: versionDisplay)
            divider
            metaRow(label: "Author", value: app.author)
            divider
            metaRow(label: "Source", value: originLabel)
        }
        .padding(.vertical, 4)
        .background(PulseColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var versionDisplay: String {
        if let installed = installedVersion {
            if let available = availableUpdate { return "v\(installed) (v\(available) available)" }
            return "v\(installed)"
        }
        return "v\(app.semanticVersion)"
    }

    private var originLabel: String {
        switch app.origin {
        case .builtIn: return "Built-in"
        case .userCreated: return "Created by you"
        case .installed: return "Installed"
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)
            Spacer()
            Text(value)
                .font(PulseFont.bodyMedium(14))
                .foregroundStyle(PulseColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle().fill(PulseColors.borderHairline).frame(height: 1).padding(.leading, 14)
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Permissions")
            ForEach(Array(app.permissions).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { perm in
                HStack(spacing: 10) {
                    Image(systemName: permissionIcon(perm))
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 22)
                    Text(permissionLabel(perm))
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                }
            }
        }
    }

    private func permissionLabel(_ p: SubAppPermission) -> String {
        switch p {
        case .healthRead: return "Read your health data"
        case .healthWrite: return "Write health data"
        case .notifications: return "Send notifications"
        case .network: return "Access the network"
        case .camera: return "Use the camera"
        case .microphone: return "Use the microphone"
        case .location: return "Use your location"
        }
    }

    private func permissionIcon(_ p: SubAppPermission) -> String {
        switch p {
        case .healthRead, .healthWrite: return "heart.text.square"
        case .notifications: return "bell"
        case .network: return "network"
        case .camera: return "camera"
        case .microphone: return "mic"
        case .location: return "location"
        }
    }

    // MARK: AI tools

    private var aiToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("AI tools added")
            Text("This module gives the assistant \(aiToolLabels.count) new \(aiToolLabels.count == 1 ? "ability" : "abilities").")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textMuted)
            ForEach(aiToolLabels, id: \.self) { label in
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.accent)
                        .frame(width: 22)
                    Text(label)
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                }
            }
        }
    }

    // MARK: Version history (P2)

    /// Released versions newest-first. The module's installed version is badged so
    /// the user can see exactly where they sit relative to the history.
    private var changelogEntries: [SubAppChangelogEntry] {
        app.changelog.sorted { $0.version > $1.version }
    }

    private var versionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Version history")
            ForEach(changelogEntries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("v\(entry.version)")
                            .font(PulseFont.bodySemibold(14))
                            .foregroundStyle(PulseColors.textPrimary)
                        if installedVersion == entry.version {
                            Text("Installed")
                                .font(PulseFont.bodySemibold(10))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if let date = entry.date {
                            Text(date)
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }
                    ForEach(entry.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(PulseFont.body(13))
                                .foregroundStyle(PulseColors.textMuted)
                            Text(note)
                                .font(PulseFont.body(13))
                                .foregroundStyle(PulseColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(PulseColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            }
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(PulseFont.bodySemibold(13))
            .foregroundStyle(PulseColors.textMuted)
            .textCase(.uppercase)
    }
}
