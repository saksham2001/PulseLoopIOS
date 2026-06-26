import Foundation
import SwiftData
import os

// MARK: - DataSyncService (roadmap W3)
//
// The generic counterpart to `CloudSyncService.sync` for *non-metric* module
// data. Where `CloudSyncService` uploads health `Measurement`s, this walks a
// registry of `SyncableRecordProvider`s — one per module (Tasks, Notes, …) —
// and uploads their records to the generic `/api/v1/sync/records` endpoint so
// the web app can render them (W4+).
//
// It deliberately reuses `CloudSyncService` for configuration, consent, the
// device token, and transport (`requireSyncToken` + `uploadRecords`), so there
// is exactly one place that knows how to reach the backend.
//
// This ships upload-first (phone → cloud), mirroring the metric flow. The
// backend table supports two-way sync (LWW + tombstones); cloud → phone
// read-back is a later enhancement.

// MARK: - Sync date formatting

/// Shared ISO-8601 formatter for sync wire values. Free function so value types
/// like `SyncRecord` can use it without crossing actor isolation.
private let syncISO8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

// MARK: - SyncRecord

/// A single module record in the generic sync wire shape. `payload` carries the
/// module-defined fields; `clientId` is stable for idempotent upserts;
/// `updatedAt` is the last-writer-wins key; `deleted` is a tombstone.
struct SyncRecord {
    let type: String
    let clientId: String
    let payload: [String: Any]
    let updatedAt: Date
    let deleted: Bool

    init(type: String, clientId: String, payload: [String: Any], updatedAt: Date, deleted: Bool = false) {
        self.type = type
        self.clientId = clientId
        self.payload = payload
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    /// JSON-ready dictionary for the request body.
    func wireDictionary() -> [String: Any] {
        [
            "type": type,
            "clientId": clientId,
            "payload": payload,
            "updatedAt": syncISO8601.string(from: updatedAt),
            "deleted": deleted,
        ]
    }
}

// MARK: - SyncableRecordProvider

/// A module's adapter into generic sync. Each provider knows its record `type`
/// and how to map its SwiftData rows to `SyncRecord`s. (`apply` is reserved for
/// future two-way sync and unused by the upload-first path.)
@MainActor
protocol SyncableRecordProvider {
    /// Stable record type, matching the server `synced_records.type` column.
    var recordType: String { get }

    /// Records modified at-or-after `since` mapped to the wire shape. Implementations
    /// should include tombstones for deletions when they can detect them.
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord]
}

// MARK: - DataSyncService

@MainActor
@Observable
final class DataSyncService {
    static let shared = DataSyncService()

    private let cloud: CloudSyncService
    private var providers: [SyncableRecordProvider]

    var lastSyncAt: Date?
    var lastError: String?
    var isSyncing = false

    init(cloud: CloudSyncService = .shared, providers: [SyncableRecordProvider]? = nil) {
        self.cloud = cloud
        self.providers = providers ?? DataSyncService.defaultProviders()
    }

    /// The built-in providers shipped with the app — one per module so every
    /// feature's data reaches the web (full parity). New modules add a provider here.
    static func defaultProviders() -> [SyncableRecordProvider] {
        [
            TasksSyncProvider(),
            NotesSyncProvider(),
            SleepSyncProvider(),
            MoodSyncProvider(),
            WorkoutSyncProvider(),
            MealSyncProvider(),
            MedicationSyncProvider(),
            MeditationSyncProvider(),
            StressSyncProvider(),
            SymptomSyncProvider(),
            LabResultSyncProvider(),
            HabitSyncProvider(),
            ViceSyncProvider(),
            DayPlanSyncProvider(),
            FriendActivitySyncProvider(),
            TripSyncProvider(),
        ]
    }

    /// Registers an additional provider (e.g. a dynamically installed module).
    func register(_ provider: SyncableRecordProvider) {
        guard !providers.contains(where: { $0.recordType == provider.recordType }) else { return }
        providers.append(provider)
    }

