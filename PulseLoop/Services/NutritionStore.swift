import Foundation
import SwiftData

// MARK: - Nutrition Diary Math (pure, testable)
//
// Day-level aggregation for the food diary: per-meal-type grouping, day totals, and
// remaining-vs-goal math. Kept free of SwiftUI/SwiftData specifics where possible so
// the numbers can be unit-tested directly.

/// A summed nutrition total for a set of meals (a section subtotal or a day total).
struct NutritionTotals: Equatable {
    var calories: Int = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double = 0
    var sugarG: Double = 0
    var sodiumMg: Double = 0

    static func + (lhs: NutritionTotals, rhs: NutritionTotals) -> NutritionTotals {
        NutritionTotals(
            calories: lhs.calories + rhs.calories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG,
            fiberG: lhs.fiberG + rhs.fiberG,
            sugarG: lhs.sugarG + rhs.sugarG,
            sodiumMg: lhs.sodiumMg + rhs.sodiumMg
        )
    }
}

enum NutritionDiary {
    /// Totals for an arbitrary list of meals.
    static func totals(of meals: [MealLog]) -> NutritionTotals {
        meals.reduce(into: NutritionTotals()) { acc, m in
            acc.calories += m.calories
            acc.proteinG += m.proteinG ?? 0
            acc.carbsG += m.carbsG ?? 0
            acc.fatG += m.fatG ?? 0
            acc.fiberG += m.fiberG ?? 0
            acc.sugarG += m.sugarG ?? 0
            acc.sodiumMg += m.sodiumMg ?? 0
        }
    }

    /// Meals for `day`, grouped by meal type in diary order. Planned meals excluded.
    static func grouped(_ meals: [MealLog], on day: Date) -> [(type: MealType, meals: [MealLog])] {
        let cal = Calendar.current
        let logged = meals.filter { !$0.isPlanned && cal.isDate($0.loggedAt, inSameDayAs: day) }
        return MealType.allCases
            .sorted { $0.order < $1.order }
            .map { type in
                (type, logged.filter { $0.mealType == type }.sorted { $0.loggedAt < $1.loggedAt })
            }
    }

    /// Calories remaining against the goal (can go negative when over budget).
    static func caloriesRemaining(goal: NutritionGoal?, consumed: NutritionTotals) -> Int {
        guard let goal else { return -consumed.calories }
        return goal.calories - consumed.calories
    }

    /// Fraction [0, 1] of a goal value consumed, clamped. Returns 0 when goal ≤ 0.
    static func progress(consumed: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(1, max(0, consumed / goal))
    }
}

// MARK: - Nutrition Store (SwiftData access for the diary)

@MainActor
enum NutritionStore {
    /// The currently active nutrition goal, if any.
    static func activeGoal(_ context: ModelContext) -> NutritionGoal? {
        let goals = (try? context.fetch(FetchDescriptor<NutritionGoal>())) ?? []
        return goals.first { $0.isActive } ?? goals.first
    }

    /// Set the active goal to the supplied values, deactivating any previous active
    /// goals so exactly one stays active. Returns the goal.
    @discardableResult
    static func setActiveGoal(
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double? = nil,
        sodiumMg: Double? = nil,
        in context: ModelContext
    ) -> NutritionGoal {
        let existing = (try? context.fetch(FetchDescriptor<NutritionGoal>())) ?? []
        for g in existing { g.isActive = false }
        let goal: NutritionGoal
        if let reuse = existing.first {
            reuse.calories = calories
            reuse.proteinG = proteinG
            reuse.carbsG = carbsG
            reuse.fatG = fatG
            reuse.fiberG = fiberG
            reuse.sodiumMg = sodiumMg
            reuse.isActive = true
            reuse.updatedAt = Date()
            goal = reuse
        } else {
            let created = NutritionGoal(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG, sodiumMg: sodiumMg, isActive: true)
            context.insert(created)
            goal = created
        }
        context.saveOrLog("nutrition.goal")
        return goal
    }

    /// Recently used / saved foods for the "My foods" quick re-log list.
    static func recentFoods(_ context: ModelContext, limit: Int = 20) -> [FoodItem] {
        let foods = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        return Array(
            foods.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
                .prefix(limit)
        )
    }
}

// MARK: - FoodItem ↔ MealLog mapping

extension FoodItem {
    /// Build a `MealLog` for this food at the given serving count + meal type. Macros
    /// scale linearly with `servings`.
    func makeMealLog(servings: Double, mealType: MealType, loggedAt: Date = Date()) -> MealLog {
        let s = max(0, servings)
        func scale(_ v: Double?) -> Double? { v.map { $0 * s } }
        return MealLog(
            name: brand.map { "\(name) (\($0))" } ?? name,
            description_: servingDescription,
            emoji: "fork.knife",
            calories: Int((Double(caloriesPerServing) * s).rounded()),
            proteinG: scale(proteinG),
            carbsG: scale(carbsG),
            fatG: scale(fatG),
            fiberG: scale(fiberG),
            sugarG: scale(sugarG),
            sodiumMg: scale(sodiumMg),
            mealType: mealType,
            servings: s,
            servingDescription: servingDescription,
            loggedAt: loggedAt
        )
    }
}

// MARK: - Open Food Facts → FoodItem

extension FoodItem {
    /// Map an Open Food Facts product (macros are per 100 g) into a saved `FoodItem`.
    /// We store the per-100g values as a "100 g" serving so logging math is uniform.
    static func from(offProduct p: OpenFoodFactsProduct) -> FoodItem {
        let n = p.nutriments
        return FoodItem(
            name: p.name,
            brand: p.brand,
            servingDescription: "100 g",
            caloriesPerServing: Int((n?.calories ?? 0).rounded()),
            proteinG: n?.protein,
            carbsG: n?.carbs,
            fatG: n?.fat,
            fiberG: n?.fiber,
            sugarG: n?.sugar,
            // OFF reports sodium in grams; convert to mg.
            sodiumMg: n?.sodium.map { $0 * 1000 },
            barcode: p.barcode,
            source: "Open Food Facts",
            isCustom: false
        )
    }
}
