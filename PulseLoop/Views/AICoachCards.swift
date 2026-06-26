import SwiftUI

// MARK: - AI Coaching Cards (module surfaces for the multi-agent assistant)
//
// On-design entry points that hand a context-aware prompt to the existing multi-agent
// assistant (`CoachNavigation.askAI` → routes through `AgentRouter`, renders in the
// normal chat with its trace). These are NOT a parallel chat UI: they compose a good
// prompt from the module's live data and open the assistant prefilled. Design system:
// `.cursor/rules/design-system.mdc` (SF Symbols, Pulse tokens, no emoji).

/// A compact "ask the AI" prompt card with a headline, supporting line, an accent
/// icon, and one or more suggestion chips that each open the assistant prefilled.
struct AICoachCard: View {
    let icon: String
    let title: String
    let subtitle: String
    /// Chip label → prefill prompt handed to the assistant.
    let suggestions: [(label: String, prompt: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PulseColors.accent)
                    .frame(width: 34, height: 34)
                    .background(PulseColors.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(subtitle)
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer(minLength: 0)
            }
            FlowChips(suggestions: suggestions)
        }
        .padding(16)
        .pulseCardSurface()
    }
}

/// Wrapping row of suggestion chips. Each chip opens the assistant prefilled with its
/// prompt (consumed by `CoachView` on open; not auto-sent).
private struct FlowChips: View {
    let suggestions: [(label: String, prompt: String)]

    var body: some View {
        FlexibleChipLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                Button {
                    HapticService.impact(.light)
                    CoachNavigation.shared.askAI(s.prompt)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text(s.label)
                            .font(PulseFont.bodyMedium(13))
                    }
                    .foregroundStyle(PulseColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PulseColors.fillSubtle)
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(PulseColors.borderHairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask AI: \(s.label)")
            }
        }
    }
}

/// Minimal wrapping layout for chips (avoids depending on any external flow layout).
private struct FlexibleChipLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Nutrition coach card (Food Diary)

/// Daily nutrition coach: turns the day's remaining macros into targeted prompts the
/// Researcher/Generalist can answer ("what should I eat to hit my protein?").
struct NutritionCoachCard: View {
    let totals: NutritionTotals
    let goal: NutritionGoal?

    private var remainingCalories: Int? {
        goal.map { $0.calories - totals.calories }
    }
    private var remainingProtein: Int? {
        goal.map { max(0, Int($0.proteinG - totals.proteinG)) }
    }

    var body: some View {
        AICoachCard(
            icon: "fork.knife",
            title: "Daily nutrition coach",
            subtitle: subtitle,
            suggestions: suggestions
        )
    }

    private var subtitle: String {
        guard goal != nil, let cal = remainingCalories else {
            return "Get AI ideas for what to eat next."
        }
        if cal <= 0 { return "You're at your calorie goal — ask how to balance the rest of the day." }
        var s = "\(cal) kcal left"
        if let p = remainingProtein, p > 0 { s += " · \(p)g protein to go" }
        return s
    }

    private var suggestions: [(label: String, prompt: String)] {
        let macroLine: String
        if let goal {
            macroLine = "My goal is \(goal.calories) kcal, \(Int(goal.proteinG))g protein, \(Int(goal.carbsG))g carbs, \(Int(goal.fatG))g fat. So far today I've had \(totals.calories) kcal, \(Int(totals.proteinG))g protein, \(Int(totals.carbsG))g carbs, \(Int(totals.fatG))g fat."
        } else {
            macroLine = "So far today I've had \(totals.calories) kcal, \(Int(totals.proteinG))g protein."
        }
        return [
            ("What should I eat next?",
             "Look at my nutrition for today and suggest 2–3 specific meals or snacks for the rest of the day to hit my remaining macros. \(macroLine)"),
            ("Hit my protein",
             "I want to hit my protein goal today. \(macroLine) Suggest a few high-protein foods with their macros, and offer to log one."),
            ("Review my day",
             "Review what I've eaten today against my goals and give me one concise, actionable tip. \(macroLine)"),
        ]
    }
}

// MARK: - Workout coach card (Fitness Dashboard)

/// AI workout suggestion: proposes today's session from recent history + templates.
/// The "plan my week" prompt is phrased to route to the Strategist.
struct WorkoutCoachCard: View {
    let recentWorkouts: [WorkoutLog]
    let templateNames: [String]

    var body: some View {
        AICoachCard(
            icon: "figure.strengthtraining.traditional",
            title: "AI workout coach",
            subtitle: subtitle,
            suggestions: suggestions
        )
    }

    private var subtitle: String {
        if let last = recentWorkouts.first {
            return "Last: \(last.name) · \(last.date.formatted(.relative(presentation: .named)))"
        }
        return "Get a session suggestion based on your history."
    }

    private var suggestions: [(label: String, prompt: String)] {
        let history = recentWorkouts.prefix(5)
            .map { "\($0.name) (\($0.type.rawValue), \($0.date.formatted(.dateTime.month().day())))" }
            .joined(separator: ", ")
        let templates = templateNames.prefix(6).joined(separator: ", ")
        let context = "Recent workouts: \(history.isEmpty ? "none logged" : history). My templates: \(templates.isEmpty ? "none" : templates)."
        return [
            ("Suggest today's workout",
             "Suggest a good workout for me today based on my recent training and what muscle groups I've hit. \(context) Keep it specific and offer to start one of my templates if it fits."),
            ("Plan my week",
             "Plan a balanced 7-day training split for me, taking my recent workouts and existing templates into account, and explain the reasoning. \(context)"),
            ("What am I neglecting?",
             "Analyze my recent training and tell me which muscle groups or movement patterns I'm neglecting, with one corrective suggestion. \(context)"),
        ]
    }
}
