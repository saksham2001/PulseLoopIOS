import Foundation
import Combine

// MARK: - Per-sub-app analytics (roadmap G1)
//
// Lightweight, privacy-preserving, on-device usage counters per sub-app: how often a
// sub-app was opened, how many records were created, and when it was last used. No
// content is recorded — only counts + timestamps — so it never leaves the device and
// needs no permission. Built-ins and spec sub-apps both report through `record(...)`.
// A future backend (E3) can batch-upload aggregates if the user opts in.

struct SubAppUsageStat: Codable, Hashable, Identifiable {
    let subAppID: String
    var opens: Int
    var recordsCreated: Int
    var lastUsed: Date?
    /// Count of recoverable runtime errors (e.g. a record failed to decode/save).
    var recoverableErrors: Int

    var id: String { subAppID }

    init(subAppID: String, opens: Int = 0, recordsCreated: Int = 0, lastUsed: Date? = nil, recoverableErrors: Int = 0) {
        self.subAppID = subAppID
        self.opens = opens
        self.recordsCreated = recordsCreated
        self.lastUsed = lastUsed
        self.recoverableErrors = recoverableErrors
    }
}

@MainActor
final class SubAppAnalytics: ObservableObject {
    static let shared = SubAppAnalytics()

    enum Event {
        case opened
        case recordCreated
        case recoverableError
    }

    private static let storageKey = "pulseloop.subapp.analytics.v1"
    private let defaults: UserDefaults

    @Published private(set) var stats: [String: SubAppUsageStat] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: SubAppUsageStat].self, from: data) {
            stats = decoded
        }
    }

    func stat(for subAppID: String) -> SubAppUsageStat {
        stats[subAppID] ?? SubAppUsageStat(subAppID: subAppID)
    }

    func record(_ event: Event, subAppID: String) {
        guard !subAppID.isEmpty else { return }
        var stat = stats[subAppID] ?? SubAppUsageStat(subAppID: subAppID)
        switch event {
        case .opened:
            stat.opens += 1
            stat.lastUsed = Date()
        case .recordCreated:
            stat.recordsCreated += 1
            stat.lastUsed = Date()
        case .recoverableError:
            stat.recoverableErrors += 1
        }
        stats[subAppID] = stat
        persist()
    }

    func reset() {
        stats = [:]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
