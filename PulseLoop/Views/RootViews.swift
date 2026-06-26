import SwiftUI
import SwiftData
import UIKit

struct RootAppView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LiveWorkoutManager.self) private var liveWorkout
    @Query private var profiles: [UserProfile]
    @State private var path = NavigationPath()
    @State private var showModuleOnboarding = false
    @AppStorage("appAppearance") private var appearance: String = AppAppearance.system.rawValue

    private var colorScheme: ColorScheme? {
        AppAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if profiles.first?.onboardingCompleted == true {
                    MainTabView(path: $path)
                } else {
                    OnboardingFlowView()
                }
            }
            .background(PulseColors.canvas.ignoresSafeArea())
            .task {
                ModuleManager.shared.runMigrations()
                SubAppRegistry.shared.runInstallMigration()
                SubAppRegistry.shared.runVersionBackfill()
                SubAppRegistry.shared.registerAllRoutes()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-seedDemo") || UserDefaults.standard.bool(forKey: "seedDemo") {
                    SeedData.clearAll(modelContext)
                    SeedData.seedDemo(modelContext, completeOnboarding: true)
                }
                #endif
                // A truly empty install now shows the onboarding flow instead of
                // silently seeding demo data + completing onboarding. The demo-seed
                // path above is DEBUG-only and never ships in a release build.
                // The exercise library is content, not demo data, so seed it on
                // any install where it's still empty.
                SeedData.seedExerciseCatalogIfNeeded(modelContext)
                if UserDefaults.standard.bool(forKey: "openWorkout"),
                   let session = ActivityRepository.sessions(context: modelContext).first(where: { $0.status == .finished && $0.useGps }) {
                    path.append(AppRoute.activityDetail(session.id))
                }
                if UserDefaults.standard.bool(forKey: "openRecord") {
                    path.append(AppRoute.recordSelect)
                }
                liveWorkout.recover()
                routeDeepLinkIfNeeded()
                // Once-per-day AI knowledge-base pass. Self-gating + silent when
                // the coach is off or no API key is set, so it's safe to fire on
                // every app open. Detached so it never blocks first paint.
                let learningContext = modelContext
                Task { await DailyLearningService(modelContext: learningContext).runIfNeeded() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    liveWorkout.recover()
                    routeDeepLinkIfNeeded()
                }
            }
            .onOpenURL { url in
                guard url.scheme == "pulseloop", url.host == "workout",
                      let id = UUID(uuidString: url.lastPathComponent) else { return }
                liveWorkout.requestOpen(sessionID: id)
                routeDeepLinkIfNeeded()
            }
            .navigationDestination(for: AppRoute.self) { route in
                destinationView(for: route)
            }
            .subAppNavigationDestinations(path: $path)
        }
        .tint(PulseColors.accent)
        .preferredColorScheme(colorScheme)
        .fullScreenCover(isPresented: $showModuleOnboarding) {
            ModulePickerView(isOnboarding: true) {
                showModuleOnboarding = false
            }
        }
        .onAppear {
            if profiles.first?.onboardingCompleted == true && !ModuleManager.shared.hasOnboarded {
                showModuleOnboarding = true
            }
        }
    }

    private func routeDeepLinkIfNeeded() {
        guard let id = liveWorkout.pendingDeepLinkSession else { return }
        liveWorkout.clearDeepLink()
        guard let session = ActivityRepository.sessions(context: modelContext).first(where: { $0.id == id }) else { return }
        let route: AppRoute = session.status == .finished ? .recordSummary(id) : .recordLive(id)
        path.append(route)
    }

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case let .activityDetail(id):
            ActivityDetailView(sessionId: id)
        case .recordSelect:
            RecordSelectView(path: $path)
        case let .recordLive(id):
            RecordLiveView(sessionId: id, path: $path)
        case let .recordSummary(id):
            RecordSummaryView(sessionId: id, path: $path)
        case .settings:
            SettingsView(path: $path)
        case .debug:
            DebugView()
        case .componentGallery:
            ComponentGalleryView()
        case .subAppBuilder:
            SubAppBuilderView()
        case let .subAppEditor(specID):
            subAppEditorDestination(specID: specID)
        case .credits:
            CreditsView()
        case .mySubApps:
            MySubAppsView(path: $path)
        case let .subApp(specID):
            SpecSubAppHost(specID: specID)
        case .subAppRegistry:
            SubAppRegistryView()
        case .moduleUpdates:
            ModuleUpdatesView()
        case .coachQuality:
            CoachQualityView()
        case .inbox:
            InboxView(path: $path)
        case .dayPlan:
            DayPlanView()
        case .notesList:
            NotesListView(path: $path)
        case let .noteEditor(id):
            NoteEditorView(noteId: id)
        case let .mailReply(id):
            MailReplyView(itemId: id)
        case .connectAccounts:
            ConnectAccountsView()
        case .privacyPermissions:
            PrivacyPermissionsView()
        case .sidebar:
            SidebarView(path: $path)
        case .health:
            HealthView(path: $path)
        case .vitals:
            VitalsView()
        case .sleep:
            SleepView()
        case .activity:
            ActivityView(path: $path)
        case .tasksList:
            TasksView()
        case .friends:
            FriendsView(path: $path)
        case .profile:
            ProfileView()
        case .insights:
            InsightsChartsView()
        case .modulePicker:
            ModulePickerView()
        case .fitness:
            FitnessDashboardView()
        case .workoutBuilder:
            WorkoutBuilderView()
        case .exerciseLibrary:
            ExerciseLibraryView { _ in }
        case .foodDiary:
            FoodDiaryView(path: $path)
        case let .foodSearch(mealTypeRaw):
            FoodSearchView(mealType: MealType(rawValue: mealTypeRaw) ?? .snack, path: $path)
        case let .workoutSession(id):
            WorkoutSessionRoute(templateId: id)
        case .bodyProgress:
            BodyProgressView()
        case .journal:
            JournalView()
        case .knowledgeBase:
            KnowledgeBaseView()
        case .travel:
            TravelView(path: $path)
        case let .tripDetail(id):
            TripDetailView(tripId: id)
        }
    }

    /// Resolves the editor for an existing user spec (by id), or a fresh blank spec
    /// when `specID` is nil. Falls back to an empty-state if the id can't be found.
    @ViewBuilder
    private func subAppEditorDestination(specID: String?) -> some View {
        if let specID, let spec = UserSubAppStore.shared.specs.first(where: { $0.id == specID }) {
            SubAppEditorView(spec: spec, isNew: false)
        } else if specID == nil {
            SubAppEditorView(spec: SubAppEditorView.blankSpec(), isNew: true)
        } else {
            InlineEmptyState(title: "Unavailable", message: "This sub-app could not be loaded for editing.")
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Binding var path: NavigationPath
    @State private var selected: MainTab = .home
    @State private var showCommandPalette = false
    @State private var showVoiceCapture = false
    @State private var pendingRoute: AppRoute?
    @State private var pendingTab: MainTab?

    init(path: Binding<NavigationPath>) {
        self._path = path
        let raw = UserDefaults.standard.string(forKey: "startTab")
        let requested = MainTab.allCases.first { $0.rawValue.lowercased() == raw } ?? .home
        _selected = State(initialValue: requested == .askAI ? .home : requested)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                TabView(selection: $selected) {
                    HomeView(path: $path, onSwitchTab: { tab in selected = tab }).tag(MainTab.home)
                    TrackerView(path: $path).tag(MainTab.tracker)
                    Color.clear.tag(MainTab.askAI)
                    InboxView(path: $path).tag(MainTab.inbox)
                    FriendsView(path: $path).tag(MainTab.friends)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                BottomNavBar(selected: $selected, onCenterTap: { showCommandPalette = true })
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: selected) { _, newTab in
                if newTab == .askAI {
                    selected = .home
                    showCommandPalette = true
                }
                UIApplication.shared.endEditing()
            }
        }
        .fullScreenCover(isPresented: $showCommandPalette, onDismiss: applyPendingNavigation) {
            CoachView(onDismiss: { showCommandPalette = false })
        }
        .fullScreenCover(isPresented: $showVoiceCapture) {
            VoiceCaptureView(path: $path)
        }
        .background(PulseColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { notification in
            if let tab = notification.object as? MainTab {
                selected = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCoach)) { _ in
            showCommandPalette = true
        }
    }

    /// Run queued navigation once the command palette has fully dismissed, avoiding
    /// the previous fixed-delay timing hack that could miss transitions on slow devices.
    private func applyPendingNavigation() {
        // Local quick-add navigation (existing behavior).
        if let route = pendingRoute {
            pendingRoute = nil
            path.append(route)
        }
        if let tab = pendingTab {
            pendingTab = nil
            selected = tab
        }
        // Navigation requested by the Coach `navigate_to` tool.
        let coachNav = CoachNavigation.shared
        if let tab = coachNav.requestedTab {
            coachNav.requestedTab = nil
            selected = tab
        }
        if let route = coachNav.requestedRoute {
            coachNav.requestedRoute = nil
            path.append(route)
        }
    }
}

// MARK: - Bottom Nav Bar

struct BottomNavBar: View {
    @Binding var selected: MainTab
    var onCenterTap: () -> Void
    @AppStorage("tabOrder") private var tabOrderData: Data = Data()
    /// Bumped on `.installedModulesChanged` so tab visibility recomputes when the
    /// user installs/uninstalls a module-backed tab.
    @State private var installVersion = 0

    /// Module that a tab represents, if any. Home/Tracker/Ask AI are fixed anchors
    /// (always present); Inbox and Friends map to installable modules and hide when
    /// their module isn't installed.
    private func backingModule(_ tab: MainTab) -> AppModule? {
        switch tab {
        case .inbox: return .aiCapture
        case .friends: return .accountability
        default: return nil
        }
    }

    private func isVisible(_ tab: MainTab) -> Bool {
        guard let module = backingModule(tab) else { return true }
        return ModuleManager.shared.isEnabled(module)
    }

    private var outerTabs: [MainTab] {
        let saved = (try? JSONDecoder().decode([String].self, from: tabOrderData)) ?? []
        let defaultOrder: [MainTab] = [.home, .tracker, .inbox, .friends]
        let base: [MainTab]
        if saved.isEmpty {
            base = defaultOrder
        } else {
            let mapped = saved.compactMap { raw in MainTab.allCases.first { $0.rawValue == raw } }
            base = mapped.isEmpty ? defaultOrder : mapped
        }
        return base.filter(isVisible)
    }

    private var tabs: [MainTab] {
        // Always-present anchors flank the center Ask AI button. Module-backed tabs
        // (Inbox/Friends) drop out when uninstalled; the row stays balanced.
        let outer = outerTabs
        let leading = Array(outer.prefix(2))
        let trailing = Array(outer.dropFirst(2))
        return leading + [.askAI] + trailing
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                if tab == .askAI {
                    Button {
                        HapticService.impact(.light)
                        onCenterTap()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                                .fill(PulseColors.accent)
                                .frame(width: 52, height: 52)
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .offset(y: -4)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Ask AI")
                    .accessibilityHint("Opens the command palette to capture or ask")
                } else {
                    Button {
                        if selected != tab { HapticService.selection() }
                        selected = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 20, weight: selected == tab ? .medium : .light))
                                .frame(width: 38, height: 28)
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(selected == tab ? PulseColors.textPrimary : PulseColors.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: PulseLayout.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selected == tab ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(PulseColors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 0.5)
        }
        .id(installVersion)
        .onReceive(NotificationCenter.default.publisher(for: .installedModulesChanged)) { _ in
            installVersion &+= 1
            // If the currently selected tab was just uninstalled, fall back to Home.
            if !isVisible(selected) { selected = .home }
        }
    }
}

// MARK: - Onboarding

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var step = 0
    @State private var name = ""
    private let steps = ["Welcome", "Name", "Health", "Privacy", "Comfort"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? PulseColors.accent : PulseColors.fillSubtle)
                        .frame(height: 4)
                }
            }
            .padding()
            .accessibilityElement()
            .accessibilityLabel("Step \(step + 1) of \(steps.count): \(steps[step])")

            TabView(selection: $step) {
                OnboardingWelcomeView(next: next).tag(0)
                OnboardingNameView(name: $name, next: next).tag(1)
                OnboardingValueView(next: next).tag(2)
                OnboardingPrivacyView(next: next).tag(3)
                OnboardingComfortView(finish: finish).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(PulseColors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .onAppear {
            // Pre-fill if a profile already has a name (e.g. re-running onboarding).
            if name.isEmpty, let existing = profiles.first?.name, !existing.isEmpty {
                name = existing
            }
        }
    }

    private func next() {
        withAnimation(.snappy) { step = min(step + 1, steps.count - 1) }
    }

    private func finish() {
        let profile = profiles.first ?? UserProfile()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { profile.name = trimmed }
        profile.onboardingCompleted = true
        profile.baselineCompleted = true
        profile.updatedAt = Date()
        modelContext.insert(profile)
        try? modelContext.save()
    }
}

