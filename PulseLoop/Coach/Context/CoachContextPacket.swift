import Foundation

/// Compact context the model sees every turn  -  ports the web app's
/// CoachContextPacket (`backend/app/coach/context.py`). Deliberately small:
/// latest values + rollups + warnings. Dense arrays are never embedded; the
/// model fetches those on demand via tools.
///
/// Encoded camelCase → snake_case by the prompt builder so property names stay
/// idiomatic Swift while the wire shape matches the web contract.
struct CoachContextPacket: Encodable {
    var generatedAt: String
    var timezone: String
    var profile: ProfileContext
    var device: DeviceContext
    var goals: GoalContext
    var today: DayContext
    var lastSevenDays: WeekContext
    var latestVitals: VitalsContext
    var latestSleep: SleepContext?
    var recentWorkouts: [WorkoutContext]
    var memories: [MemoryContext]
    /// Durable, AI-derived learnings from the daily knowledge-base pass.
    var learnings: [LearningContext]
    var conversationSummary: String?
    var dataQualityWarnings: [String]
    /// Module awareness (Experience loop M3): what the user has installed vs.
    /// what's available to install, so the assistant can route a request to the
    /// right module — or offer to install an uninstalled one — without first
    /// calling `list_modules` every turn.
    var modules: ModulesContext
    /// Active/upcoming trips so the assistant is travel-aware without a tool call
    /// (X5). Empty when the Travel module is uninstalled or there are no trips.
    var trips: [TripContext] = []

    /// Connected third-party wearable accounts (Fitbit / Google Fit) by display
    /// name, so the coach can attribute step/HR data and suggest connecting one
    /// when none is linked. Empty when nothing is connected.
    var connectedWearables: [String] = []

    struct TripContext: Encodable {
        var id: String
        var destination: String
        /// "planning" | "active" | "completed" | "cancelled"
        var status: String
        var startDate: String?
        var endDate: String?
        /// "active today" | "upcoming" | "past" — relative to now.
        var phase: String
        var daysUntil: Int?
        var itemCount: Int
        var openChecklistCount: Int
    }

    struct ProfileContext: Encodable {
        var name: String?
        var age: Int?
        var sex: String?
        var heightCm: Double?
        var weightKg: Double?
        /// "empty" | "partial" | "complete"
        var completeness: String
    }

    struct DeviceContext: Encodable {
        var name: String?
        var batteryPercent: Int?
        var state: String
        var lastConnectedAt: String?
        var lastSyncAt: String?
    }

    struct GoalContext: Encodable {
        var stepsDaily: Int
        var activeMinutesDaily: Int
        var sleepHours: Double
        var exerciseDaysWeekly: Int
    }

    struct DayContext: Encodable {
        var localDate: String
        var steps: Int?
        var calories: Double?
        var distanceKm: Double?
        var activeMinutes: Int?
        /// "none" | "low" | "medium" | "high"
        var dataConfidence: String
    }

    struct WeekContext: Encodable {
        var daysAvailable: Int
        var avgSteps: Int?
        var totalSteps: Int?
        var activeMinutesTotal: Int?
        var exerciseDays: Int
        var mostActiveDay: String?
    }

    struct VitalsContext: Encodable {
        var latestHr: Double?
        var latestHrAt: String?
        var latestSpo2: Double?
        var latestSpo2At: String?
        var restingHrEstimate: Double?
        var peakHrToday: Double?
    }

    struct SleepContext: Encodable {
        var date: String
        var totalMin: Int
        var deepMin: Int
        var lightMin: Int
        var awakeMin: Int
        var score: Int?
        var confidence: String
        var decoderNote: String
    }

    struct WorkoutContext: Encodable {
        var id: String
        var type: String
        var startTime: String
        var durationMin: Double?
        var distanceKm: Double?
        var avgHr: Double?
        var status: String
    }

    struct MemoryContext: Encodable {
        var type: String
        var key: String
        var value: String
        var importance: Int
    }

    struct LearningContext: Encodable {
        var category: String
        var title: String
        var detail: String
        var importance: Int
    }

    /// Snapshot of the module catalog the assistant can act on.
    struct ModulesContext: Encodable {
        /// Modules the user currently has installed (visible features + their AI tools).
        var installed: [ModuleSummary]
        /// Modules that exist but aren't installed — the assistant can offer to install these.
        var available: [ModuleSummary]
        /// Installed modules with a newer version available (ids only; details via tools).
        var updatesAvailable: [String]

        struct ModuleSummary: Encodable {
            var id: String
            var name: String
            var summary: String
        }
    }
}
