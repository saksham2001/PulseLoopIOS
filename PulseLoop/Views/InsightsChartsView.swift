import SwiftUI
import Charts
import SwiftData

struct InsightsChartsView: View {
    @Query(sort: \MealLog.loggedAt, order: .reverse) private var meals: [MealLog]
    @Query(sort: \MedicationLog.loggedAt, order: .reverse) private var medLogs: [MedicationLog]
    @Query(sort: \Medication.name) private var medications: [Medication]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                streakCard
                calorieChart
                adherenceChart
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(PulseColors.background)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        let streak = calculateStreak()
        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT STREAK")
                        .font(PulseFont.bodyMedium(11))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(streak)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("days")
                            .font(PulseFont.body(16))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(streak > 0 ? Color.orange : PulseColors.textFaint)
            }

            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { dayOffset in
                    let date = Calendar.current.date(byAdding: .day, value: -(6 - dayOffset), to: Date()) ?? Date()
                    let hasLog = dayHasLog(date)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(hasLog ? Color.black : PulseColors.fillSubtle)
                        .frame(height: 28)
                        .overlay {
                            Text(shortDay(date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(hasLog ? .white : PulseColors.textMuted)
                        }
                }
            }
        }
        .padding(16)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    // MARK: - Calorie Chart

    private var calorieChart: some View {
        let data = last7DaysCalories()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CALORIES · 7 DAYS")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                if let avg = data.isEmpty ? nil : data.map(\.calories).reduce(0, +) / data.count {
                    Text("avg \(avg) kcal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }

            if data.isEmpty {
                Text("Log meals to see your calorie trend")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(data) { point in
                    AreaMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Calories", point.calories)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Color.black.opacity(0.1), Color.clear], startPoint: .top, endPoint: .bottom)
                    )

                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Calories", point.calories)
                    )
                    .foregroundStyle(Color.black)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Calories", point.calories)
                    )
                    .foregroundStyle(Color.black)
                    .symbolSize(20)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel()
                            .font(.system(size: 10))
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(16)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    // MARK: - Adherence Chart

    private var adherenceChart: some View {
        let data = last7DaysAdherence()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUPPLEMENT ADHERENCE · 7 DAYS")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                if let avg = data.isEmpty ? nil : data.map(\.percentage).reduce(0, +) / data.count {
                    Text("\(avg)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }

            if medications.isEmpty {
                Text("Add supplements to track adherence")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(data) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Adherence", point.percentage)
                    )
                    .foregroundStyle(point.percentage >= 80 ? Color.black : Color.black.opacity(0.3))
                    .cornerRadius(4)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisValueLabel {
                            Text("\(value.as(Int.self) ?? 0)%")
                                .font(.system(size: 10))
                        }
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(16)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    // MARK: - Data Helpers

    struct CaloriePoint: Identifiable {
        let id = UUID()
        let date: Date
        let calories: Int
    }

    struct AdherencePoint: Identifiable {
        let id = UUID()
        let date: Date
        let percentage: Int
    }

    private func last7DaysCalories() -> [CaloriePoint] {
        let cal = Calendar.current
        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let startOfDay = cal.startOfDay(for: date)
            guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
            let dayMeals = meals.filter { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay }
            let total = dayMeals.reduce(0) { $0 + $1.calories }
            return total > 0 ? CaloriePoint(date: startOfDay, calories: total) : nil
        }.reversed()
    }

    private func last7DaysAdherence() -> [AdherencePoint] {
        let cal = Calendar.current
        let activeMedCount = medications.filter(\.isActive).count
        guard activeMedCount > 0 else { return [] }

        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let startOfDay = cal.startOfDay(for: date)
            guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
            let dayLogs = medLogs.filter { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay && $0.statusRaw == "taken" }
            let uniqueMedsTaken = Set(dayLogs.map(\.medicationId)).count
            let pct = min(100, (uniqueMedsTaken * 100) / activeMedCount)
            return AdherencePoint(date: startOfDay, percentage: pct)
        }.reversed()
    }

    private func calculateStreak() -> Int {
        let cal = Calendar.current
        var streak = 0
        let activeMedCount = medications.filter(\.isActive).count
        guard activeMedCount > 0 else { return 0 }

        for offset in 0..<365 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { break }
            let startOfDay = cal.startOfDay(for: date)
            guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { break }
            let dayLogs = medLogs.filter { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay && $0.statusRaw == "taken" }
            let uniqueMedsTaken = Set(dayLogs.map(\.medicationId)).count
            if uniqueMedsTaken >= activeMedCount / 2 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private func dayHasLog(_ date: Date) -> Bool {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return false }
        return medLogs.contains { $0.loggedAt >= startOfDay && $0.loggedAt < endOfDay && $0.statusRaw == "taken" }
    }

    private func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(1))
    }
}
