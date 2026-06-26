import Foundation
import SwiftData

// MARK: - Workout Session Bridge
//
// The strength domain (`WorkoutTemplate` → `TemplateExercise` → `ExerciseSet`) and
// the session-logging domain (`WorkoutLog` + `ExerciseEntry`) were disconnected:
// completing a template did not produce a logged session, so it never showed up in
// history or the progression charts. This bridge turns a performed template into a
// `WorkoutLog`, preserving the actual reps/weight per exercise.

enum WorkoutSessionBridge {
    /// Build a `WorkoutLog` from a (just-performed) template. `completedOnly` keeps
    /// only sets the user marked done, mirroring how MyFitnessPal logs the work
    /// actually completed. Does NOT insert — the caller owns persistence so this is
    /// pure and unit-testable.
    static func makeLog(
        from template: WorkoutTemplate,
        durationMinutes: Int,
        intensity: Int = 5,
        caloriesBurned: Int? = nil,
        notes: String? = nil,
        completedOnly: Bool = true,
        date: Date = Date()
    ) -> WorkoutLog {
        let entries: [ExerciseEntry] = template.exercises
            .sorted { $0.order < $1.order }
            .compactMap { te in
                let sets = completedOnly ? te.sets.filter { $0.completed } : te.sets
                guard !sets.isEmpty else { return nil }
                // Representative reps/weight = the top (heaviest) working set; total
                // set count captures volume. This matches what the charts read back.
                let topSet = sets.max { $0.weightKg < $1.weightKg }
                return ExerciseEntry(
                    name: te.name,
                    sets: sets.count,
                    reps: topSet?.reps,
                    weight: topSet?.weightKg,
                    durationSeconds: nil
                )
            }

        return WorkoutLog(
            date: date,
            type: .strength,
            name: template.name,
            durationMinutes: durationMinutes,
            caloriesBurned: caloriesBurned,
            intensity: min(10, max(1, intensity)),
            notes: notes,
            exercises: entries
        )
    }

    /// Total volume (Σ reps × weight) across the template's completed sets — the
    /// number the strength-progression / total-volume charts visualize.
    static func totalVolume(of template: WorkoutTemplate, completedOnly: Bool = true) -> Double {
        template.exercises.reduce(0) { acc, te in
            let sets = completedOnly ? te.sets.filter { $0.completed } : te.sets
            return acc + sets.reduce(0) { $0 + $1.volume }
        }
    }

    /// Persist a session from a template and stamp the template's `lastPerformed`.
    @MainActor
    @discardableResult
    static func logSession(
        from template: WorkoutTemplate,
        durationMinutes: Int,
        intensity: Int = 5,
        caloriesBurned: Int? = nil,
        notes: String? = nil,
        completedOnly: Bool = true,
        in context: ModelContext,
        date: Date = Date()
    ) -> WorkoutLog {
        let log = makeLog(
            from: template,
            durationMinutes: durationMinutes,
            intensity: intensity,
            caloriesBurned: caloriesBurned,
            notes: notes,
            completedOnly: completedOnly,
            date: date
        )
        context.insert(log)
        template.lastPerformed = date
        context.saveOrLog("workout.session")
        return log
    }
}
