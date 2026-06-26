import Foundation

// MARK: - Journal Metric Definitions

/// Static catalog of journal metrics, grouped by time-of-day section, mirroring
/// the daily check-in journals in dedicated health apps. State is tri-state
/// (no / neutral / yes) with optional numeric input for measured metrics.
struct JournalMetric: Identifiable {
    enum Section: String, CaseIterable {
        case pinned = "Pinned"
        case daytime = "Daytime"
        case nighttime = "Nighttime"
        case automatic = "Automatic"
    }

    /// How the value is captured.
    enum Kind {
        /// Tri-state x / – / ✓.
        case toggle
        /// Tri-state plus a numeric amount with a unit (e.g. drinks, mg).
        case amount(unit: String)
        /// Read-only, computed elsewhere (steps, cardio mins from ring).
        case automatic(unit: String)
        /// A score target that's met/unmet (e.g. "50+ stress score").
        case score
    }

    let key: String
    let title: String
    let emoji: String
    let section: Section
    let kind: Kind

    var id: String { key }

    var isAutomatic: Bool {
        if case .automatic = kind { return true }
        return false
    }
}

enum JournalCatalog {
    static let all: [JournalMetric] = [
        // Pinned
        JournalMetric(key: "daily_mood", title: "Daily mood", emoji: "face.smiling", section: .pinned, kind: .toggle),

        // Daytime
        JournalMetric(key: "added_sugar", title: "Added sugar", emoji: "birthday.cake.fill", section: .daytime, kind: .toggle),
        JournalMetric(key: "alcohol", title: "Alcohol", emoji: "wineglass.fill", section: .daytime, kind: .amount(unit: "drinks")),
        JournalMetric(key: "caffeine", title: "Caffeine", emoji: "cup.and.saucer.fill", section: .daytime, kind: .amount(unit: "mg")),
        JournalMetric(key: "hydration", title: "Hydration", emoji: "drop.fill", section: .daytime, kind: .amount(unit: "fl oz")),
        JournalMetric(key: "keto_diet", title: "Keto diet", emoji: "leaf.fill", section: .daytime, kind: .toggle),
        JournalMetric(key: "low_carbs", title: "Low carbs", emoji: "carrot.fill", section: .daytime, kind: .toggle),
        JournalMetric(key: "stress_score", title: "50+ stress score", emoji: "bolt.heart.fill", section: .daytime, kind: .score),
        JournalMetric(key: "nutrition_score", title: "67+ nutrition score", emoji: "fork.knife", section: .daytime, kind: .score),
        JournalMetric(key: "mindfulness", title: "Mindfulness session", emoji: "figure.mind.and.body", section: .daytime, kind: .amount(unit: "mins")),
        JournalMetric(key: "morning_sunlight", title: "Morning sunlight", emoji: "sun.max.fill", section: .daytime, kind: .toggle),
        JournalMetric(key: "naps", title: "Naps", emoji: "zzz", section: .daytime, kind: .toggle),

        // Nighttime
        JournalMetric(key: "device_in_bed", title: "Device in bed", emoji: "iphone", section: .nighttime, kind: .toggle),
        JournalMetric(key: "late_meal", title: "Late meal", emoji: "fork.knife", section: .nighttime, kind: .toggle),
        JournalMetric(key: "sleeping_noise", title: "50+ dB sleeping noise", emoji: "speaker.wave.3.fill", section: .nighttime, kind: .score),

        // Automatic (from ring / phone)
        JournalMetric(key: "daylight", title: "20+ mins of daylight", emoji: "cloud.sun.fill", section: .automatic, kind: .automatic(unit: "mins")),
        JournalMetric(key: "strength_mins", title: "20+ mins of strength", emoji: "figure.strengthtraining.traditional", section: .automatic, kind: .automatic(unit: "mins")),
        JournalMetric(key: "zone2", title: "30+ mins of zone 2", emoji: "heart.fill", section: .automatic, kind: .automatic(unit: "mins")),
        JournalMetric(key: "steps", title: "10,000+ steps", emoji: "shoeprints.fill", section: .automatic, kind: .automatic(unit: "steps")),
        JournalMetric(key: "cardio_mins", title: "20+ mins of cardio", emoji: "figure.run", section: .automatic, kind: .automatic(unit: "mins")),
    ]

    static func metrics(in section: JournalMetric.Section) -> [JournalMetric] {
        all.filter { $0.section == section }
    }

    static func metric(for key: String) -> JournalMetric? {
        all.first { $0.key == key }
    }
}
