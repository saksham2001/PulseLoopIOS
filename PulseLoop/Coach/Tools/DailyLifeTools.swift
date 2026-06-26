import Foundation
import SwiftData

// MARK: - Daily-Life Coach Tools (Day Plan · Mood · Nutrition · Habits)
//
// Read + write across the everyday-tracking modules. Reads are always on; writes
// gated by `flags.writeToolsEnabled`. All writes here are additive/reversible
// logs and toggles, so they apply immediately (no confirm card). Destructive
// deletes for these entities can be added later via `.deleteEntity` if needed.
@MainActor
enum DailyLifeTools {
    static var readTools: [AnyCoachTool] {
        [getDayPlan, listMoodEntries, listMeals, listHabits]
    }
    static var writeTools: [AnyCoachTool] {
        [setDayPlanActionStatus, logMood, logMeal, checkInHabit]
    }

    private static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()

    // MARK: - Day Plan

    private static func todayPlan(_ ctx: ToolExecutionContext) -> DayPlan? {
        let cal = Calendar.current
        return ((try? ctx.modelContext.fetch(FetchDescriptor<DayPlan>())) ?? [])
            .first { cal.isDateInToday($0.date) }
    }

    private static var getDayPlan: AnyCoachTool {
        .make(
            name: "get_day_plan",
            label: "Reading today's plan",
            description: "Get today's day plan: its summary and the list of planned actions with their status (pending/approved/skipped/undone) and ids (for set_day_plan_action_status).",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            guard let plan = todayPlan(ctx) else {
                return .object(["has_plan": false, "note": "No day plan exists for today yet."])
            }
            let actions = plan.actions.sorted { $0.order < $1.order }.map { a in
                ["id": a.id.uuidString, "title": a.title, "subtitle": a.subtitle, "status": a.statusRaw]
            }
            return .object(["has_plan": true, "summary": plan.summary ?? "", "actions": actions])
        }
    }

    private struct ActionStatusArgs: Decodable {
        let actionId: String
        let status: String
        enum CodingKeys: String, CodingKey { case actionId = "action_id", status }
    }

