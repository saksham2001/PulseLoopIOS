import Foundation
import os

/// Lightweight structured-logging facade over `os.Logger`.
///
/// One subsystem (`xyz.sakshambhutani.PulseLoop`) with a fixed set of categories so
/// log output is filterable in Console.app / `log stream`. This replaces the app's
/// previous pattern of swallowing errors with `try?` and no record: failures that
/// matter should be logged here with enough context to diagnose them in the field.
///
/// Usage:
/// ```swift
/// AppLog.persistence.error("Save failed: \(error)")
/// AppLog.network.debug("GET \(url) -> \(status)")
/// ```
enum AppLog {
    static let subsystem = "xyz.sakshambhutani.PulseLoop"

    /// SwiftData saves, container/schema, migrations.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    /// URLSession requests, decoding, retries, caching.
    static let network = Logger(subsystem: subsystem, category: "network")
    /// Coach orchestration, tools, provider clients.
    static let coach = Logger(subsystem: subsystem, category: "coach")
    /// HealthKit ingestion + authorization.
    static let health = Logger(subsystem: subsystem, category: "health")
    /// Ring BLE client + sync.
    static let ring = Logger(subsystem: subsystem, category: "ring")
    /// View-layer / navigation / general app lifecycle.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
