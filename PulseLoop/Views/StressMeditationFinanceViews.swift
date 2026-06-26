import SwiftUI
import SwiftData

// MARK: - Stress Tracking View

struct StressTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StressLog.date, order: .reverse) private var logs: [StressLog]
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if let latest = logs.first, Calendar.current.isDateInToday(latest.date) {
                todayCard(latest)
            } else {
                quickLog
            }
            if logs.count > 1 { weeklyTrend }
        }
        .sheet(isPresented: $showAdd) { AddStressSheet() }
    }

    private var header: some View {
        HStack {
            Text("STRESS")
                .font(PulseFont.bodyMedium(11)).foregroundStyle(PulseColors.textMuted).tracking(0.8)
            Spacer()
            Button { showAdd = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Log").font(PulseFont.bodySemibold(12))
                }
                .foregroundStyle(PulseColors.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(PulseColors.accent.opacity(0.1)).clipShape(Capsule())
            }
        }
    }

    private var quickLog: some View {
        VStack(spacing: 10) {
            Text("How stressed are you?")
                .font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
            HStack(spacing: 6) {
                ForEach([1, 3, 5, 7, 9], id: \.self) { level in
                    Button { quickSave(level) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: stressEmoji(level)).font(.system(size: 18, weight: .medium)).foregroundStyle(PulseColors.textPrimary)
                            Text("\(level)").font(PulseFont.body(10)).foregroundStyle(PulseColors.textMuted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private func todayCard(_ log: StressLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stressEmoji(log.level))
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 40, height: 40)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Today: \(log.level)/10").font(PulseFont.bodySemibold(14)).foregroundStyle(PulseColors.textPrimary)
                if !log.triggers.isEmpty {
                    Text(log.triggers.joined(separator: ", ")).font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private var weeklyTrend: some View {
        let week = Array(logs.prefix(7).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            Text("This Week").font(PulseFont.bodyMedium(12)).foregroundStyle(PulseColors.textSecondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, log in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stressColor(log.level))
                            .frame(maxWidth: .infinity)
                            .frame(height: CGFloat(log.level) * 5)
                        Text("\(log.level)").font(PulseFont.body(9)).foregroundStyle(PulseColors.textFaint)
                    }
                }
            }.frame(height: 60)
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private func stressEmoji(_ level: Int) -> String {
        if level <= 2 { return "leaf.fill" }; if level <= 4 { return "wind" }
        if level <= 6 { return "wind.circle" }; if level <= 8 { return "bolt.fill" }; return "bolt.trianglebadge.exclamationmark.fill"
    }

    private func stressColor(_ level: Int) -> Color {
        if level <= 3 { return .green }; if level <= 6 { return .orange }; return .red
    }

    private func quickSave(_ level: Int) {
        modelContext.insert(StressLog(level: level))
        try? modelContext.save()
    }
}

struct AddStressSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var level = 5
    @State private var selectedTriggers: Set<String> = []
    @State private var notes = ""
    private let triggerOptions = ["Work", "Relationships", "Health", "Money", "Sleep", "News", "Traffic", "Deadline", "Social", "Unknown"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Level: \(level)/10").font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textMuted)
                        HStack(spacing: 4) {
                            ForEach(1...10, id: \.self) { i in
                                Button { level = i } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(i <= level ? stressColor(level) : PulseColors.fillSubtle).frame(height: 28)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Triggers").font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textMuted)
                        FlowLayout(spacing: 8) {
                            ForEach(triggerOptions, id: \.self) { t in
                                Button {
                                    if selectedTriggers.contains(t) { selectedTriggers.remove(t) }
                                    else { selectedTriggers.insert(t) }
                                } label: {
                                    Text(t).font(PulseFont.body(13))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(selectedTriggers.contains(t) ? PulseColors.accent.opacity(0.15) : PulseColors.fillSubtle)
                                        .foregroundStyle(selectedTriggers.contains(t) ? PulseColors.accent : PulseColors.textSecondary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    TextField("Notes", text: $notes).font(PulseFont.body(15)).padding(12)
                        .background(PulseColors.fillSubtle).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button { save() } label: {
                        Text("Log Stress").font(PulseFont.bodySemibold(15)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Log Stress").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func stressColor(_ level: Int) -> Color {
        if level <= 3 { return .green }; if level <= 6 { return .orange }; return .red
    }

    private func save() {
        modelContext.insert(StressLog(level: level, triggers: Array(selectedTriggers), notes: notes.isEmpty ? nil : notes))
        try? modelContext.save(); dismiss()
    }
}

// MARK: - Meditation Tracking View

struct MeditationTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeditationLog.date, order: .reverse) private var logs: [MeditationLog]
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 16) {
            header
            stats
            if !logs.isEmpty { recentSessions }
        }
        .sheet(isPresented: $showAdd) { AddMeditationSheet() }
    }

    private var header: some View {
        HStack {
            Text("MEDITATION")
                .font(PulseFont.bodyMedium(11)).foregroundStyle(PulseColors.textMuted).tracking(0.8)
            Spacer()
            Button { showAdd = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Log").font(PulseFont.bodySemibold(12))
                }
                .foregroundStyle(PulseColors.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(PulseColors.accent.opacity(0.1)).clipShape(Capsule())
            }
        }
    }

    private var stats: some View {
        let thisWeek = logs.filter { $0.date > (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()) }
        let totalMin = thisWeek.reduce(0) { $0 + $1.durationMinutes }
        let streak = calculateStreak()
        return HStack(spacing: 10) {
            statPill("figure.mind.and.body", "\(thisWeek.count)", "sessions")
            statPill("clock.fill", "\(totalMin)", "min")
            statPill("flame.fill", "\(streak)", "streak")
        }
    }

    private func statPill(_ systemIcon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemIcon).font(.system(size: 14, weight: .medium)).foregroundStyle(PulseColors.textPrimary)
            Text(value).font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
            Text(label).font(PulseFont.body(10)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(logs.prefix(5)) { log in
                HStack {
                    Text(log.type.rawValue).font(PulseFont.bodySemibold(13)).foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                    Text("\(log.durationMinutes) min").font(PulseFont.body(13)).foregroundStyle(PulseColors.textSecondary)
                    Text(log.date, style: .date).font(PulseFont.body(11)).foregroundStyle(PulseColors.textFaint)
                }.padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1) }
    }

    private func calculateStreak() -> Int {
        var streak = 0
        var check = Calendar.current.startOfDay(for: Date())
        let days = Set(logs.map { Calendar.current.startOfDay(for: $0.date) })
        while days.contains(check) {
            streak += 1
            check = Calendar.current.date(byAdding: .day, value: -1, to: check) ?? check
        }
        return streak
    }
}

struct AddMeditationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var duration = 10
    @State private var type: MeditationType = .mindfulness
    @State private var moodBefore = 3
    @State private var moodAfter = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Stepper("Duration: \(duration) min", value: $duration, in: 1...120, step: 5)
                    .font(PulseFont.body(15))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type").font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MeditationType.allCases, id: \.self) { t in
                                Button { type = t } label: {
                                    Text(t.rawValue).font(PulseFont.body(12))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(type == t ? PulseColors.accent.opacity(0.15) : PulseColors.fillSubtle)
                                        .foregroundStyle(type == t ? PulseColors.accent : PulseColors.textSecondary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("Before").font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                        Stepper("\(moodBefore)/5", value: $moodBefore, in: 1...5).font(PulseFont.body(14))
                    }
                    VStack(spacing: 4) {
                        Text("After").font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                        Stepper("\(moodAfter)/5", value: $moodAfter, in: 1...5).font(PulseFont.body(14))
                    }
                }

                Spacer()
                Button { save() } label: {
                    Text("Log Session").font(PulseFont.bodySemibold(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
            .background(PulseColors.background)
            .navigationTitle("Meditation").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        modelContext.insert(MeditationLog(durationMinutes: duration, type: type, moodBefore: moodBefore, moodAfter: moodAfter))
        try? modelContext.save(); dismiss()
    }
}
