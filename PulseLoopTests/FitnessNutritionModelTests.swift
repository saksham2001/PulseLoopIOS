import XCTest
import SwiftData
@testable import PulseLoop

@MainActor
final class FitnessNutritionModelTests: XCTestCase {

    // MARK: - MealLog extended fields

    func testMealLogPersistsExtendedFields() throws {
        let ctx = try TestSupport.makeContext()
        let meal = MealLog(
            name: "Greek yogurt bowl",
            calories: 320,
            proteinG: 24,
            carbsG: 38,
            fatG: 8,
            fiberG: 5,
            sugarG: 18,
            sodiumMg: 95,
            mealType: .breakfast,
            servings: 1.5,
            servingDescription: "1.5 cups"
        )
        ctx.insert(meal)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<MealLog>()).first)
        XCTAssertEqual(fetched.fiberG, 5)
        XCTAssertEqual(fetched.sugarG, 18)
        XCTAssertEqual(fetched.sodiumMg, 95)
        XCTAssertEqual(fetched.mealType, .breakfast)
        XCTAssertEqual(fetched.servings, 1.5)
        XCTAssertEqual(fetched.servingDescription, "1.5 cups")
    }

    func testMealTypeForCurrentTimeBuckets() {
        func at(_ hour: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        }
        XCTAssertEqual(MealType.forCurrentTime(at(8)), .breakfast)
        XCTAssertEqual(MealType.forCurrentTime(at(13)), .lunch)
        XCTAssertEqual(MealType.forCurrentTime(at(19)), .dinner)
        XCTAssertEqual(MealType.forCurrentTime(at(2)), .snack)
    }

    func testMealTypeDiaryOrdering() {
        let ordered = MealType.allCases.sorted { $0.order < $1.order }
        XCTAssertEqual(ordered, [.breakfast, .lunch, .dinner, .snack])
    }

    // MARK: - NutritionGoal

    func testNutritionGoalPersistsAndMacroMath() throws {
        let ctx = try TestSupport.makeContext()
        let goal = NutritionGoal(calories: 2100, proteinG: 160, carbsG: 210, fatG: 70)
        ctx.insert(goal)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<NutritionGoal>()).first)
        XCTAssertTrue(fetched.isActive)
        // 160*4 + 210*4 + 70*9 = 640 + 840 + 630 = 2110
        XCTAssertEqual(fetched.caloriesFromMacros, 2110)
    }

    // MARK: - FoodItem / Recipe

    func testFoodItemRoundTrips() throws {
        let ctx = try TestSupport.makeContext()
        let item = FoodItem(
            name: "Protein bar",
            brand: "Acme",
            servingDescription: "1 bar (40 g)",
            caloriesPerServing: 190,
            proteinG: 20,
            carbsG: 22,
            fatG: 7,
            barcode: "0123456789012",
            source: "Open Food Facts",
            isCustom: false
        )
        ctx.insert(item)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FoodItem>()).first)
        XCTAssertEqual(fetched.brand, "Acme")
        XCTAssertEqual(fetched.barcode, "0123456789012")
        XCTAssertEqual(fetched.caloriesPerServing, 190)
        XCTAssertFalse(fetched.isCustom)
    }

    func testRecipeTotalsAndPerServing() throws {
        let ctx = try TestSupport.makeContext()
        let recipe = Recipe(name: "Chili", servings: 4, items: [
            RecipeItem(name: "Beans", calories: 400, proteinG: 24, carbsG: 72, fatG: 4, order: 0),
            RecipeItem(name: "Beef", calories: 800, proteinG: 80, carbsG: 0, fatG: 52, order: 1),
        ])
        ctx.insert(recipe)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Recipe>()).first)
        XCTAssertEqual(fetched.totalCalories, 1200)
        XCTAssertEqual(fetched.totalProteinG, 104)
        XCTAssertEqual(fetched.perServingCalories, 300)
        XCTAssertEqual(fetched.perServingProteinG, 26)
    }

    // MARK: - Template -> session bridge

    private func sampleTemplate() -> WorkoutTemplate {
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest, equipment: .barbell)
        let te = TemplateExercise(exercise: bench, order: 0, sets: [
            ExerciseSet(order: 0, reps: 10, weightKg: 60, completed: true),
            ExerciseSet(order: 1, reps: 8, weightKg: 70, completed: true),
            ExerciseSet(order: 2, reps: 6, weightKg: 80, completed: false),
        ])
        return WorkoutTemplate(name: "Push Day", exercises: [te])
    }

    func testMakeLogFromTemplateCompletedOnly() {
        let template = sampleTemplate()
        let log = WorkoutSessionBridge.makeLog(from: template, durationMinutes: 45, intensity: 7)
        XCTAssertEqual(log.name, "Push Day")
        XCTAssertEqual(log.type, .strength)
        XCTAssertEqual(log.durationMinutes, 45)
        XCTAssertEqual(log.intensity, 7)
        XCTAssertEqual(log.exercises.count, 1)
        let entry = log.exercises[0]
        // Only the 2 completed sets count; top set is 70kg x 8.
        XCTAssertEqual(entry.sets, 2)
        XCTAssertEqual(entry.weight, 70)
        XCTAssertEqual(entry.reps, 8)
    }

    func testTotalVolumeCompletedOnly() {
        let template = sampleTemplate()
        // 10*60 + 8*70 = 600 + 560 = 1160 (third set not completed)
        XCTAssertEqual(WorkoutSessionBridge.totalVolume(of: template), 1160)
        // Including incomplete: + 6*80 = 480 -> 1640
        XCTAssertEqual(WorkoutSessionBridge.totalVolume(of: template, completedOnly: false), 1640)
    }

    func testLogSessionPersistsAndStampsTemplate() throws {
        let ctx = try TestSupport.makeContext()
        let template = sampleTemplate()
        ctx.insert(template)
        try ctx.save()

        XCTAssertNil(template.lastPerformed)
        WorkoutSessionBridge.logSession(from: template, durationMinutes: 50, in: ctx)

        let logs = try ctx.fetch(FetchDescriptor<WorkoutLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.name, "Push Day")
        XCTAssertNotNil(template.lastPerformed)
    }
}
