import Foundation
import SwiftData

/// Turns a raw voice transcript into a structured, app-wide plan instead of a
/// verbatim "Transcript" dump.
///
/// The router asks the AI to *regenerate* the transcript into a clean note plus
/// a set of classified action items (tasks), optionally scheduled across the
/// current week when the user is clearly planning ahead. When no AI key is
/// available — or the model returns something unparseable — a deterministic
/// local parser produces the same shape so the experience never degrades to a
/// raw transcript.
@MainActor
struct VoiceCaptureRouter {
    var ai: AIService = .shared
    /// Injected for deterministic week scheduling in tests.
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current

    // MARK: - Plan model

    /// Everything the capture will create across the app once confirmed.
    struct CapturePlan: Equatable {
        var title: String
        /// Cleaned, rewritten note body grouped into sections. Never the raw transcript.
        var sections: [Section]
        var tasks: [PlannedTask]
        /// The original transcript, kept for provenance (shown collapsed, not as the headline).
        var transcript: String

        struct Section: Equatable {
            var heading: String
            var bullets: [String]
        }

        struct PlannedTask: Equatable {
            var title: String
            /// Optional grouping/project, e.g. "Oravilles.com".
            var group: String
            /// Day offset from today (0 = today) when the user is planning a week. Nil = no due date.
            var dayOffset: Int?
        }

        var taskCount: Int { tasks.count }
        var scheduledCount: Int { tasks.filter { $0.dayOffset != nil }.count }
    }

    // MARK: - Public API

    /// Regenerates the transcript into a `CapturePlan`. Always returns a usable
    /// plan, even with no network / no API key (via the local fallback).
    func plan(from transcript: String) async -> CapturePlan {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CapturePlan(title: "Voice Note", sections: [], tasks: [], transcript: trimmed)
        }

