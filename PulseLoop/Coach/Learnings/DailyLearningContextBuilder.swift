import Foundation
import SwiftData

/// Assembles the context for the once-per-day knowledge-base pass: a 14-day
/// rollup of the user's data (so the model can spot patterns, not just restate a
/// single day) plus the learnings already on file (so it avoids duplicates and
/// can refine). Also produces a `signature` used to gate the run to once per day.
@MainActor
enum DailyLearningContextBuilder {
    struct Built {
        let scopeKey: String        // local date "YYYY-MM-DD"
        let json: String
        let signature: String
        /// False when there's effectively nothing to learn from (no activity,
        /// sleep, journal, or supplement data in the window).
        let hasMeaningfulData: Bool
    }

    private static let windowDays = 14

    static func build(context: ModelContext, now: Date = Date()) -> Built {
        let cal = Calendar.current
        let scope = CoachDataAccess.localDateString(now)
        let startDate = cal.date(byAdding: .day, value: -(windowDays - 1), to: cal.startOfDay(for: now)) ?? now
        let start = CoachDataAccess.localDateString(startDate)

        let activity = CoachDataAccess.activityRows(start: start, end: scope, context: context)
        let sleep = CoachDataAccess.sleepSessions(start: start, end: scope, context: context)
        let hr = CoachDataAccess.measurements(kind: .heartRate, start: start, end: scope, context: context).map(\.value)
        let spo2 = CoachDataAccess.measurements(kind: .spo2, start: start, end: scope, context: context).map(\.value)

        let days: [DayRollup] = activity.map { row in
            let night = sleep.first { cal.isDate($0.date, inSameDayAs: row.date) }
            return DayRollup(
                date: CoachDataAccess.localDateString(row.date),
                steps: row.steps,
                activeMinutes: row.activeMinutes,
                calories: Int(row.calories.rounded()),
                sleepMinutes: night?.totalMinutes,
                sleepScore: night?.score
            )
        }

        let journal = journalRollup(context: context, since: startDate, cal: cal)
        let supplements = supplementRollup(context: context, since: startDate)
        let moods = moodRollup(context: context, since: startDate)
        let goals = MetricsRepository.goals(context: context)
        let existing = existingLearnings(context: context)

        struct Packet: Encodable {
            let window: String
            let goals: GoalsBlock?
            let days: [DayRollup]
            let hr: CoachDataAccess.Stats
            let spo2: CoachDataAccess.Stats
            let journal: [JournalRollup]
            let supplementsTaken: [SupplementRollup]
            let recentMoods: [MoodRollup]
            let existingLearnings: [String]
        }

        let packet = Packet(
            window: "\(start) to \(scope)",
            goals: goals.map { GoalsBlock(stepsDaily: $0.steps, activeMinutesDaily: $0.activeMinutes, sleepMinutes: $0.sleepMinutes) },
            days: days,
            hr: CoachDataAccess.stats(hr),
            spo2: CoachDataAccess.stats(spo2),
            journal: journal,
            supplementsTaken: supplements,
            recentMoods: moods,
            existingLearnings: existing
        )

        let hasData = !days.isEmpty || !sleep.isEmpty || !journal.isEmpty || !supplements.isEmpty

        let lastDayDate: String? = days.last?.date
        let lastDaySteps: String? = days.last.map { String($0.steps) }
        let lastSleepMin: String? = sleep.last.map { String($0.totalMinutes) }
        let sigParts: [String?] = [
            scope,
            String(days.count),
            lastDayDate,
            lastDaySteps,
            lastSleepMin,
            String(journal.count),
            String(supplements.count),
            String(existing.count),
        ]
        let sig = signature(sigParts)

        return Built(scopeKey: scope, json: encode(packet), signature: sig, hasMeaningfulData: hasData)
    }

    // MARK: - Rollups

    private struct DayRollup: Encodable {
        let date: String
        let steps: Int
        let activeMinutes: Int
        let calories: Int
        let sleepMinutes: Int?
        let sleepScore: Int?
    }

    private struct GoalsBlock: Encodable {
        let stepsDaily: Int
        let activeMinutesDaily: Int
        let sleepMinutes: Int
    }

    private struct JournalRollup: Encodable {
        let date: String
        /// metricKey → tri-state ("yes"/"no") plus optional amount, only for set entries.
        let entries: [String]
    }

    private struct SupplementRollup: Encodable {
        let name: String
        let category: String
        let daysTaken: Int
    }

    private struct MoodRollup: Encodable {
        let date: String
        let mood: Int
        let energy: Int
        let note: String?
    }

    private static func journalRollup(context: ModelContext, since: Date, cal: Calendar) -> [JournalRollup] {
        let descriptor = FetchDescriptor<JournalDay>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let days = (try? context.fetch(descriptor)) ?? []
        return days
            .filter { $0.date >= cal.startOfDay(for: since) }
            .prefix(windowDays)
            .compactMap { day -> JournalRollup? in
                let set = day.entries.filter { $0.state != 0 }
                guard !set.isEmpty else { return nil }
                let entries = set.map { e -> String in
                    let title = JournalCatalog.metric(for: e.metricKey)?.title ?? e.metricKey
                    let value = e.state == 1 ? "yes" : "no"
                    if let amount = e.amount, amount > 0 {
                        return "\(title): \(value) (\(formatted(amount)))"
                    }
                    return "\(title): \(value)"
                }
                return JournalRollup(date: CoachDataAccess.localDateString(day.date), entries: entries)
            }
    }

    private static func supplementRollup(context: ModelContext, since: Date) -> [SupplementRollup] {
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        guard !meds.isEmpty else { return [] }
        let logs = ((try? context.fetch(FetchDescriptor<MedicationLog>())) ?? [])
            .filter { $0.loggedAt >= since && $0.status == .taken }
        let countsById = Dictionary(grouping: logs, by: { $0.medicationId }).mapValues { $0.count }
        return meds
            .filter { $0.isActive }
            .compactMap { med -> SupplementRollup? in
                let days = countsById[med.id] ?? 0
                guard days > 0 else { return nil }
                return SupplementRollup(name: med.name, category: med.category.rawValue, daysTaken: days)
            }
            .sorted { $0.daysTaken > $1.daysTaken }
    }

    private static func moodRollup(context: ModelContext, since: Date) -> [MoodRollup] {
        var descriptor = FetchDescriptor<MoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = windowDays
        let rows = ((try? context.fetch(descriptor)) ?? []).filter { $0.date >= since }
        return rows.map {
            MoodRollup(date: CoachDataAccess.localDateString($0.date), mood: $0.mood, energy: $0.energy, note: $0.notes?.isEmpty == false ? $0.notes : nil)
        }
    }

    private static func existingLearnings(context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<DailyLearning>(
            sortBy: [SortDescriptor(\.importance, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return ((try? context.fetch(descriptor)) ?? []).map(\.title)
    }

    // MARK: - Helpers

    private static func formatted(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.1f", d)
    }

    private static func signature(_ parts: [String?]) -> String {
        parts.map { $0 ?? "·" }.joined(separator: "|")
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
