import SwiftUI
import SwiftData

// MARK: - Fitness Dashboard

/// Fitness home: an activity calendar heatmap, strain vs target, cardio metrics,
/// strength total-volume radar by muscle group, strength progression, and the
/// workout templates list. Matches the multi-card "Fitness" overview.
struct FitnessDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutLog.date, order: .reverse) private var workouts: [WorkoutLog]

    @State private var showBuilder = false
    @State private var editingTemplate: WorkoutTemplate?
    @State private var activeSession: WorkoutTemplate?

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ActivityCalendarCard(workouts: workouts, templates: templates)
                WorkoutCoachCard(recentWorkouts: workouts, templateNames: templates.map(\.name))
                strainCard

                sectionTitle("Cardio")
                cardioRow

                sectionTitle("Strength")
                TotalVolumeRadarCard(templates: templates)
                StrengthProgressionCard(templates: templates)

                sectionTitle("Workout Templates")
                templatesSection

                if !workouts.isEmpty {
                    sectionTitle("Recent Sessions")
                    WorkoutHistoryCard(workouts: workouts)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(PulseColors.canvas)
        .sheet(isPresented: $showBuilder) {
            WorkoutBuilderView()
        }
        .sheet(item: $editingTemplate) { tmpl in
            WorkoutBuilderView(template: tmpl)
        }
        .sheet(item: $activeSession) { tmpl in
            WorkoutSessionView(template: tmpl)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fitness")
                    .font(PulseFont.title(28))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Last 30 days")
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Button {
                HapticService.impact(.light)
                showBuilder = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(PulseColors.background)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(PulseColors.borderStrong, lineWidth: 1) }
            }
            .accessibilityLabel("New workout")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(PulseFont.titleMedium(20))
            .foregroundStyle(PulseColors.textPrimary)
    }

    // MARK: Strain

    private var strainCard: some View {
        let pct = strainPercent
        return PulseCard(radius: PulseRadius.large) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Strain Performance", systemImage: "target")
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(PulseColors.textSecondary)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pct > 0 ? "+" : "")\(pct)%")
                            .font(PulseFont.titleMedium(30))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text(pct < 0 ? "Below target" : "On target")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.spo2)
                    }
                    Spacer()
                    MiniSparkline(values: strainTrend, color: PulseColors.spo2)
                        .frame(width: 150, height: 50)
                }
            }
        }
    }

    private var strainPercent: Int {
        let recent = workouts.prefix(7).reduce(0) { $0 + $1.intensity }
        let target = 7 * 6
        guard target > 0 else { return 0 }
        return Int((Double(recent - target) / Double(target)) * 100)
    }

    private var strainTrend: [Double] {
        let days = (0..<14).map { offset -> Double in
            let day = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let load = workouts.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.intensity }
            return Double(load)
        }
        return days.reversed()
    }

    // MARK: Cardio

    private var cardioRow: some View {
        let cardioWorkouts = workouts.filter { [.cardio, .running, .cycling, .swimming, .hiit].contains($0.type) }
        let recent = cardioWorkouts.filter { $0.date > thirtyDaysAgo }
        let totalMin = recent.reduce(0) { $0 + $1.durationMinutes }
        return HStack(spacing: 12) {
            FitnessStatCard(
                icon: "figure.run",
                title: "Cardio Load",
                value: totalMin > 0 ? "\(totalMin) min" : "No data",
                subtitle: totalMin > 0 ? "Last 30 days" : "No range"
            )
            FitnessStatCard(
                icon: "heart",
                title: "HRR",
                value: bestHRR != nil ? "\(bestHRR!) bpm" : "No data",
                subtitle: bestHRR != nil ? "Recovery" : "No range"
            )
        }
    }

    private var bestHRR: Int? {
        let withHR = workouts.compactMap { w -> Int? in
            guard let max = w.heartRateMax, let avg = w.heartRateAvg else { return nil }
            return max - avg
        }
        return withHR.max()
    }

    private var thirtyDaysAgo: Date {
        calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    // MARK: Templates

    private var templatesSection: some View {
        Group {
            if templates.isEmpty {
                VStack(spacing: 12) {
                    InlineEmptyState(
                        title: "No workouts",
                        message: "Start a Strength Builder to create your first template."
                    )
                    Button {
                        HapticService.impact(.light)
                        showBuilder = true
                    } label: {
                        Text("New Workout")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 46)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .pulseCardSurface()
            } else {
                VStack(spacing: 10) {
                    ForEach(templates) { tmpl in
                        WorkoutTemplateRow(
                            template: tmpl,
                            onTap: { editingTemplate = tmpl },
                            onStart: { activeSession = tmpl }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Fitness Stat Card

struct FitnessStatCard: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String?

    private var isNoData: Bool { value == "No data" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(PulseFont.bodySemibold(13))
                .foregroundStyle(PulseColors.textSecondary)
            Text(value)
                .font(PulseFont.titleMedium(22))
                .foregroundStyle(isNoData ? PulseColors.textMuted : PulseColors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pulseCardSurface()
    }
}

// MARK: - Workout Template Row

struct WorkoutTemplateRow: View {
    let template: WorkoutTemplate
    let onTap: () -> Void
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                HapticService.impact(.light)
                onTap()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(PulseFont.bodySemibold(16))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text(subtitle)
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(template.name), \(template.exercises.count) exercises. Edit")

            Button {
                HapticService.impact(.light)
                onStart()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start \(template.name)")
        }
        .padding(14)
        .pulseCardSurface()
    }

    private var subtitle: String {
        var parts = ["\(template.exercises.count) exercises · \(template.totalSets) sets"]
        if let last = template.lastPerformed {
            parts.append("Last \(last.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
