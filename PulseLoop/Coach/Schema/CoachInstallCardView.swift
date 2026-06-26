import SwiftUI

/// Install-confirmation card for an AI-designed sub-app (the "describe it and it
/// exists" flow). Unlike the plain `CoachActionCardView`, this shows a real
/// preview of the staged module, a live interactive preview sheet, and an
/// explicit Install action, so the user always reviews before anything is
/// created. Reads the draft from `SubAppBuilderDraftStore` (still staged until
/// the user confirms); falls back to a slim text card if the draft is gone.
struct CoachInstallCardView: View {
    let action: PendingAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var draftStore = SubAppBuilderDraftStore.shared
    @State private var previewStore = InMemorySubAppRecordStore()
    @State private var showingPreview = false

    /// The staged spec this card is about, matched by id so a stale card (after a
    /// refine produced a new draft) doesn't preview the wrong module.
    private var spec: SubAppSpec? {
        guard let draft = draftStore.draft, draft.id == action.platform?.targetId else { return nil }
        return draft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let spec {
                summaryBlock(spec)
                entityChips(spec)
                if !spec.permissions.isEmpty { permissionsRow(spec) }
                previewButton(spec)
            } else {
                Text(action.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(PulseColors.textPrimary)
            }
            buttons(enabled: spec != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PulseColors.accent.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(PulseColors.accent.opacity(0.25), lineWidth: 1))
        .sheet(isPresented: $showingPreview) {
            if let spec {
                NavigationStack {
                    SubAppRuntimeView(spec: spec, store: previewStore)
                        .navigationTitle("Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showingPreview = false }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: spec?.icon ?? "wand.and.stars")
                .font(.system(size: 12))
                .foregroundStyle(PulseColors.accent)
            Text("NEW MODULE")
                .font(.system(size: 10, weight: .semibold)).tracking(1.0)
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    private func summaryBlock(_ spec: SubAppSpec) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(spec.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseColors.textPrimary)
            if !spec.summary.isEmpty {
                Text(spec.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
        }
    }

    private func entityChips(_ spec: SubAppSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(spec.entities, id: \.name) { entity in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entity.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(entity.fields.map { "\($0.label) (\($0.type.rawValue))" }.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
            Text("\(spec.entities.count) data type\(spec.entities.count == 1 ? "" : "s") · \(spec.screens.count) screen\(spec.screens.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textFaint)
        }
    }

    private func permissionsRow(_ spec: SubAppSpec) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.warning)
            Text("Requests: " + spec.permissions.map { $0.rawValue }.joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    private func previewButton(_ spec: SubAppSpec) -> some View {
        Button { showingPreview = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                Text("Live preview")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PulseColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(PulseColors.cardSoft, in: Capsule())
            .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func buttons(enabled: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .foregroundStyle(PulseColors.textPrimary)
                    .background(PulseColors.cardSoft, in: Capsule())
                    .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: onConfirm) {
                Text(action.confirmLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(enabled ? PulseColors.accent : PulseColors.textFaint, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
    }
}
