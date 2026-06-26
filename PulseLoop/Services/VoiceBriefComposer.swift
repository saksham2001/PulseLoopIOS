import Foundation

/// Builds the short, spoken **daily brief** the hands-free voice surface can read
/// when the user opts in. It is intentionally pure (no SwiftData, no I/O) so the
/// exact wording is deterministic and unit-testable: feed it the time of day and
/// the user's durable learnings, get back a ready-to-speak script.
///
/// The brief is meant to feel like a calm morning hand-off, not a data dump: a
/// time-aware greeting, the one or two things most worth knowing today, then a
/// soft prompt to start organizing. It de-dashes its output through the same
/// rule the Coach uses so the spoken/printed text stays consistent.
enum VoiceBriefComposer {
    /// A learning reduced to just what the brief needs, so callers can map their
    /// SwiftData models in without this type depending on persistence.
    struct Item: Equatable {
        var title: String
        var detail: String
        /// 1...5; higher surfaces first and caps how many we read.
        var importance: Int

        init(title: String, detail: String, importance: Int) {
            self.title = title
            self.detail = detail
            self.importance = importance
        }
    }

    /// The most important learnings to mention, newest/strongest first. We read
    /// at most this many so the brief stays under ~15 seconds.
    static let maxMentions = 2

    /// Builds the spoken script. Returns an empty string when there's nothing
    /// worth saying, so the caller can simply skip speaking.
    static func script(now: Date = Date(),
                       learnings: [Item],
                       calendar: Calendar = .current) -> String {
        let greeting = greeting(for: now, calendar: calendar)

        let ranked = learnings
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.importance > $1.importance }
            .prefix(maxMentions)

        var parts: [String] = [greeting]

        if ranked.isEmpty {
            parts.append("What would you like to organize?")
        } else if ranked.count == 1, let only = ranked.first {
            parts.append("Here's one thing worth keeping in mind today.")
            parts.append(mention(only))
            parts.append("What would you like to do first?")
        } else {
            parts.append("Here are a couple of things worth keeping in mind today.")
            for item in ranked { parts.append(mention(item)) }
            parts.append("Where would you like to start?")
        }

        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return CoachResponse.deDash(joined)
    }

    /// Whether the brief should play right now: opted in and not already spoken
    /// today. Pure so it can be tested with an injected "today" key.
    static func shouldSpeak(enabled: Bool, lastSpokenDay: String?, today: String) -> Bool {
        guard enabled else { return false }
        return lastSpokenDay != today
    }

    /// The stable `yyyy-MM-dd` key for a date in the given calendar's locale,
    /// used to gate the once-per-day brief.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Pieces

    private static func greeting(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default: return "Hi."
        }
    }

    /// One learning rendered as a single spoken sentence. Prefers the detail
    /// (which is already a sentence) and falls back to the title.
    private static func mention(_ item: Item) -> String {
        let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = detail.isEmpty ? title : detail
        return body.hasSuffix(".") || body.hasSuffix("!") || body.hasSuffix("?") ? body : body + "."
    }
}
