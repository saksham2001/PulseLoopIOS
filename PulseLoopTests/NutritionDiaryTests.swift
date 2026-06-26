import XCTest
import SwiftData
@testable import PulseLoop

@MainActor
final class NutritionDiaryTests: XCTestCase {

    // MARK: - Totals & grouping

    func testTotalsSumsMacrosAndMicros() {
        let meals = [
            MealLog(name: "Eggs", calories: 200, proteinG: 14, carbsG: 2, fatG: 14, fiberG: 0, sugarG: 1, sodiumMg: 180, mealType: .breakfast),
            MealLog(name: "Toast", calories: 150, proteinG: 5, carbsG: 28, fatG: 2, fiberG: 3, sugarG: 4, sodiumMg: 220, mealType: .breakfast),
        ]
        let t = NutritionDiary.totals(of: meals)
        XCTAssertEqual(t.calories, 350)
        XCTAssertEqual(t.proteinG, 19)
        XCTAssertEqual(t.carbsG, 30)
        XCTAssertEqual(t.fatG, 16)
        XCTAssertEqual(t.fiberG, 3)
        XCTAssertEqual(t.sodiumMg, 400)
    }

    func testGroupedByMealTypeInDiaryOrderAndExcludesOtherDays() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let meals = [
            MealLog(name: "Dinner today", calories: 600, mealType: .dinner, loggedAt: today),
            MealLog(name: "Breakfast today", calories: 300, mealType: .breakfast, loggedAt: today),
            MealLog(name: "Old lunch", calories: 500, mealType: .lunch, loggedAt: yesterday),
            MealLog(name: "Planned", calories: 100, mealType: .snack, isPlanned: true, loggedAt: today),
        ]
        let groups = NutritionDiary.grouped(meals, on: today)
        XCTAssertEqual(groups.map(\.type), [.breakfast, .lunch, .dinner, .snack])
        XCTAssertEqual(groups[0].meals.map(\.name), ["Breakfast today"])
        XCTAssertTrue(groups[1].meals.isEmpty)  // yesterday's lunch excluded
        XCTAssertEqual(groups[2].meals.map(\.name), ["Dinner today"])
        XCTAssertTrue(groups[3].meals.isEmpty)  // planned excluded
    }

    func testCaloriesRemainingAndProgress() {
        let goal = NutritionGoal(calories: 2000, proteinG: 150, carbsG: 200, fatG: 67)
        var consumed = NutritionTotals(); consumed.calories = 1400
        XCTAssertEqual(NutritionDiary.caloriesRemaining(goal: goal, consumed: consumed), 600)
        consumed.calories = 2300
        XCTAssertEqual(NutritionDiary.caloriesRemaining(goal: goal, consumed: consumed), -300)
        XCTAssertEqual(NutritionDiary.caloriesRemaining(goal: nil, consumed: consumed), -2300)
        XCTAssertEqual(NutritionDiary.progress(consumed: 100, goal: 200), 0.5, accuracy: 0.001)
        XCTAssertEqual(NutritionDiary.progress(consumed: 300, goal: 200), 1.0)
        XCTAssertEqual(NutritionDiary.progress(consumed: 50, goal: 0), 0)
    }

    // MARK: - FoodItem mapping & logging

    func testFoodItemMakeMealLogScalesMacros() {
        let food = FoodItem(name: "Rice", servingDescription: "100 g", caloriesPerServing: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3, fiberG: 0.4)
        let meal = food.makeMealLog(servings: 2, mealType: .lunch)
        XCTAssertEqual(meal.calories, 260)
        XCTAssertEqual(meal.proteinG ?? 0, 5.4, accuracy: 0.001)
        XCTAssertEqual(meal.carbsG ?? 0, 56, accuracy: 0.001)
        XCTAssertEqual(meal.mealType, .lunch)
        XCTAssertEqual(meal.servings, 2)
    }

    func testFoodItemFromOFFConvertsSodiumToMg() {
        let product = OpenFoodFactsProduct(
            name: "Granola",
            brand: "Acme",
            categories: [],
            ingredients: nil,
            nutriments: OFFNutriments(calories: 450, protein: 9, carbs: 64, fat: 16, fiber: 7, sugar: 20, sodium: 0.2),
            imageURL: nil,
            barcode: "111222333"
        )
        let food = FoodItem.from(offProduct: product)
        XCTAssertEqual(food.name, "Granola")
        XCTAssertEqual(food.brand, "Acme")
        XCTAssertEqual(food.caloriesPerServing, 450)
        XCTAssertEqual(food.servingDescription, "100 g")
        XCTAssertEqual(food.sodiumMg ?? 0, 200, accuracy: 0.001) // 0.2 g -> 200 mg
        XCTAssertEqual(food.barcode, "111222333")
        XCTAssertEqual(food.source, "Open Food Facts")
        XCTAssertFalse(food.isCustom)
    }

    // MARK: - NutritionStore goal management

    func testSetActiveGoalKeepsSingleActive() throws {
        let ctx = try TestSupport.makeContext()
        let g1 = NutritionStore.setActiveGoal(calories: 2000, proteinG: 150, carbsG: 200, fatG: 67, in: ctx)
        XCTAssertTrue(g1.isActive)
        let g2 = NutritionStore.setActiveGoal(calories: 2200, proteinG: 170, carbsG: 210, fatG: 70, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<NutritionGoal>())
        XCTAssertEqual(all.filter { $0.isActive }.count, 1)
        XCTAssertEqual(NutritionStore.activeGoal(ctx)?.calories, 2200)
        XCTAssertEqual(g2.calories, 2200)
    }

    func testRecentFoodsSortedByLastUsed() throws {
        let ctx = try TestSupport.makeContext()
        let a = FoodItem(name: "A"); a.lastUsedAt = Date(timeIntervalSince1970: 100)
        let b = FoodItem(name: "B"); b.lastUsedAt = Date(timeIntervalSince1970: 200)
        ctx.insert(a); ctx.insert(b)
        try ctx.save()
        let recents = NutritionStore.recentFoods(ctx)
        XCTAssertEqual(recents.first?.name, "B")
    }
}
