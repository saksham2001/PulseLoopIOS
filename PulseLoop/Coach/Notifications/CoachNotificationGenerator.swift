import Foundation

/// Single-shot OpenAI call that turns a 12h context packet into a check-in.
/// No tools  -  just system + developer → strict `{title, body}`. Falls back to a
/// deterministic, grounded notification if disabled or the API fails, so a
/// delivered check-in is always sensible.
@MainActor
enum CoachNotificationGenerator {
    static func generate(
        slot: CoachNotificationSlot,
        packet: NotificationContextPacket,
        flags: CoachFeatureFlags,
        client: ResponsesClient
    ) async -> CoachNotification {
        guard flags.coachEnabled else { return scripted(slot: slot, packet: packet) }
        do {
            let input: [[String: Any]] = [
                OpenAIRequestBuilder.message(role: "system", content: NotificationPromptBuilder.systemPrompt(slot: slot)),
                OpenAIRequestBuilder.message(role: "developer", content: NotificationPromptBuilder.developerMessage(packet: packet)),
            ]
            let body = try OpenAIRequestBuilder.data(
                model: flags.model, input: input, tools: [],
                textFormat: CoachNotificationSchema.textFormat,
                previousResponseId: nil, reasoningEffort: flags.settings.reasoningEffort
            )
            let response = try await client.send(requestBody: body)
            return CoachNotification.decode(fromJSON: response.outputText) ?? scripted(slot: slot, packet: packet)
        } catch {
            return scripted(slot: slot, packet: packet)
        }
    }

    /// Grounded, deterministic fallback.
    static func scripted(slot: CoachNotificationSlot, packet: NotificationContextPacket) -> CoachNotification {
        let name = packet.profileName.map { ", \($0)" } ?? ""
        switch slot {
        case .morning:
            if let sleep = packet.latestSleep {
                let h = sleep.totalMin / 60, m = sleep.totalMin % 60
                return CoachNotification(title: "Good morning\(name)",
                                         body: "You logged \(h)h \(m)m of sleep. Here's to a strong day  -  get moving when you can.")
            }
            return CoachNotification(title: "Good morning\(name)",
                                     body: "Ready to start the day? Take a measurement and I'll help you plan it.")
        case .evening:
            if let steps = packet.today.steps {
                let goal = packet.goals.stepsDaily
                let hit = steps >= goal ? "You hit your \(goal) step goal  -  nice work." : "\(goal - steps) steps to your goal."
                return CoachNotification(title: "Evening check-in",
                                         body: "\(steps) steps today. \(hit) Time to start winding down.")
            }
            return CoachNotification(title: "Evening check-in",
                                     body: "How did today feel? Sync your ring and I'll recap your day.")
        }
    }
}
