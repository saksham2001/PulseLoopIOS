import SwiftUI
import SwiftData

private let weekLabels = ["M", "T", "W", "T", "F", "S", "S"]

/// Tap-through trends for the daily activity summary widget. Modeled on `MetricDetailView` (the Vitals
/// heart-rate detail screen): a shared Week/Month segmented selector on top, then one section per
/// activity metric — a large chart card plus a 2-column stat-tile grid. Uses the same data the old
/// inline Activity charts did: the summary's aligned 7-day trends for Week, and `metricRange` for
/// Month; no new data plumbing.
struct ActivityTrendsView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var period: MetricRange = .sevenDays

    private var units: UnitsPreference { profiles.first?.units ?? .metric }
    private var distanceUnit: String { UnitsFormatter.distance(meters: 0, units: units).unit }

    var body: some View {
        let summary = MetricsService.buildTodaySummary(context: modelContext)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                periodSelector

                // Steps — bar chart. Week uses the aligned 7-day trend (M–S), Month the 30-day series.
                section(
                    title: "Steps",
                    color: PulseColors.steps,
                    values: stepsValues(summary),
                    format: { "\(Int($0.rounded()).formatted())" },
                    unit: nil
                ) { values in
                    StepBarsChart(values: values, labels: period == .sevenDays ? weekLabels : [], height: 300)
                }

                // Distance — values are in the user's display unit (km/mi) for both chart and tiles.
                section(
                    title: "Distance",
                    color: PulseColors.distance,
                    values: distanceValues(summary),
                    format: { String(format: "%.2f", $0) },
                    unit: distanceUnit
                ) { values in
                    DistanceLineChart(values: values, height: 300)
                }

                section(
                    title: "Calories",
                    color: PulseColors.calories,
                    values: caloriesValues(summary),
                    format: { "\(Int($0.rounded()).formatted())" },
                    unit: "cal"
                ) { values in
                    CaloriesAreaChart(values: values, height: 300)
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(PulseColors.background)
        .navigationTitle("Activity Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Period selector

    private var periodSelector: some View {
        Picker("Period", selection: $period) {
            Text("Week").tag(MetricRange.sevenDays)
            Text("Month").tag(MetricRange.thirtyDays)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Section (chart card + stat tiles)

    @ViewBuilder
    private func section<Chart: View>(
        title: String,
        color: Color,
        values: [Double],
        format: @escaping (Double) -> String,
        unit: String?,
        @ViewBuilder chart: @escaping ([Double]) -> Chart
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(1.0)
                .foregroundStyle(PulseColors.textMuted)

            VStack(alignment: .leading, spacing: 8) {
                if values.isEmpty {
                    Text("Not enough data for this period.")
                        .font(.system(size: 13)).foregroundStyle(PulseColors.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                } else {
                    chart(values)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PulseColors.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))

            statTiles(values: values, color: color, format: format, unit: unit)
        }
    }

    private func statTiles(values: [Double], color: Color, format: @escaping (Double) -> String, unit: String?) -> some View {
        let latest = values.last.map(format) ?? "--"
        let avg = values.isEmpty ? "--" : format(values.reduce(0, +) / Double(values.count))
        let lo = values.min().map(format) ?? "--"
        let hi = values.max().map(format) ?? "--"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "Latest", value: latest, unit: unit, color: color)
            MetricTile(title: "Average", value: avg, unit: unit, color: color)
            MetricTile(title: "Min", value: lo, unit: unit, color: color)
            MetricTile(title: "Max", value: hi, unit: unit, color: color)
        }
    }

    // MARK: - Data (mirrors the former inline-chart helpers on ActivityView)

    private func stepsValues(_ summary: TodaySummary) -> [Double] {
        period == .sevenDays ? summary.trends.steps7d.map(\.value) : MetricsService.metricRange(metric: .steps, range: period, context: modelContext).map(\.value)
    }

    private func distanceValues(_ summary: TodaySummary) -> [Double] {
        let meters = period == .sevenDays ? summary.trends.distance7d.map(\.value) : MetricsService.metricRange(metric: .distance, range: period, context: modelContext).map(\.value)
        return meters.map { Double(UnitsFormatter.distance(meters: $0, units: units).value) ?? 0 }
    }

    private func caloriesValues(_ summary: TodaySummary) -> [Double] {
        period == .sevenDays ? summary.trends.calories7d.map(\.value) : MetricsService.metricRange(metric: .calories, range: period, context: modelContext).map(\.value)
    }
}