        if ai.hasAPIKey {
            if let aiPlan = await aiPlan(from: trimmed) {
                return aiPlan
            }
        }
        return localPlan(from: trimmed)
    }

    // MARK: - AI path

    private func aiPlan(from transcript: String) async -> CapturePlan? {
        let weekContext = weekContextLine()
        let prompt = """
        You are PulseLoop's capture router. Rewrite a raw, rambling voice transcript \
        into a clean, organized note AND extract concrete action items as tasks so the \
        app can file everything in the right place. Do NOT echo the transcript verbatim.

        \(weekContext)

        Rules:
        1. "title": a short, specific title (max 6 words). No quotes.
        2. "sections": group the cleaned-up thoughts under clear headings. Fix grammar, \
        remove filler ("um", "so", "I want to be able to"). Keep bullets concise.
        3. "tasks": each concrete to-do the person mentioned. For each task give:
           - "title": imperative and specific (e.g. "Finish Oravilles.com packaging").
           - "group": the project/area it belongs to (e.g. "Oravilles.com", "Horizon AURA"), else "Inbox".
           - "dayOffset": integer 0–6 = which day THIS WEEK to do it (0 = today), or null if no timing.
             If the person says they want to "plan my week" / "this week", spread tasks across \
             upcoming days starting today; otherwise leave dayOffset null.
        4. Respond with ONLY this JSON, nothing else:

        {"title":"...","sections":[{"heading":"...","bullets":["..."]}],"tasks":[{"title":"...","group":"...","dayOffset":0}]}

        Raw transcript:
        \(transcript)
        """

        let raw: String
        do {
            raw = try await ai.complete(
                messages: [AIService.Message(role: "user", content: prompt)],
                temperature: 0.2,
                maxTokens: 1500
            )
        } catch {
            return nil
        }
        return Self.parse(raw, transcript: transcript)
    }

    private func weekContextLine() -> String {
        let today = now()
        let name = calendar.weekdaySymbols[calendar.component(.weekday, from: today) - 1]
        return "Today is \(name). When scheduling a week, dayOffset 0 means today (\(name))."
    }

    /// Parses the model's JSON envelope into a plan. Returns nil if the payload
    /// can't be understood (caller then uses the local parser).
    static func parse(_ response: String, transcript: String) -> CapturePlan? {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Tolerate leading/trailing prose by slicing to the outermost braces.
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }
        let jsonSlice = String(cleaned[start...end])

        guard let data = jsonSlice.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return nil }

        let sections: [CapturePlan.Section] = (json["sections"] as? [[String: Any]] ?? []).compactMap { s in
            guard let heading = s["heading"] as? String else { return nil }
            let bullets = (s["bullets"] as? [String])?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
            return CapturePlan.Section(heading: heading, bullets: bullets)
        }

        let tasks: [CapturePlan.PlannedTask] = (json["tasks"] as? [[String: Any]] ?? []).compactMap { t in
            guard let title = (t["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            let group = (t["group"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Inbox"
            var dayOffset: Int?
            if let n = t["dayOffset"] as? Int { dayOffset = n }
            else if let d = t["dayOffset"] as? Double { dayOffset = Int(d) }
            if let v = dayOffset, !(0...6).contains(v) { dayOffset = max(0, min(6, v)) }
            return CapturePlan.PlannedTask(title: title, group: group, dayOffset: dayOffset)
        }

        // A plan with neither sections nor tasks isn't useful — let the local parser try.
        guard !sections.isEmpty || !tasks.isEmpty else { return nil }
        return CapturePlan(title: title, sections: sections, tasks: tasks, transcript: transcript)
    }

    // MARK: - Local fallback (no network / no key)

    /// Deterministic intent parser. Splits the transcript into clauses, lifts
    /// action-like clauses into tasks, and keeps the rest as a cleaned note —
    /// so the result is always structured, never a raw dump.
    func localPlan(from transcript: String) -> CapturePlan {
        let clauses = Self.clauses(in: transcript)
        let planningWeek = Self.mentionsWeekPlanning(transcript)

        var tasks: [CapturePlan.PlannedTask] = []
        var noteBullets: [String] = []

        for clause in clauses {
            if Self.looksLikeAction(clause) {
                let title = Self.taskTitle(from: clause)
                guard !title.isEmpty else { continue }
                let group = Self.projectMention(in: clause) ?? "Inbox"
                tasks.append(.init(title: title, group: group, dayOffset: nil))
            } else {
                noteBullets.append(Self.tidy(clause))
            }
        }

        if planningWeek {
            for i in tasks.indices {
                tasks[i].dayOffset = i % 7
            }
        }

        let title = Self.derivedTitle(transcript: transcript, tasks: tasks)
        var sections: [CapturePlan.Section] = []
        if !noteBullets.isEmpty {
            sections.append(.init(heading: "Notes", bullets: noteBullets))
        }
        if sections.isEmpty && tasks.isEmpty {
            sections.append(.init(heading: "Notes", bullets: [Self.tidy(transcript)]))
        }

        return CapturePlan(title: title, sections: sections, tasks: tasks, transcript: transcript)
    }

    // MARK: - Local parsing helpers

    static func clauses(in text: String) -> [String] {
        let connectors = [" and then ", " then ", " also ", " plus ", " and i need to ", " and i want to ", " i need to ", " i want to "]
        var working = text.lowercased()
        // Protect domains like "oravilles.com" from sentence-splitting on the dot.
        if let regex = try? NSRegularExpression(pattern: #"([a-z0-9-]+)\.(com|io|app|co|ai|net|org)"#) {
            let range = NSRange(working.startIndex..., in: working)
            working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: "$1\u{2}$2")
        }
        for connector in connectors {
            working = working.replacingOccurrences(of: connector, with: "\u{1}", options: .caseInsensitive)
        }
        let separators = CharacterSet(charactersIn: ".\n")
        return working
            .components(separatedBy: separators)
            .flatMap { $0.components(separatedBy: "\u{1}") }
            .map { $0.replacingOccurrences(of: "\u{2}", with: ".").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
    }

    private static let actionVerbs = [
        "finish", "complete", "do", "call", "email", "send", "buy", "book", "schedule",
        "write", "plan", "prepare", "review", "fix", "build", "ship", "package", "pack",
        "order", "pay", "submit", "follow up", "set up", "create", "draft", "update",
        "clean", "organize", "save", "remember to", "need to", "have to", "should",
    ]

    static func looksLikeAction(_ clause: String) -> Bool {
        let c = clause.lowercased()
        return actionVerbs.contains { c.hasPrefix($0 + " ") || c.contains(" " + $0 + " ") || c.hasPrefix($0) }
    }

    /// Turns a spoken clause into an imperative task title.
    static func taskTitle(from clause: String) -> String {
        var c = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["i need to ", "i want to ", "i have to ", "i should ", "need to ",
                        "want to ", "have to ", "should ", "remember to ", "please "]
        let lower = c.lowercased()
        for p in prefixes where lower.hasPrefix(p) {
            c = String(c.dropFirst(p.count))
            break
        }
        c = c.replacingOccurrences(of: " please save it", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "please save it", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return c.sentenceCased()
    }

    static func tidy(_ clause: String) -> String {
        clause.trimmingCharacters(in: .whitespacesAndNewlines).sentenceCased()
    }

    static func mentionsWeekPlanning(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("plan") && (t.contains("week") || t.contains("my days") || t.contains("days"))
    }

    /// Detects a project/area name like "oravilles.com" or capitalized phrases ("Horizon AURA").
    static func projectMention(in clause: String) -> String? {
        if let range = clause.range(of: #"[a-z0-9-]+\.(com|io|app|co|ai|net|org)"#, options: [.regularExpression, .caseInsensitive]) {
            let domain = String(clause[range])
            return domain.prefix(1).uppercased() + domain.dropFirst()
        }
        return nil
    }

    static func derivedTitle(transcript: String, tasks: [CapturePlan.PlannedTask]) -> String {
        if mentionsWeekPlanning(transcript) { return "Plan My Week" }
        if let first = tasks.first { return first.title }
        let firstWords = transcript.split(separator: " ").prefix(5).joined(separator: " ")
        return firstWords.isEmpty ? "Voice Note" : firstWords.sentenceCased()
    }

    // MARK: - Scheduling

    /// Resolves a `dayOffset` into a concrete due date (start of that day).
    func dueDate(forDayOffset offset: Int?) -> Date? {
        guard let offset else { return nil }
        let base = calendar.startOfDay(for: now())
        return calendar.date(byAdding: .day, value: offset, to: base)
    }

    // MARK: - Persistence (shared by voice capture + the brain's capture tool)

    /// Result of filing a `CapturePlan` into the store.
    struct AppliedPlan {
        var note: Note
        var taskCount: Int
        var scheduledCount: Int
    }

    /// Persists a `CapturePlan` as a structured note (headings + bullets + todos)
    /// plus standalone `TaskItem`s. Single source of truth so the voice-capture UI
    /// and the AI `capture_and_file` tool produce identical results.
    @discardableResult
    func apply(_ plan: CapturePlan, in context: ModelContext, summaryPrefix: String = "Captured") -> AppliedPlan {
        let note = Note(title: plan.title.isEmpty ? "Note" : plan.title)
        context.insert(note)

        var order = 0
        for section in plan.sections {
            let heading = NoteBlock(noteId: note.id, order: order, kind: .heading, content: section.heading)
            context.insert(heading); note.blocks.append(heading); order += 1
            for bullet in section.bullets {
                let block = NoteBlock(noteId: note.id, order: order, kind: .bulletList, content: bullet)
                context.insert(block); note.blocks.append(block); order += 1
            }
        }

        for task in plan.tasks {
            let todo = NoteBlock(noteId: note.id, order: order, kind: .todo, content: task.title)
            context.insert(todo); note.blocks.append(todo); order += 1

            let item = TaskItem(
                title: task.title,
                group: task.group,
                dueDate: dueDate(forDayOffset: task.dayOffset),
                order: order
            )
            context.insert(item)
        }

        let scheduled = plan.scheduledCount
        note.aiSummary = "\(summaryPrefix) · \(plan.taskCount) task\(plan.taskCount == 1 ? "" : "s")"
            + (scheduled > 0 ? ", \(scheduled) scheduled this week" : "")
        context.saveOrLog("capture")
        return AppliedPlan(note: note, taskCount: plan.taskCount, scheduledCount: scheduled)
    }
}

private extension String {
    func sentenceCased() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
