import Foundation

// MARK: - Media prompt moderation (multifunction roadmap P1)
//
// A local, deterministic pre-generation check on the *prompt* before any spend.
// Reuses `ModerationVerdict`. Blocks prompts that ask for clearly disallowed media
// (sexual content involving minors, explicit instructions for weapons/harm, etc.)
// and flags borderline requests. This is a first line of defense; muapi also runs
// its own safety filters server-side.

enum MediaModerator {
    /// Prompts containing these are rejected outright (no generation, no spend).
    private static let rejectPhrases = [
        "child", "minor", "underage", "cp ",
        "nude child", "naked child",
        "how to make a bomb", "build a weapon", "make a gun",
        "behead", "gore of a real person", "deepfake nude",
    ]

    /// Borderline requests that generate but warn (non-blocking).
    private static let flagPhrases = [
        "celebrity", "real person", "politician", "trademark", "brand logo",
    ]

    /// Moderate a generation prompt. `approved` → generate; `flagged` → generate with
    /// a warning; `rejected` → refuse before any network call.
    static func moderate(prompt: String) -> ModerationVerdict {
        let lower = prompt.lowercased()
        var rejects: [String] = []
        var flags: [String] = []
        for phrase in rejectPhrases where lower.contains(phrase) {
            rejects.append("Disallowed media request.")
        }
        for phrase in flagPhrases where lower.contains(phrase) {
            flags.append("Possibly involves a real person/brand: \"\(phrase.trimmingCharacters(in: .whitespaces))\".")
        }
        if !rejects.isEmpty { return .rejected(Array(Set(rejects)).sorted()) }
        if !flags.isEmpty { return .flagged(Array(Set(flags)).sorted()) }
        return .approved
    }
}
