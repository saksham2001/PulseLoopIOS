import SwiftUI
import SwiftData

struct SleepBar: Identifiable {
    let id = UUID()
    let label: String
    let durationMin: Int?
    let score: Int?
    let present: Bool

    init(label: String, durationMin: Int? = nil, score: Int? = nil, present: Bool = true) {
        self.label = label
        self.durationMin = durationMin
        self.score = score
        self.present = present
    }
}

enum SleepStageColors {
    static let awake = Color.orange.opacity(0.7)
    static let light = PulseColors.sleep.opacity(0.4)
    static let deep = PulseColors.sleep.opacity(0.8)
    static let rem = Color.purple.opacity(0.6)
}

struct SleepDurationHistogramChart: View {
    let bars: [SleepBar]
    var goalMin: Int? = nil
    var slim: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: slim ? 2 : 4) {
            ForEach(bars) { bar in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bar.present ? PulseColors.sleep : PulseColors.fillSubtle)
                        .frame(height: max(CGFloat(Double(bar.durationMin ?? 0) / 600.0) * 60, 4))
                    if !slim {
                        Text(bar.label)
                            .font(PulseFont.body(8))
                            .foregroundStyle(PulseColors.textFaint)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80)
        .overlay(alignment: .leading) {
            if let goal = goalMin, goal > 0 {
                Rectangle()
                    .fill(PulseColors.accent.opacity(0.3))
                    .frame(height: 1)
                    .offset(y: -CGFloat(Double(goal) / 600) * 60 + 40)
            }
        }
    }
}

struct SleepHypnogramView: View {
    let blocks: [SleepStageBlock]
    let totalMin: Int
    let startTs: Date?
    var height: CGFloat = 100

    private struct StageBar: Identifiable {
        let id = UUID()
        let stage: SleepStage
        let startMin: Int
        let duration: Int
    }

    var body: some View {
        let items = blocks.map { StageBar(stage: $0.stage, startMin: $0.startMinute, duration: $0.durationMinutes) }
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(items) { item in
                    let xStart = CGFloat(item.startMin) / CGFloat(max(totalMin, 1)) * w
                    let bWidth = CGFloat(item.duration) / CGFloat(max(totalMin, 1)) * w
                    let yPos = yForStage(item.stage)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForStage(item.stage))
                        .frame(width: max(bWidth, 2), height: 12)
                        .offset(x: xStart, y: yPos)
                }
            }
        }
        .frame(height: height)
    }

    private func yForStage(_ stage: SleepStage) -> CGFloat {
        switch stage {
        case .awake: return 0
        case .light: return height * 0.33
        case .deep: return height * 0.66
        case .unknown: return height * 0.15
        }
    }

    private func colorForStage(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return SleepStageColors.awake
        case .light: return SleepStageColors.light
        case .deep: return SleepStageColors.deep
        case .unknown: return PulseColors.textFaint
        }
    }
}
