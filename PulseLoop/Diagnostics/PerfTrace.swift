//
//  PerfTrace.swift
//  PulseLoop
//
//  TEMPORARY performance-diagnosis instrumentation. Gated entirely behind the
//  `PERF_TRACE` compilation condition (Debug only). To remove after diagnosis:
//    1. Delete this file.
//    2. Remove `PERF_TRACE` from SWIFT_ACTIVE_COMPILATION_CONDITIONS in project.pbxproj.
//    3. Compile — every remaining call site becomes a compile error → exact removal checklist.
//
//  When PERF_TRACE is off, every API below is an inlined no-op that returns
//  `body()` unchanged, so leftover call sites cost nothing in Release.
//
//  Console.app / log stream filter:  subsystem:xyz.sakshambhutani.pulseloop2
//  (further narrow with category, e.g. category:repo)
//

import Foundation
import SwiftUI

#if PERF_TRACE

import os

/// Lightweight timing / counting tracer for performance diagnosis.
///
/// Emits both an `os.Logger` line (human-readable, shows in Console.app and the
/// Xcode console) and an `OSSignposter` interval (shows as an Instruments lane,
/// so on-device durations can be cross-checked against Time Profiler / Hangs).
enum PerfTrace {
    nonisolated static let subsystem = "xyz.sakshambhutani.pulseloop2"

    enum Category: String {
        case repo, summary, coach, view, keychain, llm, event
    }

    // MARK: Cached loggers / signposters (one per category)

    private static let loggers = OSAllocatedUnfairLock(initialState: [String: Logger]())
    private static let signposters = OSAllocatedUnfairLock(initialState: [String: OSSignposter]())

    static func logger(_ category: Category) -> Logger {
        loggers.withLock { cache in
            if let existing = cache[category.rawValue] { return existing }
            let made = Logger(subsystem: subsystem, category: category.rawValue)
            cache[category.rawValue] = made
            return made
        }
    }

    static func signposter(_ category: Category) -> OSSignposter {
        signposters.withLock { cache in
            if let existing = cache[category.rawValue] { return existing }
            let made = OSSignposter(subsystem: subsystem, category: category.rawValue)
            cache[category.rawValue] = made
            return made
        }
    }

    // MARK: Synchronous timing

    /// Times `body`, returns its value unchanged, logs duration (ms) + thread.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ category: Category, _ body: () -> T) -> T {
        let sp = signposter(category)
        let state = sp.beginInterval(name)
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            sp.endInterval(name, state)
            logger(category).log("⏱️ \(name, privacy: .public) \(ms, format: .fixed(precision: 2))ms main=\(Thread.isMainThread, privacy: .public)")
        }
        return body()
    }

    /// Like `measure`, but the body returns an array and we also log its count —
    /// the key evidence for unbounded fetches (how many rows were materialized).
    @discardableResult
    static func measureRows<T>(_ name: StaticString, _ category: Category, _ body: () -> [T]) -> [T] {
        let sp = signposter(category)
        let state = sp.beginInterval(name)
        let start = CFAbsoluteTimeGetCurrent()
        let result = body()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        sp.endInterval(name, state)
        logger(category).log("⏱️ \(name, privacy: .public) rows=\(result.count, privacy: .public) \(ms, format: .fixed(precision: 2))ms main=\(Thread.isMainThread, privacy: .public)")
        return result
    }

    // MARK: Async timing (LLM / refresh paths)

    @discardableResult
    static func measure<T>(_ name: StaticString, _ category: Category, _ body: () async -> T) async -> T {
        let sp = signposter(category)
        let state = sp.beginInterval(name)
        let start = CFAbsoluteTimeGetCurrent()
        let result = await body()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        sp.endInterval(name, state)
        logger(category).log("⏱️ \(name, privacy: .public) \(ms, format: .fixed(precision: 2))ms main=\(Thread.isMainThread, privacy: .public)")
        return result
    }

    @discardableResult
    static func measureThrows<T>(_ name: StaticString, _ category: Category, _ body: () async throws -> T) async throws -> T {
        let sp = signposter(category)
        let state = sp.beginInterval(name)
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let result = try await body()
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            sp.endInterval(name, state)
            logger(category).log("⏱️ \(name, privacy: .public) \(ms, format: .fixed(precision: 2))ms main=\(Thread.isMainThread, privacy: .public)")
            return result
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            sp.endInterval(name, state)
            logger(category).log("⏱️ \(name, privacy: .public) THREW after \(ms, format: .fixed(precision: 2))ms main=\(Thread.isMainThread, privacy: .public)")
            throw error
        }
    }

    // MARK: Counters (render counts, event-burst counts)

    private static let counters = OSAllocatedUnfairLock(initialState: [String: Int]())

    /// Increments a named running tally and logs the total. Use the dynamic-name
    /// overload for cases keyed at runtime (e.g. event case names).
    @discardableResult
    static func count(_ name: String, _ category: Category) -> Int {
        let total = counters.withLock { dict -> Int in
            let next = (dict[name] ?? 0) + 1
            dict[name] = next
            return next
        }
        logger(category).log("🔢 \(name, privacy: .public) #\(total, privacy: .public)")
        return total
    }

    /// Fire-and-forget annotation (no timing) — for logging decision branches,
    /// JSON byte sizes, response sizes, etc.
    static func note(_ category: Category, _ message: String) {
        logger(category).log("📝 \(message, privacy: .public)")
    }

    /// SwiftUI render tick — counts a body re-render and prints WHICH input changed
    /// (via `_printChanges`). Call as the first statement of `body`:
    ///   `let _ = PerfTrace.renderTick("MyView", Self.self)`
    /// Returns `()` so it slots into a `@ViewBuilder` via `let _ =`.
    static func renderTick<V: View>(_ name: String, _ view: V.Type) {
        count(name + ".body", .view)
        V._printChanges()
    }
}

#else

// MARK: - No-op shims (PERF_TRACE off). Zero cost; preserve return values.

enum PerfTrace {
    enum Category { case repo, summary, coach, view, keychain, llm, event }

    @inline(__always) @discardableResult
    static func measure<T>(_ name: StaticString, _ category: Category, _ body: () -> T) -> T { body() }

    @inline(__always) @discardableResult
    static func measureRows<T>(_ name: StaticString, _ category: Category, _ body: () -> [T]) -> [T] { body() }

    @inline(__always) @discardableResult
    static func measure<T>(_ name: StaticString, _ category: Category, _ body: () async -> T) async -> T { await body() }

    @inline(__always) @discardableResult
    static func measureThrows<T>(_ name: StaticString, _ category: Category, _ body: () async throws -> T) async throws -> T { try await body() }

    @inline(__always) @discardableResult
    static func count(_ name: String, _ category: Category) -> Int { 0 }

    @inline(__always)
    static func note(_ category: Category, _ message: String) {}

    @inline(__always)
    static func renderTick<V: View>(_ name: String, _ view: V.Type) {}
}

#endif
