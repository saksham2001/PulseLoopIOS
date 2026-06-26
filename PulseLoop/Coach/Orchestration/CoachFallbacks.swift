import Foundation

/// Deterministic, grounded responses for when the LLM coach can't run (no key /
/// offline / API error) or when the final output can't be parsed. Ports
/// `_scripted_body` / `_fallback_body` from the web orchestrator.
enum CoachFallbacks {
    /// Used after an API failure or unrepairable output.
    static func fallback() -> CoachResponse {
        CoachResponse(
            responseType: .errorRecovery,
            title: "I had trouble with that",
            summary: "I checked your data but couldn't finish preparing the answer. Try asking again, or narrow the question.",
            dataQualityNote: "No changes were made.",
            followUpChips: ["How am I doing today?", "Summarize my week", "What data is missing?"],
            confidence: .low
        )
    }

    /// Used when the coach is disabled (offline / no key). Topic-aware: only
    /// surfaces health/ring data when the user actually asked about it. For any
    /// other topic (travel, tasks, general questions), it stays on-topic and
    /// honestly explains the assistant needs a key — it never injects a health
    /// summary into an unrelated request.
    static func scripted(packet: CoachContextPacket, userText: String = "") -> CoachResponse {
        let asksAboutHealth = isHealthIntent(userText)

        // Non-health request (or no message): don't dump health data. Engage the
        // topic at hand and point the user at the one thing that unblocks it.
        if !userText.isEmpty && !asksAboutHealth {
            return CoachResponse(
                responseType: .dataMissing,
                title: "Turn on the AI assistant to do that",
                summary: "I'd love to help with that, but the AI assistant is off right now, so I can't search the web or reason through it. Add an OpenAI (or OpenRouter) key in Settings → AI Assistant and I'll get right on it.",
                dataQualityNote: "No key configured. Nothing was changed.",
                followUpChips: ["What can you do?", "Why is the assistant off?"],
                confidence: .low
            )
        }

        let today = packet.today
        guard let steps = today.steps else {
            return CoachResponse(
                responseType: .dataMissing,
                title: "No activity synced yet",
                summary: "I don't have today's activity from the ring yet. Sync the ring or take a measurement and I'll summarize what comes in. (The AI assistant is off  -  add an OpenAI key in Settings to enable full guidance.)",
                dataQualityNote: packet.dataQualityWarnings.first,
                followUpChips: ["Is my ring connected?", "What data is missing?"],
                confidence: .low
            )
        }
        var bullets = ["Steps today: \(steps)"]
        if let cal = today.calories { bullets.append("Calories: \(Int(cal)) kcal") }
        if let hr = packet.latestVitals.latestHr { bullets.append("Latest HR: \(Int(hr)) bpm") }
        if let spo2 = packet.latestVitals.latestSpo2 { bullets.append("Latest SpO₂: \(Int(spo2))%") }
        return CoachResponse(
            responseType: .insight,
            title: "Here's where you are today",
            summary: "You're at \(steps) steps so far today. The AI assistant is off  -  add an OpenAI key in Settings for trends and tailored guidance.",
            bullets: bullets,
            dataQualityNote: packet.dataQualityWarnings.last,
            followUpChips: ["How does today compare to yesterday?", "What's my heart rate trend?"],
            confidence: today.dataConfidence == "high" ? .medium : .low
        )
    }

    /// Heuristic: does the message look like it's actually about the user's body /
    /// health / fitness / sleep / ring metrics? Used so the disabled-state
    /// fallback doesn't answer a travel (or other) question with health data.
    private static func isHealthIntent(_ text: String) -> Bool {
        let t = text.lowercased()
        guard !t.isEmpty else { return true } // empty / proactive open → default health summary
        let keywords = [
            "step", "steps", "heart", "hr ", "bpm", "spo2", "spo₂", "oxygen",
            "sleep", "slept", "recovery", "readiness", "hrv", "stress",
            "calorie", "calories", "workout", "exercise", "run", "walk", "weight",
            "bmi", "vitals", "ring", "today's activity", "how am i doing", "my health",
            "fitness", "rest", "active"
        ]
        return keywords.contains { t.contains($0) }
    }
}