struct OnboardingWelcomeView: View {
    let next: () -> Void
    var body: some View {
        OnboardingPage(
            title: "Your brain, organized",
            subtitle: "PulseLoop brings your life  -  health, tasks, notes, and routines  -  into one calm, AI-powered space.",
            systemImage: "brain.head.profile",
            actionTitle: "Get started",
            action: next
        )
    }
}

struct OnboardingNameView: View {
    @Binding var name: String
    let next: () -> Void
    @FocusState private var focused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 64))
                .foregroundStyle(PulseColors.textMuted)
                .accessibilityHidden(true)
            OnboardingHeader(
                title: "What should we call you?",
                subtitle: "Your name personalizes greetings and the way your AI assistant talks to you. You can change it anytime in Settings."
            )

            TextField("Your name", text: $name)
                .font(PulseFont.body(17))
                .foregroundStyle(PulseColors.textPrimary)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { if !trimmed.isEmpty { next() } }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(PulseColors.fillSubtle, in: RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1))
                .padding(.horizontal, 24)

            Spacer()
            PrimaryButton(title: "Continue", action: next)
                .padding(.horizontal, 24)
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.5 : 1)
        }
        .padding(24)
        .onAppear {
            // Defer focus so the paging transition settles before the keyboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }
}

struct OnboardingValueView: View {
    let next: () -> Void
    var body: some View {
        OnboardingPage(
            title: "Health at the center",
            subtitle: "Pair your ring to track heart rate, sleep, and activity  -  then let your AI assistant turn the data into simple daily guidance.",
            systemImage: "heart.text.square",
            actionTitle: "Continue",
            action: next
        )
    }
}

