import SwiftUI

/// Renders a decoded `CoachResponse` as the assistant bubble's content:
/// title, summary, bullets, embedded chart, safety + data-quality notes,
/// sources, and tappable follow-up chips.
struct CoachResponseView: View {
    let response: CoachResponse
    var onChipTap: ((String) -> Void)?
    /// Save an inline travel card to a trip. When nil, the save affordance is hidden.
    var onSaveTravelCard: ((CoachTravelCard) -> Void)?
    /// When true, the summary reveals progressively (typewriter) for a streaming
    /// feel on a freshly-arrived reply (AIN-1). Off for historical messages.
    var animateReveal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !response.title.isEmpty {
                Text(coachMarkdown: response.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
            }

            if !response.summary.isEmpty {
                if animateReveal {
                    TypewriterText(full: response.summary)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(PulseColors.textPrimary)
                } else {
                    Text(coachMarkdown: response.summary)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(PulseColors.textPrimary)
                }
            }

            if !response.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(response.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(PulseColors.accent)
                            Text(coachMarkdown: bullet).foregroundStyle(PulseColors.textSecondary)
                        }
                        .font(.system(size: 13))
                    }
                }
            }

            if let chart = response.chart {
                CoachChartView(chart: chart).padding(.top, 2)
            }

            if let diagram = response.diagram, !diagram.isEmpty {
                CoachDiagramView(diagram: diagram).padding(.top, 2)
            }

            if !response.media.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(response.media.enumerated()), id: \.offset) { _, media in
                        CoachMediaCardView(media: media)
                    }
                }
                .padding(.top, 2)
            }

            if !response.travelCards.isEmpty || !response.itinerary.isEmpty {
                CoachTravelCardsView(
                    cards: response.travelCards,
                    itinerary: response.itinerary,
                    onSave: onSaveTravelCard
                )
            }

            if let safety = response.safetyNote, !safety.isEmpty {
                noteRow(icon: "exclamationmark.triangle.fill", text: safety, tone: PulseColors.warning)
            }

            if let dq = response.dataQualityNote, !dq.isEmpty {
                noteRow(icon: "info.circle", text: dq, tone: PulseColors.textMuted)
            }

            if !response.sources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().background(PulseColors.borderHairline)
                    Text("SOURCES")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(PulseColors.textMuted)
                    ForEach(Array(response.sources.enumerated()), id: \.element.id) { index, source in
                        sourceRow(index: index + 1, source: source)
                    }
                }
                .padding(.top, 4)
            }

            if !response.followUpChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(response.followUpChips, id: \.self) { chip in
                            Button { onChipTap?(chip) } label: {
                                Text(chip)
                                    .font(.system(size: 12))
                                    .foregroundStyle(PulseColors.textSecondary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(PulseColors.cardSoft, in: Capsule())
                                    .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// A single Perplexity-style numbered, tappable source row: an index badge,
    /// the title, and the publisher. Opens the URL when valid.
    @ViewBuilder
    private func sourceRow(index: Int, source: CoachSource) -> some View {
        let content = HStack(alignment: .center, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 18, height: 18)
                .background(PulseColors.fillSubtle, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                    .lineLimit(1)
                if !source.publisher.isEmpty {
                    Text(source.publisher)
                        .font(.system(size: 10))
                        .foregroundStyle(PulseColors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if URL(string: source.url) != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }

        if let url = URL(string: source.url) {
            Link(destination: url) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private func noteRow(icon: String, text: String, tone: Color) -> some View {        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tone)
            Text(coachMarkdown: text).font(.system(size: 12)).foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Reveals text word-by-word for a streaming "typing" feel on a freshly-arrived
/// reply. Renders the final markdown once complete. Animates only once on appear.
private struct TypewriterText: View {
    let full: String
    @State private var shownWordCount = 0
    @State private var finished = false

    private var words: [Substring] { full.split(separator: " ", omittingEmptySubsequences: false) }

    var body: some View {
        Group {
            if finished {
                Text(coachMarkdown: full)
            } else {
                Text(words.prefix(shownWordCount).joined(separator: " "))
            }
        }
        .task {
            let total = words.count
            guard total > 0 else { finished = true; return }
            // ~45ms/word, capped so very long answers don't drag.
            let perWord = UInt64(min(45, max(12, 1_500 / max(1, total))) ) * 1_000_000
            while shownWordCount < total {
                if Task.isCancelled { break }
                shownWordCount += 1
                try? await Task.sleep(nanoseconds: perWord)
            }
            finished = true
        }
    }
}

extension Text {
    /// Renders inline Markdown (**bold**, *italic*, `code`, links) so model
    /// output like "**HR**" displays formatted instead of raw. Falls back to the
    /// literal string if parsing fails. `inlineOnlyPreservingWhitespace` keeps
    /// line breaks intact for multi-line summaries/bullets.
    init(coachMarkdown string: String) {
        if let attributed = try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            self.init(attributed)
        } else {
            self.init(verbatim: string)
        }
    }
}
