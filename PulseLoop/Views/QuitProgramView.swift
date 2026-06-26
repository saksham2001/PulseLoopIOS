import SwiftUI
import SwiftData

// MARK: - Quit Detail View

struct QuitDetailView: View {
    let vice: Vice
    @Environment(\.modelContext) private var modelContext
    @State private var showLogUrgeSheet = false
    @State private var aiInsight: String?
    @State private var isLoadingInsight = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                if vice.taperSchedule == .gradual { taperSection }
                urgeHistorySection
                milestonesSection
                motivationsSection
                if let insight = aiInsight { aiInsightCard(insight) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(PulseColors.background)
        .navigationTitle(vice.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showLogUrgeSheet = true } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                }
                .accessibilityLabel("Log urge")
            }
        }
        .sheet(isPresented: $showLogUrgeSheet) {
            LogUrgeSheet(vice: vice)
                .presentationDetents([.medium])
        }
        .task { await loadInsight() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            Image(systemName: vice.emoji.isEmpty ? "nosign" : vice.emoji)
                .font(.system(size: 44))
                .foregroundStyle(PulseColors.textPrimary)

            Text("\(vice.currentStreak)")
                .font(PulseFont.titleSemibold(56))
                .foregroundStyle(PulseColors.textPrimary)
            Text("days clean")
                .font(PulseFont.bodyDefault)
                .foregroundStyle(PulseColors.textMuted)

            HStack(spacing: 24) {
                statBubble(value: "$\(Int(vice.moneySaved))", label: "Saved", color: PulseColors.success)
                statBubble(value: "\(vice.longestStreak)d", label: "Best", color: PulseColors.warning)
                statBubble(value: "\(vice.logs.filter { $0.typeRaw == ViceLogType.urgeResisted.rawValue }.count)", label: "Resisted", color: PulseColors.accent)
            }

            let milestone = currentMilestone(for: vice)
            if let milestone {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.warning)
                    Text(milestone)
                        .font(PulseFont.bodySmall)
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PulseColors.warningBackground)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func statBubble(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(PulseFont.titleMedium(18))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(PulseFont.micro)
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Taper

    private var taperSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAPERING")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            if let start = vice.taperStartAmount, let target = vice.taperCurrentTarget, let unit = vice.taperUnit {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Started at \(Int(start)) \(unit)/day")
                            .font(PulseFont.body(14))
                            .foregroundStyle(PulseColors.textSecondary)
                        Text("Current target: \(Int(target)) \(unit)/day")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                    Spacer()
                }

                let progress = start > 0 ? min(1.0, (start - target) / start) : 0
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PulseColors.fillSubtle)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PulseColors.warning)
                            .frame(width: geo.size.width * progress, height: 8)
                    }
                }
                .frame(height: 8)

                Text("\(Int(progress * 100))% reduced")
                    .font(PulseFont.caption)
                    .foregroundStyle(PulseColors.warning)
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

    // MARK: - Urge History

    private var urgeHistorySection: some View {
        let sortedLogs = vice.logs.sorted { $0.date > $1.date }.prefix(10)

        return VStack(alignment: .leading, spacing: 10) {
            Text("RECENT ACTIVITY")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            if sortedLogs.isEmpty {
                Text("No activity logged yet")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(sortedLogs), id: \.id) { log in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(logColor(log))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.type.rawValue)
                                .font(PulseFont.bodyMedium(14))
                                .foregroundStyle(PulseColors.textPrimary)
                            if let trigger = log.triggerContext {
                                Text(trigger)
                                    .font(PulseFont.caption)
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                        }
                        Spacer()
                        Text(log.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(PulseFont.micro)
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    .padding(.vertical, 6)
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

    private func logColor(_ log: ViceLog) -> Color {
        switch log.type {
        case .relapse: return PulseColors.alert
        case .urgeResisted: return PulseColors.success
        case .triggerLogged: return PulseColors.warning
        case .taperDose: return PulseColors.accent
        }
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        let days = vice.daysSinceQuit
        let milestones = milestonesForSubstance(vice.name)

        return VStack(alignment: .leading, spacing: 10) {
            Text("HEALTH MILESTONES")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            ForEach(milestones, id: \.days) { m in
                HStack(spacing: 12) {
                    Image(systemName: days >= m.days ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(days >= m.days ? PulseColors.success : PulseColors.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title)
                            .font(PulseFont.bodyMedium(14))
                            .foregroundStyle(days >= m.days ? PulseColors.textPrimary : PulseColors.textMuted)
                        Text(m.description)
                            .font(PulseFont.caption)
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    Spacer()
                    Text(m.timeLabel)
                        .font(PulseFont.micro)
                        .foregroundStyle(days >= m.days ? PulseColors.success : PulseColors.textFaint)
                }
                .padding(.vertical, 4)
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

    // MARK: - Motivations

    private var motivationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR MOTIVATIONS")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            if vice.motivations.isEmpty {
                Text("Add reasons to quit in settings")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textMuted)
            } else {
                ForEach(vice.motivations, id: \.self) { motivation in
                    HStack(spacing: 10) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.alert)
                        Text(motivation)
                            .font(PulseFont.body(14))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    // MARK: - AI Insight

    private func aiInsightCard(_ insight: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.accent)
                Text("AI INSIGHT")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.accent)
                    .tracking(0.8)
            }
            Text(insight)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textPrimary)
                .lineSpacing(3)
        }
        .padding(18)
        .background(PulseColors.accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.accent.opacity(0.2), lineWidth: 1)
        }
    }

    private func loadInsight() async {
        guard !vice.logs.isEmpty else { return }
        isLoadingInsight = true
        let relapseCount = vice.logs.filter { $0.typeRaw == ViceLogType.relapse.rawValue }.count
        let resistedCount = vice.logs.filter { $0.typeRaw == ViceLogType.urgeResisted.rawValue }.count
        let triggers = vice.logs.compactMap(\.triggerContext).prefix(10)
        let triggerList = triggers.isEmpty ? "none logged" : triggers.joined(separator: ", ")

        let prompt = """
        User is quitting \(vice.name). Stats: \(vice.currentStreak) day streak, \(relapseCount) relapses, \(resistedCount) urges resisted. Common triggers: \(triggerList). Give ONE concise, encouraging insight or pattern observation in 1-2 sentences. Be specific and actionable.
        """
        do {
            let messages = [AIService.Message(role: "user", content: prompt)]
            let response = try await AIService.shared.complete(messages: messages)
            await MainActor.run { aiInsight = response.trimmingCharacters(in: .whitespacesAndNewlines) }
        } catch {}
        await MainActor.run { isLoadingInsight = false }
    }

    // MARK: - Milestone Data

    private struct MilestoneData {
        let days: Int
        let title: String
        let description: String
        let timeLabel: String
    }

    private func currentMilestone(for vice: Vice) -> String? {
        let days = vice.daysSinceQuit
        let milestones = milestonesForSubstance(vice.name)
        let achieved = milestones.filter { days >= $0.days }
        return achieved.last.map { "\($0.title)" }
    }

    private func milestonesForSubstance(_ name: String) -> [MilestoneData] {
        let lowered = name.lowercased()
        if lowered.contains("nicotine") || lowered.contains("smoking") || lowered.contains("vape") {
            return [
                MilestoneData(days: 0, title: "Heart rate normalizing", description: "20 minutes after last use", timeLabel: "20min"),
                MilestoneData(days: 1, title: "Oxygen levels recover", description: "Carbon monoxide cleared", timeLabel: "8h"),
                MilestoneData(days: 3, title: "Nicotine leaves body", description: "Withdrawal peaks then fades", timeLabel: "72h"),
                MilestoneData(days: 14, title: "Circulation improves", description: "Walking becomes easier", timeLabel: "2wk"),
                MilestoneData(days: 30, title: "Lung function improves", description: "Coughing decreases", timeLabel: "1mo"),
                MilestoneData(days: 365, title: "Heart disease risk halved", description: "Major health milestone", timeLabel: "1yr"),
            ]
        } else if lowered.contains("alcohol") {
            return [
                MilestoneData(days: 1, title: "Blood sugar normalizes", description: "Body starts recovering", timeLabel: "24h"),
                MilestoneData(days: 3, title: "Withdrawal subsides", description: "Worst is over", timeLabel: "72h"),
                MilestoneData(days: 7, title: "Sleep improves", description: "REM cycles normalize", timeLabel: "1wk"),
                MilestoneData(days: 30, title: "Liver fat reduces 15%", description: "Organ recovery begins", timeLabel: "1mo"),
                MilestoneData(days: 90, title: "Blood pressure drops", description: "Cardiovascular improvement", timeLabel: "3mo"),
            ]
        } else if lowered.contains("caffeine") || lowered.contains("coffee") {
            return [
                MilestoneData(days: 1, title: "Withdrawal headache", description: "Your body adjusting", timeLabel: "12h"),
                MilestoneData(days: 2, title: "Peak withdrawal", description: "Hardest day — push through", timeLabel: "2d"),
                MilestoneData(days: 9, title: "Body adjusts", description: "Energy stabilizing", timeLabel: "9d"),
                MilestoneData(days: 14, title: "Full reset", description: "Natural energy restored", timeLabel: "2wk"),
            ]
        } else {
            return [
                MilestoneData(days: 1, title: "First day done", description: "You took the hardest step", timeLabel: "1d"),
                MilestoneData(days: 3, title: "72 hours", description: "Initial cravings fading", timeLabel: "3d"),
                MilestoneData(days: 7, title: "One week", description: "New patterns forming", timeLabel: "1wk"),
                MilestoneData(days: 14, title: "Two weeks", description: "Habit loop weakening", timeLabel: "2wk"),
                MilestoneData(days: 30, title: "One month", description: "Major milestone reached", timeLabel: "1mo"),
                MilestoneData(days: 90, title: "Three months", description: "New identity forming", timeLabel: "3mo"),
                MilestoneData(days: 365, title: "One year", description: "You did it", timeLabel: "1yr"),
            ]
        }
    }
}

