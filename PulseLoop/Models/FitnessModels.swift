import Foundation
import SwiftData

// MARK: - Muscle Groups & Equipment

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case core = "Core"
    case legs = "Legs"
    case glutes = "Glutes"
    case fullBody = "Full Body"
    case cardio = "Cardio"

    var id: String { rawValue }

    /// Coarse radar bucket used by the Total Volume chart.
    var volumeBucket: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        case .legs, .glutes: return "Legs"
        case .fullBody, .cardio: return "Core"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell = "Barbell"
    case dumbbellDouble = "Dumbbell (Double)"
    case dumbbellSingle = "Dumbbell (Single)"
    case machine = "Machine"
    case machineAssisted = "Machine Assisted"
    case cableSingle = "Cable (Single)"
    case cableDouble = "Cable (Double)"
    case band = "Band"
    case bodyweight = "Bodyweight"
    case kettlebellSingle = "Kettlebell (Single)"
    case kettlebellDouble = "Kettlebell (Double)"
    case ezBar = "EZ Bar"
    case trx = "TRX"
    case smithMachine = "Smith Machine"
    case landmine = "Landmine"
    case rope = "Rope"
    case other = "Other"

    var id: String { rawValue }

    /// SF Symbol used for the small thumbnail when no illustration exists.
    var symbol: String {
        switch self {
        case .barbell, .ezBar, .smithMachine: return "figure.strengthtraining.traditional"
        case .dumbbellDouble, .dumbbellSingle: return "dumbbell.fill"
        case .machine, .machineAssisted: return "figure.strengthtraining.functional"
        case .cableSingle, .cableDouble, .rope: return "cablecar"
        case .band: return "figure.flexibility"
        case .bodyweight: return "figure.cooldown"
        case .kettlebellSingle, .kettlebellDouble: return "figure.kickboxing"
        case .trx: return "figure.gymnastics"
        case .landmine: return "figure.martial.arts"
        case .other: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Exercise (catalog)

/// A single exercise definition in the library. Built-in exercises are seeded
/// from `ExerciseCatalog`; users can also create custom ones (`isCustom`).
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var muscleGroupRaw: String
    var equipmentRaw: String
    var instructions: String?
    var isCustom: Bool
    var createdAt: Date

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, muscleGroup: MuscleGroup, equipment: Equipment, instructions: String? = nil, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentRaw = equipment.rawValue
        self.instructions = instructions
        self.isCustom = isCustom
        self.createdAt = Date()
    }
}

// MARK: - Workout Template

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var lastPerformed: Date?
    @Relationship(deleteRule: .cascade) var exercises: [TemplateExercise]

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    init(id: UUID = UUID(), name: String = "New Workout", notes: String? = nil, exercises: [TemplateExercise] = []) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = Date()
        self.lastPerformed = nil
        self.exercises = exercises
    }
}

@Model
final class TemplateExercise {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var name: String
    var muscleGroupRaw: String
    var equipmentRaw: String
    var order: Int
    @Relationship(deleteRule: .cascade) var sets: [ExerciseSet]

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), exercise: Exercise, order: Int = 0, sets: [ExerciseSet] = []) {
        self.id = id
        self.exerciseId = exercise.id
        self.name = exercise.name
        self.muscleGroupRaw = exercise.muscleGroupRaw
        self.equipmentRaw = exercise.equipmentRaw
        self.order = order
        self.sets = sets
    }
}

@Model
final class ExerciseSet {
    @Attribute(.unique) var id: UUID
    var order: Int
    var reps: Int
    var weightKg: Double
    var completed: Bool

    var volume: Double { Double(reps) * weightKg }

    init(id: UUID = UUID(), order: Int = 0, reps: Int = 10, weightKg: Double = 0, completed: Bool = false) {
        self.id = id
        self.order = order
        self.reps = reps
        self.weightKg = weightKg
        self.completed = completed
    }
}

// MARK: - Journal

/// A single day's journal: a set of tri-state habit/metric entries.
@Model
final class JournalDay {
    @Attribute(.unique) var id: UUID
    /// Normalised to start-of-day so there's one record per calendar day.
    var date: Date
    @Relationship(deleteRule: .cascade) var entries: [JournalMetricEntry]

    init(id: UUID = UUID(), date: Date = Date(), entries: [JournalMetricEntry] = []) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.entries = entries
    }
}

/// Tri-state (and optional numeric) value for one journal metric on a given day.
@Model
final class JournalMetricEntry {
    @Attribute(.unique) var id: UUID
    /// Stable key from `JournalMetric.key`.
    var metricKey: String
    /// -1 = no / skipped, 0 = neutral / unset, 1 = yes / done.
    var state: Int
    /// Optional measured value (e.g. minutes, drinks, mg).
    var amount: Double?

    init(id: UUID = UUID(), metricKey: String, state: Int = 0, amount: Double? = nil) {
        self.id = id
        self.metricKey = metricKey
        self.state = state
        self.amount = amount
    }
}
