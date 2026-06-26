import SwiftUI
import SwiftData

// MARK: - Sub-App Builder (roadmap D2)
//
// Describe → preview → refine → save. The user describes a tracker in natural
// language; the Coach calls `generate_subapp_spec` / `refine_subapp_spec` (D1),
// which stage a validated draft in `SubAppBuilderDraftStore`. This view previews
// the staged draft live via the spec runtime (in-memory store), lets the user
// refine with more prompts, and saves it as a persistent `.userCreated` SubApp.

struct SubAppBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var draftStore = SubAppBuilderDraftStore.shared

    @State private var prompt = ""
    @State private var coach = CoachViewModel()
    @State private var conversationId = UUID()
    @State private var lastError: String?
    @State private var savedConfirmation: String?
    @State private var previewStore = InMemorySubAppRecordStore()
    @State private var permissionReview: PermissionReviewState?

    private var settings: CoachSettings { CoachSettingsStore.shared.settings }
    private var builderAvailable: Bool {
        settings.coachMasterEnabled && settings.enableSubAppBuilder
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !builderAvailable {
                    unavailableNotice
                } else {
                    promptComposer
                    if let error = lastError {
                        Text(error)
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.heartRate)
                    }
                    if let draft = draftStore.draft {
                        draftPreview(draft)
                    } else if !coach.isSending {
                        emptyHint
                    }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle("Sub-App Builder")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $permissionReview) { review in
            PermissionReviewSheet(spec: review.spec, onApprove: {
                permissionReview = nil
                persistSave(review.spec)
            }, onCancel: {
                permissionReview = nil
            })
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Build a tracker with AI")
                .font(PulseFont.title(22))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Describe what you want to track. The assistant designs a sub-app you can preview, refine, and save.")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    private var unavailableNotice: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Enable the builder", systemImage: "wand.and.stars")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Turn on the AI Assistant and the Sub-App Builder in Settings to design sub-apps.")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                draftStore.draft == nil ? "e.g. Track my daily water intake in glasses" : "Refine: e.g. add a mood rating",
                text: $prompt,
                axis: .vertical
            )
            .font(PulseFont.body(15))
            .lineLimit(2...5)
            .padding(12)
            .pulseCardSurface()

            Button(action: submit) {
                HStack(spacing: 8) {
                    if coach.isSending {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(draftStore.draft == nil ? "Design it" : "Refine")
                }
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? Color.black : PulseColors.textFaint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(!canSubmit)
        }
    }

    private var emptyHint: some View {
        PulseCard {
            InlineEmptyState(
                title: "No draft yet",
                message: "Describe a tracker above and tap Design it."
            )
        }
    }

    private func draftPreview(_ draft: SubAppSpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: draft.icon).foregroundStyle(PulseColors.textPrimary)
                Text(draft.displayName).font(PulseFont.bodySemibold(16)).foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Text("\(draft.entities.count) entity · \(draft.screens.count) screens")
                    .font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
            }

            PulseCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(draft.summary).font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
                    ForEach(draft.entities, id: \.name) { entity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entity.label).font(PulseFont.bodySemibold(13)).foregroundStyle(PulseColors.textPrimary)
                            Text(entity.fields.map { "\($0.label) (\($0.type.rawValue))" }.joined(separator: ", "))
                                .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                        }
                    }
                    if !draft.permissions.isEmpty {
                        Text("Permissions: " + draft.permissions.map { $0.rawValue }.joined(separator: ", "))
                            .font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            NavigationLink {
                SubAppRuntimeView(spec: draft, store: previewStore)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                    Text("Live preview")
                }
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .pulseCardSurface(stroke: PulseColors.borderStrong)
            }

            Button(action: { save(draft) }) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Save sub-app")
                }
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let savedConfirmation {
                Text(savedConfirmation)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.success)
            }
        }
    }

    // MARK: Actions

    private var canSubmit: Bool {
        builderAvailable && !coach.isSending && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lastError = nil
        savedConfirmation = nil
        let instruction = draftStore.draft == nil
            ? "Create a sub-app: \(text). Use the generate_subapp_spec tool."
            : "Refine the current sub-app draft: \(text). Use the refine_subapp_spec tool with the full updated spec."
        prompt = ""
        Task {
            await coach.send(instruction, conversationId: conversationId, context: modelContext)
            if let banner = coach.errorBanner { lastError = banner }
        }
    }

    private func save(_ draft: SubAppSpec) {
        savedConfirmation = nil
        do {
            try SubAppSpecValidator.validate(draft)
        } catch {
            lastError = "Can't save: \(error.localizedDescription)"
            return
        }
        let report = SubAppGuardrails.review(draft)
        guard report.canSave else {
            lastError = "Can't save: " + report.blockers.map { $0.message }.joined(separator: "; ")
            return
        }
        lastError = nil
        // Permissions require explicit user approval before the sub-app is saved.
        if report.permissionsToReview.isEmpty {
            persistSave(draft)
        } else {
            permissionReview = PermissionReviewState(spec: draft)
        }
    }

    private func persistSave(_ draft: SubAppSpec) {
        UserSubAppStore.shared.save(draft)
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(draft.id))
        savedConfirmation = "Saved \"\(draft.displayName)\". Find it in your sub-apps."
        draftStore.clear()
    }
}

/// Identifiable wrapper so the permission-review sheet can bind to `$permissionReview`.
private struct PermissionReviewState: Identifiable {
    let spec: SubAppSpec
    var id: String { spec.id }
}

/// Explicit permission-review prompt shown before a sub-app that requests
/// capabilities is saved (D3 guardrail).
private struct PermissionReviewSheet: View {
    let spec: SubAppSpec
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review permissions")
                    .font(PulseFont.title(20)).foregroundStyle(PulseColors.textPrimary)
                Text("\"\(spec.displayName)\" is requesting access to:")
                    .font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
            }

            VStack(spacing: 10) {
                ForEach(spec.permissions.sorted { $0.rawValue < $1.rawValue }, id: \.self) { permission in
                    PulseCard {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(PulseColors.textPrimary)
                            Text(SubAppGuardrails.explain(permission))
                                .font(PulseFont.body(14)).foregroundStyle(PulseColors.textPrimary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Spacer()

            Button(action: onApprove) {
                Text("Approve & save")
                    .font(PulseFont.bodySemibold(15)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button(action: onCancel) {
                Text("Cancel")
                    .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .pulseCardSurface(stroke: PulseColors.borderStrong)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}
