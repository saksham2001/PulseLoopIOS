import Foundation
import SwiftData

/// Builds a portable JSON export of the user's on-device health data (roadmap E2).
///
/// This is the local counterpart to `CloudSyncService.exportServerData()`: it
/// reads straight from the SwiftData store so the user can take their data with
/// them even if they never connected to the web backend. The output is a single
/// JSON document written to a temporary file, suitable for a share sheet.
@MainActor
enum LocalDataExport {
    /// Serializes the user's data to a temporary `.json` file and returns its URL.
    static func makeExportFile(context: ModelContext) throws -> URL {
        let document = try buildDocument(context: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        let stamp = ISO8601DateFormatter.fileStamp.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseLoop-Export-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads every model and assembles the export document.
    static func buildDocument(context: ModelContext) throws -> ExportDocument {
        let measurements = (try? context.fetch(FetchDescriptor<Measurement>(
            sortBy: [SortDescriptor(\.timestamp)]
        ))) ?? []
        let sleep = (try? context.fetch(FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []
        let activityDaily = (try? context.fetch(FetchDescriptor<ActivityDaily>(
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<ActivitySession>(
            sortBy: [SortDescriptor(\.startedAt)]
        ))) ?? []
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let goal = (try? context.fetch(FetchDescriptor<UserGoal>()))?.first

        return ExportDocument(
            exportedAt: Date(),
            schemaVersion: 1,
            profile: profile.map(ExportProfile.init),
            goal: goal.map(ExportGoal.init),
            measurements: measurements.map(ExportMeasurement.init),
            sleepSessions: sleep.map(ExportSleep.init),
            activityDaily: activityDaily.map(ExportActivityDaily.init),
            activitySessions: sessions.map(ExportActivitySession.init)
        )
    }
}

// MARK: - Codable export shapes

struct ExportDocument: Codable {
    let exportedAt: Date
    let schemaVersion: Int
    let profile: ExportProfile?
    let goal: ExportGoal?
    let measurements: [ExportMeasurement]
    let sleepSessions: [ExportSleep]
    let activityDaily: [ExportActivityDaily]
    let activitySessions: [ExportActivitySession]
}

struct ExportProfile: Codable {
    let name: String?
    let age: Int?
    let sex: String?
    let heightCm: Double?
    let weightKg: Double?

    init(_ p: UserProfile) {
        name = p.name
        age = p.age
        sex = p.sex
        heightCm = p.heightCm
        weightKg = p.weightKg
    }
}

struct ExportGoal: Codable {
    let steps: Int
    let sleepMinutes: Int
    let activeMinutes: Int
    let workoutsPerWeek: Int

    init(_ g: UserGoal) {
        steps = g.steps
        sleepMinutes = g.sleepMinutes
        activeMinutes = g.activeMinutes
        workoutsPerWeek = g.workoutsPerWeek
    }
}

struct ExportMeasurement: Codable {
    let id: UUID
    let kind: String
    let value: Double
    let unit: String
    let timestamp: Date
    let source: String

    init(_ m: Measurement) {
        id = m.id
        kind = m.kind.rawValue
        value = m.value
        unit = m.unit
        timestamp = m.timestamp
        source = m.sourceRaw
    }
}

struct ExportSleep: Codable {
    let id: UUID
    let date: Date
    let startAt: Date
    let endAt: Date
    let totalMinutes: Int
    let score: Int?

    init(_ s: SleepSession) {
        id = s.id
        date = s.date
        startAt = s.startAt
        endAt = s.endAt
        totalMinutes = s.totalMinutes
        score = s.score
    }
}

struct ExportActivityDaily: Codable {
    let id: UUID
    let date: Date
    let steps: Int
    let calories: Double
    let distanceMeters: Double
    let activeMinutes: Int

    init(_ a: ActivityDaily) {
        id = a.id
        date = a.date
        steps = a.steps
        calories = a.calories
        distanceMeters = a.distanceMeters
        activeMinutes = a.activeMinutes
    }
}

struct ExportActivitySession: Codable {
    let id: UUID
    let type: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let calories: Double?
    let distanceMeters: Double?
    let avgHeartRate: Double?

    init(_ s: ActivitySession) {
        id = s.id
        type = s.type
        status = s.statusRaw
        startedAt = s.startedAt
        endedAt = s.endedAt
        calories = s.calories
        distanceMeters = s.distanceMeters
        avgHeartRate = s.avgHeartRate
    }
}

private extension ISO8601DateFormatter {
    static let fileStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