    private static var setDayPlanActionStatus: AnyCoachTool {
        .make(
            name: "set_day_plan_action_status",
            label: "Updating your plan",
            description: "Set a day-plan action's status: pending, approved, skipped, or undone (ids from get_day_plan). Applies immediately.",
            parameters: JSONSchema.object([
                "action_id": JSONSchema.string,
                "status": JSONSchema.enumString(["pending", "approved", "skipped", "undone"]),
            ], required: ["action_id", "status"]),
            argsType: ActionStatusArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.actionId),
                  let action = ((try? ctx.modelContext.fetch(FetchDescriptor<DayPlanAction>())) ?? [])
                    .first(where: { $0.id == id }) else {
                return .error("plan action '\(args.actionId)' not found. Call get_day_plan.")
            }
            guard let status = PlanActionStatus(rawValue: args.status) else {
                return .error("invalid status.")
            }
            action.status = status
            ctx.modelContext.saveOrLog("coach.dailylife")
            return .object(["ok": true, "action_id": action.id.uuidString, "status": action.statusRaw])
        }
    }

    // MARK: - Mood

    private static var listMoodEntries: AnyCoachTool {
        struct Args: Decodable { let days: Int? }
        return .make(
            name: "list_mood_entries",
            label: "Reviewing your mood",
            description: "List recent mood check-ins (mood, energy, anxiety, focus on 1–5 scales, tags, notes) over the last N days (default 14).",
            parameters: JSONSchema.object(["days": ["type": ["integer", "null"]]], required: ["days"]),
            argsType: Args.self
        ) { args, ctx in
            let days = max(1, args.days ?? 14)
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let rows = ((try? ctx.modelContext.fetch(FetchDescriptor<MoodEntry>())) ?? [])
                .filter { $0.date >= cutoff }
                .sorted { $0.date > $1.date }
                .map { e -> [String: Any] in
                    var d: [String: Any] = ["date": dateOnly.string(from: e.date), "mood": e.mood, "energy": e.energy]
                    if let a = e.anxiety { d["anxiety"] = a }
                    if let f = e.focus { d["focus"] = f }
                    if !e.tags.isEmpty { d["tags"] = e.tags }
                    if let n = e.notes { d["notes"] = n }
                    return d
                }
            return .object(["entries": rows, "count": rows.count, "days": days])
        }
    }

    private struct LogMoodArgs: Decodable {
        let mood: Int
        let energy: Int
        let anxiety: Int?
        let focus: Int?
        let notes: String?
        let tags: [String]?
    }

    private static var logMood: AnyCoachTool {
        .make(
            name: "log_mood",
            label: "Logging your mood",
            description: "Record a mood check-in. mood and energy are required (1–5). anxiety and focus optional (1–5). Applies immediately.",
            parameters: JSONSchema.object([
                "mood": ["type": "integer"],
                "energy": ["type": "integer"],
                "anxiety": ["type": ["integer", "null"]],
                "focus": ["type": ["integer", "null"]],
                "notes": ["type": ["string", "null"]],
                "tags": ["type": ["array", "null"], "items": ["type": "string"]],
            ], required: ["mood", "energy", "anxiety", "focus", "notes", "tags"]),
            argsType: LogMoodArgs.self
        ) { args, ctx in
            func clamp(_ v: Int) -> Int { min(5, max(1, v)) }
            let entry = MoodEntry(
                mood: clamp(args.mood), energy: clamp(args.energy),
                anxiety: args.anxiety.map(clamp), focus: args.focus.map(clamp),
                tags: args.tags ?? [], notes: args.notes
            )
            ctx.modelContext.insert(entry)
            ctx.modelContext.saveOrLog("coach.dailylife")
            return .object(["ok": true, "logged": true, "mood": entry.mood, "energy": entry.energy])
        }
    }

    // MARK: - Nutrition

    private static var listMeals: AnyCoachTool {
        struct Args: Decodable { let days: Int? }
        return .make(
            name: "list_meals",
            label: "Reviewing your meals",
            description: "List logged meals (name, calories, protein/carbs/fat) over the last N days (default 3).",
            parameters: JSONSchema.object(["days": ["type": ["integer", "null"]]], required: ["days"]),
            argsType: Args.self
        ) { args, ctx in
            let days = max(1, args.days ?? 3)
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let rows = ((try? ctx.modelContext.fetch(FetchDescriptor<MealLog>())) ?? [])
                .filter { $0.loggedAt >= cutoff && !$0.isPlanned }
                .sorted { $0.loggedAt > $1.loggedAt }
                .map { m -> [String: Any] in
                    var d: [String: Any] = ["name": m.name, "calories": m.calories,
                                            "logged_at": ISO8601DateFormatter().string(from: m.loggedAt)]
                    if let p = m.proteinG { d["protein_g"] = p }
                    if let c = m.carbsG { d["carbs_g"] = c }
                    if let f = m.fatG { d["fat_g"] = f }
                    return d
                }
            return .object(["meals": rows, "count": rows.count, "days": days])
        }
    }

    private struct LogMealArgs: Decodable {
        let name: String
        let calories: Int?
        let proteinG: Double?
        let carbsG: Double?
        let fatG: Double?
        enum CodingKeys: String, CodingKey {
            case name, calories, proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g"
        }
    }

    private static var logMeal: AnyCoachTool {
        .make(
            name: "log_meal",
            label: "Logging a meal",
            description: "Log a meal the user ate. name is required (a natural description works, e.g. 'chicken bowl with rice and avocado'). calories and macros (grams) are optional — if you omit calories, nutrition is estimated automatically from the description. Applies immediately.",
            parameters: JSONSchema.object([
                "name": JSONSchema.string,
                "calories": ["type": ["integer", "null"]],
                "protein_g": ["type": ["number", "null"]],
                "carbs_g": ["type": ["number", "null"]],
                "fat_g": ["type": ["number", "null"]],
            ], required: ["name", "calories", "protein_g", "carbs_g", "fat_g"]),
            argsType: LogMealArgs.self
        ) { args, ctx in
            let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .error("meal name is empty.") }

            // Auto-estimate nutrition when the model didn't supply calories.
            var calories = args.calories ?? 0
            var protein = args.proteinG
            var carbs = args.carbsG
            var fat = args.fatG
            var note = ""
            var emoji = "fork.knife"
            var estimated = false
            if calories <= 0 {
                if let est = await MealEstimator.estimate(name) {
                    calories = est.calories
                    protein = protein ?? est.proteinG
                    carbs = carbs ?? est.carbsG
                    fat = fat ?? est.fatG
                    note = est.note
                    emoji = est.emoji
                    estimated = true
                }
            }

            let meal = MealLog(name: name, description_: note, emoji: emoji, calories: calories,
                               proteinG: protein, carbsG: carbs, fatG: fat)
            ctx.modelContext.insert(meal)
            ctx.modelContext.saveOrLog("coach.dailylife")
            return .object(["ok": true, "logged": true, "name": meal.name,
                            "calories": meal.calories, "estimated": estimated])
        }
    }

    // MARK: - Habits

    private static func habits(_ ctx: ToolExecutionContext) -> [Habit] {
        (try? ctx.modelContext.fetch(FetchDescriptor<Habit>())) ?? []
    }

    private static var listHabits: AnyCoachTool {
        .make(
            name: "list_habits",
            label: "Reviewing your habits",
            description: "List the user's habits with frequency, current streak, and whether each is done today. Returns ids for check_in_habit.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let rows = habits(ctx).filter { $0.isActive }.map { h -> [String: Any] in
                ["id": h.id.uuidString, "name": h.name, "frequency": h.frequency.rawValue,
                 "current_streak": h.currentStreak, "done_today": h.completedToday,
                 "target_count": h.targetCount]
            }
            return .object(["habits": rows, "count": rows.count])
        }
    }

    private struct HabitCheckInArgs: Decodable {
        let habitId: String
        let count: Int?
        enum CodingKeys: String, CodingKey { case habitId = "habit_id", count }
    }

    private static var checkInHabit: AnyCoachTool {
        .make(
            name: "check_in_habit",
            label: "Logging a habit",
            description: "Check in a habit for today (optional count, default 1). If already logged today, adds another entry. Applies immediately.",
            parameters: JSONSchema.object([
                "habit_id": JSONSchema.string,
                "count": ["type": ["integer", "null"]],
            ], required: ["habit_id", "count"]),
            argsType: HabitCheckInArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.habitId),
                  let habit = habits(ctx).first(where: { $0.id == id }) else {
                return .error("habit '\(args.habitId)' not found. Call list_habits.")
            }
            let log = HabitLog(count: max(1, args.count ?? 1))
            ctx.modelContext.insert(log)
            habit.logs.append(log)
            ctx.modelContext.saveOrLog("coach.dailylife")
            return .object(["ok": true, "logged": true, "habit": habit.name,
                            "current_streak": habit.currentStreak, "done_today": habit.completedToday])
        }
    }
}