    /// Uploads every provider's records modified in the last `days` days. Safe to
    /// call repeatedly — the server upserts idempotently with last-writer-wins.
    @discardableResult
    func sync(context: ModelContext, days: Int = 30) async -> Bool {
        let token: String
        do {
            token = try cloud.requireSyncToken()
        } catch let error as CloudSyncService.SyncError {
            lastError = error.errorDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast

        var wire: [[String: Any]] = []
        for provider in providers {
            do {
                let records = try provider.fetchDirty(since: since, context: context)
                wire.append(contentsOf: records.map { $0.wireDictionary() })
            } catch {
                AppLog.network.warning("DataSync: provider \(provider.recordType, privacy: .public) failed to collect: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !wire.isEmpty else {
            lastSyncAt = Date()
            return true // nothing to upload is still a success
        }

        do {
            _ = try await cloud.uploadRecords(wire, token: token)
            lastSyncAt = Date()
            return true
        } catch let error as CloudSyncService.SyncError {
            lastError = error.errorDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

// MARK: - TasksSyncProvider (first parity feature, W4)

/// Maps `TaskItem` rows to generic sync records of type `task`. The web reader
/// (`/api/v1/sync/records?type=task`) renders these on `/tasks`.
@MainActor
struct TasksSyncProvider: SyncableRecordProvider {
    let recordType = "task"

    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.updatedAt >= since },
            sortBy: [SortDescriptor(\.updatedAt)]
        )
        let items = try context.fetch(descriptor)
        return items.map { item in
            var payload: [String: Any] = [
                "title": item.title,
                "status": item.statusRaw,
                "group": item.group,
                "order": item.order,
                "weight": item.weight,
                "createdAt": syncISO8601.string(from: item.createdAt),
            ]
            if let label = item.label { payload["label"] = label }
            if let dueDate = item.dueDate {
                payload["dueDate"] = syncISO8601.string(from: dueDate)
            }
            if let boardId = item.boardId { payload["boardId"] = boardId.uuidString }
            return SyncRecord(
                type: recordType,
                clientId: item.id.uuidString,
                payload: payload,
                updatedAt: item.updatedAt
            )
        }
    }
}

// MARK: - All-module sync providers (full web parity)
//
// One provider per built-in module, mapping its primary SwiftData model to a
// generic sync record. Each `payload` is shaped for the web `/records/[type]`
// viewer (a `title`, optional `subtitle`/`detail`, and a `date`), plus the raw
// fields. The `since` cursor uses each model's natural timestamp.

private func iso(_ date: Date) -> String { syncISO8601.string(from: date) }

@MainActor
struct NotesSyncProvider: SyncableRecordProvider {
    let recordType = "note"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<Note>(predicate: #Predicate { $0.updatedAt >= since }, sortBy: [SortDescriptor(\.updatedAt)])
        return try context.fetch(d).map { n in
            var payload: [String: Any] = [
                "title": n.title.isEmpty ? "Untitled note" : n.title,
                "isPinned": n.isPinned,
                "tags": n.tags,
                "date": iso(n.updatedAt),
            ]
            if let s = n.aiSummary { payload["subtitle"] = s }
            return SyncRecord(type: recordType, clientId: n.id.uuidString, payload: payload, updatedAt: n.updatedAt)
        }
    }
}

@MainActor
struct SleepSyncProvider: SyncableRecordProvider {
    let recordType = "sleep"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<SleepLog>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { s in
            let hours = Double(s.durationMinutes) / 60.0
            var payload: [String: Any] = [
                "title": String(format: "%.1f h sleep", hours),
                "subtitle": "Quality \(s.quality)/5",
                "durationMinutes": s.durationMinutes,
                "quality": s.quality,
                "date": iso(s.date),
            ]
            if let dm = s.deepMinutes { payload["deepMinutes"] = dm }
            if let rm = s.remMinutes { payload["remMinutes"] = rm }
            return SyncRecord(type: recordType, clientId: s.id.uuidString, payload: payload, updatedAt: s.date)
        }
    }
}

@MainActor
struct MoodSyncProvider: SyncableRecordProvider {
    let recordType = "mood"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { m in
            var payload: [String: Any] = [
                "title": "Mood \(m.mood)/5",
                "subtitle": "Energy \(m.energy)/5",
                "mood": m.mood,
                "energy": m.energy,
                "tags": m.tags,
                "date": iso(m.date),
            ]
            if let n = m.notes { payload["detail"] = n }
            return SyncRecord(type: recordType, clientId: m.id.uuidString, payload: payload, updatedAt: m.date)
        }
    }
}

@MainActor
struct WorkoutSyncProvider: SyncableRecordProvider {
    let recordType = "workout"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<WorkoutLog>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { w in
            var payload: [String: Any] = [
                "title": w.name,
                "subtitle": "\(w.type.rawValue) · \(w.durationMinutes) min",
                "durationMinutes": w.durationMinutes,
                "intensity": w.intensity,
                "date": iso(w.date),
            ]
            if let c = w.caloriesBurned { payload["calories"] = c }
            return SyncRecord(type: recordType, clientId: w.id.uuidString, payload: payload, updatedAt: w.date)
        }
    }
}

