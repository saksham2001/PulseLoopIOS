import SwiftUI
import SwiftData

struct ProtocolDetailView: View {
    let medication: Medication
    let allMedications: [Medication]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isLogged = false
    @State private var aiProfile: AISupplementProfile? = nil
    @State private var isLoadingAI = false

    private var knowledgeInfo: SupplementInfo? {
        SupplementKnowledge.find(medication.name)
    }

    private var medKnowledge: MedicationInfo? {
        MedicationKnowledge.find(medication.name)
    }

    private var peptideInfo: PeptideInfo? {
        PeptideKnowledge.find(medication.name)
    }

    private var interactions: [Interaction] {
        SupplementKnowledge.getInteractions(
            for: medication.name,
            inProtocol: allMedications.map(\.name)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                benefitSection
                prosConsSection
                mechanismSection
                timingSection
                interactionsSection
                stackSection
                logSection
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchAIProfile()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: medication.emoji.isEmpty ? "pills.fill" : medication.emoji)
                .font(.system(size: 24))
                .foregroundStyle(categoryColor)
                .frame(width: 56, height: 56)
                .background(categoryColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(PulseFont.title(22))
                    .foregroundStyle(PulseColors.textPrimary)
                HStack(spacing: 8) {
                    Text(medication.dose)
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textSecondary)
                    categoryBadge
                }
            }
            Spacer()
        }
    }

    private var categoryBadge: some View {
        Text(medication.category.rawValue.capitalized)
            .font(PulseFont.bodyMedium(11))
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(categoryColor.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Benefit

    private var benefitSection: some View {
        let benefit = medication.benefit ?? knowledgeInfo?.benefit ?? medKnowledge?.benefit ?? peptideInfo?.benefit ?? aiProfile?.benefit
        return Group {
            if let benefit {
                InfoCard(
                    icon: "sparkles",
                    title: "WHAT IT DOES",
                    content: benefit,
                    accentColor: PulseColors.success
                )
            } else if isLoadingAI {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Looking up info with AI...")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textMuted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Mechanism

    private var mechanismSection: some View {
        let mechanism = medication.mechanism ?? knowledgeInfo?.mechanism ?? medKnowledge?.mechanism ?? peptideInfo?.mechanism ?? aiProfile?.mechanism
        return Group {
            if let mechanism {
                InfoCard(
                    icon: "atom",
                    title: "HOW IT WORKS",
                    content: mechanism,
                    accentColor: PulseColors.spo2
                )
            }
        }
    }

    // MARK: - Pros & Cons

    private var prosConsSection: some View {
        let (pros, cons) = resolvedProsCons
        return Group {
            if !pros.isEmpty || !cons.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.textMuted)
                        Text("PROS & CONS")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                    }

                    if !pros.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(PulseColors.success)
                                Text("Benefits")
                                    .font(PulseFont.bodySemibold(12))
                                    .foregroundStyle(PulseColors.success)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(pros, id: \.self) { pro in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(PulseColors.success)
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 6)
                                        Text(pro)
                                            .font(PulseFont.body(13))
                                            .foregroundStyle(PulseColors.textSecondary)
                                            .lineSpacing(2)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PulseColors.success.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PulseColors.success.opacity(0.15), lineWidth: 1)
                        }
                    }

                    if !cons.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                Text("Side Effects & Risks")
                                    .font(PulseFont.bodySemibold(12))
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(cons, id: \.self) { con in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 6)
                                        Text(con)
                                            .font(PulseFont.body(13))
                                            .foregroundStyle(PulseColors.textSecondary)
                                            .lineSpacing(2)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
                        }
                    }
                }
            }
        }
    }

    private var resolvedProsCons: (pros: [String], cons: [String]) {
        if let supp = knowledgeInfo, !supp.pros.isEmpty {
            return (supp.pros, supp.cons)
        }
        if let med = medKnowledge {
            return (med.pros, med.cons)
        }
        if let _ = peptideInfo {
            return PeptideKnowledge.prosAndCons(for: medication.name)
        }
        if let ai = aiProfile {
            return (ai.pros, ai.cons)
        }
        return ([], [])
    }

    private var needsAILookup: Bool {
        knowledgeInfo == nil && medKnowledge == nil && peptideInfo == nil
    }

    private func fetchAIProfile() async {
        guard needsAILookup else { return }
        isLoadingAI = true
        defer { isLoadingAI = false }

        let name = medication.name
        let prompt = """
        You are a pharmacology and supplement expert. Given the ingredient "\(name)", provide information in this exact JSON format (no markdown, no code fences, just raw JSON):
        {
          "name": "\(name)",
          "category": "supplement|vitamin|medication|peptide",
          "defaultDose": "\(medication.dose)",
          "timing": "\(medication.timing)",
          "benefit": "one sentence what it does",
          "mechanism": "one sentence how it works",
          "pros": ["benefit 1", "benefit 2", "benefit 3", "benefit 4", "benefit 5"],
          "cons": ["side effect 1", "side effect 2", "side effect 3", "side effect 4", "side effect 5"],
          "bestTimeReason": "when and why to take it",
          "interactionNotes": "key drug interactions or warnings"
        }
        Return ONLY the JSON object, nothing else.
        """

        do {
            let response = try await AIService.shared.complete(
                messages: [AIService.Message(role: "user", content: prompt)],
                systemPrompt: "You are a pharmacology database. Return only valid JSON.",
                temperature: 0.3,
                maxTokens: 800
            )

            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                aiProfile = AISupplementProfile(
                    name: json["name"] as? String ?? name,
                    category: json["category"] as? String ?? "supplement",
                    defaultDose: json["defaultDose"] as? String ?? "",
                    timing: json["timing"] as? String ?? "AM",
                    benefit: json["benefit"] as? String ?? "",
                    mechanism: json["mechanism"] as? String ?? "",
                    pros: json["pros"] as? [String] ?? [],
                    cons: json["cons"] as? [String] ?? [],
                    bestTimeReason: json["bestTimeReason"] as? String ?? "",
                    interactionNotes: json["interactionNotes"] as? String ?? ""
                )
            }
        } catch { }
    }

    // MARK: - Timing

    private var timingSection: some View {
        let reason = medication.bestTimeReason ?? knowledgeInfo?.bestTimeReason
        return Group {
            if let reason {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.accent)
                        Text("BEST TIME TO TAKE")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                    }

                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text(medication.timing)
                                .font(PulseFont.bodySemibold(18))
                                .foregroundStyle(PulseColors.textPrimary)
                            Text("timing")
                                .font(PulseFont.body(11))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        .frame(width: 50)

                        Rectangle()
                            .fill(PulseColors.borderHairline)
                            .frame(width: 1, height: 36)

                        Text(reason)
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textSecondary)
                            .lineSpacing(2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Interactions

    private var interactionsSection: some View {
        Group {
            if !interactions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.textMuted)
                        Text("INTERACTIONS IN YOUR STACK")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                    }

                    VStack(spacing: 8) {
                        ForEach(interactions) { interaction in
                            InteractionCard(interaction: interaction)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stack Context

    private var stackSection: some View {
        let notes = medication.stackNotes ?? knowledgeInfo?.stackNotes
        let warnings = medication.interactionNotes ?? knowledgeInfo?.interactionNotes
        return Group {
            if notes != nil || warnings != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.textMuted)
                        Text("STACK NOTES")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                    }

                    if let notes {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(PulseColors.success)
                            Text(notes)
                                .font(PulseFont.body(13))
                                .foregroundStyle(PulseColors.textSecondary)
                                .lineSpacing(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PulseColors.successBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if let warnings {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                            Text(warnings)
                                .font(PulseFont.body(13))
                                .foregroundStyle(PulseColors.textSecondary)
                                .lineSpacing(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Log

    private var logSection: some View {
        Button {
            let log = MedicationLog(medicationId: medication.id, status: .taken)
            modelContext.insert(log)
            try? modelContext.save()
            withAnimation { isLogged = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { dismiss() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 16))
                Text(isLogged ? "Logged!" : "Log dose now")
                    .font(PulseFont.bodySemibold(15))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isLogged ? PulseColors.success : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isLogged)
    }

    private var categoryColor: Color {
        switch medication.category {
        case .vitamin, .supplement: return PulseColors.success
        case .peptide: return PulseColors.spo2
        case .medication: return PulseColors.accent
        }
    }
}

// MARK: - Sub-views

struct InfoCard: View {
    let icon: String
    let title: String
    let content: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
            }
            Text(content)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textPrimary)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct InteractionCard: View {
    let interaction: Interaction

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(kindColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(interaction.kind.rawValue)
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(kindColor)
                    Text("with \(interaction.otherName)")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textPrimary)
                }
                Text(interaction.note)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(12)
        .background(kindColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kindColor.opacity(0.2), lineWidth: 1)
        }
    }

    private var kindColor: Color {
        switch interaction.kind {
        case .synergy: return PulseColors.success
        case .conflict: return .orange
        case .timing: return PulseColors.spo2
        }
    }
}
