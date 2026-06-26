import Foundation
import SwiftData

// MARK: - Nutrition Coach Tools (goals · food lookup · summary)
//
// Read + write across the nutrition module. Reads are always on; writes gated by
// `flags.writeToolsEnabled`. `set_nutrition_goal` updates the single active goal;
// `lookup_food` hits Open Food Facts for per-serving macros so the model can log
// accurately. `log_meal` already exists in `DailyLifeTools`; these complement it.
// Contributed via `NutritionSubApp.aiTools(flags:)`, merged by `ToolRegistry`.
@MainActor
enum NutritionTools {
    static var readTools: [AnyCoachTool] {
        [getNutritionSummary, lookupFood]
    }
    static var writeTools: [AnyCoachTool] {
        [setNutritionGoal]
    }

    // MARK: - Reads

    private static var getNutritionSummary: AnyCoachTool {
        struct Args: Decodable { let dayOffset: Int?; enum CodingKeys: String, CodingKey { case dayOffset = "day_offset" } }
        return .make(
            name: "get_nutrition_summary",
            label: "Reviewing your nutrition",
            description: "Get a day's nutrition: calories + macros consumed, the active goal (calorie/macro budget), and calories remaining. day_offset 0 = today, -1 = yesterday (default 0).",
            parameters: JSONSchema.object(["day_offset": ["type": ["integer", "null"]]], required: ["day_offset"]),
            argsType: Args.self
        ) { args, ctx in
            let day = Calendar.current.date(byAdding: .day, value: args.dayOffset ?? 0, to: Date()) ?? Date()
            let all = (try? ctx.modelContext.fetch(FetchDescriptor<MealLog>())) ?? []
            let dayMeals = all.filter { !$0.isPlanned && Calendar.current.isDate($0.loggedAt, inSameDayAs: day) }
            let totals = NutritionDiary.totals(of: dayMeals)
            let goal = NutritionStore.activeGoal(ctx.modelContext)
            var result: [String: Any] = [
                "consumed": [
                    "calories": totals.calories,
                    "protein_g": Int(totals.proteinG),
                    "carbs_g": Int(totals.carbsG),
                    "fat_g": Int(totals.fatG),
                ],
                "meals_logged": dayMeals.count,
            ]
            if let goal {
                result["goal"] = [
                    "calories": goal.calories,
                    "protein_g": Int(goal.proteinG),
                    "carbs_g": Int(goal.carbsG),
                    "fat_g": Int(goal.fatG),
                ]
                result["calories_remaining"] = NutritionDiary.caloriesRemaining(goal: goal, consumed: totals)
            }
            return .object(result)
        }
    }

    private static var lookupFood: AnyCoachTool {
        struct Args: Decodable { let query: String }
        return .make(
            name: "lookup_food",
            label: "Looking up a food",
            description: "Look up packaged/branded foods in the Open Food Facts database by name or brand. Returns per-100g calories + macros and a barcode you can reference. Use before logging branded items for accurate numbers.",
            parameters: JSONSchema.object(["query": JSONSchema.string], required: ["query"]),
            argsType: Args.self
        ) { args, ctx in
            let q = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return .error("query is empty.") }
            let products = await OpenFoodFactsService.search(query: q)
            let rows = products.prefix(5).map { p -> [String: Any] in
                var d: [String: Any] = ["name": p.name, "serving": "100 g"]
                if let b = p.brand { d["brand"] = b }
                if let n = p.nutriments {
                    if let c = n.calories { d["calories"] = Int(c.rounded()) }
                    if let pr = n.protein { d["protein_g"] = pr }
                    if let ca = n.carbs { d["carbs_g"] = ca }
                    if let f = n.fat { d["fat_g"] = f }
                }
                if let bc = p.barcode { d["barcode"] = bc }
                return d
            }
            return .object(["foods": Array(rows), "count": rows.count, "query": q])
        }
    }

    // MARK: - Writes

    private struct GoalArgs: Decodable {
        let calories: Int
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        enum CodingKeys: String, CodingKey {
            case calories, proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g"
        }
    }

    private static var setNutritionGoal: AnyCoachTool {
        .make(
            name: "set_nutrition_goal",
            label: "Setting your nutrition goal",
            description: "Set the user's active daily nutrition goal: calories and protein/carbs/fat grams. Replaces any previous active goal. The food diary reads this for its remaining-calorie + macro rings. Applies immediately.",
            parameters: JSONSchema.object([
                "calories": ["type": "integer"],
                "protein_g": JSONSchema.number,
                "carbs_g": JSONSchema.number,
                "fat_g": JSONSchema.number,
            ], required: ["calories", "protein_g", "carbs_g", "fat_g"]),
            argsType: GoalArgs.self
        ) { args, ctx in
            guard args.calories > 0 else { return .error("calories must be positive.") }
            let goal = NutritionStore.setActiveGoal(
                calories: args.calories,
                proteinG: max(0, args.proteinG),
                carbsG: max(0, args.carbsG),
                fatG: max(0, args.fatG),
                in: ctx.modelContext
            )
            return .object(["ok": true, "calories": goal.calories,
                            "protein_g": Int(goal.proteinG),
                            "carbs_g": Int(goal.carbsG),
                            "fat_g": Int(goal.fatG)])
        }
    }
}
