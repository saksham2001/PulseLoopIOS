import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(RingSyncCoordinator.self) private var coordinator
    @Environment(RingBLEClient.self) private var ble
    @Query private var profiles: [UserProfile]
    @Query private var devices: [Device]
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \MealLog.loggedAt, order: .reverse) private var meals: [MealLog]
    @Query(sort: \MedicationLog.loggedAt, order: .reverse) private var medicationLogs: [MedicationLog]
    @Query(filter: #Predicate<InboxItem> { !$0.isHandled }) private var inboxItems: [InboxItem]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Binding var path: NavigationPath
    var onSwitchTab: ((MainTab) -> Void)?
    @State private var isCustomizing = false
    @State private var showSidebar = false
    @State private var showCommandPalette = false
    @State private var showPhotoPicker = false
    @AppStorage("avatarIsFiltered") private var isFilteredAvatar = false
    @State private var energyLevel: EnergyLevel = .med
    @State private var socialBattery: SocialBattery = .some
    @State private var morningStackLogged = false
    @State private var showBreathing = false
    @State private var aiDailyBrief: String?
    @State private var isLoadingBrief = false
    @State private var checkInSaved = false
    @State private var pendingRoute: AppRoute?
    @State private var showInstallCatalog = false
    @AppStorage("homeModuleOrder") private var moduleOrderData: Data = Data()
    @AppStorage("aiDigestFocus") private var aiDigestFocus: String = "balanced"

    private var moduleOrder: [HomeModule] {
        // Decode loosely as strings so one removed/renamed case doesn't throw away
        // the user's whole custom order. Keep the known ones in their saved order,
        // then append any modules added since (so new modules still appear).
        let stored = (try? JSONDecoder().decode([String].self, from: moduleOrderData)) ?? []
        let known = stored.compactMap(HomeModule.init(rawValue:))
        guard !known.isEmpty else { return HomeModule.allCases }
        return known + HomeModule.allCases.filter { !known.contains($0) }
    }

    private func setModuleOrder(_ order: [HomeModule]) {
        moduleOrderData = (try? JSONEncoder().encode(order)) ?? Data()
    }

    enum HomeModule: String, CaseIterable, Codable, Identifiable {
        case upNext = "Up Next"
        case tasks = "Tasks"
        case rightNow = "Right Now"
        case aiDigest = "AI Digest"
        case checkIn = "Check-in"
        case collections = "Collections"
        case inbox = "Life Inbox"
        case calendar = "Calendar"
        case travel = "Travel"
        var id: String { rawValue }
    }

    enum EnergyLevel: String, CaseIterable, CustomStringConvertible {
        case low = "Low"
        case med = "Med"
        case high = "High"
        var description: String { rawValue }
    }

    enum SocialBattery: String, CaseIterable, CustomStringConvertible {
        case drained = "Drained"
        case some = "Some"
        case full = "Full"
        var description: String { rawValue }
    }

    private var userName: String { profiles.first?.name ?? "there" }

    /// The soonest upcoming (non-cancelled, non-past) trip, for the Home Travel card.
    private var nextTrip: Trip? {
        let now = Calendar.current.startOfDay(for: Date())
        return trips
            .filter { $0.status != .cancelled && $0.status != .completed && (($0.endDate ?? .distantFuture) >= now) }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    /// Real consecutive-day streak of any logged medication, counting back from today.
    private var loggingStreakDays: Int {
        let cal = Calendar.current
        let loggedDays = Set(medicationLogs.map { cal.startOfDay(for: $0.loggedAt) })
        guard !loggedDays.isEmpty else { return 0 }
        var streak = 0
        var day = cal.startOfDay(for: Date())
        // Allow the streak to count even if today hasn't been logged yet.
        if !loggedDays.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while loggedDays.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                homeHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                VStack(spacing: 14) {
                    searchBar
                        .padding(.horizontal, 16)

                    feedToggleRow
                        .padding(.horizontal, 16)

                    if isCustomizing {
                        customizeList
                            .padding(.horizontal, 16)
                    } else {
                        if SubAppRegistry.shared.installedIDs.isEmpty {
                            emptyShellCard
                                .padding(.horizontal, 16)
                        }
                        feedContent
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .refreshable { await coordinator.pullToRefresh() }
        .sheet(isPresented: $showSidebar) {
            SidebarView(path: $path)
        }
        .fullScreenCover(isPresented: $showCommandPalette, onDismiss: {
            if let route = pendingRoute {
                pendingRoute = nil
                path.append(route)
            }
        }) {
            CoachView(onDismiss: { showCommandPalette = false })
        }
        .sheet(isPresented: $showBreathing) {
            BreathingExerciseView()
        }
        .fullScreenCover(isPresented: $showInstallCatalog) {
            NavigationStack {
                ModulePickerView(isOnboarding: false)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showInstallCatalog = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            AvatarPhotoPickerView(existingAvatarData: profiles.first?.avatarData) { processedData, isFiltered in
                if let profile = profiles.first {
                    profile.avatarData = processedData
                    try? modelContext.save()
                }
                isFilteredAvatar = isFiltered
            }
        }
    }

    // MARK: - Header

    private var homeHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Button { showSidebar = true } label: {
                    HStack(spacing: 6) {
                        Text("\(userName)'s Brain")
                            .font(PulseFont.bodySemibold(14))
                            .foregroundStyle(PulseColors.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
                .buttonStyle(.plain)

                Text(dayString())
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textMuted)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(greetingForHour()),")
                        .font(PulseFont.title(28))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(userName)
                        .font(PulseFont.title(28))
                        .foregroundStyle(PulseColors.textPrimary)
                }
            }

            Spacer()

            profileAvatar
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        let size: CGFloat = 88
        if let data = profiles.first?.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
                .if(colorScheme == .dark && isFilteredAvatar) { view in
                    view.colorInvert()
                }
                .onTapGesture { showPhotoPicker = true }
                .accessibilityLabel("Profile photo")
                .accessibilityHint("Double tap to change")
                .accessibilityAddTraits(.isButton)
        } else {
            Button { showPhotoPicker = true } label: {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PulseColors.fillSubtle)
                    .frame(width: size, height: size)
                    .overlay {
                        Text(String(userName.prefix(1)).uppercased())
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(PulseColors.borderHairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add profile photo")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        Button {
            HapticService.impact(.light)
            showCommandPalette = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Capture, log a meal, or ask AI…")
                    .font(PulseFont.body(15))
                    .foregroundStyle(PulseColors.textMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(PulseColors.fillMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.03), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture, log a meal, or ask AI")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Feed / Grid Toggle

    private var feedToggleRow: some View {
        HStack(spacing: 12) {
            Text("A calm daily feed")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textMuted)
            Spacer()
            Button { withAnimation(.snappy) { isCustomizing.toggle() } } label: {
                Text(isCustomizing ? "Done" : "Customize")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PulseColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(PulseColors.borderStrong, lineWidth: 1)
                    }
            }
        }
    }

    // MARK: - Feed Content (ordered modules)

    private var feedContent: some View {
        VStack(spacing: 14) {
            ForEach(moduleOrder.filter { shouldShowModule($0) }) { module in
                moduleView(for: module)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// Shown when the user has no modules installed — the "personal app store" empty
    /// shell. Invites them to open the catalog and install their first module.
    private var emptyShellCard: some View {
        PulseCard(padding: 24, radius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PulseColors.accent.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(PulseColors.accent)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("home.empty.title", comment: "Home empty-state title")
                        .font(PulseFont.titleMedium(22))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("home.empty.body", comment: "Home empty-state body")
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                        .lineSpacing(2)
                }
                Button {
                    HapticService.impact(.light)
                    showInstallCatalog = true
                } label: {
                    Text("home.empty.button", comment: "Home empty-state button")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(PulseColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("home.empty.button"))
                .accessibilityHint("Opens the module catalog so you can install features")
                .accessibilityAddTraits(.isButton)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shouldShowModule(_ module: HomeModule) -> Bool {
        switch module {
        case .upNext:
            return !medications.isEmpty
        case .tasks:
            return !allTasks.isEmpty
        case .rightNow:
            let amMeds = medications.filter { $0.timing == "AM" }
            return !amMeds.isEmpty && !morningStackLogged
        case .aiDigest:
            return !medications.isEmpty || !meals.isEmpty
        case .checkIn:
            return !checkInSaved
        case .collections:
            return true
        case .inbox:
            return !inboxItems.isEmpty
        case .calendar:
            return true
        case .travel:
            return SubAppRegistry.shared.isInstalled(SubAppID(AppModule.travel.rawValue)) && nextTrip != nil
        }
    }

    // MARK: - Customize List

    private var customizeList: some View {
        let removedModules = HomeModule.allCases.filter { module in
            !moduleOrder.contains(where: { $0 == module })
        }

        return VStack(spacing: 6) {
            ForEach(Array(moduleOrder.enumerated()), id: \.element.id) { index, module in
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulseColors.textFaint)

                    Text(module.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PulseColors.textPrimary)

                    Spacer()

                    HStack(spacing: 6) {
                        Button { moveModule(index, direction: -1) } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(index > 0 ? PulseColors.textSecondary : PulseColors.textFaint)
                                .frame(width: 44, height: 44)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                        }
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(module.rawValue) up")

                        Button { moveModule(index, direction: 1) } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(index < moduleOrder.count - 1 ? PulseColors.textSecondary : PulseColors.textFaint)
                                .frame(width: 44, height: 44)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                        }
                        .disabled(index >= moduleOrder.count - 1)
                        .accessibilityLabel("Move \(module.rawValue) down")

                        Button { removeModule(at: index) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PulseColors.textMuted)
                                .frame(width: 44, height: 44)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                        }
                        .accessibilityLabel("Remove \(module.rawValue)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(PulseColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            }

            if !removedModules.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REMOVED")
                        .font(PulseFont.bodyMedium(11))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.8)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    ForEach(removedModules) { module in
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PulseColors.textSecondary)

                            Text(module.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PulseColors.textSecondary)

                            Spacer()

                            Button { addModule(module) } label: {
                                Text("Add")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(PulseColors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(PulseColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(PulseColors.borderHairline.opacity(0.5), lineWidth: 1)
                        }
                    }
                }
            }
        }
    }

    private func moveModule(_ index: Int, direction: Int) {
        var order = moduleOrder
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < order.count else { return }
        order.swapAt(index, newIndex)
        withAnimation(.snappy(duration: 0.2)) { setModuleOrder(order) }
    }

    private func removeModule(at index: Int) {
        var order = moduleOrder
        guard order.count > 1 else { return }
        order.remove(at: index)
        withAnimation(.snappy(duration: 0.2)) { setModuleOrder(order) }
    }

    private func addModule(_ module: HomeModule) {
        var order = moduleOrder
        order.append(module)
        withAnimation(.snappy(duration: 0.2)) { setModuleOrder(order) }
    }

    @ViewBuilder
    private func moduleView(for module: HomeModule) -> some View {
        switch module {
        case .rightNow: rightNowSection
        case .upNext: upNextSection
        case .tasks: inlineTasksSection
        case .aiDigest: aiDailyDigestCard
        case .checkIn: checkInCard
        case .collections: collectionsSection
        case .inbox: lifeInboxCard
        case .calendar: calendarSyncCard
        case .travel: travelSection
        }
    }

    // MARK: - Travel

    @ViewBuilder private var travelSection: some View {
        if let trip = nextTrip {
            VStack(alignment: .leading, spacing: 10) {
                Text("UPCOMING TRIP")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)

                Button {
                    path.append(AppRoute.tripDetail(trip.id))
                } label: {
                    PulseCard(padding: 20, radius: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "airplane")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(PulseColors.accent)
                                Text(trip.destination)
                                    .font(PulseFont.titleMedium(20))
                                    .foregroundStyle(PulseColors.textPrimary)
                                Spacer()
                                if let countdown = countdownLabel(trip) {
                                    Text(countdown)
                                        .font(PulseFont.bodyMedium(12))
                                        .foregroundStyle(PulseColors.textSecondary)
                                }
                            }
                            if let start = trip.startDate {
                                let range = trip.endDate.map { "\(homeDate(start)) – \(homeDate($0))" } ?? homeDate(start)
                                Text(range)
                                    .font(PulseFont.body(13))
                                    .foregroundStyle(PulseColors.textSecondary)
                            }
                            HStack(spacing: 14) {
                                Label("\(trip.items.count) plans", systemImage: "list.bullet")
                                    .font(PulseFont.body(12))
                                    .foregroundStyle(PulseColors.textMuted)
                                if trip.estimatedCost > 0 {
                                    Spacer()
                                    Text(homeMoney(trip.estimatedCost, trip.effectiveCurrency))
                                        .font(PulseFont.bodySemibold(13))
                                        .foregroundStyle(PulseColors.textPrimary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func countdownLabel(_ trip: Trip) -> String? {
        guard let start = trip.startDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: start)).day ?? 0
        if days > 0 { return "in \(days)d" }
        if days == 0 { return "today" }
        return nil
    }

    private func homeDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }

    private func homeMoney(_ amount: Double, _ currency: String) -> String {
        let symbol: String
        switch currency.uppercased() {
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        case "JPY": symbol = "¥"
        default: symbol = currency.uppercased() + " "
        }
        return symbol + (amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(format: "%.0f", amount))
    }

    // MARK: - Right Now

    private var rightNowSection: some View {
        let amMeds = medications.filter { $0.timing == "AM" }

        return VStack(alignment: .leading, spacing: 10) {
            Text("RIGHT NOW")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            PulseCard(padding: 20, radius: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Circle().fill(morningStackLogged ? PulseColors.success : PulseColors.accent).frame(width: 7, height: 7)
                        Text(morningStackLogged ? "DONE" : "JUST THIS ONE THING")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                    }

                    Text(morningStackLogged ? "Morning stack logged ✓" : "Take your morning stack")
                        .font(PulseFont.titleMedium(22))
                        .foregroundStyle(PulseColors.textPrimary)

                    Text("\(amMeds.count) items · 2 minutes · then you're set until lunch")
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)

                    if !morningStackLogged {
                        HStack(spacing: 8) {
                            Button { logMorningStack() } label: {
                                Text("Start")
                                    .font(PulseFont.bodySemibold(15))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(PulseColors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                            }
                            Button {
                                HapticService.impact(.light)
                                morningStackLogged = true
                            } label: {
                                Text("Not now")
                                    .font(PulseFont.bodySemibold(15))
                                    .foregroundStyle(PulseColors.textSecondary)
                                    .padding(.horizontal, 16)
                                    .frame(height: 44)
                                    .background(PulseColors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                                            .stroke(PulseColors.borderStrong, lineWidth: 1)
                                    }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func logMorningStack() {
        let amMeds = medications.filter { $0.timing == "AM" }
        for med in amMeds {
            modelContext.insert(MedicationLog(medicationId: med.id, status: .taken))
        }
        try? modelContext.save()
        HapticService.success()
        withAnimation { morningStackLogged = true }
    }

    // MARK: - Up Next

    private var upNextSection: some View {
        let amMeds = medications.filter { $0.timing == "AM" }
        let pmMeds = medications.filter { $0.timing == "PM" }
        let amNames = amMeds.prefix(3).map(\.name).joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("UP NEXT")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Button {
                    onSwitchTab?(.tracker)
                } label: {
                    Text("Open tracker →")
                        .font(PulseFont.bodyMedium(13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                if !amMeds.isEmpty {
                    UpNextRow(time: "Morning", icon: "pills.fill", title: amNames, subtitle: "Medication & supplements")
                }
                if let nextTask = allTasks.first(where: { $0.group == "Today" && $0.status != .done }) {
                    UpNextRow(time: "Today", icon: "checklist", title: nextTask.title, subtitle: nextTask.label ?? "Task")
                }
                if let pm = pmMeds.first(where: { $0.category == .peptide }) {
                    UpNextRow(time: "Evening", icon: "syringe.fill", title: "\(pm.name)  -  \(pm.dose.components(separatedBy: " ·").first ?? "")", subtitle: "Peptide · before bed")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Inline Tasks

    private var inlineTasksSection: some View {
        let todayTasks = allTasks.filter { $0.group == "Today" }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY · \(todayTasks.count) TASKS")
                    .font(PulseFont.bodySemibold(11.5))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
                    .textCase(.uppercase)
                Spacer()
                Button { showCommandPalette = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PulseColors.textMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add task")
            }

            VStack(spacing: 0) {
                ForEach(todayTasks.prefix(5)) { task in
                    Button { toggleTask(task) } label: {
                        HomeTaskRow(title: task.title, isDone: task.status == .done, chip: task.label ?? "", chipStyle: task.label == "Today" ? .alert : .normal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleTask(_ task: TaskItem) {
        let willComplete = task.status != .done
        withAnimation {
            task.status = task.status == .done ? .todo : .done
            task.updatedAt = Date()
            try? modelContext.save()
        }
        if willComplete {
            HapticService.success()
        } else {
            HapticService.impact(.light)
        }
    }

    // MARK: - AI Daily Digest

    private var aiDailyDigestCard: some View {
        let todayCals = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }.reduce(0) { $0 + $1.calories }
        let amMeds = medications.filter { $0.timing == "AM" }
        let medNames = amMeds.prefix(3).map(\.name).joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                    .accessibilityHidden(true)
                Text("AI daily digest")
                    .font(PulseFont.bodySemibold(11.5))
                    .foregroundStyle(PulseColors.textPrimary)
                    .tracking(0.4)
                Spacer()
                Menu {
                    ForEach(["balanced", "nutrition", "supplements", "sleep", "productivity"], id: \.self) { focus in
                        Button {
                            aiDigestFocus = focus
                            aiDailyBrief = nil
                            loadAIDailyBrief()
                        } label: {
                            HStack {
                                Text(focus.capitalized)
                                if aiDigestFocus == focus {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(aiDigestFocus.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PulseColors.fillSubtle)
                    .clipShape(Capsule())
                }
                if isLoadingBrief {
                    ProgressView().controlSize(.mini)
                }
            }

            if let brief = aiDailyBrief {
                Text(brief)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textSecondary)
                    .lineSpacing(14 * 0.55)
            } else {
                let medsClause = medNames.isEmpty ? "" : "Morning stack is due (\(medNames)). "
                Text("\(medsClause)You logged **\(todayCals > 0 ? "\(todayCals)" : "0") kcal** today.")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textSecondary)
                    .lineSpacing(14 * 0.55)
            }

            HStack(spacing: 10) {
                Button { logMorningStack() } label: {
                    Text("Log morning stack")
                        .font(PulseFont.bodySemibold(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(PulseColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                }
                Button { showCommandPalette = true } label: {
                    Text("Ask AI")
                        .font(PulseFont.bodySemibold(13))
                        .foregroundStyle(PulseColors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(PulseColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous)
                                .stroke(PulseColors.borderHairline, lineWidth: 1)
                        }
                }
            }
        }
        .padding(15)
        .background(
            ZStack {
                PulseColors.fillSubtle
                RadialGradient(colors: [PulseColors.accent.opacity(0.05), Color.clear], center: .topTrailing, startRadius: 0, endRadius: 200)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
        .onAppear { loadAIDailyBrief() }
    }

    private func loadAIDailyBrief() {
        if aiDailyBrief == nil, let cached = UserDefaults.standard.string(forKey: "cachedDailyBrief"),
           let cachedDate = UserDefaults.standard.object(forKey: "cachedBriefDate") as? Date,
           Calendar.current.isDateInToday(cachedDate) {
            aiDailyBrief = cached
            return
        }
        guard aiDailyBrief == nil else { return }
        isLoadingBrief = true
        Task {
            let hour = Calendar.current.component(.hour, from: Date())
            let timeStr = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
            let todayMeals = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }
            let cals = todayMeals.reduce(0) { $0 + $1.calories }

            let context = AIService.UserContext(
                name: userName,
                timeOfDay: timeStr,
                medicationsDue: medications.filter { $0.isActive && $0.timing == "AM" }.map(\.name),
                pendingTasks: allTasks.filter { $0.statusRaw == "todo" }.prefix(5).map(\.title),
                recentMeals: todayMeals.prefix(3).map(\.name),
                caloriesToday: cals,
                streakDays: loggingStreakDays
            )

            let brief = await AIService.shared.generateDailyBrief(context: context, focus: aiDigestFocus)
            aiDailyBrief = brief
            isLoadingBrief = false
            UserDefaults.standard.set(brief, forKey: "cachedDailyBrief")
            UserDefaults.standard.set(Date(), forKey: "cachedBriefDate")
        }
    }

    // MARK: - Check-in

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("CHECK-IN")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
            }

            Text("How are you feeling right now?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PulseColors.textPrimary)

            HStack(spacing: 10) {
                moodButton(icon: "cloud.rain", label: "Low", selected: energyLevel == .low) { energyLevel = .low; showSavedFeedback() }
                moodButton(icon: "sun.haze", label: "Okay", selected: energyLevel == .med) { energyLevel = .med; showSavedFeedback() }
                moodButton(icon: "sun.max", label: "Great", selected: energyLevel == .high) { energyLevel = .high; showSavedFeedback() }
            }

            if checkInSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.success)
                    Text("Saved")
                        .font(PulseFont.bodySmall)
                        .foregroundStyle(PulseColors.success)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if energyLevel == .low {
                HStack(spacing: 10) {
                    Image(systemName: "wind")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.textMuted)
                        .accessibilityHidden(true)
                    Text("Feeling low? A minute of slow breathing can help reset.")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .padding(12)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))

                Button { showBreathing = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wind")
                            .font(.system(size: 14, weight: .medium))
                        Text("60s breathing exercise")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(PulseColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Social battery")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
                HStack(spacing: 10) {
                    socialButton(label: "Need space", selected: socialBattery == .drained) { socialBattery = .drained; showSavedFeedback() }
                    socialButton(label: "Selective", selected: socialBattery == .some) { socialBattery = .some; showSavedFeedback() }
                    socialButton(label: "Social", selected: socialBattery == .full) { socialBattery = .full; showSavedFeedback() }
                }
            }
        }
        .padding(18)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: energyLevel)
        .animation(.easeInOut(duration: 0.2), value: checkInSaved)
    }

    private func moodButton(icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selected ? PulseColors.textPrimary : PulseColors.textMuted)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? PulseColors.textPrimary : PulseColors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selected ? PulseColors.fillSubtle : PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                    .stroke(selected ? PulseColors.borderStrong : PulseColors.borderHairline, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Energy: \(label)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func socialButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? PulseColors.textPrimary : PulseColors.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? PulseColors.fillSubtle : PulseColors.background)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous)
                        .stroke(selected ? PulseColors.borderStrong : PulseColors.borderHairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Social battery: \(label)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func showSavedFeedback() {
        let energyInt: Int = { switch energyLevel { case .low: return 2; case .med: return 3; case .high: return 5 } }()
        let entry = MoodEntry(mood: energyInt, energy: energyInt)
        modelContext.insert(entry)
        try? modelContext.save()
        HapticService.success()
        withAnimation(.easeInOut(duration: 0.2)) { checkInSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) { checkInSaved = false }
        }
    }

    // MARK: - Collections

    private var collectionsSection: some View {
        let modules = ModuleManager.shared
        let medCount = medications.count
        let suppCount = medications.filter { $0.category == .supplement || $0.category == .vitamin }.count
        let peptideCount = medications.filter { $0.category == .peptide }.count
        let todayCals = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }.reduce(0) { $0 + $1.calories }
        let todayTasks = allTasks.filter { $0.group == "Today" }
        let doneTasks = todayTasks.filter { $0.status == .done }.count
        let hasMeals = !meals.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            Text("COLLECTIONS")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if modules.isEnabled(.dayPlan) {
                    Button { path.append(AppRoute.dayPlan) } label: {
                        CollectionCard(icon: "calendar", title: "Today's Plan", subtitle: "View schedule")
                    }
                    .buttonStyle(.plain)
                }

                if modules.isEnabled(.nutrition) {
                    Button {
                        onSwitchTab?(.tracker)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .trackerSegmentRequest, object: "Meals")
                        }
                    } label: {
                        CollectionCard(icon: "fork.knife", title: "Meals", subtitle: hasMeals ? "\(todayCals) / 2,200 kcal" : "Log your first meal")
                    }
                    .buttonStyle(.plain)
                }

                if modules.isEnabled(.notes) {
                    Button { path.append(AppRoute.notesList) } label: {
                        CollectionCard(icon: "doc.text", title: "Notes", subtitle: "\(notes.count) pages")
                    }
                    .buttonStyle(.plain)
                }

                if modules.isEnabled(.tasks) {
                    Button { path.append(AppRoute.tasksList) } label: {
                        CollectionCard(icon: "checklist", title: "Tasks", subtitle: "\(doneTasks)/\(todayTasks.count) done today")
                    }
                    .buttonStyle(.plain)
                }

                if modules.isEnabled(.protocol_) {
                    Button {
                        onSwitchTab?(.tracker)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .trackerSegmentRequest, object: "Protocol")
                        }
                    } label: {
                        CollectionCard(icon: "pills.fill", title: "Protocol", subtitle: "\(medCount - suppCount - peptideCount) meds · \(suppCount) supps · \(peptideCount) peptides")
                    }
                    .buttonStyle(.plain)
                }

                if modules.isEnabled(.sleep) {
                    Button { path.append(AppRoute.sleep) } label: {
                        CollectionCard(icon: "moon.fill", title: "Sleep", subtitle: "Last night's score")
                    }
                    .buttonStyle(.plain)
                }

                if modules.isEnabled(.accountability) {
                    Button { onSwitchTab?(.friends) } label: {
                        CollectionCard(icon: "flame.fill", title: "Accountability", subtitle: "Streaks & goals")
                    }
                    .buttonStyle(.plain)
                }

                if modules.isEnabled(.workouts) {
                    Button { path.append(AppRoute.fitness) } label: {
                        CollectionCard(icon: "dumbbell.fill", title: "Fitness", subtitle: "Workouts & strength")
                    }
                    .buttonStyle(.plain)
                }

                Button { path.append(AppRoute.journal) } label: {
                    CollectionCard(icon: "book.closed.fill", title: "Journal", subtitle: "Daily check-in")
                }
                .buttonStyle(.plain)

                Button { path.append(AppRoute.knowledgeBase) } label: {
                    CollectionCard(icon: "sparkles", title: "AI Insights", subtitle: "What PulseLoop learned")
                }
                .buttonStyle(.plain)

                Button { path.append(AppRoute.insights) } label: {
                    CollectionCard(icon: "chart.line.uptrend.xyaxis", title: "Insights", subtitle: "Streaks & trends")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Life Inbox

    private var lifeInboxCard: some View {
        Button { path.append(AppRoute.inbox) } label: {
            HStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 16))
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Life inbox")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("\(inboxItems.count) items sorted from your accounts")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                if !inboxItems.isEmpty {
                    Text("\(inboxItems.count)")
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(PulseColors.accent)
                        .clipShape(Circle())
                }
            }
            .padding(14)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar Sync

    private var calendarSyncCard: some View {
        Button { path.append(AppRoute.connectAccounts) } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendar")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("Connect to see events here")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Connect")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(PulseColors.fillSubtle)
                .clipShape(Capsule())
            }
            .padding(14)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func dayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

// MARK: - Up Next Row

struct UpNextRow: View {
    let time: String
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Text(time)
                .font(PulseFont.bodyMedium(13))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 42, alignment: .leading)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 30, height: 30)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(subtitle)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
        }
    }
}

// MARK: - Home Task Row

struct HomeTaskRow: View {
    let title: String
    let isDone: Bool
    let chip: String
    let chipStyle: TaskChipStyle

    enum TaskChipStyle {
        case normal
        case alert
    }

    var body: some View {
        HStack(spacing: 12) {
            if isDone {
                Circle()
                    .fill(PulseColors.accent)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
            } else {
                Circle()
                    .stroke(PulseColors.borderStrong, lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            }

            Text(title)
                .font(PulseFont.body(15))
                .foregroundStyle(isDone ? PulseColors.textMuted : PulseColors.textPrimary)
                .strikethrough(isDone, color: PulseColors.textMuted)

            Spacer()

            if !chip.isEmpty {
                Text(chip)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(chipStyle == .alert ? PulseColors.alert : PulseColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(chipStyle == .alert ? PulseColors.alert.opacity(0.12) : PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(minHeight: PulseLayout.minTapTarget)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isDone ? "Completed" : "Not completed")
        .accessibilityHint("Double tap to toggle")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Collection Card

struct CollectionCard: View {
    let icon: String
    let title: String
    let subtitle: String

    init(emoji: String, title: String, subtitle: String) {
        self.icon = CollectionCard.sfSymbol(for: title)
        self.title = title
        self.subtitle = subtitle
    }

    init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    private static func sfSymbol(for title: String) -> String {
        switch title.lowercased() {
        case "notes": return "doc.text"
        case "protocol": return "pills.fill"
        case "journal": return "book.closed.fill"
        case "goals": return "target"
        case "health": return "heart.fill"
        case "people": return "person.2"
        case "bookmarks": return "bookmark.fill"
        case "travel": return "airplane"
        case "money": return "creditcard"
        default: return "folder"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
            Text(title)
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textPrimary)
            Text(subtitle)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }
}