import SwiftUI
import SwiftData

// MARK: - Workout Tracking View

struct WorkoutTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutLog.date, order: .reverse) private var workouts: [WorkoutLog]
    @State private var showAddWorkout = false

    var body: some View {
        VStack(spacing: 16) {
            header
            weekSummary
            if !workouts.isEmpty {
                recentWorkouts
            }
        }
        .sheet(isPresented: $showAddWorkout) {
            AddWorkoutSheet()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("WORKOUTS")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Text(weeklyLabel)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            Spacer()
            Button { showAddWorkout = true } label: {
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
    }

    private var weeklyLabel: String {
        let thisWeek = workouts.filter { $0.date > (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()) }
        let totalMin = thisWeek.reduce(0) { $0 + $1.durationMinutes }
        return "\(thisWeek.count) sessions · \(totalMin)min this week"
    }

    private var weekSummary: some View {
        let thisWeek = workouts.filter { $0.date > (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()) }
        let totalCal = thisWeek.compactMap(\.caloriesBurned).reduce(0, +)

        return HStack(spacing: 10) {
            summaryCard("dumbbell.fill", "\(thisWeek.count)", "Sessions")
            summaryCard("flame.fill", "\(totalCal)", "Calories")
            summaryCard("clock.fill", "\(thisWeek.reduce(0) { $0 + $1.durationMinutes })", "Minutes")
        }
    }

    private func summaryCard(_ systemIcon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
            Text(value)
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textPrimary)
            Text(label)
                .font(PulseFont.body(10))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var recentWorkouts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(PulseFont.bodyMedium(12))
                .foregroundStyle(PulseColors.textSecondary)
            ForEach(workouts.prefix(5)) { w in
                HStack(spacing: 12) {
                    Image(systemName: w.type.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PulseColors.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.name)
                            .font(PulseFont.bodySemibold(14))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("\(w.durationMinutes)min · Intensity \(w.intensity)/10")
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    Spacer()
                    Text(w.date, style: .date)
                        .font(PulseFont.body(11))
                        .foregroundStyle(PulseColors.textFaint)
                }
                .padding(.vertical, 4)
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
}

// MARK: - Add Workout Sheet

struct AddWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: WorkoutType = .strength
    @State private var duration = 30
    @State private var intensity = 5
    @State private var calories = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TextField("Workout name", text: $name)
                        .font(PulseFont.body(15))
                        .padding(12)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(WorkoutType.allCases, id: \.self) { t in
                                    Button { type = t } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: t.icon)
                                                .font(.system(size: 11, weight: .medium))
                                            Text(t.rawValue)
                                                .font(PulseFont.body(12))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(type == t ? PulseColors.accent.opacity(0.15) : PulseColors.fillSubtle)
                                        .foregroundStyle(type == t ? PulseColors.accent : PulseColors.textSecondary)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Duration (min)")
                                .font(PulseFont.bodyMedium(13))
                                .foregroundStyle(PulseColors.textMuted)
                            Stepper("\(duration) min", value: $duration, in: 5...300, step: 5)
                                .font(PulseFont.body(14))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Intensity: \(intensity)/10")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                        HStack(spacing: 4) {
                            ForEach(1...10, id: \.self) { i in
                                Button { intensity = i } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(i <= intensity ? PulseColors.accent : PulseColors.fillSubtle)
                                        .frame(height: 28)
                                }
                            }
                        }
                    }

                    TextField("Calories burned (optional)", text: $calories)
                        .font(PulseFont.body(15))
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button { save() } label: {
                        Text("Log Workout")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(name.isEmpty ? PulseColors.textMuted : PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(name.isEmpty)
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let w = WorkoutLog(
            type: type,
            name: name,
            durationMinutes: duration,
            caloriesBurned: Int(calories),
            intensity: intensity,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(w)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Body Metrics View

struct BodyMetricsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if let latest = metrics.first {
                currentMetrics(latest)
            }
            if metrics.count > 1 {
                weightTrend
            }
        }
        .sheet(isPresented: $showAdd) {
            AddBodyMetricSheet()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("BODY")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Text(trendLabel)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            Spacer()
            Button { showAdd = true } label: {
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
    }

    private var trendLabel: String {
        guard metrics.count >= 2, let current = metrics.first?.weightKg, let prev = metrics.dropFirst().first?.weightKg else {
            return "Log your first measurement"
        }
        let diff = current - prev
        let sign = diff >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", diff)) kg since last"
    }

    private func currentMetrics(_ m: BodyMetric) -> some View {
        HStack(spacing: 12) {
            if let w = m.weightKg {
                metricPill("scalemass.fill", String(format: "%.1f", w), "kg")
            }
            if let bf = m.bodyFatPercent {
                metricPill("chart.bar.fill", String(format: "%.1f", bf), "% BF")
            }
            if let mm = m.muscleMassKg {
                metricPill("figure.strengthtraining.traditional", String(format: "%.1f", mm), "kg muscle")
            }
        }
    }

    private func metricPill(_ systemIcon: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
            Text(value)
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textPrimary)
            Text(unit)
                .font(PulseFont.body(10))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var weightTrend: some View {
        let recent = Array(metrics.prefix(10).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            Text("Weight Trend")
                .font(PulseFont.bodyMedium(12))
                .foregroundStyle(PulseColors.textSecondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(recent.enumerated()), id: \.offset) { _, m in
                    let w = m.weightKg ?? 0
                    let minW = recent.compactMap(\.weightKg).min() ?? 0
                    let maxW = recent.compactMap(\.weightKg).max() ?? 100
                    let range = max(maxW - minW, 1)
                    let h = max(CGFloat((w - minW) / range) * 50, 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PulseColors.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
                }
            }
            .frame(height: 60)
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

// MARK: - Add Body Metric Sheet

struct AddBodyMetricSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var bodyFat = ""
    @State private var muscle = ""
    @State private var waist = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    field("Weight (kg)", text: $weight)
                    field("Body Fat %", text: $bodyFat)
                    field("Muscle Mass (kg)", text: $muscle)
                    field("Waist (cm)", text: $waist)

                    Button { save() } label: {
                        Text("Save Measurement")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Body Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(PulseFont.bodyMedium(13))
                .foregroundStyle(PulseColors.textMuted)
            TextField(label, text: text)
                .font(PulseFont.body(15))
                .keyboardType(.decimalPad)
                .padding(12)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func save() {
        let m = BodyMetric(
            weightKg: Double(weight),
            bodyFatPercent: Double(bodyFat),
            muscleMassKg: Double(muscle),
            waistCm: Double(waist)
        )
        modelContext.insert(m)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Habits View

struct HabitsTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.name) private var habits: [Habit]
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if habits.isEmpty {
                emptyState
            } else {
                habitsGrid
            }
        }
        .sheet(isPresented: $showAdd) {
            AddHabitSheet()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("HABITS")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Text(streakLabel)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            Spacer()
            Button { showAdd = true } label: {
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
        }
    }

    private var streakLabel: String {
        let completed = habits.filter(\.completedToday).count
        return "\(completed)/\(habits.count) done today"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(PulseColors.textMuted)
            Text("Add habits to track")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var habitsGrid: some View {
        VStack(spacing: 8) {
            ForEach(habits.filter(\.isActive)) { habit in
                habitRow(habit)
            }
        }
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack(spacing: 12) {
            Button { toggleHabit(habit) } label: {
                ZStack {
                    Circle()
                        .fill(habit.completedToday ? PulseColors.accent : PulseColors.fillSubtle)
                        .frame(width: 36, height: 36)
                    if habit.completedToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(habit.emoji)
                            .font(.system(size: 16))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(habit.completedToday ? PulseColors.textMuted : PulseColors.textPrimary)
                    .strikethrough(habit.completedToday)
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(PulseColors.textMuted)
                    Text("\(habit.currentStreak) day streak")
                }
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Spacer()

            Text(habit.frequency.rawValue)
                .font(PulseFont.body(11))
                .foregroundStyle(PulseColors.textFaint)
        }
        .padding(12)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func toggleHabit(_ habit: Habit) {
        if habit.completedToday {
            if let log = habit.logs.first(where: { Calendar.current.isDateInToday($0.date) }) {
                modelContext.delete(log)
            }
        } else {
            let log = HabitLog()
            habit.logs.append(log)
        }
        try? modelContext.save()
    }
}

// MARK: - Add Habit Sheet

struct AddHabitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "checkmark"
    @State private var frequency: HabitFrequency = .daily

    private let iconOptions = ["checkmark", "figure.yoga", "drop.fill", "book.fill", "figure.run", "snowflake", "sun.max.fill", "pills.fill", "leaf.fill", "moon.fill", "pencil", "target"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Habit name", text: $name)
                    .font(PulseFont.body(15))
                    .padding(12)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(PulseFont.bodyMedium(13))
                        .foregroundStyle(PulseColors.textMuted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(iconOptions, id: \.self) { ic in
                            Button { emoji = ic } label: {
                                Image(systemName: ic)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(emoji == ic ? PulseColors.accent : PulseColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(emoji == ic ? PulseColors.accent.opacity(0.12) : PulseColors.fillSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(emoji == ic ? PulseColors.accent : Color.clear, lineWidth: 1.5)
                                    }
                            }
                        }
                    }
                }

                Picker("Frequency", selection: $frequency) {
                    ForEach(HabitFrequency.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button { save() } label: {
                    Text("Create Habit")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(name.isEmpty ? PulseColors.textMuted : PulseColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(name.isEmpty)
            }
            .padding(20)
            .background(PulseColors.background)
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let h = Habit(name: name, emoji: emoji, frequency: frequency)
        modelContext.insert(h)
        try? modelContext.save()
        dismiss()
    }
}