struct OnboardingPrivacyView: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(PulseColors.textMuted)
                .accessibilityHidden(true)
            OnboardingHeader(
                title: "Private by default",
                subtitle: "Your data stays on your device. You can connect accounts like email or calendar later, from Settings, whenever a feature needs them  -  never before."
            )
            Spacer()
            PrimaryButton(title: "Sounds good", action: next)
                .padding(.horizontal, 24)
        }
        .padding(24)
    }
}

struct OnboardingComfortView: View {
    let finish: () -> Void
    @AppStorage(ComfortPrefs.reduceMotionKey) private var reduceMotion = false
    @AppStorage(ComfortPrefs.softHapticsKey) private var softHaptics = true
    @AppStorage(ComfortPrefs.quietHoursKey) private var quietHours = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "hand.raised")
                .font(.system(size: 64))
                .foregroundStyle(PulseColors.textMuted)
                .accessibilityHidden(true)
            OnboardingHeader(title: "Comfort profile", subtitle: "Set your sensory preferences. You can change these anytime in Settings.")

            VStack(spacing: 12) {
                ComfortToggleRow(icon: "wind", title: "Reduce motion", subtitle: "Minimal animations", isOn: $reduceMotion)
                ComfortToggleRow(icon: "iphone.radiowaves.left.and.right", title: "Soft haptics", subtitle: "Gentle tactile feedback", isOn: $softHaptics)
                ComfortToggleRow(icon: "moon", title: "Quiet hours", subtitle: "Mute alerts 10pm–7am", isOn: $quietHours)
            }
            .padding(.horizontal)

            Spacer()
            PrimaryButton(title: "Enter PulseLoop", action: finish)
                .padding(.horizontal, 24)
        }
        .padding(24)
    }
}

