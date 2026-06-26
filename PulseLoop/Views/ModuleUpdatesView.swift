import SwiftUI
import SwiftData

// MARK: - Manage Modules + Updates (NOTES_LOOP roadmap B1–B3)
//
// One place to see every installed module, its current version, and any available
// update. Updates run `SubAppRegistry.applyUpdate(_:context:)`, which executes the
// module's data-preserving `migrate(from:to:context:)` hook and records the new
// installed version. Risky migrations (those that return `false`) are confirmed
// before they run. Mirrors the update affordance in `SubAppRegistryView`.

struct ModuleUpdatesView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var installed: [ModuleRow] = []
    @State private var banner: String?
    @State private var pendingConfirm: ModuleRow?
    @State private var improvements: [ModuleImprovementProposal] = []
    @State private var autoApply = ModuleImprovementStore.shared.autoApplyNonBreaking

    /// A snapshot row so the view doesn't hold `any SubApp` existentials in state.
    struct ModuleRow: Identifiable, Equatable {
        let id: SubAppID
        let displayName: String
        let iconSystemName: String
        let currentVersion: SemanticVersion
        let availableUpdate: SemanticVersion?

        static func == (lhs: ModuleRow, rhs: ModuleRow) -> Bool {
            lhs.id == rhs.id && lhs.currentVersion == rhs.currentVersion && lhs.availableUpdate == rhs.availableUpdate
        }
    }

    private var updatesAvailable: [ModuleRow] { installed.filter { $0.availableUpdate != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let banner {
                    Label(banner, systemImage: "checkmark.circle.fill")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.success)
                }

                if !updatesAvailable.isEmpty {
                    updatesBanner
                }

                improvementsSection

                if installed.isEmpty {
                    PulseCard {
                        InlineEmptyState(title: "No modules installed", message: "Install modules from the catalog to manage them here.")
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(installed) { row in
                            moduleRow(row)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle("Modules")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload(); runImprovements() }
        .onReceive(NotificationCenter.default.publisher(for: .installedModulesChanged)) { _ in
            reload()
        }
        .alert(item: $pendingConfirm) { row in
            Alert(
                title: Text("Update \(row.displayName)?"),
                message: Text("This update may change stored data and can't be undone. Continue?"),
                primaryButton: .default(Text("Update")) { apply(row, confirmed: true) },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Installed modules")
                .font(PulseFont.title(22)).foregroundStyle(PulseColors.textPrimary)
            Text("See each module's version and update it when a new version is available.")
                .font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
        }
    }

    private var updatesBanner: some View {
        Button { updateAll() } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(updatesAvailable.count) update\(updatesAvailable.count == 1 ? "" : "s") available")
                        .font(PulseFont.bodySemibold(15))
                    Text("Tap to update all")
                        .font(PulseFont.body(12)).opacity(0.7)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(updatesAvailable.count) updates available. Update all modules.")
    }

    // MARK: Suggested improvements (T5 self-improvement)

    @ViewBuilder
    private var improvementsSection: some View {
        if !improvements.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Suggested improvements", systemImage: "wand.and.stars")
                        .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                }
                Toggle(isOn: $autoApply) {
                    Text("Auto-apply safe improvements")
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
                }
                .tint(.black)
                .onChange(of: autoApply) { _, newValue in
                    ModuleImprovementStore.shared.autoApplyNonBreaking = newValue
                }

                ForEach(improvements) { proposal in
                    improvementRow(proposal)
                }
            }
        }
    }

    private func improvementRow(_ proposal: ModuleImprovementProposal) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(proposal.proposedSpec.displayName)
                        .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                    if proposal.isBreaking {
                        Text("May change data")
                            .font(PulseFont.bodyMedium(11)).foregroundStyle(PulseColors.warning)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(PulseColors.warning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                Text(proposal.rationale)
                    .font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button { dismissImprovement(proposal) } label: {
                        Text("Dismiss")
                            .font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textMuted)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button { applyImprovement(proposal) } label: {
                        Text("Apply")
                            .font(PulseFont.bodySemibold(14)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moduleRow(_ row: ModuleRow) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: row.iconSystemName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(PulseColors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName)
                            .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                        Text("Version \(row.currentVersion.description)")
                            .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                    }
                    Spacer()
                    if row.availableUpdate == nil {
                        Text("Up to date")
                            .font(PulseFont.bodyMedium(12)).foregroundStyle(PulseColors.textFaint)
                    }
                }

                if let update = row.availableUpdate {
                    Button { startUpdate(row) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Update to v\(update.description)")
                        }
                        .font(PulseFont.bodySemibold(14)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Update \(row.displayName) to version \(update.description)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private func reload() {
        installed = SubAppRegistry.shared.installedSubApps
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { app in
                ModuleRow(
                    id: app.id,
                    displayName: app.displayName,
                    iconSystemName: app.iconSystemName,
                    currentVersion: SubAppRegistry.shared.installedVersion(of: app.id) ?? app.semanticVersion,
                    availableUpdate: SubAppRegistry.shared.availableUpdate(for: app.id)
                )
            }
    }

    private func startUpdate(_ row: ModuleRow) {
        if SubAppRegistry.shared.updateNeedsConfirmation(row.id) {
            pendingConfirm = row
        } else {
            apply(row, confirmed: true)
        }
    }

    private func apply(_ row: ModuleRow, confirmed: Bool) {
        guard confirmed else { return }
        if let applied = SubAppRegistry.shared.applyUpdate(row.id, context: modelContext) {
            banner = "\(row.displayName) updated to v\(applied.description)."
            HapticService.success()
        }
        reload()
    }

    private func updateAll() {
        var count = 0
        for row in updatesAvailable {
            if SubAppRegistry.shared.applyUpdate(row.id, context: modelContext) != nil { count += 1 }
        }
        if count > 0 {
            banner = "Updated \(count) module\(count == 1 ? "" : "s")."
            HapticService.success()
        }
        reload()
    }

    // MARK: Improvement handlers

    private func runImprovements() {
        ModuleImprovementRunner.runIfDue(context: modelContext)
        improvements = ModuleImprovementStore.shared.pending
    }

    private func applyImprovement(_ proposal: ModuleImprovementProposal) {
        if let reason = ModuleImprovementApplier.validationFailure(proposal.proposedSpec) {
            banner = "Couldn't apply: \(reason)"
            return
        }
        let version = ModuleImprovementApplier.commit(proposal, context: modelContext)
        banner = "Improved \(proposal.proposedSpec.displayName) to v\(version.description)."
        HapticService.success()
        improvements = ModuleImprovementStore.shared.pending
        reload()
    }

    private func dismissImprovement(_ proposal: ModuleImprovementProposal) {
        ModuleImprovementStore.shared.clear(moduleId: proposal.moduleId)
        improvements = ModuleImprovementStore.shared.pending
        HapticService.selection()
    }
}

struct ModuleUpdatesRow: View {
    let action: () -> Void
    @State private var updateCount = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.badge.a.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(width: 24)
                Text("Modules")
                    .font(PulseFont.bodyMedium(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                if updateCount > 0 {
                    Text("\(updateCount)")
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PulseColors.accent)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PulseColors.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .pulseCardSurface()
        }
        .buttonStyle(.plain)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .installedModulesChanged)) { _ in refresh() }
        .accessibilityLabel(updateCount > 0 ? "Modules. \(updateCount) updates available." : "Modules")
    }

    private func refresh() {
        updateCount = SubAppRegistry.shared.modulesWithUpdates.count
    }
}

