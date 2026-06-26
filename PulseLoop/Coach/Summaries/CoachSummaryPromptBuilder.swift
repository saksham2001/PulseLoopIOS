import Foundation

/// Prompts for the Today/Sleep coach-card summaries.
enum CoachSummaryPromptBuilder {
    static func systemPrompt(kind: CoachSummaryKind) -> String {
        let focus: String
        switch kind {
        case .today:
            focus = "This card sits on the Today page. Give a quick, motivating read on how the day is going so far (steps, heart rate, sleep last night, activity)."
        case .sleepDay:
            focus = "This card sits on the Sleep page for last night. Interpret the night  -  duration, deep/light/awake balance, and the sleep score  -  and what it means for today."
        case .sleepRange:
            focus = "This card sits on the Sleep page for a multi-night range. Summarize the sleep trend (average duration, consistency, score) over the period."
        }
        return """
        You write a short coach card for PulseLoop, a smart-ring health app, grounded in the user's own data.

        \(focus)

        Rules:
        - Output ONLY JSON {"title","body","chips"}. Title ≤ ~6 words. Body 1–2 short, specific sentences citing real numbers from the data.
        - `chips` is up to 3 short follow-up questions the user might tap to dig in (e.g. "Why is my deep sleep low?", "How do I compare to last week?"). Phrase them as the user would ask the coach.
        - Be warm, specific, and genuinely useful  -  not generic. Ground every claim in the provided data; if data is thin, say so lightly and never invent numbers.
        - No medical diagnosis or alarming language. Wellness tone. At most one emoji, only if it fits.
        """
    }

    static func developerMessage(contextJSON: String) -> String {
        """
        Data for this card:
        \(contextJSON)

        Write the card now as {"title","body","chips"}.
        """
    }
}
