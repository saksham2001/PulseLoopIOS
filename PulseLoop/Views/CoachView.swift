import SwiftUI
import SwiftData
import UIKit
import Combine
import PhotosUI

private let onboardingGoals = [
    ("I want to build strength and improve my fitness", "fitness"),
    ("I want to sleep better and recover faster", "sleep"),
    ("I want to reduce stress and feel more balanced", "stress"),
    ("I want to lose weight and improve body composition", "weight"),
    ("I want to optimize my supplement protocol", "protocol"),
]

struct CoachView: View {
    /// When presented as a sheet (from the center AI button), this shows a close
    /// button in the header and dismisses on tap. Nil when used as a root/tab view.
    var onDismiss: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(RingSyncCoordinator.self) private var coordinator
    @Query(sort: \CoachMessage.createdAt) private var allMessages: [CoachMessage]
    @Query(sort: \CoachConversation.updatedAt, order: .reverse) private var conversations: [CoachConversation]
    @State private var draft = ""
    @State private var viewModel = CoachViewModel()
    @State private var activeConversationId: UUID?
    @State private var showHistory = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var nav = CoachNavigation.shared
    @State private var showPersonalityPicker = false
    @State private var showSettings = false
    @State private var showCreditsPaywall = false
    @State private var showVoiceMode = false
    @State private var voiceModeConversationId: UUID?
    @FocusState private var composerFocused: Bool
    @State private var settingsStore = CoachSettingsStore.shared
    @State private var voiceServices = VoiceServices()
    @State private var isDictating = false
    @State private var draftBeforeDictation = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachedImages: [Data] = []
    @State private var showCamera = false
    @State private var cameraImage: UIImage?

    /// Bottom inset for the composer: clears the overlaid nav bar (~60) when the
    /// keyboard is hidden, and sits just above the keyboard when shown. Computed
    /// manually because the tab layout pins the keyboard safe area (see RootViews).
    private var composerBottomInset: CGFloat {
        guard keyboardHeight > 0 else { return 60 }
        return max(8, keyboardHeight - bottomSafeInset + 8)
    }

