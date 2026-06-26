import Foundation

/// Derives the chat's first-run greeting and cold-start suggestion chips from the
/// modules the user actually has installed (`SubAppRegistry.installedSubApps`),
/// so the assistant feels like *their* assistant — not a generic health bot
/// (Experience loop M2). With no modules installed it offers neutral, install-
/// oriented suggestions rather than health prompts that wouldn't work.
@MainActor
enum ModuleAwareChat {

    /// Per-module suggestion prompts keyed by `SubAppID.rawValue`. A module that
    /// isn't listed here falls back to a generic "Help me with <name>" chip.
    private static let promptsByModule: [String: [String]] = [
        "health": ["How am I doing today?", "Explain my heart rate trend"],
        "activity": ["Summarize my activity this week", "Did I hit my step goal?"],
        "sleep": ["How did I sleep last night?", "Show my sleep this week"],
        "workouts": ["Plan a workout for me", "Log my last workout"],
        "tasks": ["What's on my list today?", "Add a task to call the dentist"],
        "notes": ["Summarize my recent notes", "Take a note for me"],
        "journal": ["Help me reflect on today", "Start a journal entry"],
        "day_plan": ["Plan my day", "What's next on my schedule?"],
        "travel": ["Plan a trip", "Find flights for my next trip"],
        "mood_tracking": ["Log how I'm feeling", "How has my mood been?"],
        "nutrition": ["Log what I ate", "How's my nutrition today?"],
        "stress": ["Help me de-stress", "How stressed have I been?"],
        "meditation": ["Start a short meditation", "Help me wind down"],
        "protocol": ["Review my protocol", "What supplements am I taking?"],
        "symptoms_labs": ["Log a symptom", "Explain my latest labs"],
        "quit_program": ["How's my quit streak?", "I had a craving"],
        "accountability": ["How are my friends doing?", "Share my progress"],
        "ai_capture": ["What's in my inbox?", "Capture this for me"],
    ]

    /// Neutral suggestions when nothing health-specific is installed yet.
    private static let neutralPrompts = [
        "What can you help me with?",
        "Show me available modules",
        "Help me set up my app",
    ]

    /// The cold-start chips, ordered by the user's installed modules and capped so
    /// the row stays scannable. De-duplicated, falling back to neutral prompts when
    /// the user has no modules that suggest concrete actions.
    static func suggestionChips(installed: [any SubApp], limit: Int = 6) -> [String] {
        var chips: [String] = []
        var seen = Set<String>()

        func add(_ prompt: String) {
            guard !seen.contains(prompt) else { return }
            seen.insert(prompt)
            chips.append(prompt)
        }

        for app in installed {
            let mapped = promptsByModule[app.id.rawValue]
            if let mapped {
                mapped.forEach(add)
            } else {
                add("Help me with \(app.displayName)")
            }
            if chips.count >= limit { break }
        }

        if chips.isEmpty { neutralPrompts.forEach(add) }
        return Array(chips.prefix(limit))
    }

    /// A short greeting that nods to a couple of the user's installed modules so the
    /// empty state feels personalized, prefixed with a time-of-day salutation so it
    /// feels context-aware rather than static (AIN-8). Generic when nothing installed.
    static func greeting(installed: [any SubApp], date: Date = Date(), calendar: Calendar = .current) -> String {
        let hello = timeOfDayGreeting(date: date, calendar: calendar)
        let names = installed.prefix(3).map(\.displayName)
        switch names.count {
        case 0:
            return "\(hello). I'm your PulseLoop assistant. Ask me anything, or install a module to get started."
        case 1:
            return "\(hello). I can help with \(names[0]) and anything else on your mind."
        case 2:
            return "\(hello). I can help with \(names[0]), \(names[1]), and whatever else you need."
        default:
            return "\(hello). I can help across \(names[0]), \(names[1]), \(names[2]), and more. What's up?"
        }
    }

    /// "Good morning/afternoon/evening" based on the local hour.
    static func timeOfDayGreeting(date: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hi"
        }
    }
}