struct ComfortToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PulseFont.bodyMedium(15)).foregroundStyle(PulseColors.textPrimary)
                Text(subtitle).font(PulseFont.bodySmall).foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(PulseColors.accent)
        }
        .padding(14)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(subtitle)
    }
}

struct OnboardingPage: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(PulseColors.textMuted)
                .accessibilityHidden(true)
            OnboardingHeader(title: title, subtitle: subtitle)
            Spacer()
            PrimaryButton(title: actionTitle, action: action)
        }
        .padding(24)
    }
}

struct OnboardingHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(PulseFont.titleMedium(28))
                .foregroundStyle(PulseColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }
}

// MARK: - Shared Small Views

struct SectionHeader: View {
    let title: String
    let action: String?
    var body: some View {
        HStack {
            Text(title)
                .font(PulseFont.bodySemibold(13))
                .foregroundStyle(PulseColors.textSecondary)
                .textCase(.uppercase)
            Spacer()
            if let action {
                Text(action)
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.accent)
            }
        }
    }
}

struct StatusCopy: View {
    let title: String
    let text: String

    init(title: String, body: String) {
        self.title = title
        self.text = body
    }

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(PulseFont.bodySemibold(16))
                Text(text)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    init(title: String, body: String) {
        self.title = title
        self.message = body
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(PulseColors.textMuted)
            Text(title).font(PulseFont.bodySemibold(16))
            Text(message)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct InlineEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
            Text(message).font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Time-of-day greeting.
func greetingForHour(_ date: Date = Date()) -> String {
    switch Calendar.current.component(.hour, from: date) {
    case 5..<12: return "Good morning"
    case 12..<17: return "Good afternoon"
    case 17..<22: return "Good evening"
    default: return "Good night"
    }
}

// MARK: - Connection Status Pill (retained for BLE ring)

struct ConnectionStatusPill: View {
    let state: RingConnectionState
    let batteryPercent: Int?
    @Environment(\.motionReduced) private var motionReduced
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .opacity(isPulsing && pulse ? 0.35 : 1)
            Text(label)
                .font(PulseFont.bodyMedium(12))
                .foregroundStyle(PulseColors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PulseColors.fillSubtle, in: Capsule())
        .overlay(Capsule().stroke(PulseColors.borderHairline, lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            guard isPulsing, !motionReduced else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Ring connection")
        .accessibilityValue(label)
    }

    private var isPulsing: Bool {
        state == .connecting || state == .reconnecting || state == .scanning
    }

    private var dotColor: Color {
        switch state {
        case .connected: return PulseColors.success
        case .connecting, .reconnecting: return PulseColors.textMuted
        case .scanning: return PulseColors.textMuted
        case .failed: return PulseColors.alert
        case .idle, .disconnected: return PulseColors.textFaint
        }
    }

    private var label: String {
        switch state {
        case .connected:
            if let battery = batteryPercent, battery > 0 { return "Connected · \(battery)%" }
            return "Connected"
        case .connecting, .reconnecting: return "Connecting…"
        case .scanning: return "Searching…"
        case .failed: return "Sync failed"
        case .idle, .disconnected: return "Disconnected"
        }
    }
}