    private var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
    }

    /// Messages for the currently selected conversation.
    private var messages: [CoachMessage] {
        guard let id = activeConversationId else { return allMessages }
        return allMessages.filter { $0.conversationId == id }
    }

    /// The most recent user message before the given assistant message — the prompt to
    /// re-run when the user picks a different model (Life OS T4 transparency).
    private func precedingUserText(for assistant: CoachMessage) -> String? {
        let convo = messages
        guard let idx = convo.firstIndex(where: { $0.id == assistant.id }) else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) where convo[i].role == "user" {
            let body = convo[i].body.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }
        return nil
    }

    /// The module cold-start chip row above the composer is only for a genuinely
    /// empty conversation. After an assistant reply, the structured `followUpChips`
    /// in the bubble cover follow-ups — showing both is redundant (AIN-5).
    private var showColdStart: Bool {
        !viewModel.isSending && messages.isEmpty
    }

    /// Animate the typewriter reveal only for the freshly-arrived latest assistant
    /// reply (created in the last few seconds), so reopening an old chat renders
    /// instantly instead of re-typing every bubble (AIN-1).
    private func shouldAnimateReveal(_ message: CoachMessage) -> Bool {
        guard message.role == "assistant", message.id == messages.last?.id else { return false }
        return Date().timeIntervalSince(message.createdAt) < 3
    }

    /// Cold-start suggestion chips derived from the user's installed modules (M2).
    private var moduleAwareChips: [String] {
        ModuleAwareChat.suggestionChips(installed: SubAppRegistry.shared.installedSubApps)
    }

    /// Personalized, module-aware greeting shown in the empty chat (M4). Reframes
    /// the surface from a narrow "coach" into the user's adaptive life-OS assistant.
    private var assistantGreeting: some View {
        VStack(spacing: 14) {
            CoachOrb(size: 56)
            Text(ModuleAwareChat.greeting(installed: SubAppRegistry.shared.installedSubApps))
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.bottom, 8)
    }

    var body: some View {
        if !settingsStore.settings.hasCompletedOnboarding {
            coachOnboarding
        } else {
            chatBody
        }
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if messages.isEmpty && !viewModel.isSending {
                            assistantGreeting
                        }
                        ForEach(messages) { message in
                            CoachBubble(
                                message: message,
                                voiceServices: voiceServices,
                                onChipTap: { send($0) },
                                onConfirm: { viewModel.confirmPendingAction(message, at: $0, context: modelContext) },
                                onCancel: { viewModel.cancelPendingAction(message, at: $0, context: modelContext) },
                                onSaveTravelCard: { viewModel.saveTravelCard($0, context: modelContext) },
                                onRetryModel: { slug in
                                    if let prompt = precedingUserText(for: message) {
                                        viewModel.retry(prompt, on: slug, conversationId: message.conversationId, context: modelContext)
                                    }
                                },
                                animateReveal: shouldAnimateReveal(message)
                            ).id(message.id)
                        }
                        if viewModel.isSending {
                            CoachTraceStrip(events: viewModel.traceEvents).id("trace")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    autoSpeakIfNeeded()
                }
                .onChange(of: viewModel.traceEvents.count) {
                    withAnimation { proxy.scrollTo("trace", anchor: .bottom) }
                }
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
            }

            VStack(spacing: 0) {
                if showColdStart {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(moduleAwareChips, id: \.self) { prompt in
                                Button { send(prompt) } label: {
                                    Text(prompt)
                                        .font(.system(size: 12))
                                        .foregroundStyle(PulseColors.textSecondary)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(PulseColors.card, in: Capsule())
                                        .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
                if let banner = viewModel.errorBanner, !viewModel.outOfCredits {
                    errorBanner(banner)
                }
                composer
            }
            // Clears the nav bar when idle; rises above the keyboard when typing.
            .padding(.bottom, composerBottomInset)
            .background(PulseColors.secondaryBackground)
        }
        .background(PulseColors.background)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            // Visible keyboard height = how far its top is above the screen bottom.
            keyboardHeight = max(0, screenHeight - frame.origin.y)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onAppear {
            if activeConversationId == nil {
                activeConversationId = allMessages.last?.conversationId ?? conversations.first?.id
            }
            if nav.requestedConversationId != nil { openRequestedConversation() }
            consumePrefillIfPresent()
        }
        .onChange(of: nav.prefill) { _, value in
            if value != nil { consumePrefillIfPresent() }
        }
        .onChange(of: nav.requestedConversationId) { _, id in
            if id != nil { openRequestedConversation() }
        }
        .onChange(of: nav.requestedRoute) { _, route in
            // The `navigate_to` tool queued a destination; close the Coach so
            // MainTabView's onDismiss can switch tabs / push the route.
            if route != nil || nav.requestedTab != nil { onDismiss?() }
        }
        .sheet(isPresented: $showHistory) {
            CoachHistorySheet(conversations: conversations, activeId: activeConversationId) { id in
                activeConversationId = id
            }
        }
        .sheet(isPresented: $showPersonalityPicker) {
            CoachPersonalityPicker(settingsStore: settingsStore)
        }
        .sheet(isPresented: $showSettings) {
            CoachSettingsSheet()
        }
        .sheet(isPresented: $showCreditsPaywall) {
            NavigationStack { CreditsView() }
        }
        .onChange(of: viewModel.outOfCredits) { _, isOut in
            if isOut { showCreditsPaywall = true }
        }
        .fullScreenCover(isPresented: $showVoiceMode) {
            VoiceConversationView(
                conversationId: voiceModeConversationId ?? resolveConversationId(),
                onClose: { showVoiceMode = false }
            )
        }
    }

    /// Opens the hands-free voice surface against the active conversation, so
    /// anything said by voice also lands in this chat's history.
    private func openVoiceMode() {
        if isDictating { stopDictation() }
        composerFocused = false
        voiceModeConversationId = resolveConversationId()
        HapticService.selection()
        showVoiceMode = true
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let onDismiss {
                Button { onDismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(PulseColors.card, in: Circle())
                        .overlay(Circle().stroke(PulseColors.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            CoachOrb(size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("PulseLoop Assistant")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("\(activeProviderShortLabel) · \(settingsStore.settings.personality.label)")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button { newConversation() } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 15))
                    .foregroundStyle(PulseColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.card, in: Circle())
                    .overlay(Circle().stroke(PulseColors.borderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { composerFocused = false; showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 15))
                    .foregroundStyle(PulseColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.card, in: Circle())
                    .overlay(Circle().stroke(PulseColors.borderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { openVoiceMode() } label: {
                Image(systemName: "waveform").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Talk hands-free")

            overflowMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(PulseColors.secondaryBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(PulseColors.borderSubtle).frame(height: 1) }
    }

    /// Consolidates the secondary controls (model/provider, AI settings,
    /// personality) into one overflow menu so the header stays uncluttered.
    private var overflowMenu: some View {
        Menu {
            Button { showPersonalityPicker = true } label: {
                Label("Personality (\(settingsStore.settings.personality.label))", systemImage: "face.smiling")
            }
            Button { showSettings = true } label: {
                Label("AI Settings", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 36, height: 36)
                .background(PulseColors.card, in: Circle())
                .overlay(Circle().stroke(PulseColors.borderSubtle, lineWidth: 1))
        }
    }

    /// Short label for the header subtitle reflecting the provider that will
    /// actually answer this turn — mirroring `CoachViewModel.makeClient`'s
    /// resolution so the header doesn't misrepresent the backend in use (AIN-7).
    private var activeProviderShortLabel: String {
        let settings = settingsStore.settings
        let hasKey = (AIService.shared.currentAPIKey?.isEmpty == false)

        switch settings.providerMode {
        case .backendProxy:
            let trimmed = settings.backendProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if URL(string: trimmed)?.scheme?.hasPrefix("http") == true { return "Cloud AI" }
        case .bedrock:
            let region = settings.bedrockRegion.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = settings.bedrockModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !region.isEmpty, !model.isEmpty { return "Bedrock" }
        case .offlineStub, .userOpenAIKey:
            break
        }

        // BYO on-device key → name the selected OpenRouter model.
        if hasKey {
            let slug = AIModel.smart.resolvedSlug
            return AIModel.smart.options.first { $0.slug == slug }?.label ?? slug
        }

        // Paired-device zero-config proxy fallback.
        if CoachFeatureFlags.appWebBaseURL != nil { return "Cloud AI" }
        return "Set up AI"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(PulseColors.danger)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(PulseColors.textPrimary)
            Spacer(minLength: 8)
            Button {
                viewModel.errorBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PulseColors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PulseColors.danger.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !attachedImages.isEmpty {
                attachmentStrip
            }
            HStack(spacing: 8) {
                attachMenu

                Button { toggleDictation() } label: {
                    Image(systemName: isDictating ? "mic.fill" : "mic")
                        .font(.system(size: 16))
                        .foregroundStyle(isDictating ? .white : PulseColors.textMuted)
                        .frame(width: 36, height: 36)
                        .background(isDictating ? PulseColors.accent : PulseColors.card, in: Circle())
                        .overlay(Circle().stroke(PulseColors.borderSubtle, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .symbolEffect(.pulse, isActive: isDictating)

                TextField("Ask the assistant...", text: $draft)
                    .focused($composerFocused)
                    .textFieldStyle(.plain)
                    .font(PulseFont.body(14))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(PulseColors.card, in: Capsule())
                    .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))
                    .onSubmit { send(draft) }

                if viewModel.isSending {
                    Button { viewModel.cancel() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(PulseColors.danger, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop generating")
                } else {
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(canSend ? .white : PulseColors.textMuted)
                            .frame(width: 36, height: 36)
                            .background(canSend ? PulseColors.accent : PulseColors.card, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .onChange(of: voiceServices.transcribedText) { _, newValue in
            guard isDictating else { return }
            let captured = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = appendDictation(captured)
        }
        .onChange(of: voiceServices.isListening) { _, listening in
            if !listening && isDictating { stopDictation() }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            loadPickedPhotos(items)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, image in
            guard let image, let data = image.jpegData(compressionQuality: 0.9) else { return }
            attachedImages.append(data)
            cameraImage = nil
        }
    }

    /// Attach button: choose a photo from the library or take one with the camera.
    private var attachMenu: some View {
        Menu {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    composerFocused = false
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 36, height: 36)
                .background(PulseColors.card, in: Circle())
                .overlay(Circle().stroke(PulseColors.borderSubtle, lineWidth: 0.5))
        }
        .accessibilityLabel("Attach image")
    }

    /// Thumbnails of images queued to send, each removable.
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
                            Button {
                                attachedImages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white, Color.black.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove image")
                        }
                        .padding(.top, 6).padding(.trailing, 6)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 78)
    }

    /// Loads picked PhotosPicker items into raw image data and resets the picker.
    private func loadPickedPhotos(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append(data)
                }
            }
            await MainActor.run {
                attachedImages.append(contentsOf: loaded)
                photoItems = []
            }
        }
    }

    private func toggleDictation() {
        if isDictating {
            stopDictation()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        Task {
            let authorized = await voiceServices.requestSpeechAuthorization()
            guard authorized else { return }
            await MainActor.run {
                composerFocused = false
                draftBeforeDictation = draft
                voiceServices.startListening()
                isDictating = true
                HapticService.selection()
            }
        }
    }

    private func stopDictation() {
        let captured = voiceServices.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceServices.stopListening()
        isDictating = false
        if !captured.isEmpty {
            draft = appendDictation(captured)
        }
        HapticService.success()
    }

    /// Merges captured speech with whatever was already typed before dictation began.
    private func appendDictation(_ captured: String) -> String {
        let base = draftBeforeDictation.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? captured : "\(base) \(captured)"
    }

    /// Reads the latest assistant reply aloud when "Auto-speak replies" is on.
    /// No-op while a turn is still streaming or when the last message is the
    /// user's.
    private func autoSpeakIfNeeded() {
        guard VoicePreferences.autoSpeakReplies, !viewModel.isSending else { return }
        guard let last = messages.last, last.role == "assistant" else { return }
        let text = CoachSpeech.spokenText(for: last)
        guard !text.isEmpty else { return }
        voiceServices.speak(text)
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespaces).isEmpty
        return (hasText || !attachedImages.isEmpty) && !viewModel.isSending
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = attachedImages
        guard (!trimmed.isEmpty || !images.isEmpty), !viewModel.isSending else { return }
        let conversationId = resolveConversationId()
        // Title a fresh conversation from its opening message.
        if let convo = conversations.first(where: { $0.id == conversationId }),
           isDefaultTitle(convo.title),
           !allMessages.contains(where: { $0.conversationId == conversationId }) {
            convo.title = String((trimmed.isEmpty ? "Photo" : trimmed).prefix(40))
            try? modelContext.save()
        }
        draft = ""
        attachedImages = []
        composerFocused = false
        viewModel.startTurn(trimmed, conversationId: conversationId, context: modelContext, coordinator: coordinator, images: images)
    }

    /// The active conversation, creating one on first use.
    private func resolveConversationId() -> UUID {
        if let id = activeConversationId { return id }
        if let existing = conversations.first {
            activeConversationId = existing.id
            return existing.id
        }
        let conversation = CoachConversation(title: "New chat")
        modelContext.insert(conversation)
        try? modelContext.save()
        activeConversationId = conversation.id
        return conversation.id
    }

    private func isDefaultTitle(_ title: String) -> Bool {
        title == "New chat" || title == "Today check-in"
    }

    /// Open a specific conversation requested via deep-link (notification tap or
    /// a Today/Sleep summary-card tap).
    private func openRequestedConversation() {
        if let id = nav.requestedConversationId {
            activeConversationId = id
        }
        nav.requestedConversationId = nil
    }

    /// Drop a queued "Ask AI"/"Plan with AI" prefill into the composer (without
    /// auto-sending) and focus it, so the user can review/edit and hit send.
    private func consumePrefillIfPresent() {
        guard let text = nav.prefill, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        nav.prefill = nil
        draft = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            composerFocused = true
        }
    }

    private func newConversation() {
        composerFocused = false
        let conversation = CoachConversation(title: "New chat")
        modelContext.insert(conversation)
        try? modelContext.save()
        activeConversationId = conversation.id
    }

    // MARK: - Onboarding

    @State private var onboardingStep: Int = 0

    private var coachOnboarding: some View {
        VStack(spacing: 0) {
            if onboardingStep == 0 {
                welcomeStep
            } else if onboardingStep == 1 {
                goalStep
            } else {
                personalityStep
            }
        }
        .background(PulseColors.background)
        .animation(.easeInOut(duration: 0.3), value: onboardingStep)
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            CoachOrb(size: 72)

            VStack(spacing: 8) {
                Text("PulseLoop Assistant")
                    .font(PulseFont.title(26))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Your adaptive assistant for your\nwhole life. Ask anything, get\npersonalized answers, and take action.")
                    .font(PulseFont.body(15))
                    .foregroundStyle(PulseColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 16) {
                coachCapabilityRow(icon: "square.grid.2x2", title: "Adapts to your modules", subtitle: "Knows what you've installed and helps across all of it")
                coachCapabilityRow(icon: "sparkles", title: "Ask in plain language", subtitle: "Tasks, notes, plans, health data — just say what you need")
                coachCapabilityRow(icon: "bolt.fill", title: "Takes action for you", subtitle: "Create tasks and notes, log entries, install modules, navigate")
                coachCapabilityRow(icon: "chart.line.uptrend.xyaxis", title: "Understands your data", subtitle: "Explains your trends and surfaces what needs attention")
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                withAnimation { onboardingStep = 1 }
            } label: {
                Text("Continue")
                    .font(PulseFont.bodySemibold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(PulseColors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func coachCapabilityRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(PulseColors.accent)
                .frame(width: 40, height: 40)
                .background(PulseColors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(subtitle)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
    }

    private var goalStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            CoachOrb(size: 48)

            Text("What's your primary goal?")
                .font(PulseFont.title(22))
                .foregroundStyle(PulseColors.textPrimary)

            Text("This helps the assistant personalize\ninsights and suggestions for you.")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(onboardingGoals, id: \.1) { label, key in
                    Button {
                        settingsStore.settings.primaryGoal = key
                        withAnimation { onboardingStep = 2 }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PulseColors.textMuted)
                            Text(label)
                                .font(PulseFont.bodyMedium(14))
                                .foregroundStyle(PulseColors.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(16)
                        .background(PulseColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PulseColors.borderSubtle, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private var personalityStep: some View {
        CoachPersonalityOnboarding(settingsStore: settingsStore)
    }
}

/// Conversation history sheet  -  pick a past conversation to resume.
struct CoachHistorySheet: View {
    let conversations: [CoachConversation]
    let activeId: UUID?
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    Text("No conversations yet.")
                        .font(.system(size: 14)).foregroundStyle(PulseColors.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(conversations) { convo in
                            Button { onSelect(convo.id); dismiss() } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(convo.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(PulseColors.textPrimary)
                                        Text(Self.dateFormatter.string(from: convo.updatedAt))
                                            .font(.system(size: 11))
                                            .foregroundStyle(PulseColors.textMuted)
                                    }
                                    Spacer()
                                    if convo.id == activeId {
                                        Image(systemName: "checkmark").foregroundStyle(PulseColors.accent)
                                    }
                                }
                            }
                            .listRowBackground(PulseColors.card)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(PulseColors.background)
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

extension UIApplication {
    /// Resigns the first responder app-wide (used to dismiss the keyboard on
    /// tab changes, where no single FocusState is in scope).
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct CoachOrb: View {
    var size: CGFloat = 40
    @State private var phase: CGFloat = 0
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.7), Color.black],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(x: -size * 0.1, y: -size * 0.1)

            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: size * 0.7, height: size * 0.7)
                .scaleEffect(phase > 0.5 ? 1.1 : 0.95)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

/// Plain-text extraction for text-to-speech. Prefers the structured response's
/// title + summary + bullets (skipping chart/diagram/source markup), falling
/// back to the raw markdown body stripped of formatting.
enum CoachSpeech {
    static func spokenText(for message: CoachMessage) -> String {
        if message.role == "assistant",
           let structured = CoachResponse.decode(fromJSON: message.cardsJSON) {
            var parts: [String] = []
            if !structured.title.isEmpty { parts.append(structured.title) }
            if !structured.summary.isEmpty { parts.append(structured.summary) }
            parts.append(contentsOf: structured.bullets)
            if let safety = structured.safetyNote, !safety.isEmpty { parts.append(safety) }
            let joined = parts.joined(separator: ". ")
            if !joined.isEmpty { return joined }
        }
        return stripMarkdown(message.body)
    }

    private static func stripMarkdown(_ text: String) -> String {
        var result = text
        for token in ["**", "__", "*", "_", "`", "#", ">"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CoachBubble: View {
    let message: CoachMessage
    var voiceServices: VoiceServices?
    var onChipTap: ((String) -> Void)?
    var onConfirm: ((Int) -> Void)?
    var onCancel: ((Int) -> Void)?
    var onSaveTravelCard: ((CoachTravelCard) -> Void)?
    /// Re-run the preceding user turn on a specific model slug (transparency T4).
    var onRetryModel: ((String) -> Void)?
    /// Reveal the summary progressively (typewriter) — set only for the just-arrived
    /// latest assistant reply so historical messages render instantly (AIN-1).
    var animateReveal: Bool = false

    @State private var isSpeakingThis = false
    @Environment(\.modelContext) private var modelContext

    private var structured: CoachResponse? {
        message.role == "assistant" ? CoachResponse.decode(fromJSON: message.cardsJSON) : nil
    }

    private var pendingActions: [PendingAction] {
        message.role == "assistant" ? PendingAction.decodeArray(fromJSON: message.pendingActionJSON) : []
    }

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                content
                if message.role == "assistant" {
                    CoachToolTraceView(messageId: message.id)
                }
                if message.role == "assistant" {
                    CoachRouteBadge(messageId: message.id, onRetryModel: onRetryModel)
                }
                if message.role == "assistant", structured != nil {
                    CoachFeedbackBar(
                        messageId: message.id,
                        conversationId: message.conversationId
                    )
                }
                ForEach(Array(pendingActions.enumerated()), id: \.offset) { index, action in
                    if action.kind == .installSubApp {
                        CoachInstallCardView(
                            action: action,
                            onConfirm: { onConfirm?(index) },
                            onCancel: { onCancel?(index) }
                        )
                    } else {
                        CoachActionCardView(
                            action: action,
                            onConfirm: { onConfirm?(index) },
                            onCancel: { onCancel?(index) }
                        )
                    }
                }
                if message.role == "assistant", voiceServices != nil {
                    speakButton
                }
            }
            if message.role != "user" { Spacer(minLength: 40) }
        }
    }

    private var speakButton: some View {
        Button {
            guard let voiceServices else { return }
            if isSpeakingThis {
                voiceServices.stopSpeaking()
                isSpeakingThis = false
            } else {
                voiceServices.speak(CoachSpeech.spokenText(for: message))
                isSpeakingThis = true
            }
            HapticService.selection()
        } label: {
            Label(isSpeakingThis ? "Stop" : "Listen",
                  systemImage: isSpeakingThis ? "stop.circle.fill" : "speaker.wave.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PulseColors.textMuted)
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .onChange(of: voiceServices?.isSpeaking ?? false) { _, speaking in
            if !speaking { isSpeakingThis = false }
        }
    }

    @ViewBuilder private var content: some View {
        if let structured {
            CoachResponseView(response: structured, onChipTap: onChipTap, onSaveTravelCard: onSaveTravelCard, animateReveal: animateReveal)
                .padding(14)
                .background(PulseColors.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
        } else {
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                if let data = message.attachmentData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
                }
                if !message.body.isEmpty {
                    (message.role == "user" ? Text(message.body) : Text(coachMarkdown: message.body))
                        .font(.system(size: 14))
                        .foregroundStyle(message.role == "user" ? .white : PulseColors.textPrimary)
                        .padding(14)
                        .background(message.role == "user" ? PulseColors.accent : PulseColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(message.role == "user" ? Color.clear : PulseColors.borderSubtle, lineWidth: 1)
                        )
                }
            }
        }
    }
}

/// On-design thumbs up/down feedback row shown under an assistant reply (Life OS
/// T0). A down vote reveals low-cardinality reason chips. Persists via
/// `CoachFeedbackStore`; reflects any previously recorded rating on appear. Design
/// system: SF Symbols only, muted tones, no accent fills.
struct CoachFeedbackBar: View {
    let messageId: UUID
    let conversationId: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var rating: CoachFeedbackStore.Rating?
    @State private var showReasons = false
    @State private var chosenReason: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                thumb(.up, icon: "hand.thumbsup")
                thumb(.down, icon: "hand.thumbsdown")
            }
            if showReasons, rating == .down {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(CoachFeedbackStore.downReasons, id: \.code) { reason in
                            reasonChip(reason.code, reason.label)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.top, 2)
        .onAppear {
            if let existing = CoachFeedbackStore.fetch(messageId: messageId, in: modelContext) {
                rating = CoachFeedbackStore.Rating(rawValue: existing.rating)
                chosenReason = existing.reason
            }
        }
    }

    private func thumb(_ value: CoachFeedbackStore.Rating, icon: String) -> some View {
        let selected = rating == value
        return Button {
            rating = value
            showReasons = (value == .down)
            CoachFeedbackStore.record(
                messageId: messageId,
                conversationId: conversationId,
                rating: value,
                reason: value == .down ? chosenReason : "",
                in: modelContext
            )
            HapticService.selection()
        } label: {
            Image(systemName: selected ? "\(icon).fill" : icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? PulseColors.textPrimary : PulseColors.textMuted)
        }
        .buttonStyle(.plain)
    }

    private func reasonChip(_ code: String, _ label: String) -> some View {
        let selected = chosenReason == code
        return Button {
            chosenReason = selected ? "" : code
            CoachFeedbackStore.record(
                messageId: messageId,
                conversationId: conversationId,
                rating: .down,
                reason: chosenReason,
                in: modelContext
            )
            HapticService.selection()
        } label: {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(selected ? PulseColors.textPrimary : PulseColors.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? PulseColors.fillSubtle : PulseColors.cardSoft, in: Capsule())
                .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Live progress strip shown while a turn runs (in-process trace). Renders a
/// Perplexity-style vertical step list — each phase/tool the assistant runs
/// (think → search → analyze → write) shows as a row with a status icon:
/// completed steps get a checkmark, the active step a spinner.
struct CoachTraceStrip: View {
    let events: [CoachTraceEvent]
    @State private var startTime = Date()
    @State private var elapsed: TimeInterval = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// One displayed step, collapsed from the raw event stream.
    private struct Step: Identifiable {
        let id: String
        var label: String
        var done: Bool
        var failed: Bool
        /// Optional SF Symbol to show instead of the default circle (e.g. the routed
        /// agent's icon for the "Routing to …" step). No emoji — design system.
        var symbol: String?
    }

    /// The routing step is emitted as a phase event whose label starts with this
    /// prefix; we render it with the routed agent's SF Symbol for a multi-agent feel.
    private static let routingPrefix = "Routing to "

    private static func symbol(forRoutingLabel label: String) -> String? {
        guard label.hasPrefix(routingPrefix) else { return nil }
        let lower = label.lowercased()
        for role in AgentRole.allCases where lower.contains(role.label.lowercased()) {
            return role.symbolName
        }
        return "point.3.connected.trianglepath.dotted"
    }

    /// Collapse the event stream into ordered, de-duplicated steps. A tool's
    /// running→completed events merge into one row keyed by tool name; phase
    /// events (thinking/writing) key by their label.
    private var steps: [Step] {
        var order: [String] = []
        var byKey: [String: Step] = [:]
        for e in events where e.status != .done {
            let key = e.toolName ?? e.label
            if byKey[key] == nil {
                byKey[key] = Step(id: key, label: e.label.isEmpty ? key : e.label,
                                  done: false, failed: false,
                                  symbol: Self.symbol(forRoutingLabel: e.label))
                order.append(key)
            }
            if e.status == .completedTool { byKey[key]?.done = true }
            if e.status == .failedTool { byKey[key]?.done = true; byKey[key]?.failed = true }
            if !e.label.isEmpty { byKey[key]?.label = e.label }
        }
        // Earlier phase steps have logically passed once a later step exists; mark
        // all but the last as done so the routing/planning rows don't spin forever.
        var result = order.compactMap { byKey[$0] }
        if result.count > 1 {
            for i in 0..<(result.count - 1) where !result[i].failed { result[i].done = true }
        }
        return result
    }

    private var elapsedText: String { "\(Int(elapsed))s" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PulseColors.accent)
                Text("Working")
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer(minLength: 0)
                Text("\(steps.count) step\(steps.count == 1 ? "" : "s") · \(elapsedText)")
                    .font(PulseFont.body(10))
                    .foregroundStyle(PulseColors.textMuted)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    let isActive = index == steps.count - 1 && !step.done
                    stepRow(step, isActive: isActive)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
        .onAppear { startTime = Date() }
        .onReceive(timer) { _ in elapsed = Date().timeIntervalSince(startTime) }
    }

    @ViewBuilder
    private func stepRow(_ step: Step, isActive: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if step.failed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(PulseColors.warning)
                } else if isActive {
                    ProgressView().controlSize(.mini).tint(PulseColors.accent)
                } else if let symbol = step.symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(PulseColors.accent)
                } else if step.done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PulseColors.accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
            .font(.system(size: 12))
            .frame(width: 16, height: 16)

            Text(step.label)
                .font(PulseFont.body(12))
                .foregroundStyle(step.done ? PulseColors.textSecondary : PulseColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Personality Orb

struct CoachPersonalityOnboarding: View {
    @Bindable var settingsStore: CoachSettingsStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            Text("Select a personality")
                .font(PulseFont.title(22))
                .foregroundStyle(PulseColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(CoachPersonality.allCases), id: \.self) { p in
                        personalityCard(p)
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    private func personalityCard(_ p: CoachPersonality) -> some View {
        VStack(spacing: 16) {
            CoachPersonalityOrb(personality: p, size: 80)

            Text(p.label)
                .font(PulseFont.titleSemibold(18))
                .foregroundStyle(PulseColors.textPrimary)

            HStack(spacing: 6) {
                ForEach(p.traits, id: \.self) { trait in
                    Text(trait)
                        .font(PulseFont.bodyMedium(11))
                        .foregroundStyle(PulseColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PulseColors.fillSubtle)
                        .clipShape(Capsule())
                }
            }

            Text(p.description)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 10)

            Button {
                settingsStore.settings.personality = p
                settingsStore.settings.hasCompletedOnboarding = true
            } label: {
                Text("Get started")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(PulseColors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .background(PulseColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PulseColors.borderSubtle, lineWidth: 1)
        }
    }
}

struct CoachPersonalityOrb: View {
    let personality: CoachPersonality
    var size: CGFloat = 80
    @State private var phase: CGFloat = 0

    private var orbColors: [Color] {
        switch personality {
        case .friend: return [.blue.opacity(0.6), .purple.opacity(0.4)]
        case .dataNerd: return [.teal.opacity(0.6), .green.opacity(0.4)]
        case .guardian: return [.orange.opacity(0.5), .pink.opacity(0.4)]
        case .commander: return [.red.opacity(0.6), .orange.opacity(0.4)]
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: orbColors,
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.18, height: size * 0.18)
                .offset(x: -size * 0.12, y: -size * 0.05)

            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.18, height: size * 0.18)
                .offset(x: size * 0.12, y: -size * 0.05)

            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: size * 0.75, height: size * 0.75)
                .scaleEffect(phase > 0.5 ? 1.08 : 0.95)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

// MARK: - Personality Picker Sheet

struct CoachPersonalityPicker: View {
    @Bindable var settingsStore: CoachSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(CoachPersonality.allCases) { personality in
                        Button {
                            settingsStore.settings.personality = personality
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                CoachPersonalityOrb(personality: personality, size: 44)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(personality.label)
                                            .font(PulseFont.bodySemibold(15))
                                            .foregroundStyle(PulseColors.textPrimary)
                                        if settingsStore.settings.personality == personality {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(PulseColors.success)
                                        }
                                    }
                                    Text(personality.description)
                                        .font(PulseFont.body(12))
                                        .foregroundStyle(PulseColors.textMuted)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                settingsStore.settings.personality == personality
                                ? PulseColors.accentSoft
                                : PulseColors.card
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        settingsStore.settings.personality == personality
                                        ? PulseColors.accent.opacity(0.3)
                                        : PulseColors.borderSubtle,
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Assistant Personality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AI Settings Sheet

/// Hosts the full `CoachSettingsSection` (provider, model, personality, keys,
/// capability toggles, notifications) in a sheet so the AI's settings can be
/// switched right from the Coach header without leaving the conversation.
struct CoachSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    CoachSettingsSection()
                }
                .padding(16)
            }
            .background(PulseColors.background)
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Collapsible "what I did" trace shown under a finished assistant reply. Reads the
/// persisted `CoachToolCall` rows for the message so the user can see, after the
/// fact, the steps the AI took (searched the web → created a trip → added items).
struct CoachToolTraceView: View {
    let messageId: UUID
    @Query private var calls: [CoachToolCall]
    @State private var expanded = false

    init(messageId: UUID) {
        self.messageId = messageId
        _calls = Query(
            filter: #Predicate<CoachToolCall> { $0.messageId == messageId },
            sort: \.createdAt, order: .forward
        )
    }

    var body: some View {
        if !calls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10))
                        Text(expanded ? "Hide steps" : "\(calls.count) step\(calls.count == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .foregroundStyle(PulseColors.textMuted)
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(calls) { call in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(PulseColors.textMuted)
                                    .padding(.top, 5)
                                Text(Self.humanize(call.toolName))
                                    .font(.system(size: 11))
                                    .foregroundStyle(PulseColors.textSecondary)
                            }
                        }
                    }
                    .padding(.leading, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(PulseColors.cardSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    /// Turn a snake_case tool name into a readable phrase, e.g. `create_trip` →
    /// "Created trip", `web_search` → "Searched the web".
    static func humanize(_ toolName: String) -> String {
        switch toolName {
        case "web_search": return "Searched the web"
        default:
            let words = toolName.split(separator: "_").map(String.init)
            guard let verb = words.first else { return toolName }
            let past: String
            switch verb {
            case "create": past = "Created"
            case "add": past = "Added"
            case "update": past = "Updated"
            case "delete", "remove": past = "Removed"
            case "set": past = "Set"
            case "get", "list", "read": past = "Reviewed"
            case "navigate": past = "Opened"
            case "log": past = "Logged"
            default: past = verb.capitalized
            }
            let rest = words.dropFirst().joined(separator: " ")
            return rest.isEmpty ? past : "\(past) \(rest)"
        }
    }
}

/// Transparency strip (Life OS T4): shows which specialist + model handled a reply
/// and why, and lets the user re-run the turn on a different model in one tap.
struct CoachRouteBadge: View {
    let messageId: UUID
    var onRetryModel: ((String) -> Void)?
    @Query private var telemetry: [TurnTelemetry]

    init(messageId: UUID, onRetryModel: ((String) -> Void)?) {
        self.messageId = messageId
        self.onRetryModel = onRetryModel
        _telemetry = Query(
            filter: #Predicate<TurnTelemetry> { $0.messageId == messageId },
            sort: \.createdAt, order: .reverse
        )
    }

    private var turn: TurnTelemetry? { telemetry.first }

    private var role: AgentRole {
        AgentRole.allCases.first { $0.label == turn?.roleLabel } ?? .generalist
    }

    /// Alternative models to offer, drawn from the registry candidates for the role,
    /// excluding the one already used.
    private var alternatives: [ModelCapability] {
        let used = turn?.model ?? ""
        return ModelRegistry.candidates(for: role).filter { $0.slug != used }.prefix(6).map { $0 }
    }

    var body: some View {
        if let turn, !turn.model.isEmpty {
            Menu {
                Section("Reasked on a different model") {
                    ForEach(alternatives, id: \.slug) { cap in
                        Button {
                            onRetryModel?(cap.slug)
                        } label: {
                            Label(cap.displayName, systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: role.symbolName)
                        .font(.system(size: 10))
                    Text("\(role.label) · \(AgentRouter.shortModelName(turn.model))")
                        .font(.system(size: 11, weight: .semibold))
                    if turn.recovered {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9))
                    }
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(PulseColors.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(PulseColors.cardSoft, in: Capsule())
        }
    }
}
