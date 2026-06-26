import Foundation
import SwiftData

// MARK: - Fitness Coach Tools (workouts · body weight)
//
// Read + write across the strength/fitness module. Reads are always on; writes are
// gated by `flags.writeToolsEnabled`. Writes here are additive logs (a workout
// session, a weigh-in) so they apply immediately. Contributed via
// `FitnessSubApp.aiTools(flags:)` and merged by `ToolRegistry`.
@MainActor
enum FitnessTools {
    static var readTools: [AnyCoachTool] {
        [listWorkoutTemplates, listWorkouts]
    }
    static var writeTools: [AnyCoachTool] {
        [logWorkout, startWorkoutTemplate, logWeight]
    }

    private static let iso = ISO8601DateFormatter()

    // MARK: - Reads

    private static var listWorkoutTemplates: AnyCoachTool {
        .make(
            name: "list_workout_templates",
            label: "Reviewing your workouts",
            description: "List the user's saved workout templates with exercise + set counts and when each was last performed. Returns ids for start_workout.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let templates = ((try? ctx.modelContext.fetch(FetchDescriptor<WorkoutTemplate>())) ?? [])
                .sorted { $0.createdAt > $1.createdAt }
                .map { t -> [String: Any] in
                    var d: [String: Any] = [
                        "id": t.id.uuidString,
                        "name": t.name,
                        "exercises": t.exercises.count,
                        "sets": t.totalSets,
                    ]
                    if let last = t.lastPerformed { d["last_performed"] = iso.string(from: last) }
                    return d
                }
            return .object(["templates": templates, "count": templates.count])
        }
    }

    private static var listWorkouts: AnyCoachTool {
        struct Args: Decodable { let days: Int? }
        return .make(
            name: "list_workouts",
            label: "Reviewing your training",
            description: "List recent logged workout sessions (name, type, duration, intensity, calories) over the last N days (default 14).",
            parameters: JSONSchema.object(["days": ["type": ["integer", "null"]]], required: ["days"]),
            argsType: Args.self
        ) { args, ctx in
            let days = max(1, args.days ?? 14)
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let rows = ((try? ctx.modelContext.fetch(FetchDescriptor<WorkoutLog>())) ?? [])
                .filter { $0.date >= cutoff }
                .sorted { $0.date > $1.date }
                .map { w -> [String: Any] in
                    var d: [String: Any] = [
                        "name": w.name,
                        "type": w.type.rawValue,
                        "duration_min": w.durationMinutes,
                        "intensity": w.intensity,
                        "date": iso.string(from: w.date),
                    ]
                    if let cal = w.caloriesBurned { d["calories"] = cal }
                    return d
                }
            return .object(["workouts": rows, "count": rows.count, "days": days])
        }
    }

    // MARK: - Writes

    private struct LogWorkoutArgs: Decodable {
        let name: String
        let type: String?
        let durationMin: Int
        let intensity: Int?
        let calories: Int?
        let notes: String?
        enum CodingKeys: String, CodingKey {
            case name, type, durationMin = "duration_min", intensity, calories, notes
        }
    }

    private static var logWorkout: AnyCoachTool {
        .make(
            name: "log_workout",
            label: "Logging a workout",
            description: "Log a completed workout session. name + duration_min required. type is one of strength/cardio/hiit/yoga/running/cycling/swimming/walking/sports/flexibility/other (default strength). intensity is 1–10. Applies immediately.",
            parameters: JSONSchema.object([
                "name": JSONSchema.string,
                "type": ["type": ["string", "null"]],
                "duration_min": ["type": "integer"],
                "intensity": ["type": ["integer", "null"]],
                "calories": ["type": ["integer", "null"]],
                "notes": ["type": ["string", "null"]],
            ], required: ["name", "type", "duration_min", "intensity", "calories", "notes"]),
            argsType: LogWorkoutArgs.self
        ) { args, ctx in
            let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .error("workout name is empty.") }
            let type = WorkoutType(rawValue: (args.type ?? "Strength").capitalized)
                ?? WorkoutType.allCases.first { $0.rawValue.lowercased() == (args.type ?? "").lowercased() }
                ?? .strength
            let log = WorkoutLog(
                type: type,
                name: name,
                durationMinutes: max(1, args.durationMin),
                caloriesBurned: args.calories,
                intensity: min(10, max(1, args.intensity ?? 5)),
                notes: args.notes
            )
            ctx.modelContext.insert(log)
            ctx.modelContext.saveOrLog("coach.fitness")
            return .object(["ok": true, "logged": true, "name": log.name,
                            "type": log.type.rawValue, "duration_min": log.durationMinutes])
        }
    }

    private struct StartWorkoutArgs: Decodable {
        let templateId: String
        let durationMin: Int?
        let intensity: Int?
        enum CodingKeys: String, CodingKey {
            case templateId = "template_id", durationMin = "duration_min", intensity
        }
    }

    private static var startWorkoutTemplate: AnyCoachTool {
        .make(
            name: "start_workout",
            label: "Logging your workout",
            description: "Complete a saved workout template as a session: logs a WorkoutLog from all its sets and stamps it as performed now. Use template_id from list_workout_templates. Applies immediately.",
            parameters: JSONSchema.object([
                "template_id": JSONSchema.string,
                "duration_min": ["type": ["integer", "null"]],
                "intensity": ["type": ["integer", "null"]],
            ], required: ["template_id", "duration_min", "intensity"]),
            argsType: StartWorkoutArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.templateId),
                  let template = ((try? ctx.modelContext.fetch(FetchDescriptor<WorkoutTemplate>())) ?? [])
                    .first(where: { $0.id == id }) else {
                return .error("workout template '\(args.templateId)' not found. Call list_workout_templates.")
            }
            let log = WorkoutSessionBridge.logSession(
                from: template,
                durationMinutes: max(1, args.durationMin ?? 45),
                intensity: min(10, max(1, args.intensity ?? 6)),
                completedOnly: false,
                in: ctx.modelContext
            )
            return .object(["ok": true, "logged": true, "name": log.name,
                            "exercises": log.exercises.count, "duration_min": log.durationMinutes])
        }
    }

    private struct LogWeightArgs: Decodable {
        let weightKg: Double?
        let weightLb: Double?
        let bodyFatPercent: Double?
        enum CodingKeys: String, CodingKey {
            case weightKg = "weight_kg", weightLb = "weight_lb", bodyFatPercent = "body_fat_percent"
        }
    }

    private static var logWeight: AnyCoachTool {
        .make(
            name: "log_weight",
            label: "Logging your weight",
            description: "Record a body-weight weigh-in. Provide weight_kg OR weight_lb (one is required). body_fat_percent optional. Applies immediately.",
            parameters: JSONSchema.object([
                "weight_kg": ["type": ["number", "null"]],
                "weight_lb": ["type": ["number", "null"]],
                "body_fat_percent": ["type": ["number", "null"]],
            ], required: ["weight_kg", "weight_lb", "body_fat_percent"]),
            argsType: LogWeightArgs.self
        ) { args, ctx in
            let kg: Double?
            if let k = args.weightKg, k > 0 { kg = k }
            else if let lb = args.weightLb, lb > 0 { kg = lb * 0.45359237 }
            else { kg = nil }
            guard let kg else { return .error("provide weight_kg or weight_lb.") }
            let metric = BodyMetric(weightKg: kg, bodyFatPercent: args.bodyFatPercent)
            ctx.modelContext.insert(metric)
            ctx.modelContext.saveOrLog("coach.fitness")
            return .object(["ok": true, "logged": true, "weight_kg": kg])
        }
    }
}
