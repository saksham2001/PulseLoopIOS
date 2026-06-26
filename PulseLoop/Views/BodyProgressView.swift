import SwiftUI
import SwiftData
import Charts

// MARK: - Body Progress & Goals
//
// MyFitnessPal-style progress hub: log body weight (and optional body-fat), see a
// weight trend chart with start → current → goal deltas, and edit the active
// nutrition goal (calorie + macro budget). All values respect the user's weight-unit
// preference; weight is stored in kilograms.

struct BodyProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMetric.date, order: .forward) private var metrics: [BodyMetric]
    @Query private var goals: [NutritionGoal]

    @AppStorage(WeightUnit.storageKey) private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @AppStorage("bodyGoalWeightKg") private var goalWeightKg: Double = 0

    @State private var showLogWeight = false
    @State private var showGoalEditor = false

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var weighIns: [BodyMetric] { metrics.filter { $0.weightKg != nil } }
    private var activeGoal: NutritionGoal? { goals.first { $0.isActive } ?? goals.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                weightCard
                if !weighIns.isEmpty { trendCard }
                nutritionGoalCard
                measurementsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(PulseColors.canvas)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticService.impact(.light)
                    showLogWeight = true
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log weight")
            }
        }
        .sheet(isPresented: $showLogWeight) {
            LogWeightSheet(unit: unit)
        }
        .sheet(isPresented: $showGoalEditor) {
            NutritionGoalEditor(goal: activeGoal)
        }
    }

    // MARK: Weight summary

    private var weightCard: some View {
        let current = weighIns.last?.weightKg
        let start = weighIns.first?.weightKg
        return VStack(alignment: .leading, spacing: 14) {
            Text("Weight")
                .font(PulseFont.titleMedium(20))
                .foregroundStyle(PulseColors.textPrimary)
            HStack(spacing: 0) {
                weightStat("Current", current)
                Divider().frame(height: 40)
                weightStat("Start", start)
                Divider().frame(height: 40)
                if goalWeightKg > 0 {
                    weightStat("Goal", goalWeightKg)
                } else {
                    Button {
                        HapticService.impact(.light)
                        showLogWeight = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "flag")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(PulseColors.textSecondary)
                            Text("Set goal").font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let current, let start, abs(current - start) > 0.05 {
                let deltaKg = current - start
                Label {
                    Text("\(deltaKg < 0 ? "Down" : "Up") \(unit.displayValue(fromKilograms: abs(deltaKg))) \(unit.label) since start")
                        .font(PulseFont.bodyMedium(13))
                } icon: {
                    Image(systemName: deltaKg < 0 ? "arrow.down.right" : "arrow.up.right")
                }
                .foregroundStyle(deltaKg < 0 ? PulseColors.success : PulseColors.textSecondary)
            }
        }
        .padding(16)
        .pulseCardSurface()
    }

    private func weightStat(_ label: String, _ kg: Double?) -> some View {
        VStack(spacing: 2) {
            Text(kg.map { unit.displayValue(fromKilograms: $0) } ?? "—")
                .font(PulseFont.titleMedium(24))
                .foregroundStyle(PulseColors.textPrimary)
            Text(label).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Trend chart

    private var trendCard: some View {
        let points = weighIns.suffix(60)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Trend").font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textSecondary)
            Chart {
                ForEach(points) { m in
                    if let kg = m.weightKg {
                        LineMark(
                            x: .value("Date", m.date),
                            y: .value("Weight", unit.fromKilograms(kg))
                        )
                        .foregroundStyle(PulseColors.textPrimary)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Date", m.date),
                            y: .value("Weight", unit.fromKilograms(kg))
                        )
                        .foregroundStyle(LinearGradient(colors: [PulseColors.textPrimary.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    }
                }
                if goalWeightKg > 0 {
                    RuleMark(y: .value("Goal", unit.fromKilograms(goalWeightKg)))
                        .foregroundStyle(PulseColors.success.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Goal").font(PulseFont.body(10)).foregroundStyle(PulseColors.success)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
        }
        .padding(16)
        .pulseCardSurface()
    }

    // MARK: Nutrition goal

    private var nutritionGoalCard: some View {
        Button {
            HapticService.impact(.light)
            showGoalEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nutrition Goal").font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textSecondary)
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(PulseColors.textMuted)
                }
                if let g = activeGoal {
                    HStack(spacing: 0) {
                        goalStat("\(g.calories)", "kcal")
                        Divider().frame(height: 32)
                        goalStat("\(Int(g.proteinG))g", "protein")
                        Divider().frame(height: 32)
                        goalStat("\(Int(g.carbsG))g", "carbs")
                        Divider().frame(height: 32)
                        goalStat("\(Int(g.fatG))g", "fat")
                    }
                } else {
                    Text("Set a daily calorie + macro budget")
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
                }
            }
            .padding(16)
            .pulseCardSurface()
        }
        .buttonStyle(.plain)
    }

    private func goalStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(PulseFont.bodySemibold(16)).foregroundStyle(PulseColors.textPrimary)
            Text(label).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Measurements

    @ViewBuilder
    private var measurementsCard: some View {
        let latest = metrics.last { $0.bodyFatPercent != nil || $0.waistCm != nil }
        if let latest {
            VStack(alignment: .leading, spacing: 12) {
                Text("Measurements").font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textSecondary)
                HStack(spacing: 0) {
                    if let bf = latest.bodyFatPercent { goalStat(String(format: "%.1f%%", bf), "body fat") }
                    if let waist = latest.waistCm { goalStat("\(Int(waist)) cm", "waist") }
                    if let chest = latest.chestCm { goalStat("\(Int(chest)) cm", "chest") }
                }
            }
            .padding(16)
            .pulseCardSurface()
        }
    }
}

// MARK: - Log Weight Sheet

struct LogWeightSheet: View {
    let unit: WeightUnit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bodyGoalWeightKg") private var goalWeightKg: Double = 0

    @State private var weight = ""
    @State private var bodyFat = ""
    @State private var goalWeight = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Weigh-in") {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("0", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text(unit.label).foregroundStyle(PulseColors.textMuted)
                    }
                    HStack {
                        Text("Body fat")
                        Spacer()
                        TextField("optional", text: $bodyFat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("%").foregroundStyle(PulseColors.textMuted)
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section("Goal weight") {
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField(goalWeightKg > 0 ? unit.displayValue(fromKilograms: goalWeightKg) : "optional", text: $goalWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text(unit.label).foregroundStyle(PulseColors.textMuted)
                    }
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(Double(weight) == nil && goalWeight.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let entered = Double(weight), entered > 0 {
            let metric = BodyMetric(
                date: date,
                weightKg: unit.toKilograms(entered),
                bodyFatPercent: Double(bodyFat)
            )
            modelContext.insert(metric)
        }
        if let g = Double(goalWeight), g > 0 {
            goalWeightKg = unit.toKilograms(g)
        }
        modelContext.saveOrLog("body.weight")
        HapticService.success()
        dismiss()
    }
}

// MARK: - Nutrition Goal Editor

struct NutritionGoalEditor: View {
    let goal: NutritionGoal?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var calories: Int
    @State private var proteinG: Double
    @State private var carbsG: Double
    @State private var fatG: Double

    init(goal: NutritionGoal?) {
        self.goal = goal
        _calories = State(initialValue: goal?.calories ?? 2000)
        _proteinG = State(initialValue: goal?.proteinG ?? 150)
        _carbsG = State(initialValue: goal?.carbsG ?? 200)
        _fatG = State(initialValue: goal?.fatG ?? 67)
    }

    private var macroCalories: Int {
        Int((proteinG * 4 + carbsG * 4 + fatG * 9).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily calories") {
                    Stepper(value: $calories, in: 1000...6000, step: 50) {
                        HStack {
                            Text("Calories")
                            Spacer()
                            Text("\(calories) kcal").foregroundStyle(PulseColors.textSecondary)
                        }
                    }
                }
                Section {
                    macroStepper("Protein", value: $proteinG, tint: PulseColors.accent)
                    macroStepper("Carbs", value: $carbsG, tint: PulseColors.warning)
                    macroStepper("Fat", value: $fatG, tint: PulseColors.success)
                } header: {
                    Text("Macros")
                } footer: {
                    Text("Macros total \(macroCalories) kcal\(macroCalories != calories ? " — \(macroCalories < calories ? "under" : "over") your calorie goal" : "").")
                        .foregroundStyle(abs(macroCalories - calories) > 100 ? PulseColors.warning : PulseColors.textMuted)
                }
            }
            .navigationTitle("Nutrition Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        NutritionStore.setActiveGoal(
                            calories: calories,
                            proteinG: proteinG,
                            carbsG: carbsG,
                            fatG: fatG,
                            in: modelContext
                        )
                        HapticService.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func macroStepper(_ label: String, value: Binding<Double>, tint: Color) -> some View {
        Stepper(value: value, in: 0...500, step: 5) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue)) g").foregroundStyle(PulseColors.textSecondary)
            }
        }
    }
}
