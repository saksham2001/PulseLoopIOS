import Foundation
import SwiftData
import os
#if canImport(HealthKit)
import HealthKit
#endif

/// Protocol that abstracts wearable data sources (ring, HealthKit, Oura API, etc.)
/// so the same SwiftData models can be populated from any device.
protocol WearableDataSource {
    var sourceName: String { get }
    func requestAuthorization() async throws
    func fetchLatestHeartRate() async throws -> Double?
    func fetchLatestSpO2() async throws -> Double?
    func fetchSteps(for date: Date) async throws -> Int?
    func fetchSleep(for date: Date) async throws -> (start: Date, end: Date, minutes: Int)?
}

/// Authorization / availability state for a health data source, so the UI can show an
/// honest state instead of silently rendering nothing.
enum HealthAuthorizationState: Equatable {
    /// HealthKit isn't available on this device (e.g. iPad without Health, simulator).
    case unavailable
    /// Available but the user hasn't been asked / hasn't granted access yet.
    case notAuthorized
    /// Access granted; reads should return real data.
    case authorized
}

/// HealthKit ingestion layer. Reads from Apple Health and writes into the same
/// SwiftData models the ring already populates.
///
/// On a device with the HealthKit entitlement this performs real `HKHealthStore`
/// authorization + sample queries. On the Simulator (where `isHealthDataAvailable()`
/// is false) it reports `.unavailable` so callers can render an honest "Apple Health
/// isn't available here" state rather than implying it has data.
final class HealthKitIngestion: WearableDataSource {
    let sourceName = "HealthKit"
    private let context: ModelContext

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    init(context: ModelContext) {
        self.context = context
    }

    /// Whether Apple Health is usable on this device at all.
    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// Best-effort current authorization state for reads. HealthKit deliberately does
    /// not reveal read-permission status (privacy), so once available we treat the
    /// share-status of a representative type as a proxy and otherwise report
    /// `.notAuthorized` until `requestAuthorization()` succeeds.
    var authorizationState: HealthAuthorizationState {
        guard isAvailable else { return .unavailable }
        #if canImport(HealthKit)
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            switch store.authorizationStatus(for: hr) {
            case .sharingAuthorized: return .authorized
            default: return .notAuthorized
            }
        }
        return .notAuthorized
        #else
        return .unavailable
        #endif
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            AppLog.health.info("HealthKit unavailable on this device; skipping authorization.")
            return
        }
        #if canImport(HealthKit)
        var readTypes: Set<HKObjectType> = []
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { readTypes.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) { readTypes.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { readTypes.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { readTypes.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { readTypes.insert(t) }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            AppLog.health.error("HealthKit authorization failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        #endif
    }

    func fetchLatestHeartRate() async throws -> Double? {
        #if canImport(HealthKit)
        return try await latestQuantity(.heartRate, unit: heartRateUnit)
        #else
        return nil
        #endif
    }

    func fetchLatestSpO2() async throws -> Double? {
        #if canImport(HealthKit)
        // SpO2 is a 0–1 fraction in HealthKit; surface as a percentage to match the app.
        guard let fraction = try await latestQuantity(.oxygenSaturation, unit: percentUnit) else { return nil }
        return fraction * 100
        #else
        return nil
        #endif
    }

    func fetchSteps(for date: Date) async throws -> Int? {
        guard isAvailable else { return nil }
        #if canImport(HealthKit)
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let (start, end) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let count = stats?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: count.map { Int($0) })
            }
            store.execute(query)
        }
        #else
        return nil
        #endif
    }

    func fetchSleep(for date: Date) async throws -> (start: Date, end: Date, minutes: Int)? {
        guard isAvailable else { return nil }
        #if canImport(HealthKit)
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let (start, end) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let asleep = (samples as? [HKCategorySample])?.filter { Self.isAsleep($0.value) } ?? []
                guard let first = asleep.min(by: { $0.startDate < $1.startDate }),
                      let last = asleep.max(by: { $0.endDate < $1.endDate }) else {
                    continuation.resume(returning: nil)
                    return
                }
                let minutes = asleep.reduce(0) { $0 + Int($1.endDate.timeIntervalSince($1.startDate) / 60) }
                continuation.resume(returning: (first.startDate, last.endDate, minutes))
            }
            store.execute(query)
        }
        #else
        return nil
        #endif
    }

    /// Persisted timestamp of the last successful HealthKit import (UserDefaults).
    /// Surfaced in the connector UI as "Last imported …".
    private static let lastImportKey = "healthkit.lastImportAt.v1"
    var lastImportAt: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastImportKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastImportKey) }
    }

    /// Outcome of a manual import, so the UI can show an honest result.
    enum ImportResult: Equatable {
        case unavailable
        case notAuthorized
        case imported(steps: Int?, heartRate: Int?, spo2: Int?)
        case failed(String)
    }

    /// Syncs HealthKit data into the shared SwiftData models.
    @MainActor
    func syncToModels() async {
        _ = await importNow()
    }

    /// Pulls the latest Apple Health data into the app's SwiftData models and
    /// records the import time. Returns an honest result for the UI.
    @MainActor
    @discardableResult
    func importNow() async -> ImportResult {
        guard isAvailable else { return .unavailable }
        guard authorizationState == .authorized else { return .notAuthorized }

        var importedSteps: Int?
        var importedHR: Int?
        var importedSpO2: Int?
        do {
            if let steps = try await fetchSteps(for: Date()) {
                importedSteps = steps
                let existing = MetricsRepository.activity(on: Date(), context: context)
                if let row = existing {
                    row.steps = max(row.steps, steps)
                } else {
                    context.insert(ActivityDaily(date: Date(), steps: steps, source: "healthkit"))
                }
            }
            if let hr = try await fetchLatestHeartRate() { importedHR = Int(hr.rounded()) }
            if let spo2 = try await fetchLatestSpO2() { importedSpO2 = Int(spo2.rounded()) }
        } catch {
            AppLog.health.error("HealthKit import failed: \(String(describing: error), privacy: .public)")
            return .failed("Couldn't read from Apple Health.")
        }

        context.saveOrLog("health.sync")
        lastImportAt = Date()
        return .imported(steps: importedSteps, heartRate: importedHR, spo2: importedSpO2)
    }

    // MARK: - Helpers

    #if canImport(HealthKit)
    private var heartRateUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }
    private var percentUnit: HKUnit { HKUnit.percent() }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func dayBounds(for date: Date) -> (Date, Date) {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }

    private static func isAsleep(_ value: Int) -> Bool {
        if #available(iOS 16.0, *) {
            switch HKCategoryValueSleepAnalysis(rawValue: value) {
            case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified, .some(.asleep):
                return true
            default:
                return false
            }
        } else {
            return value == HKCategoryValueSleepAnalysis.asleep.rawValue
        }
    }
    #endif
}
