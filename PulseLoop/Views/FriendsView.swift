import SwiftUI
import SwiftData
import UserNotifications

struct FriendsView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @AppStorage("friendsHiddenSections") private var hiddenSectionsData: Data = Data()
    @AppStorage("friendsSectionOrder") private var sectionOrderData: Data = Data()
    @State private var isCustomizing = false
    @State private var showWishlistSheet = false
    @State private var selectedWishlist: Wishlist?
    @State private var showAddEventSheet = false

    @Query(sort: \ActivitySession.startedAt, order: .reverse) private var sessions: [ActivitySession]
    @Query(sort: \MedicationLog.loggedAt, order: .reverse) private var medLogs: [MedicationLog]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moodEntries: [MoodEntry]
    @Query(sort: \Wishlist.createdAt, order: .reverse) private var wishlists: [Wishlist]
    @Query(filter: #Predicate<Vice> { $0.isActive }, sort: \Vice.quitDate) private var vices: [Vice]

    @State private var showAddViceSheet = false
    @State private var showLogUrgeSheet = false
    @State private var selectedVice: Vice?
    @State private var detailVice: Vice?
    @State private var aiMotivations: [UUID: String] = [:]
    @State private var editingVice: Vice?

    enum FriendsSection: String, CaseIterable, Identifiable {
        case streaks = "Streaks"
        case quitProgram = "Quit Program"
        case activityStreak = "Activity"
        case goals = "Goals"
        case moodTrend = "Mood Trend"
        case wishlists = "Wishlists"
        case milestones = "Milestones"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .streaks: return "flame.fill"
            case .quitProgram: return "xmark.circle.fill"
            case .activityStreak: return "figure.walk"
            case .goals: return "target"
            case .moodTrend: return "chart.line.uptrend.xyaxis"
            case .wishlists: return "gift"
            case .milestones: return "trophy"
            }
        }
    }

    private var hiddenSections: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: hiddenSectionsData)) ?? []
    }

    private var sectionOrder: [FriendsSection] {
        if let decoded = try? JSONDecoder().decode([String].self, from: sectionOrderData) {
            let sections = decoded.compactMap { FriendsSection(rawValue: $0) }
            if !sections.isEmpty { return sections }
        }
        return FriendsSection.allCases.filter { !hiddenSections.contains($0.rawValue) }
    }

    private func setSectionOrder(_ order: [FriendsSection]) {
        sectionOrderData = (try? JSONEncoder().encode(order.map(\.rawValue))) ?? Data()
    }

    private func isSectionVisible(_ section: FriendsSection) -> Bool {
        sectionOrder.contains(section)
    }

    private func toggleSection(_ section: FriendsSection) {
        var hidden = hiddenSections
        if hidden.contains(section.rawValue) {
            hidden.remove(section.rawValue)
        } else {
            hidden.insert(section.rawValue)
        }
        hiddenSectionsData = (try? JSONEncoder().encode(hidden)) ?? Data()
    }

    private func moveSection(_ index: Int, direction: Int) {
        var order = sectionOrder
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < order.count else { return }
        order.swapAt(index, newIndex)
        withAnimation(.snappy(duration: 0.2)) { setSectionOrder(order) }
        HapticService.impact(.light)
    }

    private func removeSection(at index: Int) {
        var order = sectionOrder
        let removed = order.remove(at: index)
        var hidden = hiddenSections
        hidden.insert(removed.rawValue)
        hiddenSectionsData = (try? JSONEncoder().encode(hidden)) ?? Data()
        withAnimation(.snappy(duration: 0.2)) { setSectionOrder(order) }
        HapticService.impact(.light)
    }

    private func addSection(_ section: FriendsSection) {
        var order = sectionOrder
        order.append(section)
        var hidden = hiddenSections
        hidden.remove(section.rawValue)
        hiddenSectionsData = (try? JSONEncoder().encode(hidden)) ?? Data()
        withAnimation(.snappy(duration: 0.2)) { setSectionOrder(order) }
        HapticService.impact(.light)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                accountabilityHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                if isCustomizing {
                    friendsCustomizeList
                        .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 20) {
                        ForEach(sectionOrder) { section in
                            sectionView(for: section)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
        .background(PulseColors.background)
        .onAppear { loadMotivations() }
        .sheet(isPresented: $showWishlistSheet) {
            if let wishlist = selectedWishlist {
                WishlistEditSheet(wishlist: wishlist)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showAddEventSheet) {
            AddFriendEventSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddViceSheet) {
            AddViceSheet()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showLogUrgeSheet) {
            if let vice = selectedVice {
                LogUrgeSheet(vice: vice)
                    .presentationDetents([.medium])
            }
        }
        .sheet(item: $detailVice) { vice in
            NavigationStack {
                QuitDetailView(vice: vice)
            }
        }
        .sheet(item: $editingVice) { vice in
            EditViceSheet(vice: vice)
                .presentationDetents([.medium])
        }
    }

    private var friendsCustomizeList: some View {
        let removedSections = FriendsSection.allCases.filter { section in
            !sectionOrder.contains(section)
        }

        return VStack(spacing: 6) {
            ForEach(Array(sectionOrder.enumerated()), id: \.element.id) { index, section in
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulseColors.textFaint)

                    Text(section.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PulseColors.textPrimary)

                    Spacer()

                    HStack(spacing: 6) {
                        Button { moveSection(index, direction: -1) } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(index > 0 ? PulseColors.textSecondary : PulseColors.textFaint)
                                .frame(width: 30, height: 30)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .disabled(index == 0)

                        Button { moveSection(index, direction: 1) } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(index < sectionOrder.count - 1 ? PulseColors.textSecondary : PulseColors.textFaint)
                                .frame(width: 30, height: 30)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .disabled(index >= sectionOrder.count - 1)

                        Button { removeSection(at: index) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PulseColors.textMuted)
                                .frame(width: 30, height: 30)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
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

            if !removedSections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REMOVED")
                        .font(PulseFont.bodyMedium(11))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.8)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    ForEach(removedSections) { section in
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PulseColors.textSecondary)

                            Text(section.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PulseColors.textSecondary)

                            Spacer()

                            Button { addSection(section) } label: {
                                Text("Add")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .padding(.bottom, 100)
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: FriendsSection) -> some View {
        switch section {
        case .streaks: streaksCard
        case .quitProgram: quitProgramSection
        case .activityStreak: activityStreakCard
        case .goals: goalsSection
        case .moodTrend: moodTrendCard
        case .wishlists: wishlistSection
        case .milestones: milestonesSection
        }
    }

    // MARK: - Header

    private var accountabilityHeader: some View {
        HStack {
            Text("Accountability")
                .font(PulseFont.title(32))
                .foregroundStyle(PulseColors.textPrimary)
            Spacer()
            Button { withAnimation(.snappy) { isCustomizing.toggle() } } label: {
                Text(isCustomizing ? "Done" : "Edit")
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
        .padding(.top, 12)
    }

    // MARK: - Streaks Card

    private var streaksCard: some View {
        let medStreak = calculateMedStreak()
        let taskStreak = calculateTaskStreak()
        let quitStreak = vices.first?.currentStreak ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            Text("STREAKS")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            HStack(spacing: 16) {
                streakPill(icon: "pills.fill", value: "\(medStreak)", label: "Protocol", color: .orange)
                streakPill(icon: "checklist", value: "\(taskStreak)", label: "Tasks", color: .blue)
            }
            if quitStreak > 0 {
                HStack(spacing: 16) {
                    streakPill(icon: "xmark.circle.fill", value: "\(quitStreak)", label: "Clean", color: .red)
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
    }

    private func streakPill(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("days")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
        }
        .padding(12)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Activity Streak

    private var activityStreakCard: some View {
        let cal = Calendar.current
        let finishedSessions = sessions.filter { $0.statusRaw == "finished" }
        let sessionDays = Set(finishedSessions.map { cal.startOfDay(for: $0.startedAt) })
        let streak = calculateActivityStreak(sessionDays: sessionDays)
        let todayCount = finishedSessions.filter { cal.isDateInToday($0.startedAt) }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your activity streak")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(streak) days")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { dayOffset in
                    let date = cal.date(byAdding: .day, value: -(6 - dayOffset), to: Date()) ?? Date()
                    let dayStart = cal.startOfDay(for: date)
                    let hasActivity = sessionDays.contains(dayStart)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(hasActivity ? PulseColors.success.opacity(0.8) : PulseColors.fillMuted)
                        .frame(height: 8)
                }
            }

            Text(todayCount > 0 ? "\(todayCount) session\(todayCount == 1 ? "" : "s") logged today" : "No activity logged today — get moving!")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .background(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Goals

    private var goalsSection: some View {
        let todayTasks = tasks.filter { $0.group == "Today" }
        let doneTasks = todayTasks.filter { $0.status == .done }
        let completionRate = todayTasks.isEmpty ? 0 : Int(Double(doneTasks.count) / Double(todayTasks.count) * 100)

        return VStack(alignment: .leading, spacing: 12) {
            Text("DAILY GOALS")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            VStack(spacing: 10) {
                goalRow(icon: "checklist", title: "Complete today's tasks", progress: completionRate, detail: "\(doneTasks.count)/\(todayTasks.count) done")
                goalRow(icon: "pills.fill", title: "Take all supplements", progress: protocolCompletionRate, detail: protocolDetail)
                goalRow(icon: "drop.fill", title: "Drink 3L water", progress: hydrationRate, detail: hydrationDetail)
            }
        }
        .padding(18)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func goalRow(icon: String, title: String, progress: Int, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(progress >= 100 ? PulseColors.success : PulseColors.textMuted)
                .frame(width: 32, height: 32)
                .background(progress >= 100 ? PulseColors.successBackground : PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(PulseColors.fillSubtle)
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(progress >= 100 ? PulseColors.success : PulseColors.textSecondary.opacity(0.6))
                            .frame(width: geo.size.width * min(1.0, CGFloat(progress) / 100.0), height: 5)
                    }
                }
                .frame(height: 5)
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    private var protocolCompletionRate: Int {
        let activeMeds = medications.filter(\.isActive)
        guard !activeMeds.isEmpty else { return 0 }
        let cal = Calendar.current
        let todayLogs = medLogs.filter { cal.isDateInToday($0.loggedAt) && $0.statusRaw == "taken" }
        let uniqueTaken = Set(todayLogs.map(\.medicationId)).count
        return Int(Double(uniqueTaken) / Double(activeMeds.count) * 100)
    }

    private var protocolDetail: String {
        let activeMeds = medications.filter(\.isActive)
        let cal = Calendar.current
        let todayLogs = medLogs.filter { cal.isDateInToday($0.loggedAt) && $0.statusRaw == "taken" }
        let uniqueTaken = Set(todayLogs.map(\.medicationId)).count
        return "\(uniqueTaken)/\(activeMeds.count) taken"
    }

    @AppStorage("hydrationCount") private var hydrationGlasses: Int = 0

    private var hydrationRate: Int { min(100, Int(Double(hydrationGlasses) / 8.0 * 100)) }
    private var hydrationDetail: String { "\(String(format: "%.1f", Double(hydrationGlasses) * 0.375))/3.0 L" }

    // MARK: - Mood Trend

    private var moodTrendCard: some View {
        let last7 = Array(moodEntries.prefix(7))

        return VStack(alignment: .leading, spacing: 12) {
            Text("MOOD TREND")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            if last7.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16))
                        .foregroundStyle(PulseColors.textMuted)
                    Text("Check in daily to see your trend")
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .padding(.vertical, 8)
            } else if last7.count < 3 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(last7.reversed(), id: \.id) { entry in
                            Image(systemName: moodEmoji(entry.mood))
                                .font(.system(size: 20))
                                .foregroundStyle(moodColor(entry.mood))
                        }
                    }
                    Text("\(last7.count)/3 check-ins needed for trend")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.textMuted)
                    ProgressView(value: Double(last7.count), total: 3)
                        .tint(PulseColors.accent)
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(last7.reversed(), id: \.id) { entry in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(moodColor(entry.mood))
                                .frame(width: 28, height: CGFloat(entry.mood) * 10)
                            Image(systemName: moodEmoji(entry.mood))
                                .font(.system(size: 10))
                                .foregroundStyle(moodColor(entry.mood))
                        }
                    }
                    Spacer()
                }
                .frame(height: 60, alignment: .bottom)

                let avg = last7.reduce(0) { $0 + $1.mood } / last7.count
                Text("Average mood: \(moodLabel(avg)) · \(last7.count) check-ins this week")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
        .padding(18)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func moodColor(_ mood: Int) -> Color {
        switch mood {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        default: return .green.opacity(0.8)
        }
    }

    private func moodEmoji(_ mood: Int) -> String {
        switch mood {
        case 1: return "cloud.rain.fill"
        case 2: return "cloud.fill"
        case 3: return "cloud.sun.fill"
        case 4: return "sun.max.fill"
        default: return "flame.fill"
        }
    }

    private func moodLabel(_ mood: Int) -> String {
        switch mood {
        case 1: return "Low"
        case 2: return "Okay"
        case 3: return "Good"
        case 4: return "Great"
        default: return "Excellent"
        }
    }

    // MARK: - Wishlists (Personal)

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WISHLISTS")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Button {
                    let newWishlist = Wishlist(title: "New Wishlist", ownerName: "You", isOwn: true)
                    modelContext.insert(newWishlist)
                    selectedWishlist = newWishlist
                    showWishlistSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }

            if wishlists.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "gift")
                        .font(.system(size: 16))
                        .foregroundStyle(PulseColors.textMuted)
                    Text("Track things you want to buy or gift")
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ForEach(wishlists) { wishlist in
                    Button {
                        selectedWishlist = wishlist
                        showWishlistSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gift")
                                .font(.system(size: 14))
                                .foregroundStyle(PulseColors.textMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wishlist.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(PulseColors.textPrimary)
                                Text("\(wishlist.items.count) items")
                                    .font(.system(size: 12))
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        .padding(14)
                        .background(PulseColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PulseColors.borderHairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Quit Program

    private var quitProgramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("QUIT PROGRAM")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Button { showAddViceSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }

            if vices.isEmpty {
                Button { showAddViceSheet = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(PulseColors.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Track something you're quitting")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(PulseColors.textPrimary)
                            Text("Smoking, alcohol, caffeine, or anything else")
                                .font(.system(size: 13))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(PulseColors.accent)
                    }
                    .padding(16)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(vices) { vice in
                    quitCard(vice)
                        .contextMenu {
                            Button { detailVice = vice } label: {
                                Label("View Details", systemImage: "chart.bar")
                            }
                            Button { editingVice = vice } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) { deleteVice(vice) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func quitCard(_ vice: Vice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: vice.emoji.isEmpty ? "nosign" : vice.emoji)
                    .font(.system(size: 20))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(vice.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { detailVice = vice } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulseColors.textMuted)
                        .padding(8)
                }
            }

            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text(cleanTimeDisplay(vice))
                        .font(PulseFont.titleMedium(28))
                        .monospacedDigit()
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(cleanTimeLabel(vice))
                        .font(PulseFont.micro)
                        .foregroundStyle(PulseColors.textMuted)
                }
                if vice.dailyCostSaved > 0 {
                    VStack(spacing: 2) {
                        Text("$\(Int(vice.moneySaved))")
                            .font(PulseFont.titleMedium(28))
                            .monospacedDigit()
                            .foregroundStyle(PulseColors.success)
                        Text("saved")
                            .font(PulseFont.micro)
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
                VStack(spacing: 2) {
                    Text("\(vice.longestStreak)")
                        .font(PulseFont.titleMedium(28))
                        .monospacedDigit()
                        .foregroundStyle(PulseColors.textSecondary)
                    Text("best streak")
                        .font(PulseFont.micro)
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
            }

            if vice.taperSchedule == .gradual, let target = vice.taperCurrentTarget, let unit = vice.taperUnit {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("Tapering: \(Int(target)) \(unit)/day target")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }

            if let motivation = aiMotivations[vice.id] {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseColors.accent)
                        .padding(.top, 2)
                    Text(motivation)
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.textSecondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .background(PulseColors.accent.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                Button {
                    selectedVice = vice
                    showLogUrgeSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text("Log Urge")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(PulseColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(PulseColors.fillSubtle)
                    .clipShape(Capsule())
                }

                Button {
                    logRelapse(vice)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text("I Slipped")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(PulseColors.alert)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(PulseColors.alertBackground)
                    .clipShape(Capsule())
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
    }

    private func cleanTimeDisplay(_ vice: Vice) -> String {
        let hours = Int(Date().timeIntervalSince(vice.quitDate) / 3600)
        if hours < 24 {
            return "\(hours)"
        } else {
            return "\(vice.currentStreak)"
        }
    }

    private func cleanTimeLabel(_ vice: Vice) -> String {
        let hours = Int(Date().timeIntervalSince(vice.quitDate) / 3600)
        if hours < 24 {
            return "hours clean"
        } else {
            return "days clean"
        }
    }

    private func deleteVice(_ vice: Vice) {
        withAnimation {
            modelContext.delete(vice)
            try? modelContext.save()
        }
    }

    private func logRelapse(_ vice: Vice) {
        let log = ViceLog(viceId: vice.id, type: .relapse, intensity: 8)
        modelContext.insert(log)
        vice.logs.append(log)
        try? modelContext.save()
        HapticService.impact(.heavy)
    }

    private func loadMotivations() {
        for vice in vices where aiMotivations[vice.id] == nil {
            Task {
                let prompt = """
                The user says they want to quit "\(vice.name)". First, determine if this is actually harmful (like nicotine, alcohol, drugs, excessive sugar, social media addiction) or if it's something healthy/neutral (like salad, exercise, water, vegetables, reading).

                If it IS harmful: Give ONE short motivational fact (1 sentence, max 20 words) about why quitting it improves their health. Be specific and scientific.

                If it is NOT harmful (it's actually good for them): Say something like "This is actually good for you! [brief reason why]. Consider keeping it." Be honest — don't encourage quitting healthy habits.

                Respond with ONLY the sentence, no quotes or labels.
                """
                do {
                    let messages = [AIService.Message(role: "user", content: prompt)]
                    let response = try await AIService.shared.complete(messages: messages)
                    await MainActor.run {
                        aiMotivations[vice.id] = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } catch {}
            }
        }
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        let totalSessions = sessions.filter { $0.statusRaw == "finished" }.count
        let totalMedLogs = medLogs.filter { $0.statusRaw == "taken" }.count
        let totalTasks = tasks.filter { $0.status == .done }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("MILESTONES")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            HStack(spacing: 10) {
                milestoneCell(value: totalSessions, label: "Workouts", icon: "figure.run", thresholds: [5, 25, 100])
                milestoneCell(value: totalMedLogs, label: "Doses", icon: "pills.fill", thresholds: [10, 50, 200])
                milestoneCell(value: totalTasks, label: "Tasks", icon: "checkmark.circle", thresholds: [10, 50, 200])
            }

            let nextBadge = nextMilestoneBadge(workouts: totalSessions, doses: totalMedLogs, tasks: totalTasks)
            if let badge = nextBadge {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                    Text(badge)
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func milestoneCell(value: Int, label: String, icon: String, thresholds: [Int]) -> some View {
        let badge = thresholds.last(where: { value >= $0 })
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(PulseColors.textMuted)
                if badge != nil {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                        .offset(x: 4, y: -2)
                }
            }
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PulseColors.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func nextMilestoneBadge(workouts: Int, doses: Int, tasks: Int) -> String? {
        let allThresholds: [(String, Int, [Int])] = [
            ("workouts", workouts, [5, 25, 100, 500]),
            ("doses taken", doses, [10, 50, 200, 1000]),
            ("tasks done", tasks, [10, 50, 200, 1000]),
        ]
        var closest: (String, Int)? = nil
        for (label, current, thresholds) in allThresholds {
            if let next = thresholds.first(where: { current < $0 }) {
                let remaining = next - current
                if closest == nil || remaining < closest!.1 {
                    closest = ("\(remaining) more \(label) until next badge", remaining)
                }
            }
        }
        return closest?.0
    }

    // MARK: - Helpers

    private func calculateMedStreak() -> Int {
        let cal = Calendar.current
        let activeMedCount = medications.filter(\.isActive).count
        guard activeMedCount > 0 else { return 0 }
        var streak = 0
        var check = cal.startOfDay(for: Date())
        for _ in 0..<365 {
            guard let endOfDay = cal.date(byAdding: .day, value: 1, to: check) else { break }
            let dayLogs = medLogs.filter { $0.loggedAt >= check && $0.loggedAt < endOfDay && $0.statusRaw == "taken" }
            if Set(dayLogs.map(\.medicationId)).count >= activeMedCount / 2 {
                streak += 1
            } else { break }
            check = cal.date(byAdding: .day, value: -1, to: check) ?? check
        }
        return streak
    }

    private func calculateTaskStreak() -> Int {
        let cal = Calendar.current
        var streak = 0
        var check = cal.startOfDay(for: Date())
        let doneTasks = tasks.filter { $0.status == .done }
        let daysWithCompletion = Set(doneTasks.map { cal.startOfDay(for: $0.updatedAt) })
        while daysWithCompletion.contains(check) {
            streak += 1
            check = cal.date(byAdding: .day, value: -1, to: check) ?? check
        }
        return streak
    }

    private func calculateActivityStreak(sessionDays: Set<Date>) -> Int {
        let cal = Calendar.current
        var streak = 0
        var check = cal.startOfDay(for: Date())
        while sessionDays.contains(check) {
            streak += 1
            check = cal.date(byAdding: .day, value: -1, to: check) ?? check
        }
        return streak
    }
}
// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let seconds = Int(-self.timeIntervalSinceNow)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Wishlist Edit Sheet

struct WishlistEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var wishlist: Wishlist
    @State private var newItemName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Wishlist name", text: $wishlist.title)
                        .font(.system(size: 16, weight: .medium))
                }

                Section("Items") {
                    ForEach(wishlist.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 15))
                                    .strikethrough(item.isClaimed)
                                if let price = item.price {
                                    Text(price)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !wishlist.isOwn {
                                Button {
                                    item.isClaimed.toggle()
                                    item.claimedBy = item.isClaimed ? "You" : nil
                                } label: {
                                    Text(item.isClaimed ? "Claimed" : "Claim")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(item.isClaimed ? .green : .primary)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let item = wishlist.items[index]
                            modelContext.delete(item)
                        }
                        wishlist.items.remove(atOffsets: indexSet)
                    }

                    if wishlist.isOwn {
                        HStack {
                            TextField("Add item...", text: $newItemName)
                                .font(.system(size: 15))
                                .submitLabel(.done)
                                .onSubmit { addItem() }
                            if !newItemName.isEmpty {
                                Button { addItem() } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(wishlist.isOwn ? "Edit Wishlist" : wishlist.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func addItem() {
        guard !newItemName.isEmpty else { return }
        let item = WishlistItem(name: newItemName)
        wishlist.items.append(item)
        newItemName = ""
    }
}

// MARK: - Add Friend Event Sheet

struct AddFriendEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var date = Date()
    @State private var icon = "calendar"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Event name", text: $title)
                DatePicker("Date & Time", selection: $date)
                Picker("Icon", selection: $icon) {
                    Label("Calendar", systemImage: "calendar").tag("calendar")
                    Label("Dinner", systemImage: "fork.knife").tag("fork.knife")
                    Label("Run", systemImage: "figure.run").tag("figure.run")
                    Label("Party", systemImage: "party.popper").tag("party.popper")
                    Label("Movie", systemImage: "film").tag("film")
                }
            }
            .navigationTitle("Plan Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        guard !title.isEmpty else { return }
                        let event = FriendEvent(title: title, icon: icon, date: date)
                        modelContext.insert(event)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Travel Plan Sheet

struct TravelPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var plan: TravelPlan
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(plan.destination, systemImage: "airplane")
                        .font(.system(size: 20, weight: .bold))
                    Text("With \(plan.friendName) · \(plan.startDate.formatted(.dateTime.month().day())) – \(plan.endDate.formatted(.dateTime.month().day()))")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Divider()

                TextField("Add notes or ideas for the trip...", text: $notes, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(4...8)

                Button {
                    plan.hasPlanned = true
                    HapticService.success()
                    dismiss()
                } label: {
                    Text(plan.hasPlanned ? "Planned" : "Mark as planned")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(plan.hasPlanned ? PulseColors.success : PulseColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Trip Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView(path: .constant(NavigationPath()))
    }
}

// MARK: - FriendProfileView

struct FriendProfileView: View {
    let name: String
    let joinedDate: String
    let sharedActivities: Int
    let mutualFriends: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Circle()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 88, height: 88)
                    .overlay {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                    }

                VStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("joined \(joinedDate)")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.textMuted)
                }

                HStack(spacing: 0) {
                    statBox("\(sharedActivities)", "shared")
                    Rectangle().fill(PulseColors.borderHairline).frame(width: 1, height: 40)
                    statBox("\(mutualFriends)", "mutual")
                }
                .padding(.vertical, 14)
                .background(PulseColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            }
            .padding(20)
        }
        .background(PulseColors.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statBox(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(PulseColors.textPrimary)
            Text(label).font(.system(size: 13)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - InviteFriendsView

struct InviteFriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    private let inviteText = "Join me on PulseLoop — your calm, voice-first life OS. https://pulseloop.app/invite"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(PulseColors.textMuted)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Invite friends")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Share your link so friends can join PulseLoop and connect with you.")
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Button { showShare = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                    Text("Share invite link")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .sheet(isPresented: $showShare) { ShareSheet(items: [inviteText]) }

            Spacer()
        }
        .background(PulseColors.background)
        .navigationTitle("Invite")
        .navigationBarTitleDisplayMode(.inline)
    }
}
