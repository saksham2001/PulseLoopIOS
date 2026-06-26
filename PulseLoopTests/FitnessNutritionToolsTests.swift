import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Verifies the Fitness + Nutrition coach tools against an in-memory store: the AI can
/// log a workout, complete a saved template as a session, log a weigh-in, set the
/// active nutrition goal, and read back a day's nutrition summary.
@MainActor
final class FitnessNutritionToolsTests: XCTestCase {

    private func writeFlags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    private func ctx(_ c: ModelContext) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: c, flags: writeFlags())
    }

    private func fitnessTool(_ name: String) throws -> AnyCoachTool {
        let all = FitnessTools.readTools + FitnessTools.writeTools
        return try XCTUnwrap(all.first { $0.name == name }, "missing fitness tool \(name)")
    }

    private func nutritionTool(_ name: String) throws -> AnyCoachTool {
        let all = NutritionTools.readTools + NutritionTools.writeTools
        return try XCTUnwrap(all.first { $0.name == name }, "missing nutrition tool \(name)")
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    // MARK: - Workouts

    func testLogWorkoutPersists() async throws {
        let c = try TestSupport.makeContext()
        let result = try await fitnessTool("log_workout").run(
            Data(#"{"name":"Morning Run","type":"running","duration_min":32,"intensity":7,"calories":310,"notes":null}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        XCTAssertEqual(out["ok"] as? Bool, true)

        let logs = try c.fetch(FetchDescriptor<WorkoutLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.name, "Morning Run")
        XCTAssertEqual(logs.first?.type, .running)
        XCTAssertEqual(logs.first?.durationMinutes, 32)
        XCTAssertEqual(logs.first?.caloriesBurned, 310)
    }

    func testStartWorkoutFromTemplateLogsSession() async throws {
        let c = try TestSupport.makeContext()
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest, equipment: .barbell)
        let te = TemplateExercise(exercise: bench, order: 0, sets: [
            ExerciseSet(order: 0, reps: 10, weightKg: 60, completed: false),
            ExerciseSet(order: 1, reps: 8, weightKg: 70, completed: false),
        ])
        let template = WorkoutTemplate(name: "Push Day", exercises: [te])
        c.insert(template)
        try c.save()

        let result = try await fitnessTool("start_workout").run(
            Data(#"{"template_id":"\#(template.id.uuidString)","duration_min":50,"intensity":6}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        XCTAssertEqual(out["ok"] as? Bool, true)

        let logs = try c.fetch(FetchDescriptor<WorkoutLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.name, "Push Day")
        XCTAssertNotNil(template.lastPerformed)
    }

    func testStartWorkoutUnknownTemplateErrors() async throws {
        let c = try TestSupport.makeContext()
        let result = try await fitnessTool("start_workout").run(
            Data(#"{"template_id":"\#(UUID().uuidString)","duration_min":null,"intensity":null}"#.utf8),
            ctx(c)
        )
        XCTAssertTrue(result.jsonString.lowercased().contains("not found"))
    }

    func testLogWeightConvertsPounds() async throws {
        let c = try TestSupport.makeContext()
        let result = try await fitnessTool("log_weight").run(
            Data(#"{"weight_kg":null,"weight_lb":154,"body_fat_percent":18.5}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        XCTAssertEqual(out["ok"] as? Bool, true)

        let metrics = try c.fetch(FetchDescriptor<BodyMetric>())
        XCTAssertEqual(metrics.count, 1)
        let kg = try XCTUnwrap(metrics.first?.weightKg)
        XCTAssertEqual(kg, 154 * 0.45359237, accuracy: 0.001)
        XCTAssertEqual(metrics.first?.bodyFatPercent, 18.5)
    }

    // MARK: - Nutrition

    func testSetNutritionGoalIsActiveAndSingle() async throws {
        let c = try TestSupport.makeContext()
        _ = try await nutritionTool("set_nutrition_goal").run(
            Data(#"{"calories":2100,"protein_g":170,"carbs_g":200,"fat_g":65}"#.utf8),
            ctx(c)
        )
        // Set again — should reuse + stay single active.
        _ = try await nutritionTool("set_nutrition_goal").run(
            Data(#"{"calories":2300,"protein_g":180,"carbs_g":220,"fat_g":70}"#.utf8),
            ctx(c)
        )
        let goals = try c.fetch(FetchDescriptor<NutritionGoal>())
        XCTAssertEqual(goals.filter(\.isActive).count, 1)
        let active = try XCTUnwrap(NutritionStore.activeGoal(c))
        XCTAssertEqual(active.calories, 2300)
        XCTAssertEqual(active.proteinG, 180)
    }

    func testNutritionSummaryReflectsMealsAndGoal() async throws {
        let c = try TestSupport.makeContext()
        _ = try await nutritionTool("set_nutrition_goal").run(
            Data(#"{"calories":2000,"protein_g":150,"carbs_g":200,"fat_g":67}"#.utf8),
            ctx(c)
        )
        c.insert(MealLog(name: "Oatmeal", calories: 350, proteinG: 12, carbsG: 60, fatG: 7, mealType: .breakfast))
        c.insert(MealLog(name: "Chicken bowl", calories: 650, proteinG: 50, carbsG: 55, fatG: 20, mealType: .lunch))
        try c.save()

        let result = try await nutritionTool("get_nutrition_summary").run(
            Data(#"{"day_offset":0}"#.utf8),
            ctx(c)
        )
        let out = try parse(result)
        let consumed = try XCTUnwrap(out["consumed"] as? [String: Any])
        XCTAssertEqual(consumed["calories"] as? Int, 1000)
        XCTAssertEqual(out["meals_logged"] as? Int, 2)
        XCTAssertEqual(out["calories_remaining"] as? Int, 1000)
    }

    // MARK: - Gating

    func testWriteToolsGatedBehindFlag() {
        XCTAssertEqual(FitnessTools.writeTools.map(\.name).sorted(),
                       ["log_weight", "log_workout", "start_workout"])
        XCTAssertEqual(NutritionTools.writeTools.map(\.name), ["set_nutrition_goal"])
        // SubApp only exposes writes when the flag is on.
        var s = CoachSettings.default
        s.enableWriteTools = false
        let readOnly = CoachFeatureFlags(settings: s, hasAPIKey: true)
        let fitnessReadOnly = FitnessSubApp().aiTools(flags: readOnly).map(\.name)
        XCTAssertFalse(fitnessReadOnly.contains("log_workout"))
        XCTAssertTrue(fitnessReadOnly.contains("list_workout_templates"))
    }
}
