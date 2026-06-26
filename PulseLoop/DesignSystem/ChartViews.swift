import SwiftUI

struct HRLineChart: View {
    let samples: [MetricSample]
    var height: CGFloat = 80

    var body: some View {
        MiniSparkline(values: samples.map(\.value), color: PulseColors.heartRate)
            .frame(height: height)
    }
}

struct SpO2DotsChart: View {
    let samples: [MetricSample]
    var height: CGFloat = 80

    var body: some View {
        MiniSparkline(values: samples.map(\.value), color: PulseColors.spo2)
            .frame(height: height)
    }
}

struct ElevationAreaChart: View {
    let altitudes: [Double]
    var height: CGFloat = 80

    var body: some View {
        MiniSparkline(values: altitudes, color: PulseColors.distance)
            .frame(height: height)
    }
}

struct DistanceLineChart: View {
    let values: [Double]
    var labels: [String]? = nil
    var body: some View {
        MiniSparkline(values: values, color: PulseColors.distance)
            .frame(height: 60)
    }
}

struct CaloriesAreaChart: View {
    let values: [Double]
    var labels: [String]? = nil
    var body: some View {
        MiniSparkline(values: values, color: PulseColors.calories)
            .frame(height: 60)
    }
}

struct StepBarsChart: View {
    let values: [Double]
    var labels: [String]? = nil
    var goal: Double? = nil
    var todayIndex: Int? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            let maxVal = max(values.max() ?? 1, goal ?? 1)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == todayIndex ? PulseColors.steps : PulseColors.steps.opacity(0.6))
                        .frame(height: max(CGFloat(value / maxVal) * 60, 4))
                    if let labels, index < labels.count {
                        Text(labels[index])
                            .font(PulseFont.body(8))
                            .foregroundStyle(PulseColors.textFaint)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80)
        .overlay(alignment: .top) {
            if let goal {
                let maxVal = max(values.max() ?? 1, goal)
                Rectangle()
                    .fill(PulseColors.textMuted.opacity(0.5))
                    .frame(height: 1)
                    .offset(y: 80 - CGFloat(goal / maxVal) * 60 - 10)
            }
        }
    }
}
