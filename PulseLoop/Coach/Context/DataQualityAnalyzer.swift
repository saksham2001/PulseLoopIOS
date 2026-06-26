import Foundation

/// Builds the first-class data-quality warnings that ride in the context packet,
/// keeping the spirit of the web app's warnings so the coach never over-claims.
enum DataQualityAnalyzer {
    static let sleepDecoderNote =
        "Sleep stage decoding is experimental  -  light/deep/awake only, no REM; awake time may read as zero."

    struct Inputs {
        var profileCompleteness: String       // empty | partial | complete
        var daysAvailable: Int
        var hasSleep: Bool
        var lastSyncAt: Date?
        var isDemo: Bool
    }

    static func warnings(_ input: Inputs, now: Date = Date()) -> [String] {
        var out: [String] = []

        if input.isDemo {
            out.append("This is demo/sample data, not live readings from the ring.")
        }

        if input.profileCompleteness != "complete" {
            out.append(
                "User profile is incomplete (missing age/height/weight). "
                + "Don't compute personalized HR zones, BMI, or weight targets."
            )
        }

        if input.daysAvailable <= 3 {
            out.append(
                "Only \(input.daysAvailable) day(s) of activity data available  -  "
                + "trends are limited; avoid strong week-over-week claims."
            )
        }

        if input.hasSleep {
            out.append(sleepDecoderNote)
        }

        if !input.isDemo {
            if let last = input.lastSyncAt {
                let hours = Int(now.timeIntervalSince(last) / 3600)
                if hours >= 12 {
                    out.append("Ring hasn't synced in ~\(hours)h  -  today's data may be stale.")
                }
            } else {
                out.append("No recent ring sync recorded  -  data may be incomplete.")
            }
        }

        out.append("Ring HR and SpO₂ are wellness signals, not medical-grade measurements; do not diagnose.")
        return out
    }
}
