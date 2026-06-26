import SwiftUI
import SwiftData

// MARK: - Knowledge Base (AI Insights)

/// "What PulseLoop has learned about you" — the durable, AI-derived knowledge
/// base produced by the once-daily `DailyLearningService`. Learnings accumulate
/// over time and feed back into the coach's context so advice gets more
/// personalised. Users can mute a learning (keep it but stop the coach using it)
/// or delete it outright, and trigger a manual refresh.
struct KnowledgeBaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyLearning.updatedAt, order: .reverse) private var learnings: [DailyLearning]

    @State private var isRefreshing = false
    @State private var refreshNote: String?

    private var activeCount: Int { learnings.filter(\.isActive).count }

    private var grouped: [(category: LearningCategory, items: [DailyLearning])] {
        let dict = Dictionary(grouping: learnings) { $0.category }
        return LearningCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.importance > $1.importance })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if learnings.isEmpty {
                    emptyState
                } else {
                    ForEach(grouped, id: \.category) { group in
                        section(group.category, items: group.items)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(PulseColors.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What I've learned")
                        .font(PulseFont.title(28))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(subtitle)
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                refreshButton
            }
            if let refreshNote {
                Text(refreshNote)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textSecondary)
            }
        }
    }

    private var subtitle: String {
        if learnings.isEmpty { return "Your personal AI knowledge base" }
        let active = activeCount
        return "\(learnings.count) insight\(learnings.count == 1 ? "" : "s") · \(active) active"
    }

    private var refreshButton: some View {
        Button {
            HapticService.impact(.light)
            refreshNow()
        } label: {
            HStack(spacing: 6) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(isRefreshing ? "Thinking" : "Update")
            }
            .font(PulseFont.bodySemibold(13))
            .foregroundStyle(PulseColors.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(PulseColors.background)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(PulseColors.borderStrong, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .accessibilityLabel("Update knowledge base now")
    }

    // MARK: Sections

    private func section(_ category: LearningCategory, items: [DailyLearning]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(category.label.uppercased()) {
                Image(systemName: category.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
            }
            ForEach(items) { learning in
                LearningRow(
                    learning: learning,
                    onToggle: { toggle(learning) },
                    onDelete: { delete(learning) }
                )
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(PulseColors.textMuted)
            InlineEmptyState(
                title: "Nothing learned yet",
                message: "Each day, PulseLoop reviews your activity, sleep, journal, and supplements to find patterns. Insights show up here as your data builds — or tap Update to run it now."
            )
        }
        .padding(.vertical, 16)
        .pulseCardSurface()
    }

    // MARK: Actions

    private func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshNote = nil
        let ctx = modelContext
        Task {
            let added = await DailyLearningService(modelContext: ctx).runIfNeeded()
            await MainActor.run {
                isRefreshing = false
                switch added {
                case 0: refreshNote = "No new patterns yet — check back after more data builds up."
                case 1: refreshNote = "Added 1 new insight."
                default: refreshNote = "Added \(added) new insights."
                }
                if added > 0 { HapticService.success() }
            }
        }
    }

    private func toggle(_ learning: DailyLearning) {
        HapticService.selection()
        learning.isActive.toggle()
        learning.updatedAt = Date()
        try? modelContext.save()
    }

    private func delete(_ learning: DailyLearning) {
        HapticService.impact(.light)
        modelContext.delete(learning)
        try? modelContext.save()
    }
}

// MARK: - Learning Row

private struct LearningRow: View {
    let learning: DailyLearning
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(learning.title)
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(learning.isActive ? PulseColors.textPrimary : PulseColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                importancePips
            }
            Text(learning.detail)
                .font(PulseFont.body(13))
                .foregroundStyle(learning.isActive ? PulseColors.textSecondary : PulseColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if !learning.isActive {
                Text("Muted · not used by assistant")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pulseCardSurface()
        .contextMenu {
            Button {
                onToggle()
            } label: {
                Label(learning.isActive ? "Mute" : "Unmute",
                      systemImage: learning.isActive ? "speaker.slash" : "speaker.wave.2")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(learning.title). \(learning.detail)")
        .accessibilityValue(learning.isActive ? "Active" : "Muted")
        .accessibilityHint("Long press for options")
    }

    private var importancePips: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < learning.importance ? PulseColors.accent : PulseColors.fillMuted)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}
