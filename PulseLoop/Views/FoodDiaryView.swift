import SwiftUI
import SwiftData

// MARK: - Food Diary (MyFitnessPal-style nutrition diary)
//
// A real food diary: a day selector, a calorie ring + macro bars showing the day's
// total against the active `NutritionGoal`, and Breakfast/Lunch/Dinner/Snacks
// sections each listing logged foods with per-section subtotals and an "Add food"
// action. Follows `.cursor/rules/design-system.mdc`.

struct FoodDiaryView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Query private var meals: [MealLog]
    @Query private var goals: [NutritionGoal]

    @State private var day: Date = Calendar.current.startOfDay(for: Date())

    private var activeGoal: NutritionGoal? {
        goals.first { $0.isActive } ?? goals.first
    }

    private var dayMeals: [MealLog] {
        let cal = Calendar.current
        return meals.filter { !$0.isPlanned && cal.isDate($0.loggedAt, inSameDayAs: day) }
    }

    private var totals: NutritionTotals { NutritionDiary.totals(of: dayMeals) }

    private var grouped: [(type: MealType, meals: [MealLog])] {
        NutritionDiary.grouped(meals, on: day)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dateSelector
                summaryCard
                NutritionCoachCard(totals: totals, goal: activeGoal)
                ForEach(grouped, id: \.type) { section in
                    mealSection(section.type, meals: section.meals)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(PulseColors.canvas)
        .navigationTitle("Food Diary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { path.append(AppRoute.bodyProgress) } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(PulseColors.textPrimary)
                }
            }
        }
    }

    // MARK: Date selector

    private var dateSelector: some View {
        HStack {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulseColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 1) {
                Text(dayTitle).font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                if !Calendar.current.isDateInToday(day) {
                    Text(day.formatted(.dateTime.weekday(.wide)))
                        .font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                }
            }
            Spacer()
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isToday ? PulseColors.textFaint : PulseColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isToday)
        }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var dayTitle: String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }
    private func shiftDay(_ delta: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: delta, to: day) else { return }
        if delta > 0 && d > Calendar.current.startOfDay(for: Date()) { return }
        day = Calendar.current.startOfDay(for: d)
    }

    // MARK: Summary (calorie ring + macros)

    private var summaryCard: some View {
        PulseCard {
            VStack(spacing: 16) {
                HStack(spacing: 18) {
                    CalorieRing(
                        consumed: totals.calories,
                        goal: activeGoal?.calories ?? 0
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        let remaining = NutritionDiary.caloriesRemaining(goal: activeGoal, consumed: totals)
                        Text("\(abs(remaining))")
                            .font(PulseFont.title(28))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text(activeGoal == nil ? "calories logged" : (remaining >= 0 ? "calories remaining" : "calories over"))
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.textMuted)
                        if activeGoal == nil {
                            Button { path.append(AppRoute.bodyProgress) } label: {
                                Text("Set a goal")
                                    .font(PulseFont.bodyMedium(12))
                                    .foregroundStyle(PulseColors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                if let goal = activeGoal {
                    VStack(spacing: 8) {
                        MacroBar(label: "Protein", value: Int(totals.proteinG), goal: Int(goal.proteinG), color: PulseColors.heartRate)
                        MacroBar(label: "Carbs", value: Int(totals.carbsG), goal: Int(goal.carbsG), color: PulseColors.calories)
                        MacroBar(label: "Fat", value: Int(totals.fatG), goal: Int(goal.fatG), color: PulseColors.sleep)
                    }
                }
            }
        }
    }

    // MARK: Meal section

    private func mealSection(_ type: MealType, meals: [MealLog]) -> some View {
        let subtotal = NutritionDiary.totals(of: meals)
        return PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: type.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(type.rawValue.uppercased())
                        .font(PulseFont.bodyMedium(11))
                        .tracking(0.8)
                        .foregroundStyle(PulseColors.textMuted)
                    Spacer()
                    if subtotal.calories > 0 {
                        Text("\(subtotal.calories) kcal")
                            .font(PulseFont.bodyMedium(12))
                            .foregroundStyle(PulseColors.textSecondary)
                    }
                }
                if meals.isEmpty {
                    Text("Nothing logged")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textFaint)
                        .padding(.vertical, 2)
                } else {
                    ForEach(meals) { meal in
                        diaryRow(meal)
                    }
                }
                Button { path.append(AppRoute.foodSearch(type.rawValue)) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Add food")
                            .font(PulseFont.bodyMedium(13))
                    }
                    .foregroundStyle(PulseColors.textPrimary)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func diaryRow(_ meal: MealLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: meal.emoji.isEmpty ? "fork.knife" : meal.emoji)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 30, height: 30)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(meal.name).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                    .lineLimit(1)
                Text(macroLine(meal)).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Text("\(meal.calories)")
                .font(PulseFont.bodyMedium(13))
                .foregroundStyle(PulseColors.textPrimary)
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.delete(meal)
                modelContext.saveOrLog("nutrition.diary")
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func macroLine(_ meal: MealLog) -> String {
        var parts: [String] = []
        if let p = meal.proteinG { parts.append("P \(Int(p))") }
        if let c = meal.carbsG { parts.append("C \(Int(c))") }
        if let f = meal.fatG { parts.append("F \(Int(f))") }
        if meal.servings != 1 { parts.append("× \(formatted(meal.servings))") }
        return parts.isEmpty ? (meal.servingDescription ?? "") : parts.joined(separator: " · ")
    }

    private func formatted(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
}

// MARK: - Calorie Ring

struct CalorieRing: View {
    let consumed: Int
    let goal: Int

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(1, max(0, Double(consumed) / Double(goal)))
    }
    private var over: Bool { goal > 0 && consumed > goal }

    var body: some View {
        ZStack {
            Circle()
                .stroke(PulseColors.fillSubtle, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    over ? PulseColors.heartRate : PulseColors.textPrimary,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(consumed)")
                    .font(PulseFont.bodySemibold(17))
                    .foregroundStyle(PulseColors.textPrimary)
                if goal > 0 {
                    Text("/ \(goal)")
                        .font(PulseFont.body(10))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
        }
        .frame(width: 74, height: 74)
    }
}