@MainActor
struct MealSyncProvider: SyncableRecordProvider {
    let recordType = "meal"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<MealLog>(predicate: #Predicate { $0.loggedAt >= since }, sortBy: [SortDescriptor(\.loggedAt)])
        return try context.fetch(d).map { m in
            var payload: [String: Any] = [
                "title": "\(m.emoji) \(m.name)",
                "subtitle": "\(m.calories) kcal",
                "calories": m.calories,
                "isPlanned": m.isPlanned,
                "date": iso(m.loggedAt),
            ]
            if let p = m.proteinG { payload["proteinG"] = p }
            return SyncRecord(type: recordType, clientId: m.id.uuidString, payload: payload, updatedAt: m.loggedAt)
        }
    }
}

@MainActor
struct MedicationSyncProvider: SyncableRecordProvider {
    let recordType = "medication"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        // Medications have no updatedAt; sync all active ones (createdAt cursor).
        let d = FetchDescriptor<Medication>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(d).filter { $0.isActive }.map { med in
            var payload: [String: Any] = [
                "title": "\(med.emoji) \(med.name)",
                "subtitle": "\(med.dose) · \(med.timing)",
                "category": med.categoryRaw,
                "isActive": med.isActive,
                "date": iso(med.createdAt),
            ]
            if let b = med.benefit { payload["detail"] = b }
            return SyncRecord(type: recordType, clientId: med.id.uuidString, payload: payload, updatedAt: med.createdAt)
        }
    }
}

@MainActor
struct MeditationSyncProvider: SyncableRecordProvider {
    let recordType = "meditation"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<MeditationLog>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { m in
            var payload: [String: Any] = [
                "title": "\(m.durationMinutes) min · \(m.type.rawValue)",
                "durationMinutes": m.durationMinutes,
                "date": iso(m.date),
            ]
            if let n = m.notes { payload["detail"] = n }
            return SyncRecord(type: recordType, clientId: m.id.uuidString, payload: payload, updatedAt: m.date)
        }
    }
}

@MainActor
struct StressSyncProvider: SyncableRecordProvider {
    let recordType = "stress"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<StressLog>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { s in
            var payload: [String: Any] = [
                "title": "Stress \(s.level)/10",
                "level": s.level,
                "triggers": s.triggers,
                "date": iso(s.date),
            ]
            if let n = s.notes { payload["detail"] = n }
            return SyncRecord(type: recordType, clientId: s.id.uuidString, payload: payload, updatedAt: s.date)
        }
    }
}

@MainActor
struct SymptomSyncProvider: SyncableRecordProvider {
    let recordType = "symptom"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<SymptomLog>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { s in
            var payload: [String: Any] = [
                "title": s.symptom,
                "subtitle": "Severity \(s.severity)/10",
                "severity": s.severity,
                "date": iso(s.date),
            ]
            if let area = s.bodyArea { payload["detail"] = area }
            return SyncRecord(type: recordType, clientId: s.id.uuidString, payload: payload, updatedAt: s.date)
        }
    }
}

@MainActor
struct LabResultSyncProvider: SyncableRecordProvider {
    let recordType = "lab_result"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<LabResult>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { l in
            let payload: [String: Any] = [
                "title": l.testName,
                "subtitle": "\(l.value) \(l.unit)",
                "value": l.value,
                "unit": l.unit,
                "outOfRange": l.isOutOfRange,
                "category": l.category,
                "date": iso(l.date),
            ]
            return SyncRecord(type: recordType, clientId: l.id.uuidString, payload: payload, updatedAt: l.date)
        }
    }
}

@MainActor
struct HabitSyncProvider: SyncableRecordProvider {
    let recordType = "habit"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(d).filter { $0.isActive }.map { h in
            let payload: [String: Any] = [
                "title": "\(h.emoji) \(h.name)",
                "subtitle": "\(h.currentStreak)-day streak · \(h.frequency.rawValue)",
                "streak": h.currentStreak,
                "completedToday": h.completedToday,
                "date": iso(h.createdAt),
            ]
            return SyncRecord(type: recordType, clientId: h.id.uuidString, payload: payload, updatedAt: h.createdAt)
        }
    }
}

@MainActor
struct ViceSyncProvider: SyncableRecordProvider {
    let recordType = "quit"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<Vice>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(d).filter { $0.isActive }.map { v in
            let payload: [String: Any] = [
                "title": "\(v.emoji) \(v.name)",
                "subtitle": "\(v.currentStreak)-day streak",
                "streak": v.currentStreak,
                "moneySaved": v.moneySaved,
                "date": iso(v.createdAt),
            ]
            return SyncRecord(type: recordType, clientId: v.id.uuidString, payload: payload, updatedAt: v.createdAt)
        }
    }
}

