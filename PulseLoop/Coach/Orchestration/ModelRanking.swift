import Foundation

// MARK: - Feedback-weighted model ranking (Life OS T4)
//
// A PURE ranking layer: given the candidate models for a role and the on-device
// outcome stats for each (from T0 telemetry + feedback), score them so routing can
// prefer models that actually work well for this user. With no signal it degrades to
// the declarative capability prior, so behavior is identical to today on day one.

/// Aggregated outcome signal for one (role, model) pair over a recent window.
struct ModelOutcomeStats: Hashable, Sendable {
    var model: String
    var upVotes: Int = 0
    var downVotes: Int = 0
    var turns: Int = 0
    var recoveredTurns: Int = 0
    var erroredTurns: Int = 0

    var totalVotes: Int { upVotes + downVotes }

    /// Wilson-ish satisfaction in 0...1, smoothed so a single vote doesn't dominate.
    var satisfaction: Double {
        let smoothing = 2.0  // pseudo-counts (1 up, 1 down) → neutral prior 0.5
        return (Double(upVotes) + 1) / (Double(totalVotes) + smoothing)
    }

    /// Fraction of turns that needed JSON recovery (lower is better).
    var recoveryRate: Double { turns == 0 ? 0 : Double(recoveredTurns) / Double(turns) }
    /// Fraction of turns that errored (lower is better).
    var errorRate: Double { turns == 0 ? 0 : Double(erroredTurns) / Double(turns) }
}

struct ModelScore: Hashable, Sendable {
    let slug: String
    let score: Double
    /// True when real feedback/telemetry (not just the prior) influenced the score.
    let hasSignal: Bool
}

enum ModelRanking {
    /// Score and sort candidates (best first). Pure: same inputs → same output.
    ///
    /// score = qualityPrior(0...1) * priorWeight
    ///       + satisfaction(0...1) * feedbackWeight
    ///       - recoveryRate * recoveryPenalty
    ///       - errorRate * errorPenalty
    ///       - costRank/100 * costWeight
    ///
    /// When a candidate has no votes and no turns, only the prior + cost terms apply
    /// (its `hasSignal` is false), so an unrated strong model still ranks sensibly.
    static func rank(
        candidates: [ModelCapability],
        stats: [String: ModelOutcomeStats],
        priorWeight: Double = 0.5,
        feedbackWeight: Double = 0.5,
        recoveryPenalty: Double = 0.3,
        errorPenalty: Double = 0.4,
        costWeight: Double = 0.1
    ) -> [ModelScore] {
        candidates.map { cap in
            let prior = Double(cap.quality) / 100.0
            let stat = stats[cap.slug]
            let hasSignal = (stat?.totalVotes ?? 0) > 0 || (stat?.turns ?? 0) > 0
            var score = prior * priorWeight
            score -= (Double(cap.costRank) / 100.0) * costWeight
            if let stat {
                if stat.totalVotes > 0 {
                    score += stat.satisfaction * feedbackWeight
                }
                score -= stat.recoveryRate * recoveryPenalty
                score -= stat.errorRate * errorPenalty
            } else {
                // No feedback: lean on the prior for the feedback term too so a
                // never-used strong model isn't dominated by a single-vote weak one.
                score += prior * feedbackWeight
            }
            return ModelScore(slug: cap.slug, score: score, hasSignal: hasSignal)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.slug < $1.slug  // deterministic tie-break
        }
    }

    /// The single best candidate slug, or nil when there are no candidates.
    static func best(
        candidates: [ModelCapability],
        stats: [String: ModelOutcomeStats]
    ) -> String? {
        rank(candidates: candidates, stats: stats).first?.slug
    }
}
