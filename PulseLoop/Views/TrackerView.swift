import SwiftUI
import SwiftData

extension Notification.Name {
    static let trackerSegmentRequest = Notification.Name("trackerSegmentRequest")
}

struct TrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RingSyncCoordinator.self) private var coordinator
    @Environment(RingBLEClient.self) private var ble
    // Most-recently-updated first so `devices.first` is the active ring, not an
    // arbitrary row when more than one device has been paired.
    @Query(sort: \Device.updatedAt, order: .reverse) private var devices: [Device]
    @Query(sort: \MealLog.loggedAt, order: .reverse) private var meals: [MealLog]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \MedicationLog.loggedAt, order: .reverse) private var medLogs: [MedicationLog]
    @Query(sort: \Routine.name) private var routines: [Routine]
    @Binding var path: NavigationPath
    @State private var segment: TrackerSegment = .schedule
    @State private var showMealInput = false
    @State private var mealDescription = ""
    @State private var mealEstimate: MealEstimate? = nil
    @State private var isEstimatingMeal = false
    @State private var selectedMedication: Medication?
    @State private var showProductScan = false
    @State private var aiInsightText: String?
    @State private var aiProtocolAnalysis: AIService.ProtocolAnalysis?
    @State private var isLoadingInsight = false
    @State private var showAddProtocol = false
    @State private var showProductSearch = false
    @State private var showAddMeal = false
    @State private var showMealScan = false
    @State private var newItemName = ""
    @State private var newItemDose = ""
    @State private var newItemCategory: MedicationCategory = .supplement
    @State private var newItemTiming = "AM"
    @State private var newItemInstructions = ""
    @State private var newItemCycleLength = ""
    @State private var newItemFrequency = "Daily"
    @State private var newItemInjectionSite = ""
    @State private var newItemStorage = ""
    @State private var newItemVialSize = ""
    @State private var newItemBacWater = ""
    @State private var showProtocolCamera = false
    @State private var isScanning = false
    @State private var scanError: String? = nil
    @State private var aiLookupResult: AISupplementProfile? = nil
    @State private var isAISearching = false
    @AppStorage("trackerVisibleSegments") private var visibleSegmentsData: Data = Data()

    private var visibleSegments: [TrackerSegment] {
        let saved = (try? JSONDecoder().decode([String].self, from: visibleSegmentsData)) ?? []
        if saved.isEmpty { return relevantSegments }
        return saved.compactMap { raw in TrackerSegment.allCases.first { $0.rawValue == raw } }
    }

    private var relevantSegments: [TrackerSegment] {
        var segments: [TrackerSegment] = [.schedule]
        if !meals.isEmpty { segments.append(.meals) }
        if !medications.isEmpty { segments.append(.protocol_) }
        segments.append(.wellness)
        return segments
    }

    enum TrackerSegment: String, CaseIterable, CustomStringConvertible {
        case schedule = "Schedule"
        case meals = "Meals"
        case protocol_ = "Protocol"
        case wellness = "Wellness"
        var description: String {
            switch self {
            case .protocol_: return "Protocol"
            default: return rawValue
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                trackerHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                VStack(spacing: 14) {
                    segmentedContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .refreshable { await coordinator.pullToRefresh() }
        .sheet(isPresented: $showProductScan) {
            ProductScanView()
        }
        .sheet(isPresented: $showAddProtocol) {
            addProtocolSheet
        }
        .sheet(isPresented: $showAddMeal) {
            addMealSheet
        }
        .sheet(isPresented: $showMealScan) {
            MealScanView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackerSegmentRequest)) { notification in
            if let segName = notification.object as? String,
               let seg = TrackerSegment.allCases.first(where: { $0.rawValue == segName }) {
                withAnimation(.easeInOut(duration: 0.2)) { segment = seg }
            }
        }
        .onAppear {
            if !visibleSegments.contains(segment), let first = visibleSegments.first {
                segment = first
            }
            CustomProductStore.cleanupDuplicates(in: modelContext)
        }
    }

    // MARK: - Header

    private var trackerHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tracker")
                    .font(PulseFont.title(28))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { showProductScan = true } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(PulseColors.fillSubtle)
                        .clipShape(Circle())
                }
                ConnectionStatusPill(state: effectiveState, batteryPercent: effectiveBattery)
            }
            .padding(.top, 8)

            HStack {
                PillToggle(selection: $segment, options: visibleSegments)
                Spacer()
            }
        }
    }

    private var effectiveState: RingConnectionState {
        let liveActive = [RingConnectionState.connected, .connecting, .reconnecting, .scanning].contains(ble.state)
        return liveActive ? ble.state : (devices.first?.state ?? ble.state)
    }
    private var effectiveBattery: Int? {
        ble.batteryPercent ?? devices.first?.batteryPercent
    }

    // MARK: - Devices Card

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DEVICES")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Text("Manage")
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }

            VStack(spacing: 0) {
                DeviceRow(icon: "circle.dotted", name: "Smart Ring", detail: "HR · steps · \(lastSyncLabel)")
                DeviceRow(icon: "applewatch", name: "Apple Watch", detail: "Not paired")
            }
            .padding(14)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
    }

    private var lastSyncLabel: String {
        guard let d = devices.first?.lastSyncAt else { return "never" }
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h"
    }

    // MARK: - Segmented Content

    @ViewBuilder
    private var segmentedContent: some View {
        switch segment {
        case .schedule:
            scheduleView
        case .meals:
            mealsView
        case .protocol_:
            protocolView
        case .wellness:
            wellnessView
        }
    }

    // MARK: Schedule

    private var scheduleView: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button { showAddMeal = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Log")
                            .font(PulseFont.bodySemibold(12))
                    }
                    .foregroundStyle(PulseColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PulseColors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            statCardsGrid
            aiInsightCard
            timelineSection
        }
    }

    private var statCardsGrid: some View {
        let todayMedLogs = medLogs.filter { Calendar.current.isDateInToday($0.loggedAt) }
        let totalMeds = medications.filter { $0.category != .peptide }.count
        let takenMeds = todayMedLogs.count
        let totalPeptides = medications.filter { $0.category == .peptide }.count
        let todayCals = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }.reduce(0) { $0 + $1.calories }

        return HStack(spacing: 10) {
            StatCard(label: "Meds & supps", value: "\(min(takenMeds, totalMeds))/\(totalMeds)")
            StatCard(label: "Peptides", value: "0/\(totalPeptides)")
            StatCard(label: "Calories", value: todayCals > 0 ? "\(todayCals)" : " - ")
        }
    }

    private var aiInsightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("AI INSIGHT")
                        .font(PulseFont.bodyMedium(10))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.6)
                    Spacer()
                    if isLoadingInsight && aiInsightText == nil {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(aiInsightText ?? "Your HRV runs ~12% lower on days you train after 6pm. Tonight's workout is at 17:30  -  good call.")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(UIColor.secondarySystemBackground), Color(UIColor.tertiarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
        .onAppear { loadAIInsight() }
    }

    private func loadAIInsight() {
        guard aiInsightText == nil else { return }
        isLoadingInsight = true
        Task {
            let medsData = medications.filter { $0.isActive }.map { (name: $0.name, dose: $0.dose, timing: $0.timing) }
            if let analysis = await AIService.shared.analyzeProtocolInteractions(medications: medsData) {
                await MainActor.run {
                    aiProtocolAnalysis = analysis
                    if !analysis.timingSuggestions.isEmpty {
                        aiInsightText = analysis.timingSuggestions.first.map { "\($0.item): \($0.suggestion)" }
                    } else {
                        aiInsightText = analysis.summary
                    }
                }
            }
            await MainActor.run {
                isLoadingInsight = false
            }
        }
    }

    private var timelineSection: some View {
        let todayMedLogs = medLogs.filter { Calendar.current.isDateInToday($0.loggedAt) }
        let loggedMedIds = Set(todayMedLogs.map(\.medicationId))
        let todayMealsList = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("TODAY · TIMELINE")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            TimelineContainer {
                ForEach(todayMealsList) { meal in
                    TimelineRow(time: formatTime(meal.loggedAt), icon: mealIcon(meal.name), title: "\(meal.name)  -  \(meal.description_)", subtitle: "\(meal.calories) kcal\(meal.proteinG.map { " · \(Int($0))g protein" } ?? "")", isDone: true)
                }
                let amMeds = medications.filter { $0.timing == "AM" }
                if !amMeds.isEmpty {
                    let amDone = amMeds.allSatisfy { loggedMedIds.contains($0.id) }
                    let amNames = amMeds.prefix(4).map(\.name).joined(separator: " · ")
                    TimelineRow(time: "08:00", icon: "pills.fill", title: "Morning stack  -  \(amMeds.count) items", subtitle: amNames, isDone: amDone)
                }
                let pmMeds = medications.filter { $0.timing == "PM" }
                ForEach(pmMeds) { med in
                    TimelineRow(time: "21:00", icon: iconForCategory(med.category), title: "\(med.name)  -  \(med.dose.components(separatedBy: " ·").first ?? "")", subtitle: med.category == .peptide ? "Peptide · before bed" : "Evening dose", isDone: loggedMedIds.contains(med.id))
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func iconForCategory(_ category: MedicationCategory) -> String {
        switch category {
        case .medication: return "pills.fill"
        case .supplement: return "pills"
        case .vitamin: return "drop.fill"
        case .peptide: return "syringe.fill"
        }
    }

    private func healthBenefitFor(_ med: Medication) -> String? {
        if let supp = SupplementKnowledge.find(med.name) {
            return healthCategoryFromBenefit(supp.benefit, category: supp.category)
        }
        if let peptide = PeptideKnowledge.find(med.name) {
            return healthCategoryFromPeptideCategory(peptide.category)
        }
        if let benefit = med.benefit, !benefit.isEmpty {
            return healthCategoryFromBenefit(benefit, category: "")
        }
        return healthCategoryFromName(med.name)
    }

    private func healthCategoryFromPeptideCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "healing": return "Recovery"
        case "gh secretagogue", "growth-hormone", "growth hormone": return "Growth & Recovery"
        case "weight management", "weight": return "Metabolic"
        case "skin & anti-aging", "skin", "anti-aging", "longevity": return "Anti-Aging"
        case "cognitive", "cognitive & nootropic": return "Brain Health"
        case "immune", "immune support": return "Immune"
        case "sexual health", "sexual-health": return "Hormonal"
        case "hormone", "hormone replacement": return "Hormonal"
        case "muscle growth", "muscle": return "Muscle"
        case "sleep", "sleep & recovery": return "Sleep"
        case "gut health", "gut": return "Gut Health"
        case "cardiovascular": return "Heart Health"
        case "detox", "detox & antioxidant": return "Detox"
        case "pain", "pain & inflammation": return "Pain Relief"
        case "hair", "hair growth": return "Hair & Skin"
        case "fertility": return "Fertility"
        default: return "Wellness"
        }
    }

    private func healthCategoryFromBenefit(_ benefit: String, category: String) -> String {
        let text = (benefit + " " + category).lowercased()
        if text.contains("bone") || text.contains("joint") || text.contains("collagen") { return "Joint & Bone" }
        if text.contains("brain") || text.contains("cogniti") || text.contains("neuro") || text.contains("focus") || text.contains("memory") { return "Brain Health" }
        if text.contains("heart") || text.contains("cardio") || text.contains("blood pressure") || text.contains("cholesterol") { return "Heart Health" }
        if text.contains("immune") || text.contains("infection") { return "Immune" }
        if text.contains("sleep") || text.contains("relax") || text.contains("calm") { return "Sleep" }
        if text.contains("gut") || text.contains("digest") || text.contains("probiotic") { return "Gut Health" }
        if text.contains("skin") || text.contains("hair") || text.contains("nail") || text.contains("anti-aging") { return "Skin & Hair" }
        if text.contains("energy") || text.contains("mitochond") || text.contains("fatigue") { return "Energy" }
        if text.contains("muscle") || text.contains("strength") || text.contains("recovery") { return "Muscle" }
        if text.contains("mood") || text.contains("stress") || text.contains("anxiety") || text.contains("depress") { return "Mood" }
        if text.contains("inflam") { return "Anti-Inflammatory" }
        if text.contains("hormone") || text.contains("thyroid") || text.contains("testosterone") { return "Hormonal" }
        if text.contains("eye") || text.contains("vision") { return "Vision" }
        if text.contains("liver") || text.contains("detox") { return "Detox" }
        if text.contains("weight") || text.contains("metaboli") || text.contains("fat") { return "Metabolic" }
        if text.contains("vitamin") { return "Essential Nutrient" }
        return "Wellness"
    }

    private func healthCategoryFromName(_ name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("omega") || lower.contains("fish oil") || lower.contains("coq10") { return "Heart Health" }
        if lower.contains("magnesium") { return "Sleep & Muscle" }
        if lower.contains("vitamin d") { return "Bone & Immune" }
        if lower.contains("vitamin c") { return "Immune" }
        if lower.contains("vitamin b") || lower.contains("b12") { return "Energy" }
        if lower.contains("zinc") { return "Immune & Skin" }
        if lower.contains("iron") { return "Energy" }
        if lower.contains("calcium") { return "Bone Health" }
        if lower.contains("probio") { return "Gut Health" }
        if lower.contains("collagen") { return "Skin & Joint" }
        if lower.contains("creatine") { return "Muscle & Brain" }
        if lower.contains("melatonin") { return "Sleep" }
        if lower.contains("ashwagandha") { return "Stress & Hormone" }
        if lower.contains("turmeric") || lower.contains("curcumin") { return "Anti-Inflammatory" }
        return nil
    }

    private func mealIcon(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("breakfast") || lower.contains("yogurt") || lower.contains("egg") { return "cup.and.saucer.fill" }
        if lower.contains("lunch") || lower.contains("bowl") || lower.contains("chicken") { return "fork.knife" }
        if lower.contains("dinner") || lower.contains("steak") { return "fork.knife" }
        if lower.contains("snack") || lower.contains("shake") || lower.contains("protein") { return "mug.fill" }
        if lower.contains("coffee") || lower.contains("tea") { return "cup.and.saucer.fill" }
        return "fork.knife"
    }

    private func routineIcon(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("morning") || lower.contains("sunrise") { return "sunrise.fill" }
        if lower.contains("evening") || lower.contains("night") || lower.contains("wind") { return "moon.fill" }
        if lower.contains("workout") || lower.contains("exercise") { return "figure.run" }
        return "clock.fill"
    }

    // MARK: Meals

    private var mealsView: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button { showMealScan = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Snap")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(PulseColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PulseColors.fillSubtle)
                    .clipShape(Capsule())
                }
                Button { showAddMeal = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Log")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(PulseColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PulseColors.fillSubtle)
                    .clipShape(Capsule())
                }
            }
            calorieRingCard
            mealLogSection
            hydrationSection
        }
    }

    private var calorieRingCard: some View {
        let todayMeals = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }
        let totalCal = todayMeals.reduce(0) { $0 + $1.calories }
        let totalProtein = todayMeals.compactMap(\.proteinG).reduce(0, +)
        let totalCarbs = todayMeals.compactMap(\.carbsG).reduce(0, +)
        let totalFat = todayMeals.compactMap(\.fatG).reduce(0, +)
        let calGoal = 2200
        let progress = calGoal > 0 ? min(Double(totalCal) / Double(calGoal), 1.0) : 0

        return VStack(alignment: .leading, spacing: 10) {
            Button { path.append(AppRoute.foodDiary) } label: {
                HStack {
                    Text("NUTRITION")
                        .font(PulseFont.bodyMedium(11))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.8)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("Food Diary")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(PulseColors.fillSubtle, lineWidth: 10)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(PulseColors.calories, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(totalCal)")
                            .font(PulseFont.bodySemibold(16))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("/ \(calGoal)")
                            .font(PulseFont.body(11))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    MacroBar(label: "Protein", value: Int(totalProtein), goal: 160, color: PulseColors.heartRate)
                    MacroBar(label: "Carbs", value: Int(totalCarbs), goal: 200, color: PulseColors.calories)
                    MacroBar(label: "Fat", value: Int(totalFat), goal: 70, color: PulseColors.sleep)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Nutrition today")
            .accessibilityValue("\(totalCal) of \(calGoal) calories. Protein \(Int(totalProtein)) grams, carbs \(Int(totalCarbs)) grams, fat \(Int(totalFat)) grams.")
            .padding(16)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
    }

    @AppStorage("hydrationDate") private var hydrationDate: String = ""
    @AppStorage("hydrationCount") private var hydrationGlasses: Int = 0

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var hydrationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.spo2)
                Text("HYDRATION")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Text("\(String(format: "%.1f", Double(hydrationGlasses) * 0.375)) / 3.0 L")
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textSecondary)
            }

            HStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { index in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            hydrationGlasses = index + 1
                            hydrationDate = todayKey
                        }
                        HapticService.impact(.light)
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index < hydrationGlasses ? PulseColors.spo2 : PulseColors.fillSubtle)
                            .frame(height: 28)
                            .overlay {
                                if index == hydrationGlasses {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(PulseColors.spo2.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                }
                            }
                    }
                    .buttonStyle(.plain)
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
        .onAppear {
            if hydrationDate != todayKey {
                hydrationGlasses = 0
                hydrationDate = todayKey
            }
        }
    }

    private var mealLogSection: some View {
        let todayMeals = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("LOGGED TODAY")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            if todayMeals.isEmpty {
                Button { showAddMeal = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(PulseColors.textMuted)
                        Text("Log your first meal")
                            .font(PulseFont.bodySemibold(14))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("Tap to add or snap a photo")
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(todayMeals) { meal in
                    MealRow(icon: mealIcon(meal.name), name: meal.name, detail: meal.description_, kcal: meal.calories, protein: meal.proteinG.map { "\(Int($0))g P" })
                }
            }

            if showMealInput {
                HStack(spacing: 10) {
                    TextField("Describe what you ate…", text: $mealDescription)
                        .font(PulseFont.body(14))
                        .submitLabel(.done)
                        .onSubmit { logMeal() }
                    Button { logMeal() } label: {
                        Text("Log")
                            .font(PulseFont.bodySemibold(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: { showMealInput.toggle() }) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Describe a meal")
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(PulseColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func logMeal() {
        let desc = mealDescription.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return }
        let meal = MealLog(name: "Meal", description_: desc, emoji: "fork.knife", calories: 0)
        modelContext.insert(meal)
        modelContext.saveOrLog("tracker", surface: true)
        mealDescription = ""
        showMealInput = false
    }

    // MARK: Wellness

    private var wellnessView: some View {
        VStack(spacing: 24) {
            SleepTrackingView()
            MoodTrackingView()
            WorkoutTrackingView()
            BodyMetricsView()
            HabitsTrackingView()
            SymptomsTrackingView()
            LabsTrackingView()
            StressTrackingView()
            MeditationTrackingView()
        }
    }

    // MARK: Protocol

    private var protocolView: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button { showProductSearch = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .bold))
                        Text("Search")
                            .font(PulseFont.bodySemibold(12))
                    }
                    .foregroundStyle(PulseColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PulseColors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Search products")
                Button { showAddProtocol = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(PulseFont.bodySemibold(12))
                    }
                    .foregroundStyle(PulseColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PulseColors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Add to protocol")
            }
            aiProtocolInsights
            if medications.isEmpty {
                Button { showAddProtocol = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(PulseColors.textMuted)
                        Text("Build your protocol")
                            .font(PulseFont.bodySemibold(14))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("Add supplements, medications, or peptides")
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PulseColors.borderHairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            } else {
                routinesSection
                medicationsSection
            }
        }
        .sheet(item: $selectedMedication) { med in
            NavigationStack {
                ProtocolDetailView(medication: med, allMedications: medications)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { selectedMedication = nil } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showProductSearch) {
            ProductSearchView { result in
                adoptSearchResult(result)
            }
        }
    }

    private var aiProtocolInsights: some View {
        let names = medications.map(\.name)
        let allInteractions = SupplementKnowledge.getAllInteractions(forProtocol: names)
        let timingWarnings = allInteractions.filter { $0.kind == .timing || $0.kind == .conflict }
        let synergies = allInteractions.filter { $0.kind == .synergy }
        let suggestions = SupplementKnowledge.getStackSuggestions(forProtocol: names)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.accent)
                Text("AI PROTOCOL INSIGHTS")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
                Spacer()
                if let analysis = aiProtocolAnalysis {
                    HStack(spacing: 3) {
                        Text("\(analysis.overallScore)/10")
                            .font(PulseFont.bodySemibold(11))
                            .foregroundStyle(analysis.overallScore >= 7 ? PulseColors.success : .orange)
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(analysis.overallScore >= 7 ? PulseColors.success : .orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((analysis.overallScore >= 7 ? PulseColors.success : Color.orange).opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if let analysis = aiProtocolAnalysis {
                    if !analysis.summary.isEmpty {
                        Text(analysis.summary)
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.textSecondary)
                            .lineSpacing(2)
                    }

                    ForEach(Array(analysis.synergies.prefix(2).enumerated()), id: \.offset) { _, synergy in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(PulseColors.success)
                            Text("\(synergy.items.joined(separator: " + ")): \(synergy.note)")
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textSecondary)
                                .lineSpacing(2)
                        }
                    }

                    ForEach(Array(analysis.conflicts.prefix(2).enumerated()), id: \.offset) { _, conflict in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                            Text("\(conflict.items.joined(separator: " & ")): \(conflict.note)")
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textSecondary)
                                .lineSpacing(2)
                        }
                    }
                } else {
                    if !synergies.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(PulseColors.success)
                            Text("\(synergies.count) synergies detected in your stack")
                                .font(PulseFont.bodyMedium(13))
                                .foregroundStyle(PulseColors.textPrimary)
                        }
                    }

                    if !timingWarnings.isEmpty {
                        ForEach(Array(timingWarnings.prefix(2).enumerated()), id: \.offset) { _, warning in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                                Text(warning.note)
                                    .font(PulseFont.body(12))
                                    .foregroundStyle(PulseColors.textSecondary)
                                    .lineSpacing(2)
                            }
                        }
                    }

                    if !suggestions.isEmpty {
                        ForEach(Array(suggestions.prefix(2).enumerated()), id: \.offset) { _, suggestion in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(PulseColors.success)
                                Text(suggestion)
                                    .font(PulseFont.body(12))
                                    .foregroundStyle(PulseColors.textSecondary)
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [PulseColors.fillSubtle, PulseColors.background], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROUTINES")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(routines) { routine in
                    let completedSteps = routine.steps.filter(\.completedToday).count
                    let totalSteps = routine.steps.count
                    RoutineGridCard(icon: routineIcon(routine.name), title: routine.name, streak: routine.currentStreak, progress: "\(completedSteps) of \(totalSteps) done")
                }
            }
        }
    }

    private var medicationsSection: some View {
        let meds = medications.filter { $0.category == .medication }
        let supps = medications.filter { $0.category == .supplement || $0.category == .vitamin }
        let peptides = medications.filter { $0.category == .peptide }

        return VStack(spacing: 20) {
            if !meds.isEmpty {
                GroupedProtocolSection(
                    title: "MEDICATIONS",
                    count: "\(meds.count) items",
                    items: meds.map { ProtocolItem(icon: iconForCategory($0.category), name: $0.name, dose: $0.dose, timing: $0.timing, healthBenefit: healthBenefitFor($0)) },
                    onLog: { logMedication($0) },
                    onTap: { item in selectMedication(named: item.name) }
                )
            }

            if !supps.isEmpty {
                GroupedProtocolSection(
                    title: "SUPPLEMENTS & VITAMINS",
                    count: "\(supps.count) items",
                    items: supps.map { ProtocolItem(icon: iconForCategory($0.category), name: $0.name, dose: $0.dose, timing: $0.timing, healthBenefit: healthBenefitFor($0)) },
                    onLog: { logMedication($0) },
                    onTap: { item in selectMedication(named: item.name) }
                )
            }

            if !peptides.isEmpty {
                GroupedProtocolSection(
                    title: "PEPTIDES",
                    count: "\(peptides.count) items",
                    items: peptides.map { ProtocolItem(icon: iconForCategory($0.category), name: $0.name, dose: $0.dose, timing: $0.timing, healthBenefit: healthBenefitFor($0)) },
                    onLog: { logMedication($0) },
                    onTap: { item in selectMedication(named: item.name) }
                )
            }
        }
    }

    private func selectMedication(named name: String) {
        selectedMedication = medications.first(where: { $0.name == name })
    }

    private func logMedication(_ item: ProtocolItem) {
        if let med = medications.first(where: { $0.name == item.name }) {
            let log = MedicationLog(medicationId: med.id, status: .taken)
            modelContext.insert(log)
            modelContext.saveOrLog("tracker", surface: true)
            HapticService.success()
        }
    }

    // MARK: - Add Protocol Sheet

    private var addProtocolSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Button { showProtocolCamera = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isScanning ? "progress.indicator" : "camera.viewfinder")
                                .font(.system(size: 16, weight: .medium))
                            Text(isScanning ? "Scanning..." : "Scan label to auto-fill")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(isScanning ? PulseColors.textMuted : PulseColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PulseColors.borderHairline, lineWidth: 1)
                        }
                    }
                    .disabled(isScanning)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                        TextField(newItemCategory == .peptide ? "e.g. BPC-157" : "e.g. Magnesium Glycinate", text: $newItemName)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if !filteredNameSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(filteredNameSuggestions, id: \.self) { suggestion in
                                        Button {
                                            newItemName = suggestion
                                            if let dose = suggestedDose(for: suggestion) {
                                                newItemDose = dose
                                            }
                                            if let cat = suggestedCategory(for: suggestion) {
                                                newItemCategory = cat
                                            }
                                            autofillPeptideFields(for: suggestion)
                                        } label: {
                                            Text(suggestion)
                                                .font(PulseFont.caption)
                                                .foregroundStyle(PulseColors.textPrimary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(PulseColors.fillSubtle)
                                                .clipShape(Capsule())
                                                .overlay {
                                                    Capsule().stroke(PulseColors.borderHairline, lineWidth: 1)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if filteredNameSuggestions.isEmpty && newItemName.count >= 3 && !isAISearching && aiLookupResult == nil {
                            Button {
                                Task { await aiSearchIngredient(newItemName) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                    Text("Search \"\(newItemName)\" with AI")
                                        .font(PulseFont.bodyMedium(12))
                                }
                                .foregroundStyle(PulseColors.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(PulseColors.accentSoft)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if isAISearching {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Searching...")
                                    .font(PulseFont.body(12))
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                        }

                        if let result = aiLookupResult, result.name.lowercased() == newItemName.lowercased() {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                        .foregroundStyle(PulseColors.accent)
                                    Text("AI found info for \(result.name)")
                                        .font(PulseFont.bodySemibold(12))
                                        .foregroundStyle(PulseColors.accent)
                                }
                                Button {
                                    applyAIResult(result)
                                } label: {
                                    Text("Auto-fill details")
                                        .font(PulseFont.bodyMedium(12))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(PulseColors.accent)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(PulseColors.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dose")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                        TextField(newItemCategory == .peptide ? "e.g. 250mcg" : "e.g. 400mg", text: $newItemDose)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if !filteredDoseSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(filteredDoseSuggestions, id: \.self) { suggestion in
                                        Button {
                                            newItemDose = suggestion
                                        } label: {
                                            Text(suggestion)
                                                .font(PulseFont.caption)
                                                .foregroundStyle(PulseColors.textPrimary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(PulseColors.fillSubtle)
                                                .clipShape(Capsule())
                                                .overlay {
                                                    Capsule().stroke(PulseColors.borderHairline, lineWidth: 1)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                        Picker("Category", selection: $newItemCategory) {
                            Text("Supplement").tag(MedicationCategory.supplement)
                            Text("Vitamin").tag(MedicationCategory.vitamin)
                            Text("Medication").tag(MedicationCategory.medication)
                            Text("Peptide").tag(MedicationCategory.peptide)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                        Picker("Timing", selection: $newItemTiming) {
                            Text("Morning").tag("AM")
                            Text("Evening").tag("PM")
                            Text("Both").tag("AM/PM")
                            if newItemCategory == .peptide {
                                Text("Pre-bed").tag("Pre-bed")
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if newItemCategory == .peptide {
                        peptideExtendedFields
                    }

                    Button { saveNewProtocolItem() } label: {
                        Text("Add to Protocol")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(newItemName.isEmpty ? PulseColors.textMuted : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(newItemName.isEmpty)
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Add to Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddProtocol = false }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: newItemCategory)
            .sheet(isPresented: $showProtocolCamera) {
                ProtocolScanCameraView { image in
                    showProtocolCamera = false
                    scanProtocolLabel(image)
                }
            }
            .alert("Scan issue", isPresented: Binding(get: { scanError != nil }, set: { if !$0 { scanError = nil } })) {
                Button("OK", role: .cancel) { scanError = nil }
            } message: {
                Text(scanError ?? "")
            }
        }
    }

    private func scanProtocolLabel(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }
        isScanning = true
        Task {
            let dataURL = AIService.imageDataURL(imageData)
            let prompt = """
            Look carefully at the actual product in this photo and read any visible label text. Identify the real product — do NOT guess a generic supplement.

            Extract:
            - NAME: the exact product/ingredient name printed on the label (e.g. "Semaglutide", "Magnesium Glycinate"). If you genuinely cannot read a name, use "Unknown".
            - DOSE: dosage/strength shown (e.g. 5mg, 400mg, 250mcg), or empty if not shown
            - CATEGORY: one of: supplement, vitamin, medication, peptide (semaglutide/tirzepatide/BPC-157 etc. are peptide/medication, NOT supplement)
            - CONFIDENCE: high, medium, or low — how sure you are you read the label correctly

            Respond EXACTLY in this format (no markdown, no extra text):
            NAME: [value]
            DOSE: [value]
            CATEGORY: [value]
            TIMING: [AM, PM, or AM/PM]
            CONFIDENCE: [high/medium/low]
            """

            if let result = try? await AIService.shared.complete(
                messages: [
                    AIService.Message(role: "user", text: prompt, imageDataURLs: [dataURL])
                ],
                systemPrompt: "You are a precise supplement/medication label reader. Read the actual text and product in the image. Never invent a product that isn't shown. If the image is not a supplement/medication label, say NAME: Unknown.",
                model: AIModel.vision.resolvedSlug,
                temperature: 0.1,
                maxTokens: 200,
                usageKind: .imageAnalysis
            ) {
                await MainActor.run {
                    var scannedName = ""
                    var lowConfidence = false
                    for line in result.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("NAME:") {
                            scannedName = trimmed.replacingOccurrences(of: "NAME:", with: "").trimmingCharacters(in: .whitespaces)
                        } else if trimmed.hasPrefix("DOSE:") {
                            newItemDose = trimmed.replacingOccurrences(of: "DOSE:", with: "").trimmingCharacters(in: .whitespaces)
                        } else if trimmed.hasPrefix("CATEGORY:") {
                            let cat = trimmed.replacingOccurrences(of: "CATEGORY:", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                            if cat.contains("peptide") { newItemCategory = .peptide }
                            else if cat.contains("vitamin") { newItemCategory = .vitamin }
                            else if cat.contains("medication") { newItemCategory = .medication }
                            else { newItemCategory = .supplement }
                        } else if trimmed.hasPrefix("TIMING:") {
                            let timing = trimmed.replacingOccurrences(of: "TIMING:", with: "").trimmingCharacters(in: .whitespaces)
                            if timing.contains("PM") && timing.contains("AM") { newItemTiming = "AM/PM" }
                            else if timing.contains("PM") { newItemTiming = "PM" }
                            else { newItemTiming = "AM" }
                        } else if trimmed.hasPrefix("CONFIDENCE:") {
                            let conf = trimmed.replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                            lowConfidence = conf.contains("low")
                        }
                    }

                    // Only accept a confidently-read, non-empty, non-"unknown" name.
                    let normalized = scannedName.lowercased()
                    if !scannedName.isEmpty, normalized != "unknown", !lowConfidence {
                        newItemName = scannedName
                    } else {
                        scanError = "Couldn't read the label clearly. Try a closer, well-lit photo or enter it manually."
                    }

                    if !newItemName.isEmpty {
                        if let suppInfo = SupplementKnowledge.find(newItemName) {
                            if newItemDose.isEmpty { newItemDose = suppInfo.defaultDose }
                        } else if let peptideInfo = PeptideKnowledge.find(newItemName) {
                            if newItemDose.isEmpty { newItemDose = peptideInfo.defaultDose }
                            newItemCategory = .peptide
                        }
                    }
                }
            } else {
                await MainActor.run {
                    scanError = "Scan failed. Check your connection and try again, or enter the item manually."
                }
            }
            await MainActor.run { isScanning = false }
        }
    }

    private var peptideExtendedFields: some View {
        VStack(spacing: 16) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 0.5)

            if let info = selectedPeptideInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(PulseColors.accent)
                        Text("About \(info.name)")
                            .font(PulseFont.bodyMedium(12))
                            .foregroundStyle(PulseColors.accent)
                    }
                    Text(info.benefit)
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textPrimary)
                        .lineSpacing(2)
                    if !info.warnings.isEmpty && info.warnings != "No significant side effects reported" {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(PulseColors.warning)
                            Text(info.warnings)
                                .font(PulseFont.body(11))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.accent.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(PulseColors.accent.opacity(0.15), lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("RECONSTITUTION")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)

                Text("Peptides come as powder in vials. Mix with bacteriostatic water before injecting.")
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textFaint)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vial size")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.textMuted)
                        HStack(spacing: 4) {
                            TextField("5", text: $newItemVialSize)
                                .font(.system(size: 15))
                                .keyboardType(.decimalPad)
                                .padding(10)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("mg")
                                .font(.system(size: 13))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BAC water")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.textMuted)
                        HStack(spacing: 4) {
                            TextField("2", text: $newItemBacWater)
                                .font(.system(size: 15))
                                .keyboardType(.decimalPad)
                                .padding(10)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("mL")
                                .font(.system(size: 13))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }
                }

                if let calc = reconstitutionCalc {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "syringe")
                                .font(.system(size: 12))
                                .foregroundStyle(PulseColors.accent)
                            Text("Concentration: \(calc.concentration)")
                                .font(PulseFont.bodyMedium(13))
                                .foregroundStyle(PulseColors.textPrimary)
                        }
                        if !newItemDose.isEmpty, let units = calc.unitsForDose {
                            HStack(spacing: 8) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(PulseColors.accent)
                                Text("Draw \(units) units for \(newItemDose)")
                                    .font(PulseFont.bodyMedium(13))
                                    .foregroundStyle(PulseColors.textPrimary)
                            }
                        }
                        Text("1mL insulin syringe = 100 units")
                            .font(PulseFont.body(11))
                            .foregroundStyle(PulseColors.textFaint)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PulseColors.accent.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PulseColors.accent.opacity(0.2), lineWidth: 1)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Frequency")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulseColors.textMuted)
                    Spacer()
                    if selectedPeptideInfo != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(PulseColors.success)
                        Text("Auto-filled")
                            .font(PulseFont.body(11))
                            .foregroundStyle(PulseColors.success)
                    }
                }
                let frequencies = [("Daily", "Daily"), ("EOD", "EOD"), ("5 on / 2 off", "5on2off"), ("2x/week", "2x/week"), ("3x/week", "3x/week"), ("Custom", "Custom")]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(frequencies, id: \.1) { label, value in
                        Button { newItemFrequency = value } label: {
                            Text(label)
                                .font(.system(size: 13, weight: newItemFrequency == value ? .semibold : .regular))
                                .foregroundStyle(newItemFrequency == value ? .white : PulseColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(newItemFrequency == value ? PulseColors.accent : PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Cycle Length")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
                TextField("e.g. 30 days, 8 weeks", text: $newItemCycleLength)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("How long to run this peptide before taking a break")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textFaint)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Injection Site")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
                Picker("Site", selection: $newItemInjectionSite) {
                    Text("Subcutaneous").tag("Subcutaneous")
                    Text("Intramuscular").tag("Intramuscular")
                    Text("Oral / Nasal").tag("Oral/Nasal")
                    Text("N/A").tag("")
                }
                .pickerStyle(.segmented)
                Text("Most peptides are injected subcutaneously (belly fat area)")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textFaint)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
                TextField("e.g. Inject on empty stomach, wait 30 min", text: $newItemInstructions)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Storage")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
                Picker("Storage", selection: $newItemStorage) {
                    Text("Refrigerate").tag("Refrigerate")
                    Text("Room temp").tag("Room temp")
                    Text("Freeze").tag("Freeze")
                }
                .pickerStyle(.segmented)
                Text("Reconstituted peptides must be refrigerated (2-8°C)")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textFaint)
            }
        }
    }

    private var reconstitutionCalc: (concentration: String, unitsForDose: String?)? {
        guard let vialMg = Double(newItemVialSize), vialMg > 0,
              let waterMl = Double(newItemBacWater), waterMl > 0 else { return nil }

        let mgPerMl = vialMg / waterMl
        let mcgPerUnit = (vialMg * 1000) / (waterMl * 100)

        let concentrationStr: String
        if mgPerMl >= 1 {
            concentrationStr = String(format: "%.1f mg/mL", mgPerMl)
        } else {
            concentrationStr = String(format: "%.0f mcg/mL", mgPerMl * 1000)
        }

        var unitsStr: String? = nil
        let doseText = newItemDose.lowercased().trimmingCharacters(in: .whitespaces)
        if !doseText.isEmpty {
            var doseMcg: Double? = nil
            if doseText.contains("mcg") {
                doseMcg = Double(doseText.replacingOccurrences(of: "mcg", with: "").trimmingCharacters(in: .whitespaces))
            } else if doseText.contains("mg") {
                if let mg = Double(doseText.replacingOccurrences(of: "mg", with: "").trimmingCharacters(in: .whitespaces)) {
                    doseMcg = mg * 1000
                }
            }
            if let doseMcg, mcgPerUnit > 0 {
                let units = doseMcg / mcgPerUnit
                if units < 1 {
                    unitsStr = String(format: "%.1f", units)
                } else {
                    unitsStr = String(format: "%.0f", units)
                }
            }
        }

        return (concentrationStr, unitsStr)
    }

    private func saveNewProtocolItem() {
        let suppInfo = SupplementKnowledge.find(newItemName) ?? SupplementKnowledge.fuzzyMatch(newItemName).first
        let peptideInfo = PeptideKnowledge.find(newItemName) ?? PeptideKnowledge.fuzzyMatch(newItemName).first

        var instructions: String? = nil
        if newItemCategory == .peptide {
            var parts: [String] = []
            if !newItemVialSize.isEmpty && !newItemBacWater.isEmpty {
                parts.append("Vial: \(newItemVialSize)mg + \(newItemBacWater)mL BAC water")
                if let calc = reconstitutionCalc {
                    parts.append("Conc: \(calc.concentration)")
                    if let units = calc.unitsForDose {
                        parts.append("Draw: \(units) units")
                    }
                }
            }
            if !newItemInstructions.isEmpty {
                parts.append(newItemInstructions)
            } else if let pi = peptideInfo {
                parts.append(pi.instructions)
            }
            if !newItemInjectionSite.isEmpty { parts.append("Site: \(newItemInjectionSite)") }
            else if let pi = peptideInfo { parts.append("Site: \(pi.injectionSite)") }
            if !newItemStorage.isEmpty { parts.append("Storage: \(newItemStorage)") }
            else if let pi = peptideInfo { parts.append("Storage: \(pi.storage)") }
            if !newItemFrequency.isEmpty && newItemFrequency != "Daily" { parts.append("Frequency: \(newItemFrequency)") }
            else if let pi = peptideInfo, pi.frequency != "Daily" { parts.append("Frequency: \(pi.frequency)") }
            instructions = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        let cycleTotal: Int? = {
            guard newItemCategory == .peptide else { return nil }
            if !newItemCycleLength.isEmpty {
                let numbers = newItemCycleLength.filter(\.isNumber)
                if let days = Int(numbers) {
                    if newItemCycleLength.lowercased().contains("week") { return days * 7 }
                    return days
                }
            }
            if let pi = peptideInfo {
                let numbers = pi.cycleLength.filter(\.isNumber)
                if let days = Int(numbers) {
                    if pi.cycleLength.lowercased().contains("week") { return days * 7 }
                    return days
                }
            }
            return nil
        }()

        let med = Medication(
            name: newItemName,
            dose: newItemDose.isEmpty ? (peptideInfo?.defaultDose ?? suppInfo?.defaultDose ?? aiLookupResult?.defaultDose ?? "1 serving") : newItemDose,
            category: newItemCategory,
            emoji: suppInfo?.emoji ?? (newItemCategory == .peptide ? "syringe" : "pills.fill"),
            timing: newItemTiming,
            instructions: instructions ?? suppInfo?.interactionNotes,
            benefit: peptideInfo?.benefit ?? suppInfo?.benefit ?? aiLookupResult?.benefit,
            mechanism: peptideInfo?.mechanism ?? suppInfo?.mechanism ?? aiLookupResult?.mechanism,
            interactionNotes: peptideInfo?.warnings ?? suppInfo?.interactionNotes ?? aiLookupResult?.interactionNotes,
            bestTimeReason: suppInfo?.bestTimeReason ?? aiLookupResult?.bestTimeReason,
            stackNotes: peptideInfo?.stackNotes ?? suppInfo?.stackNotes
        )
        if let cycleTotal { med.cycleDayTotal = cycleTotal; med.cycleDayCurrent = 1 }
        modelContext.insert(med)
        modelContext.saveOrLog("tracker", surface: true)

        newItemName = ""
        newItemDose = ""
        newItemInstructions = ""
        newItemCycleLength = ""
        newItemFrequency = "Daily"
        newItemInjectionSite = ""
        newItemStorage = ""
        newItemVialSize = ""
        newItemBacWater = ""
        aiLookupResult = nil
        showAddProtocol = false
    }

    /// Adopt a unified-search result directly into the protocol as a `Medication`.
    /// Used by the AI-first `ProductSearchView`.
    private func adoptSearchResult(_ result: ProductSearchResult) {
        let info = result.info
        let category: MedicationCategory
        switch info.category.lowercased() {
        case "vitamin": category = .vitamin
        case "medication": category = .medication
        case "peptide": category = .peptide
        default: category = .supplement
        }
        let med = Medication(
            name: info.name,
            dose: info.defaultDose.isEmpty ? "1 serving" : info.defaultDose,
            category: category,
            emoji: info.emoji.isEmpty ? (category == .peptide ? "syringe" : "pills.fill") : info.emoji,
            timing: info.timing.isEmpty ? "AM" : info.timing,
            instructions: info.bestTimeReason.isEmpty ? nil : info.bestTimeReason,
            benefit: info.benefit.isEmpty ? nil : info.benefit,
            mechanism: info.mechanism.isEmpty ? nil : info.mechanism,
            interactionNotes: info.interactionNotes.isEmpty ? nil : info.interactionNotes,
            bestTimeReason: info.bestTimeReason.isEmpty ? nil : info.bestTimeReason,
            stackNotes: info.stackNotes.isEmpty ? nil : info.stackNotes
        )
        modelContext.insert(med)
        modelContext.saveOrLog("tracker", surface: true)
    }

    // MARK: - Predictive Suggestions

    private static let commonMedications: [(name: String, dose: String, category: String)] = [
        ("Gabapentin", "300mg", "medication"),
        ("Metformin", "500mg", "medication"),
        ("Lisinopril", "10mg", "medication"),
        ("Atorvastatin", "20mg", "medication"),
        ("Levothyroxine", "50mcg", "medication"),
        ("Amlodipine", "5mg", "medication"),
        ("Omeprazole", "20mg", "medication"),
        ("Losartan", "50mg", "medication"),
        ("Metoprolol", "25mg", "medication"),
        ("Sertraline", "50mg", "medication"),
        ("Escitalopram", "10mg", "medication"),
        ("Bupropion", "150mg", "medication"),
        ("Duloxetine", "30mg", "medication"),
        ("Trazodone", "50mg", "medication"),
        ("Adderall", "20mg", "medication"),
        ("Vyvanse", "30mg", "medication"),
        ("Modafinil", "200mg", "medication"),
        ("Clonazepam", "0.5mg", "medication"),
        ("Alprazolam", "0.25mg", "medication"),
        ("Zolpidem", "10mg", "medication"),
        ("Prednisone", "10mg", "medication"),
        ("Meloxicam", "15mg", "medication"),
        ("Hydroxychloroquine", "200mg", "medication"),
        ("Montelukast", "10mg", "medication"),
        ("Fluticasone", "50mcg", "medication"),
        ("Albuterol", "2.5mg", "medication"),
        ("Spironolactone", "25mg", "medication"),
        ("Finasteride", "1mg", "medication"),
        ("Dutasteride", "0.5mg", "medication"),
        ("Sildenafil", "50mg", "medication"),
        ("Tadalafil", "5mg", "medication"),
        ("Tretinoin", "0.025%", "medication"),
        ("Isotretinoin", "20mg", "medication"),
        ("Doxycycline", "100mg", "medication"),
        ("Amoxicillin", "500mg", "medication"),
        ("Azithromycin", "250mg", "medication"),
        ("Ciprofloxacin", "500mg", "medication"),
        ("Fluconazole", "150mg", "medication"),
        ("Valacyclovir", "500mg", "medication"),
        ("Sumatriptan", "50mg", "medication"),
        ("Topiramate", "25mg", "medication"),
        ("Propranolol", "20mg", "medication"),
        ("Naltrexone", "4.5mg", "medication"),
        ("Low-Dose Naltrexone", "4.5mg", "medication"),
        ("Ozempic", "0.25mg", "medication"),
        ("Wegovy", "0.25mg", "medication"),
        ("Mounjaro", "2.5mg", "medication"),
        ("Methotrexate", "7.5mg", "medication"),
        ("Rapamycin", "1mg", "medication"),
        ("Testosterone Cypionate", "200mg/mL", "medication"),
        ("Progesterone", "100mg", "medication"),
        ("Estradiol", "1mg", "medication"),
        ("DHEA", "25mg", "medication"),
        ("Pregnenolone", "50mg", "medication"),
        ("Thyroid (Armour)", "60mg", "medication"),
        ("Liothyronine (T3)", "5mcg", "medication"),
        ("Enclomiphene", "12.5mg", "medication"),
        ("Anastrozole", "0.5mg", "medication"),
        ("HCG", "500 IU", "medication"),
        ("Methylene Blue", "5mg", "medication"),
        ("Oxandrolone", "10mg", "medication"),
        ("Ibuprofen", "400mg", "medication"),
        ("Acetaminophen", "500mg", "medication"),
        ("Aspirin", "81mg", "medication"),
        ("Famotidine", "20mg", "medication"),
        ("Cetirizine", "10mg", "medication"),
        ("Diphenhydramine", "25mg", "medication"),
        ("Melatonin", "3mg", "supplement"),
        ("Berberine", "500mg", "supplement"),
        ("Quercetin", "500mg", "supplement"),
        ("Resveratrol", "500mg", "supplement"),
        ("NMN", "250mg", "supplement"),
        ("NR (Nicotinamide Riboside)", "300mg", "supplement"),
        ("Spermidine", "1mg", "supplement"),
        ("Fisetin", "100mg", "supplement"),
        ("Apigenin", "50mg", "supplement"),
        ("Sulforaphane", "10mg", "supplement"),
        ("Tongkat Ali", "400mg", "supplement"),
        ("Turkesterone", "500mg", "supplement"),
        ("Shilajit", "250mg", "supplement"),
        ("Lions Mane", "500mg", "supplement"),
        ("Cordyceps", "750mg", "supplement"),
        ("Reishi", "500mg", "supplement"),
        ("Rhodiola Rosea", "300mg", "supplement"),
        ("L-Theanine", "200mg", "supplement"),
        ("GABA", "500mg", "supplement"),
        ("5-HTP", "100mg", "supplement"),
        ("SAMe", "400mg", "supplement"),
        ("Tudca", "250mg", "supplement"),
        ("Milk Thistle", "250mg", "supplement"),
        ("NAC", "600mg", "supplement"),
        ("Glutathione", "500mg", "supplement"),
        ("PQQ", "20mg", "supplement"),
        ("CoQ10", "200mg", "supplement"),
        ("Alpha-Lipoic Acid", "600mg", "supplement"),
    ]

    private var filteredNameSuggestions: [String] {
        let query = newItemName.lowercased().trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }

        var results: [String] = []

        let suppMatches = SupplementKnowledge.database
            .filter { $0.name.lowercased().contains(query) || $0.aliases.contains(where: { $0.contains(query) }) }
            .prefix(4)
            .map(\.name)

        let peptideMatches = PeptideKnowledge.database
            .filter { $0.name.lowercased().contains(query) || $0.aliases.contains(where: { $0.contains(query) }) }
            .prefix(4)
            .map(\.name)

        let stackMatches = PeptideKnowledge.stacks
            .filter { $0.name.lowercased().contains(query) || $0.aliases.contains(where: { $0.contains(query) }) }
            .prefix(3)
            .map(\.name)

        let medMatches = Self.commonMedications
            .filter { $0.name.lowercased().contains(query) }
            .prefix(4)
            .map(\.name)

        // Previously-discovered items the user (or AI) saved to the catalog.
        let customMatches = CustomProductStore.fuzzyMatch(query, in: modelContext)
            .prefix(4)
            .map(\.name)

        results = Array(Set(suppMatches + peptideMatches + stackMatches + medMatches + customMatches))
            .sorted { $0.lowercased().hasPrefix(query) && !$1.lowercased().hasPrefix(query) }

        return Array(results.filter { $0.lowercased() != query }.prefix(6))
    }

    private var filteredDoseSuggestions: [String] {
        let query = newItemDose.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        let commonDoses: [String]
        if newItemCategory == .peptide {
            commonDoses = ["100mcg", "250mcg", "500mcg", "1mg", "2mg", "5mg", "10mg"]
        } else if newItemCategory == .vitamin {
            commonDoses = ["500 IU", "1,000 IU", "2,000 IU", "5,000 IU", "10,000 IU", "100mcg", "500mcg", "1mg", "5mg"]
        } else if newItemCategory == .medication {
            commonDoses = ["5mg", "10mg", "20mg", "25mg", "50mg", "100mg", "150mg", "200mg", "300mg", "500mg"]
        } else {
            commonDoses = ["100mg", "200mg", "250mg", "400mg", "500mg", "600mg", "1,000mg", "1g", "2g", "5g"]
        }

        if let info = SupplementKnowledge.find(newItemName) {
            var suggestions = [info.defaultDose]
            suggestions.append(contentsOf: commonDoses.filter { $0.lowercased().contains(query) && $0 != info.defaultDose })
            return Array(suggestions.prefix(5))
        }

        if let info = PeptideKnowledge.find(newItemName) {
            var suggestions = [info.defaultDose]
            suggestions.append(contentsOf: commonDoses.filter { $0.lowercased().contains(query) && $0 != info.defaultDose })
            return Array(suggestions.prefix(5))
        }

        if let med = Self.commonMedications.first(where: { $0.name.lowercased() == newItemName.lowercased() }) {
            var suggestions = [med.dose]
            suggestions.append(contentsOf: commonDoses.filter { $0.lowercased().contains(query) && $0 != med.dose })
            return Array(suggestions.prefix(5))
        }

        return commonDoses.filter { $0.lowercased().contains(query) }.prefix(5).map { $0 }
    }

    private func suggestedDose(for name: String) -> String? {
        if let info = SupplementKnowledge.find(name) { return info.defaultDose }
        if let info = PeptideKnowledge.find(name) { return info.defaultDose }
        if let stack = PeptideKnowledge.findStack(name) {
            return stack.peptides.joined(separator: " + ")
        }
        if let med = Self.commonMedications.first(where: { $0.name.lowercased() == name.lowercased() }) { return med.dose }
        return nil
    }

    private func suggestedCategory(for name: String) -> MedicationCategory? {
        if let info = SupplementKnowledge.find(name) {
            if info.category == "vitamin" { return .vitamin }
            return .supplement
        }
        if PeptideKnowledge.find(name) != nil { return .peptide }
        if PeptideKnowledge.findStack(name) != nil { return .peptide }
        if let med = Self.commonMedications.first(where: { $0.name.lowercased() == name.lowercased() }) {
            if med.category == "medication" { return .medication }
            return .supplement
        }
        return nil
    }

    private func autofillPeptideFields(for name: String) {
        if let stack = PeptideKnowledge.findStack(name) {
            newItemCycleLength = stack.cycleLength
            newItemInstructions = stack.notes
            newItemInjectionSite = "Subcutaneous"
            newItemStorage = "Refrigerate"
            return
        }
        guard let info = PeptideKnowledge.find(name) ?? PeptideKnowledge.fuzzyMatch(name).first else { return }
        if newItemFrequency == "Daily" && info.frequency != "Daily" {
            let freq = info.frequency.lowercased()
            if freq.contains("2x") || freq.contains("twice") { newItemFrequency = "2x/week" }
            else if freq.contains("3x") { newItemFrequency = "3x/week" }
            else if freq.contains("eod") || freq.contains("every other") { newItemFrequency = "EOD" }
            else { newItemFrequency = info.frequency }
        }
        if newItemCycleLength.isEmpty { newItemCycleLength = info.cycleLength }
        if newItemInjectionSite.isEmpty {
            let site = info.injectionSite.lowercased()
            if site.contains("subcutaneous") || site.contains("sc") { newItemInjectionSite = "Subcutaneous" }
            else if site.contains("intramuscular") || site.contains("im") { newItemInjectionSite = "Intramuscular" }
            else if site.contains("oral") || site.contains("nasal") { newItemInjectionSite = "Oral/Nasal" }
        }
        if newItemStorage.isEmpty {
            let storage = info.storage.lowercased()
            if storage.contains("refrigerat") || storage.contains("2-8") { newItemStorage = "Refrigerate" }
            else if storage.contains("freeze") || storage.contains("-20") { newItemStorage = "Freeze" }
            else { newItemStorage = "Room temp" }
        }
        if newItemInstructions.isEmpty && !info.instructions.isEmpty {
            newItemInstructions = info.instructions
        }
        if newItemTiming == "AM" && info.timing != "AM" {
            newItemTiming = info.timing == "Pre-bed" ? "PM" : info.timing
        }
    }

    private var selectedPeptideInfo: PeptideInfo? {
        guard newItemCategory == .peptide, !newItemName.isEmpty else { return nil }
        return PeptideKnowledge.find(newItemName) ?? PeptideKnowledge.fuzzyMatch(newItemName).first
    }

    // MARK: - AI Ingredient Lookup (unified search engine — Tracker B3)

    /// Routes the add-protocol "Search with AI" action through the single unified
    /// search engine (`ProductSearchService.searchAndPersist`): local catalogs +
    /// persisted custom entries → Open Food Facts / openFDA → AI research pass with
    /// citations. Any discovered item is saved to the catalog for reuse. The best
    /// result is mapped into `AISupplementProfile` so the existing result card +
    /// `applyAIResult` autofill work unchanged.
    private func aiSearchIngredient(_ name: String) async {
        isAISearching = true
        aiLookupResult = nil
        defer { isAISearching = false }

        let outcome = await ProductSearchService.searchAndPersist(query: name, in: modelContext)
        guard let best = outcome.results.first else { return }

        let info = best.info
        aiLookupResult = AISupplementProfile(
            name: info.name,
            category: info.category,
            defaultDose: info.defaultDose,
            timing: info.timing,
            benefit: info.benefit,
            mechanism: info.mechanism,
            pros: info.pros,
            cons: info.cons,
            bestTimeReason: info.bestTimeReason,
            interactionNotes: info.interactionNotes
        )
    }

    private func applyAIResult(_ result: AISupplementProfile) {
        if newItemDose.isEmpty { newItemDose = result.defaultDose }
        newItemTiming = result.timing.contains("PM") ? "PM" : "AM"
        if newItemInstructions.isEmpty {
            newItemInstructions = result.bestTimeReason
        }
        switch result.category.lowercased() {
        case "vitamin": newItemCategory = .vitamin
        case "medication": newItemCategory = .medication
        case "peptide": newItemCategory = .peptide
        default: newItemCategory = .supplement
        }
    }

    // MARK: - Add Meal Sheet

    private var addMealSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What did you eat?")
                        .font(PulseFont.bodyMedium(13))
                        .foregroundStyle(PulseColors.textMuted)
                    TextField("e.g. Chicken salad with avocado", text: $mealDescription)
                        .font(PulseFont.body(15))
                        .padding(12)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .submitLabel(.done)
                        .onSubmit { Task { await estimateMeal() } }
                        .onChange(of: mealDescription) { _, _ in mealEstimate = nil }
                }

                // Live estimate: AI when available, deterministic preview otherwise.
                let preview = mealEstimate ?? MealEstimator.quickEstimate(mealDescription)
                if isEstimatingMeal {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Estimating nutrition…")
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let preview, !mealDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(PulseColors.accent)
                            Text(preview.isAIGenerated ? "AI ESTIMATE" : "QUICK ESTIMATE")
                                .font(PulseFont.bodyMedium(10))
                                .foregroundStyle(PulseColors.textMuted)
                                .tracking(0.6)
                        }
                        Text(preview.macroSummary)
                            .font(PulseFont.bodySemibold(14))
                            .foregroundStyle(PulseColors.textPrimary)
                        if !preview.note.isEmpty {
                            Text(preview.note)
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if !mealDescription.isEmpty && AIService.shared.hasAPIKey {
                    Button { Task { await estimateMeal() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Estimate nutrition with AI")
                                .font(PulseFont.bodyMedium(12))
                        }
                        .foregroundStyle(PulseColors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(PulseColors.accentSoft)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button { saveNewMeal() } label: {
                    Text("Log Meal")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(mealDescription.isEmpty ? PulseColors.textMuted : PulseColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(mealDescription.isEmpty)
            }
            .padding(20)
            .background(PulseColors.background)
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddMeal = false }
                }
            }
        }
    }

    private func estimateMeal() async {
        let d = mealDescription.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !isEstimatingMeal else { return }
        isEstimatingMeal = true
        defer { isEstimatingMeal = false }
        mealEstimate = await MealEstimator.estimate(d)
    }

    private func saveNewMeal() {
        let estimate = mealEstimate ?? MealEstimator.quickEstimate(mealDescription)
        modelContext.insert(MealLog(
            name: mealDescription,
            description_: estimate?.note ?? "",
            emoji: estimate?.emoji ?? "fork.knife",
            calories: estimate?.calories ?? 0,
            proteinG: estimate?.proteinG,
            carbsG: estimate?.carbsG,
            fatG: estimate?.fatG
        ))
        modelContext.saveOrLog("tracker", surface: true)
        mealDescription = ""
        mealEstimate = nil
        showAddMeal = false
    }
}
