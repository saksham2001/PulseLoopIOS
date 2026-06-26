import SwiftUI
import SwiftData

// MARK: - Product Search View (AI-first unified search surface — Tracker C1)
//
// A Perplexity-style search surface for the Protocol section. Type any food, drug,
// supplement, vitamin, or peptide; the unified `ProductSearchService` engine runs
// the tiered search (local catalogs + persisted custom entries → Open Food Facts /
// openFDA → AI research pass with citations) and persists discoveries. Results
// render as rich, scannable cards with a source badge, benefit/mechanism/dose/timing,
// warnings, citations, an AI-generated disclaimer, and a one-tap "Add to protocol".

struct ProductSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Adopt a chosen result into the protocol. The host owns insertion so the
    /// search view stays presentation-only.
    let onAdd: (ProductSearchResult) -> Void

    @State private var query = ""
    @State private var results: [ProductSearchResult] = []
    @State private var persistedNames: [String] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider().overlay(PulseColors.borderHairline)
                content
            }
            .background(PulseColors.canvas.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(PulseFont.bodyMedium(15))
                }
            }
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(PulseColors.textMuted)
            TextField("Search any food, drug, supplement, peptide…", text: $query)
                .font(PulseFont.body(16))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { runSearch() }
                .accessibilityLabel("Product search field")
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    didSearch = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(PulseColors.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        if isSearching {
            loadingState
        } else if didSearch && results.isEmpty {
            emptyState
        } else if results.isEmpty {
            promptState
        } else {
            resultsList
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Searching every source…")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)
            Text("Local catalog · Open Food Facts · FDA · AI research")
                .font(PulseFont.caption)
                .foregroundStyle(PulseColors.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var promptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(PulseColors.textFaint)
            Text("Find anything")
                .font(PulseFont.bodySemibold(17))
                .foregroundStyle(PulseColors.textPrimary)
            Text("If it isn't already in your catalog, AI researches it and saves it for next time.")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(PulseColors.textFaint)
            Text("No results for \"\(query)\"")
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Try a different spelling or a brand name.")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !persistedNames.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 11))
                        Text("Saved to your catalog: \(persistedNames.joined(separator: ", "))")
                            .font(PulseFont.caption)
                    }
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    ProductResultCard(result: result) {
                        onAdd(result)
                        dismiss()
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Search

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        isSearching = true
        didSearch = true
        searchTask = Task {
            let outcome = await ProductSearchService.searchAndPersist(query: q, in: modelContext)
            if Task.isCancelled { return }
            results = outcome.results
            persistedNames = outcome.persistedNames
            isSearching = false
        }
    }
}

// MARK: - Result Card

struct ProductResultCard: View {
    let result: ProductSearchResult
    let onAdd: () -> Void

    private var info: SupplementInfo { result.info }

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                if !info.benefit.isEmpty {
                    Text(info.benefit)
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                metaRow
                if !info.mechanism.isEmpty {
                    labeledLine("How it works", info.mechanism)
                }
                if !info.interactionNotes.isEmpty {
                    warning(info.interactionNotes)
                }
                if result.isAIGenerated {
                    disclaimer
                }
                if !result.citations.isEmpty {
                    citations
                }
                addButton
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: info.emoji)
                .font(.system(size: 18))
                .foregroundStyle(PulseColors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(PulseFont.bodySemibold(16))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(info.category.capitalized)
                    .font(PulseFont.caption)
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            sourceBadge
        }
    }

    private var sourceBadge: some View {
        Text(result.source.rawValue)
            .font(PulseFont.bodyMedium(10))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch result.source {
        case .localKnowledgeBase: return PulseColors.success
        case .openFDA: return PulseColors.spo2
        case .openFoodFacts: return .orange
        case .custom: return PulseColors.textMuted
        case .aiResearch: return PulseColors.accent
        }
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            if !info.defaultDose.isEmpty {
                metaItem(icon: "scalemass", text: info.defaultDose)
            }
            if !info.timing.isEmpty {
                metaItem(icon: "clock", text: info.timing)
            }
        }
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textMuted)
            Text(text)
                .font(PulseFont.bodyMedium(13))
                .foregroundStyle(PulseColors.textPrimary)
        }
    }

    private func labeledLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(PulseFont.micro)
                .foregroundStyle(PulseColors.textFaint)
                .tracking(0.5)
            Text(value)
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(text)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var disclaimer: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
            Text("AI-generated — verify with a professional before use.")
                .font(PulseFont.caption)
        }
        .foregroundStyle(PulseColors.textMuted)
    }

    private var citations: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SOURCES")
                .font(PulseFont.micro)
                .foregroundStyle(PulseColors.textFaint)
                .tracking(0.5)
            ForEach(Array(result.citations.prefix(4).enumerated()), id: \.offset) { _, c in
                Text("• \(c)")
                    .font(PulseFont.caption)
                    .foregroundStyle(PulseColors.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add to protocol")
                    .font(PulseFont.bodySemibold(14))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(PulseColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(info.name) to protocol")
    }
}
