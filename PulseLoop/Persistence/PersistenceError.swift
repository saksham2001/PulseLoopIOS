import Foundation
import SwiftData
import os

/// Error thrown/logged when a SwiftData persistence operation fails.
///
/// SwiftData's `ModelContext.save()` is throwing, but the codebase historically
/// swallowed failures with `try? context.save()`, which silently loses user data and
/// leaves no trace to diagnose. `PersistenceError` + `saveOrLog`/`saveOrThrow` give a
/// single, logged seam so a failed write is at least recorded (and can be surfaced).
enum PersistenceError: Error, CustomStringConvertible {
    case saveFailed(area: String, underlying: Error)

    var description: String {
        switch self {
        case let .saveFailed(area, underlying):
            return "Persistence save failed in \(area): \(underlying)"
        }
    }
}

extension ModelContext {
    /// Save pending changes, logging (but not throwing) on failure.
    ///
    /// Drop-in replacement for `try? context.save()` that records failures via
    /// `AppLog.persistence` instead of discarding them silently. Returns `true` on
    /// success so callers can branch (e.g. show an error toast) when it matters.
    ///
    /// - Parameters:
    ///   - area: short label for where the save originated (e.g. "coach", "notes"),
    ///     used in the log line so failures are attributable.
    ///   - surface: when `true`, a user-facing error toast is shown on failure via
    ///     `ErrorPresenter`. Use for writes the user explicitly initiated; leave
    ///     `false` for background/best-effort saves to avoid noise.
    @discardableResult
    func saveOrLog(_ area: String, surface: Bool = false) -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            AppLog.persistence.error("Save failed [\(area, privacy: .public)]: \(String(describing: error), privacy: .public)")
            if surface {
                Task { @MainActor in
                    ErrorPresenter.shared.present("Couldn't save your changes. Please try again.")
                }
            }
            return false
        }
    }

    /// Save pending changes, logging and rethrowing as `PersistenceError` on failure.
    /// Use when the caller can react to a failure (surface an error, retry, roll back).
    func saveOrThrow(_ area: String) throws {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            AppLog.persistence.error("Save failed [\(area, privacy: .public)]: \(String(describing: error), privacy: .public)")
            throw PersistenceError.saveFailed(area: area, underlying: error)
        }
    }
}
