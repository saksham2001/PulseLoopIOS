import Foundation
import SwiftData

/// A durable, AI-derived insight about the user, written once per day by the
/// `DailyLearningService`. Unlike the ephemeral `CoachSummary` cards (which are
/// keyed by date and overwritten), learnings accumulate over time to form a
/// personal knowledge base the coach reuses. Each row captures one pattern,
/// correlation, or takeaway grounded in that day's data.
@Model
final class DailyLearning {
    @Attribute(.unique) var id: UUID
    /// Short headline, e.g. "Late caffeine hurts your deep sleep".
    var title: String
    /// One- or two-sentence explanation grounded in the user's data.
    var detail: String
    /// Coarse bucket so the UI and coach can group/filter: see `LearningCategory`.
    var categoryRaw: String
    /// 1–5; higher means more actionable / confident. Drives ordering + how
    /// prominently the coach surfaces it.
    var importance: Int
    /// Local date (YYYY-MM-DD) of the data run that produced this learning.
    var sourceDate: String
    /// When true, the coach actively factors this into advice. Users can mute a
    /// learning from the Insights screen without deleting it.
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        category: LearningCategory = .general,
        importance: Int = 3,
        sourceDate: String,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.categoryRaw = category.rawValue
        self.importance = min(5, max(1, importance))
        self.sourceDate = sourceDate
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var category: LearningCategory {
        LearningCategory(rawValue: categoryRaw) ?? .general
    }
}

/// Coarse grouping for a `DailyLearning`, mapped to an SF Symbol + label for the
/// Insights screen.
enum LearningCategory: String, CaseIterable, Identifiable {
    case sleep
    case activity
    case recovery
    case nutrition
    case supplements
    case mood
    case general

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleep: return "Sleep"
        case .activity: return "Activity"
        case .recovery: return "Recovery"
        case .nutrition: return "Nutrition"
        case .supplements: return "Supplements"
        case .mood: return "Mood"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz"
        case .activity: return "figure.walk"
        case .recovery: return "heart"
        case .nutrition: return "fork.knife"
        case .supplements: return "pills"
        case .mood: return "face.smiling"
        case .general: return "sparkles"
        }
    }
}
