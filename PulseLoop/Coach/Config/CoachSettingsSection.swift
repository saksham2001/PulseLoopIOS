import SwiftUI
import SwiftData
import UserNotifications

/// "AI Coach" block for `SettingsView`: provider mode, model, OpenAI key
/// (stored in Keychain), action/measurement toggles, daily notifications, and
/// saved coach memory. Visuals reuse the existing design system.
struct CoachSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RingSyncCoordinator.self) private var coordinator
    @Query(sort: \CoachMemory.importance, order: .reverse) private var memories: [CoachMemory]
    @State private var store = CoachSettingsStore.shared

    @State private var notifPermissionDenied = false
    @State private var testStatus: String?

    @State private var muapiKeyDraft: String = ""
    @State private var muapiShowKey: Bool = false
    @State private var hasSavedMuapiKey: Bool = false
    @State private var muapiError: String?
    private let muapiStore = MuapiKeychainStore()

    private var flags: CoachFeatureFlags {
        CoachFeatureFlags(settings: store.settings, hasAPIKey: AIService.shared.hasAPIKey)
    }

    var body: some View {
        SectionHeader(title: "AI Assistant", action: nil)
        StatusCopy(title: "Status", body: flags.statusLine)
        toggleRow("Enable AI Assistant", isOn: masterEnabledBinding)

        if store.settings.coachMasterEnabled {
            labeledRow("Personality") {
                Picker("Personality", selection: personalityBinding) {
                    ForEach(CoachPersonality.allCases) { p in
                        Text("\(p.emoji) \(p.label)").tag(p)
                    }
                }
                .pickerStyle(.menu)
                .tint(PulseColors.accent)
            }

            toggleRow("Web search", isOn: webSearchBinding)
            toggleRow("AI actions (set goals, log, edit)", isOn: writeToolsBinding)
            toggleRow("Live ring measurements", isOn: liveMeasurementsBinding)
            toggleRow("Sub-App Builder (design sub-apps)", isOn: subAppBuilderBinding)
            toggleRow("Platform control (manage modules & features)", isOn: platformControlBinding)
            toggleRow("Media generation (images/video)", isOn: mediaGenerationBinding)

            if store.settings.enableMediaGeneration {
                muapiField
                toggleRow("Sandbox mode (free, example media)", isOn: muapiSandboxBinding)
            }

            notificationsSection

            if !memories.isEmpty {
                SectionHeader(title: "Assistant memory", action: nil)
                ForEach(memories) { memory in memoryRow(memory) }
            }
        }
    }

    private func memoryRow(_ memory: CoachMemory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(memory.key)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(memory.value)
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.textSecondary)
                Text(memory.memoryType.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 9, weight: .medium)).tracking(0.6)
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer(minLength: 8)
            Button {
                modelContext.delete(memory)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(PulseColors.danger)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PulseColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
    }

    // MARK: - Key field

    private var muapiField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    if muapiShowKey {
                        TextField("muapi x-api-key", text: $muapiKeyDraft)
                    } else {
                        SecureField("muapi x-api-key", text: $muapiKeyDraft)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14).monospaced())
                .foregroundStyle(PulseColors.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(PulseColors.cardSoft, in: Capsule())
                .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))

                Button { muapiShowKey.toggle() } label: {
                    Image(systemName: muapiShowKey ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(PulseColors.textMuted)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                QuickActionButton(label: hasSavedMuapiKey ? "Update key" : "Save key", accent: true) { saveMuapiKey() }
                    .disabled(muapiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasSavedMuapiKey {
                    QuickActionButton(label: "Remove") { removeMuapiKey() }
                }
            }

            if let muapiError {
                Text(muapiError).font(.caption).foregroundStyle(PulseColors.danger)
            } else {
                Text("Stored only in your device Keychain. Used to call muapi.ai for image/video generation. Get a key at muapi.ai.")
                    .font(.caption).foregroundStyle(PulseColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PulseColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
        .onAppear(perform: refreshMuapiState)
    }

    // MARK: - Small layout helpers

    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(PulseColors.textPrimary)
            Spacer()
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(PulseColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(PulseColors.textPrimary)
        }
        .tint(PulseColors.accent)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(PulseColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
    }

    // MARK: - Bindings

    private var masterEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.settings.coachMasterEnabled },
            set: { newValue in
                store.settings.coachMasterEnabled = newValue
                if !newValue {
                    // Tear down anything scheduled so a future re-enable starts clean.
                    CoachNotificationScheduler.shared.cancel()
                } else if store.settings.notificationsEnabled {
                    CoachNotificationScheduler.shared.scheduleNext()
                }
            }
        )
    }

    private var personalityBinding: Binding<CoachPersonality> {
        Binding(get: { store.settings.personality }, set: { store.settings.personality = $0 })
    }
    private var webSearchBinding: Binding<Bool> {
        Binding(get: { store.settings.enableWebSearch }, set: { store.settings.enableWebSearch = $0 })
    }
    private var writeToolsBinding: Binding<Bool> {
        Binding(get: { store.settings.enableWriteTools }, set: { store.settings.enableWriteTools = $0 })
    }
    private var liveMeasurementsBinding: Binding<Bool> {
        Binding(get: { store.settings.enableLiveMeasurements }, set: { store.settings.enableLiveMeasurements = $0 })
    }
    private var subAppBuilderBinding: Binding<Bool> {
        Binding(get: { store.settings.enableSubAppBuilder }, set: { store.settings.enableSubAppBuilder = $0 })
    }

    private var platformControlBinding: Binding<Bool> {
        Binding(get: { store.settings.enablePlatformControl }, set: { store.settings.enablePlatformControl = $0 })
    }

    private var mediaGenerationBinding: Binding<Bool> {
        Binding(get: { store.settings.enableMediaGeneration }, set: { store.settings.enableMediaGeneration = $0 })
    }

    private var muapiSandboxBinding: Binding<Bool> {
        Binding(get: { store.settings.muapiSandbox }, set: { store.settings.muapiSandbox = $0 })
    }

    private func refreshMuapiState() {
        hasSavedMuapiKey = muapiStore.hasKey
    }

    private func saveMuapiKey() {
        muapiError = nil
        do {
            try muapiStore.saveKey(muapiKeyDraft)
            muapiKeyDraft = ""
            hasSavedMuapiKey = true
        } catch {
            muapiError = error.localizedDescription
        }
    }

    private func removeMuapiKey() {
        muapiError = nil
        do {
            try muapiStore.deleteKey()
            hasSavedMuapiKey = false
        } catch {
            muapiError = error.localizedDescription
        }
    }

    // MARK: - Daily notifications

    @ViewBuilder private var notificationsSection: some View {
        toggleRow("Daily check-in notifications", isOn: Binding(
            get: { store.settings.notificationsEnabled },
            set: { setNotifications($0) }
        ))

        if store.settings.notificationsEnabled {
            labeledRow("Morning") { hourPicker(hourBinding(\.morningHour)) }
            labeledRow("Evening") { hourPicker(hourBinding(\.eveningHour)) }
            QuickActionButton(label: "Send a test check-in now") { sendTestCheckin() }
            if let testStatus {
                Text(testStatus).font(.caption).foregroundStyle(PulseColors.textMuted)
            }
        }
        if notifPermissionDenied {
            Text("Notifications are disabled for PulseLoop in iOS Settings.")
                .font(.caption).foregroundStyle(PulseColors.danger)
        }
    }

    private func hourPicker(_ binding: Binding<Int>) -> some View {
        Picker("Hour", selection: binding) {
            ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
        }
        .pickerStyle(.menu)
        .tint(PulseColors.accent)
    }

    private func hourBinding(_ keyPath: WritableKeyPath<CoachSettings, Int>) -> Binding<Int> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { store.settings[keyPath: keyPath] = $0; CoachNotificationScheduler.shared.scheduleNext() }
        )
    }

    private func setNotifications(_ on: Bool) {
        guard on else {
            store.settings.notificationsEnabled = false
            CoachNotificationScheduler.shared.cancel()
            return
        }
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            store.settings.notificationsEnabled = granted
            notifPermissionDenied = !granted
            if granted { CoachNotificationScheduler.shared.scheduleNext() }
        }
    }

    private func sendTestCheckin() {
        testStatus = "Sending…"
        let service = CoachNotificationService(modelContext: modelContext, coordinator: coordinator)
        Task {
            let outcome = await service.runDueSlot(force: true)
            switch outcome {
            case .sent(let slot): testStatus = "Sent a \(slot.label.lowercased()) check-in."
            default: testStatus = "Couldn't send (\(outcome))."
            }
        }
    }
}