// MARK: - Add Vice Sheet

struct AddViceSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var customName = ""
    @State private var emoji = ""
    @State private var taperType: TaperType = .coldTurkey
    @State private var dailyCost: String = ""
    @State private var startAmount: String = ""
    @State private var taperUnit: String = ""
    @State private var motivation1 = ""
    @State private var motivation2 = ""

    private let presets: [(name: String, emoji: String)] = [
        ("Nicotine", "smoke.fill"),
        ("Alcohol", "wineglass.fill"),
        ("Caffeine", "cup.and.saucer.fill"),
        ("Cannabis", "leaf.fill"),
        ("Sugar", "birthday.cake.fill"),
        ("Vaping", "wind"),
        ("Social Media", "iphone"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    substanceSection
                    approachSection
                    costSection
                    motivationSection
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Quit Something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { save() }
                        .disabled(selectedName.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var selectedName: String {
        name == "Custom" ? customName : name
    }

    private var selectedEmoji: String {
        if name == "Custom" { return "nosign" }
        return presets.first(where: { $0.name == name })?.emoji ?? "nosign"
    }

    private var substanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT ARE YOU QUITTING?")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                ForEach(presets, id: \.name) { preset in
                    Button {
                        name = preset.name
                        emoji = preset.emoji
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: preset.emoji)
                                .font(.system(size: 22))
                                .foregroundStyle(name == preset.name ? .white : PulseColors.textPrimary)
                            Text(preset.name)
                                .font(PulseFont.caption)
                                .foregroundStyle(name == preset.name ? .white : PulseColors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(name == preset.name ? PulseColors.accent : PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    name = "Custom"
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 22))
                            .foregroundStyle(name == "Custom" ? .white : PulseColors.textPrimary)
                        Text("Custom")
                            .font(PulseFont.caption)
                            .foregroundStyle(name == "Custom" ? .white : PulseColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(name == "Custom" ? PulseColors.accent : PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if name == "Custom" {
                TextField("What are you quitting?", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 4)
            }
        }
    }

    private var approachSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPROACH")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            ForEach(TaperType.allCases, id: \.rawValue) { type in
                Button { taperType = type } label: {
                    HStack(spacing: 12) {
                        Image(systemName: taperType == type ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(taperType == type ? PulseColors.accent : PulseColors.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .font(PulseFont.bodyMedium(15))
                                .foregroundStyle(PulseColors.textPrimary)
                            Text(type == .coldTurkey ? "Stop completely from today" : "Gradually reduce over time")
                                .font(PulseFont.caption)
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(taperType == type ? PulseColors.accentSoft : PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if taperType == .gradual {
                HStack(spacing: 12) {
                    TextField("Amount", text: $startAmount)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    TextField("Unit (e.g. cigs)", text: $taperUnit)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 4)
            }
        }
    }

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAILY COST (OPTIONAL)")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            HStack {
                Text("$")
                    .foregroundStyle(PulseColors.textMuted)
                TextField("0", text: $dailyCost)
                    .keyboardType(.decimalPad)
                Text("/ day")
                    .font(PulseFont.bodySmall)
                    .foregroundStyle(PulseColors.textMuted)
            }
            .padding(12)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var motivationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHY ARE YOU QUITTING?")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            TextField("Reason 1 (e.g. for my health)", text: $motivation1)
                .textFieldStyle(.roundedBorder)
            TextField("Reason 2 (optional)", text: $motivation2)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        let motivations = [motivation1, motivation2].filter { !$0.isEmpty }
        let cost = Double(dailyCost) ?? 0
        let start = Double(startAmount)

        let vice = Vice(
            name: selectedName,
            emoji: selectedEmoji,
            dailyCostSaved: cost,
            taperSchedule: taperType,
            taperStartAmount: start,
            taperUnit: taperUnit.isEmpty ? nil : taperUnit,
            motivations: motivations
        )
        modelContext.insert(vice)
        try? modelContext.save()
        HapticService.success()
        dismiss()
    }
}

// MARK: - Log Urge Sheet

struct LogUrgeSheet: View {
    let vice: Vice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var intensity: Double = 5
    @State private var selectedTrigger = ""
    @State private var didResist = true
    @State private var amount: String = ""
    @State private var copingUsed = ""
    @State private var notes = ""

    private let triggers = ["Stress", "Boredom", "Social", "After meal", "Alcohol", "Habit/routine", "Anxiety", "Celebration"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intensitySection
                    triggerSection
                    resistToggle
                    if vice.taperSchedule == .gradual { amountSection }
                    copingSection
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Log Urge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INTENSITY")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Text("\(Int(intensity))/10")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(intensityColor)
            }
            Slider(value: $intensity, in: 1...10, step: 1)
                .tint(intensityColor)
        }
    }

    private var intensityColor: Color {
        if intensity <= 3 { return PulseColors.success }
        if intensity <= 6 { return PulseColors.warning }
        return PulseColors.alert
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT TRIGGERED THIS?")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                ForEach(triggers, id: \.self) { trigger in
                    Button { selectedTrigger = trigger } label: {
                        Text(trigger)
                            .font(PulseFont.caption)
                            .foregroundStyle(selectedTrigger == trigger ? .white : PulseColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(selectedTrigger == trigger ? PulseColors.accent : PulseColors.fillSubtle)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var resistToggle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DID YOU RESIST?")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            HStack(spacing: 10) {
                Button { didResist = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 14))
                        Text("Yes, I resisted")
                            .font(PulseFont.bodyMedium(14))
                    }
                    .foregroundStyle(didResist ? .white : PulseColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(didResist ? PulseColors.success : PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { didResist = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                        Text("I gave in")
                            .font(PulseFont.bodyMedium(14))
                    }
                    .foregroundStyle(!didResist ? .white : PulseColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(!didResist ? PulseColors.alert : PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AMOUNT (IF APPLICABLE)")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            TextField("How much? (e.g. 2)", text: $amount)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
        }
    }

    private var copingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT HELPED? (OPTIONAL)")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            TextField("e.g. went for a walk, deep breathing", text: $copingUsed)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        let logType: ViceLogType = didResist ? .urgeResisted : .relapse
        let log = ViceLog(
            viceId: vice.id,
            type: logType,
            amount: Double(amount),
            triggerContext: selectedTrigger.isEmpty ? nil : selectedTrigger,
            intensity: Int(intensity),
            copingUsed: copingUsed.isEmpty ? nil : copingUsed,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(log)
        vice.logs.append(log)
        try? modelContext.save()
        HapticService.impact(didResist ? .light : .heavy)
        dismiss()
    }
}

// MARK: - Edit Vice Sheet

struct EditViceSheet: View {
    let vice: Vice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var dailyCost: String = ""
    @State private var taperTarget: String = ""
    @State private var motivation1: String = ""
    @State private var motivation2: String = ""
    @State private var motivation3: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DAILY COST")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.8)
                        HStack {
                            Text("$")
                                .foregroundStyle(PulseColors.textMuted)
                            TextField("0", text: $dailyCost)
                                .keyboardType(.decimalPad)
                            Text("/ day")
                                .font(PulseFont.bodySmall)
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        .padding(12)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if vice.taperSchedule == .gradual {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CURRENT TAPER TARGET")
                                .font(PulseFont.bodyMedium(11))
                                .foregroundStyle(PulseColors.textMuted)
                                .tracking(0.8)
                            HStack {
                                TextField("Target", text: $taperTarget)
                                    .keyboardType(.decimalPad)
                                Text(vice.taperUnit ?? "per day")
                                    .font(PulseFont.bodySmall)
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                            .padding(12)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("MOTIVATIONS")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.8)
                        TextField("Reason 1", text: $motivation1)
                            .textFieldStyle(.roundedBorder)
                        TextField("Reason 2", text: $motivation2)
                            .textFieldStyle(.roundedBorder)
                        TextField("Reason 3", text: $motivation3)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Edit \(vice.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                dailyCost = vice.dailyCostSaved > 0 ? String(format: "%.0f", vice.dailyCostSaved) : ""
                taperTarget = vice.taperCurrentTarget.map { String(format: "%.0f", $0) } ?? ""
                let m = vice.motivations
                motivation1 = m.indices.contains(0) ? m[0] : ""
                motivation2 = m.indices.contains(1) ? m[1] : ""
                motivation3 = m.indices.contains(2) ? m[2] : ""
            }
        }
    }

    private func save() {
        vice.dailyCostSaved = Double(dailyCost) ?? vice.dailyCostSaved
        if let target = Double(taperTarget) {
            vice.taperCurrentTarget = target
        }
        vice.motivations = [motivation1, motivation2, motivation3].filter { !$0.isEmpty }
        try? modelContext.save()
        dismiss()
    }
}
