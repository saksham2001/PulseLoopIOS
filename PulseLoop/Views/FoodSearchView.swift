import SwiftUI
import SwiftData

// MARK: - Food Search / Add Food
//
// The add-food flow for the diary: search Open Food Facts + saved foods, scan a
// barcode, or describe a meal in natural language (AI/deterministic estimate). A
// chosen result opens a serving picker that writes a `MealLog` into the given meal
// type. Follows `.cursor/rules/design-system.mdc`.

struct FoodSearchView: View {
    let mealType: MealType
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var savedFoods: [FoodItem]

    @State private var query = ""
    @State private var offResults: [FoodItem] = []
    @State private var isSearching = false
    @State private var showScanner = false
    @State private var pendingFood: FoodItem?
    @State private var describeResult: FoodItem?
    @State private var scanError: String?

    private var matchingSaved: [FoodItem] {
        guard !query.isEmpty else {
            return NutritionStore.recentFoods(modelContext, limit: 12)
        }
        let q = query.lowercased()
        return savedFoods.filter { $0.name.lowercased().contains(q) || ($0.brand?.lowercased().contains(q) ?? false) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchBar
                actionRow
                if let scanError {
                    Text(scanError).font(PulseFont.body(12)).foregroundStyle(PulseColors.heartRate)
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    describeRow
                }
                resultsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(PulseColors.canvas)
        .navigationTitle("Add to \(mealType.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView { code in lookupBarcode(code) }
        }
        .sheet(item: $pendingFood) { food in
            ServingPickerSheet(food: food, mealType: mealType) { meal in
                log(meal, from: food)
            }
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PulseColors.textMuted)
            TextField("Search foods", text: $query)
                .font(PulseFont.body(15))
                .submitLabel(.search)
                .onSubmit { runSearch() }
            if isSearching {
                ProgressView().scaleEffect(0.7)
            } else if !query.isEmpty {
                Button { query = ""; offResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(PulseColors.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(PulseColors.fillMuted)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(icon: "barcode.viewfinder", label: "Scan barcode") { showScanner = true }
            actionButton(icon: "magnifyingglass", label: "Search online") { runSearch() }
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(label).font(PulseFont.bodyMedium(13))
            }
            .foregroundStyle(PulseColors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PulseColors.borderStrong, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Describe a meal (NL)

    private var describeRow: some View {
        Button { describeMeal() } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Estimate \"\(query)\"")
                        .font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                        .lineLimit(1)
                    Text("AI nutrition estimate from your description")
                        .font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                if describeResult != nil { ProgressView().scaleEffect(0.7) }
            }
            .padding(12)
            .pulseCardSurface(radius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        if !offResults.isEmpty {
            sectionLabel("ONLINE RESULTS")
            ForEach(offResults) { food in foodRow(food) }
        }
        let saved = matchingSaved
        if !saved.isEmpty {
            sectionLabel(query.isEmpty ? "RECENT FOODS" : "YOUR FOODS")
            ForEach(saved) { food in foodRow(food) }
        }
        if offResults.isEmpty && saved.isEmpty && !isSearching {
            Text(query.isEmpty ? "Search, scan a barcode, or describe what you ate." : "No saved foods match. Try \"Search online\" or describe the meal.")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textMuted)
                .padding(.top, 4)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(PulseFont.bodyMedium(11)).tracking(0.8)
            .foregroundStyle(PulseColors.textMuted)
            .padding(.top, 4)
    }

    private func foodRow(_ food: FoodItem) -> some View {
        Button { pendingFood = food } label: {
            HStack(spacing: 12) {
                Image(systemName: food.barcode != nil ? "barcode" : "fork.knife")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(food.name).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                        .lineLimit(1)
                    Text(detail(food)).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(food.caloriesPerServing) kcal")
                    .font(PulseFont.bodyMedium(12)).foregroundStyle(PulseColors.textSecondary)
            }
            .padding(12)
            .pulseCardSurface(radius: 14)
        }
        .buttonStyle(.plain)
    }

    private func detail(_ food: FoodItem) -> String {
        var parts: [String] = []
        if let b = food.brand, !b.isEmpty { parts.append(b) }
        parts.append("per \(food.servingDescription)")
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isSearching = true
        scanError = nil
        Task {
            let products = await OpenFoodFactsService.search(query: q)
            await MainActor.run {
                offResults = products.map { FoodItem.from(offProduct: $0) }
                isSearching = false
            }
        }
    }

    private func lookupBarcode(_ code: String) {
        isSearching = true
        scanError = nil
        Task {
            let product = await OpenFoodFactsService.lookup(barcode: code)
            await MainActor.run {
                isSearching = false
                if let product {
                    pendingFood = FoodItem.from(offProduct: product)
                } else {
                    scanError = "No product found for barcode \(code). Try searching by name."
                }
            }
        }
    }

    private func describeMeal() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            let est = await MealEstimator.estimate(q)
            await MainActor.run {
                isSearching = false
                guard let est else {
                    scanError = "Couldn't estimate that meal. Try a simpler description."
                    return
                }
                let food = FoodItem(
                    name: est.name,
                    servingDescription: "1 serving",
                    caloriesPerServing: est.calories,
                    proteinG: est.proteinG,
                    carbsG: est.carbsG,
                    fatG: est.fatG,
                    source: est.isAIGenerated ? "AI estimate" : "Estimate",
                    isCustom: true
                )
                pendingFood = food
            }
        }
    }

    private func log(_ meal: MealLog, from food: FoodItem) {
        modelContext.insert(meal)
        // Persist new (non-saved) foods so they appear in "recent" + de-dupe by barcode.
        let existing = savedFoods.first { f in
            (food.barcode != nil && f.barcode == food.barcode) ||
            (f.name == food.name && f.brand == food.brand)
        }
        if let existing {
            existing.lastUsedAt = Date()
        } else {
            food.lastUsedAt = Date()
            modelContext.insert(food)
        }
        modelContext.saveOrLog("nutrition.addfood")
        dismiss()
    }
}

// MARK: - Serving Picker Sheet

private struct ServingPickerSheet: View {
    let food: FoodItem
    let mealType: MealType
    let onLog: (MealLog) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var servings: Double = 1

    private var scaledCalories: Int { Int((Double(food.caloriesPerServing) * servings).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(food.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").foregroundStyle(PulseColors.textMuted)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SERVINGS (\(food.servingDescription))")
                    .font(PulseFont.bodyMedium(11)).tracking(0.8).foregroundStyle(PulseColors.textMuted)
                HStack(spacing: 14) {
                    stepperButton("minus") { servings = max(0.25, servings - 0.25) }
                    Text(formatted(servings))
                        .font(PulseFont.title(28)).foregroundStyle(PulseColors.textPrimary)
                        .frame(minWidth: 70)
                    stepperButton("plus") { servings += 0.25 }
                    Spacer()
                }
            }

            HStack(spacing: 16) {
                macroTile("Calories", "\(scaledCalories)")
                macroTile("Protein", grams(food.proteinG))
                macroTile("Carbs", grams(food.carbsG))
                macroTile("Fat", grams(food.fatG))
            }

            Button {
                onLog(food.makeMealLog(servings: servings, mealType: mealType))
            } label: {
                Text("Add to \(mealType.rawValue)")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(20)
        .background(PulseColors.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func stepperButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func macroTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
            Text(label).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func grams(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int((v * servings).rounded()))g"
    }
    private func formatted(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.2g", d)
    }
}