@MainActor
struct DayPlanSyncProvider: SyncableRecordProvider {
    let recordType = "day_plan"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<DayPlan>(predicate: #Predicate { $0.generatedAt >= since }, sortBy: [SortDescriptor(\.date)])
        return try context.fetch(d).map { p in
            var payload: [String: Any] = [
                "title": "Day plan",
                "actionCount": p.actions.count,
                "date": iso(p.date),
            ]
            if let s = p.summary { payload["subtitle"] = s }
            return SyncRecord(type: recordType, clientId: p.id.uuidString, payload: payload, updatedAt: p.generatedAt)
        }
    }
}

@MainActor
struct FriendActivitySyncProvider: SyncableRecordProvider {
    let recordType = "friend_activity"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<FriendActivity>(predicate: #Predicate { $0.timestamp >= since }, sortBy: [SortDescriptor(\.timestamp)])
        return try context.fetch(d).map { a in
            let payload: [String: Any] = [
                "title": "\(a.friendName) \(a.action)",
                "subtitle": a.emoji,
                "date": iso(a.timestamp),
            ]
            return SyncRecord(type: recordType, clientId: a.id.uuidString, payload: payload, updatedAt: a.timestamp)
        }
    }
}

/// Maps `Trip` rows (with their items) to generic sync records of type `trip` so
/// the web `/travel` screen can render upcoming/past trips, their budget rollup,
/// and a compact itinerary — read-only parity with the iOS Travel module.
@MainActor
struct TripSyncProvider: SyncableRecordProvider {
    let recordType = "trip"
    func fetchDirty(since: Date, context: ModelContext) throws -> [SyncRecord] {
        let d = FetchDescriptor<Trip>(predicate: #Predicate { $0.updatedAt >= since }, sortBy: [SortDescriptor(\.updatedAt)])
        return try context.fetch(d).map { trip in
            let sortedItems = trip.items.sorted {
                ($0.dayOffset ?? 0, $0.startAt ?? .distantFuture, $0.order)
                    < ($1.dayOffset ?? 0, $1.startAt ?? .distantFuture, $1.order)
            }
            let items: [[String: Any]] = sortedItems.map { item in
                var i: [String: Any] = [
                    "kind": item.kindRaw,
                    "title": item.title,
                    "booked": item.booked,
                    "order": item.order,
                ]
                if let d = item.details { i["details"] = d }
                if let l = item.location { i["location"] = l }
                if let u = item.url { i["url"] = u }
                if let p = item.price { i["price"] = p }
                if let c = item.currency { i["currency"] = c }
                if let r = item.rating { i["rating"] = r }
                if let off = item.dayOffset { i["dayOffset"] = off }
                if let s = item.startAt { i["startAt"] = iso(s) }
                return i
            }

            var payload: [String: Any] = [
                "title": trip.destination,
                "status": trip.statusRaw,
                "travelerCount": trip.travelerCount,
                "itemCount": trip.items.count,
                "currency": trip.effectiveCurrency,
                "estimatedCost": trip.estimatedCost,
                "bookedCost": trip.bookedCost,
                "items": items,
                "date": iso(trip.startDate ?? trip.createdAt),
            ]
            if let origin = trip.originCity { payload["originCity"] = origin }
            if let start = trip.startDate { payload["startDate"] = iso(start) }
            if let end = trip.endDate { payload["endDate"] = iso(end) }
            if let notes = trip.notes { payload["notes"] = notes }
            if let cover = trip.coverImageURL { payload["coverImageURL"] = cover }
            if let budget = trip.budgetAmount { payload["budgetAmount"] = budget }
            if let c = trip.destinationCurrency { payload["destinationCurrency"] = c }
            if let l = trip.destinationLanguage { payload["destinationLanguage"] = l }
            if let tz = trip.destinationTimeZoneId { payload["destinationTimeZoneId"] = tz }
            if let tip = trip.destinationTip { payload["destinationTip"] = tip }

            let subtitle: String
            if let start = trip.startDate {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                fmt.timeStyle = .none
                subtitle = "\(fmt.string(from: start)) · \(trip.items.count) plans"
            } else {
                subtitle = "\(trip.items.count) plans"
            }
            payload["subtitle"] = subtitle

            return SyncRecord(type: recordType, clientId: trip.id.uuidString, payload: payload, updatedAt: trip.updatedAt)
        }
    }
}
