import SwiftUI
import SwiftData

// MARK: - AI Quality dashboard (Life OS T6)
//
// An on-design, read-only readout of how the assistant is doing, built purely from
// on-device signal (T0 telemetry + feedback) plus the deterministic eval harness.
// No network. It answers: are users satisfied, which models perform best, what are
// the top complaints, and do the shape/routing contracts still hold.

struct CoachQualityView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var report = CoachQualityReport()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                evalCard
                if report.hasSignal {
                    headlineCard
                    if !report.models.isEmpty { modelsCard }
                    if !report.downReasons.isEmpty { reasonsCard }
                } else {
                    PulseCard {
                        InlineEmptyState(
                            title: "No usage signal yet",
                            message: "Chat with the assistant and rate replies. Quality stats appear here as data accrues."
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle("AI Quality")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: rebuild)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assistant quality")
                .font(PulseFont.title(22)).foregroundStyle(PulseColors.textPrimary)
            Text("Computed on-device from your recent turns, ratings, and a built-in contract check. Nothing leaves your phone.")
                .font(PulseFont.body(14)).foregroundStyle(PulseColors.textMuted)
        }
    }

    private var evalCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: report.evalPassRate >= 1 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(report.evalPassRate >= 1 ? PulseColors.success : PulseColors.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contract checks")
                            .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                        Text("\(report.evalPassCount) of \(report.evalResults.count) passing")
                            .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                    }
                    Spacer()
                    Text(percent(report.evalPassRate))
                        .font(PulseFont.title(20))
                        .foregroundStyle(report.evalPassRate >= 1 ? PulseColors.success : PulseColors.warning)
                }
                ForEach(report.evalResults.filter { !$0.passed }) { result in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(PulseColors.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textPrimary)
                            Text(result.failures.joined(separator: "; "))
                                .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headlineCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last \(report.totalTurns) turns")
                    .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                HStack(spacing: 12) {
                    stat("Satisfaction", report.satisfaction.map(percent) ?? "—",
                         tone: (report.satisfaction ?? 1) >= 0.6 ? .success : .warning)
                    stat("Recovered", percent(report.recoveryRate), tone: .neutral)
                    stat("Errors", percent(report.errorRate),
                         tone: report.errorRate <= 0.05 ? .success : .warning)
                }
                HStack(spacing: 16) {
                    Label("\(report.totalUp)", systemImage: "hand.thumbsup.fill")
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.success)
                    Label("\(report.totalDown)", systemImage: "hand.thumbsdown.fill")
                        .font(PulseFont.body(13)).foregroundStyle(PulseColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelsCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("By model")
                    .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                ForEach(report.models) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.displayName)
                                .font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                            Spacer()
                            Text("\(row.turns) turn\(row.turns == 1 ? "" : "s")")
                                .font(PulseFont.body(12)).foregroundStyle(PulseColors.textFaint)
                        }
                        HStack(spacing: 14) {
                            if let sat = row.satisfaction {
                                Label(percent(sat), systemImage: "hand.thumbsup")
                                    .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                            } else {
                                Text("no votes")
                                    .font(PulseFont.body(12)).foregroundStyle(PulseColors.textFaint)
                            }
                            if row.errorRate > 0 {
                                Text("err \(percent(row.errorRate))")
                                    .font(PulseFont.body(12)).foregroundStyle(PulseColors.warning)
                            }
                            if row.recoveryRate > 0 {
                                Text("recov \(percent(row.recoveryRate))")
                                    .font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
                            }
                        }
                    }
                    if row.id != report.models.last?.id {
                        Divider().background(PulseColors.borderHairline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reasonsCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top complaints")
                    .font(PulseFont.bodySemibold(15)).foregroundStyle(PulseColors.textPrimary)
                ForEach(report.downReasons, id: \.code) { reason in
                    HStack {
                        Text(reason.label)
                            .font(PulseFont.body(13)).foregroundStyle(PulseColors.textPrimary)
                        Spacer()
                        Text("\(reason.count)")
                            .font(PulseFont.bodySemibold(13)).foregroundStyle(PulseColors.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Bits

    private enum Tone { case success, warning, neutral }

    private func stat(_ label: String, _ value: String, tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(PulseFont.title(20))
                .foregroundStyle(color(for: tone))
            Text(label)
                .font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for tone: Tone) -> Color {
        switch tone {
        case .success: return PulseColors.success
        case .warning: return PulseColors.warning
        case .neutral: return PulseColors.textPrimary
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func rebuild() {
        report = CoachQualityReportBuilder.build(in: modelContext)
    }
}
