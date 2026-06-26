import Foundation
import SwiftData

/// Persists user feedback on assistant replies (Life OS T0). Kept tiny and pure so
/// the write path is unit-testable and reused by every surface (chat bubble, voice
/// confirmation). One feedback row per (message, rating); re-rating the same message
/// updates the existing row rather than piling up duplicates.
enum CoachFeedbackStore {
    enum Rating: String { case up, down }

    /// Record (or update) feedback for an assistant message. Looks up the turn's
    /// decision log to snapshot the role/model that produced the reply, so feedback
    /// can later be sliced by model without a join. Returns the saved record.
    @discardableResult
    @MainActor
    static func record(
        messageId: UUID,
        conversationId: UUID,
        rating: Rating,
        reason: String = "",
        in context: ModelContext
    ) -> CoachFeedback {
        let existing = fetch(messageId: messageId, in: context)
        let telemetry = telemetry(for: messageId, in: context)

        if let existing {
            existing.rating = rating.rawValue
            existing.reason = reason
            if let telemetry {
                existing.roleLabel = telemetry.roleLabel
                existing.model = telemetry.model
            }
            existing.createdAt = Date()
            context.saveOrLog("coach.feedback")
            Analytics.track("coach_feedback", ["rating": rating.rawValue, "had_reason": String(!reason.isEmpty)])
            return existing
        }

        let record = CoachFeedback(
            messageId: messageId,
            conversationId: conversationId,
            rating: rating.rawValue,
            reason: reason,
            roleLabel: telemetry?.roleLabel ?? "",
            model: telemetry?.model ?? ""
        )
        context.insert(record)
        context.saveOrLog("coach.feedback")
        Analytics.track("coach_feedback", ["rating": rating.rawValue, "had_reason": String(!reason.isEmpty)])
        return record
    }

    /// The existing feedback for a message, if any.
    static func fetch(messageId: UUID, in context: ModelContext) -> CoachFeedback? {
        var descriptor = FetchDescriptor<CoachFeedback>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func telemetry(for messageId: UUID, in context: ModelContext) -> TurnTelemetry? {
        var descriptor = FetchDescriptor<TurnTelemetry>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Low-cardinality reason codes offered when the user taps thumbs-down. Stable
    /// strings so they aggregate cleanly on the quality dashboard (T6).
    static let downReasons: [(code: String, label: String)] = [
        ("inaccurate", "Inaccurate"),
        ("too_long", "Too long"),
        ("off_topic", "Off topic"),
        ("didnt_act", "Didn't do it"),
    ]

    // MARK: - Aggregate signal (Life OS T4 feedback-weighted routing)

    /// Aggregate recent on-device outcomes per model, optionally scoped to one role
    /// (matched on `TurnTelemetry.roleLabel`). Joins telemetry (turns/recovered/
    /// errored) with feedback (up/down) by model. Pure read; never throws — returns
    /// an empty map when there's no data, so routing degrades to the capability prior.
    @MainActor
    static func outcomeStats(
        roleLabel: String? = nil,
        limit: Int = 400,
        in context: ModelContext
    ) -> [String: ModelOutcomeStats] {
        var byModel: [String: ModelOutcomeStats] = [:]

        var telemetryDescriptor = FetchDescriptor<TurnTelemetry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        telemetryDescriptor.fetchLimit = limit
        let telemetry = (try? context.fetch(telemetryDescriptor)) ?? []
        for t in telemetry {
            if let roleLabel, t.roleLabel != roleLabel { continue }
            guard !t.model.isEmpty else { continue }
            var stat = byModel[t.model] ?? ModelOutcomeStats(model: t.model)
            stat.turns += 1
            if t.recovered { stat.recoveredTurns += 1 }
            if !t.errorReason.isEmpty { stat.erroredTurns += 1 }
            byModel[t.model] = stat
        }

        var feedbackDescriptor = FetchDescriptor<CoachFeedback>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        feedbackDescriptor.fetchLimit = limit
        let feedback = (try? context.fetch(feedbackDescriptor)) ?? []
        for f in feedback {
            if let roleLabel, f.roleLabel != roleLabel { continue }
            guard !f.model.isEmpty else { continue }
            var stat = byModel[f.model] ?? ModelOutcomeStats(model: f.model)
            if f.rating == Rating.up.rawValue { stat.upVotes += 1 }
            else if f.rating == Rating.down.rawValue { stat.downVotes += 1 }
            byModel[f.model] = stat
        }

        return byModel
    }
}
