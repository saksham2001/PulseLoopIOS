import SwiftUI
import WidgetKit

// MARK: - Widget Entry

struct PulseWidgetEntry: TimelineEntry {
    let date: Date
    let nextDose: String?
    let rightNow: String?
    let readinessScore: Int
    let upNext: [(String, String)]
    let hydrationCups: Int
    let streakDays: Int

    static var sample: PulseWidgetEntry {
        PulseWidgetEntry(
            date: .now,
            nextDose: "Magnesium L-Threonate",
            rightNow: "Morning walk",
            readinessScore: 82,
            upNext: [("8:30 AM", "Cold plunge"), ("9:00 AM", "Deep work block"), ("12:00 PM", "Lunch + supps")],
            hydrationCups: 4,
            streakDays: 12
        )
    }
}

// MARK: - Small Widget: Next Dose

struct NextDoseWidgetView: View {
    let entry: PulseWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "pills.fill")
                .font(.system(size: 20))
                .foregroundStyle(PulseColors.accent)

            Spacer()

            if let dose = entry.nextDose {
                Text(dose)
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                    .lineLimit(2)
            } else {
                Text("All done")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
            }

            Text(entry.nextDose != nil ? "Due now" : "No doses left")
                .font(PulseFont.body(11))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(PulseColors.background)
    }
}

// MARK: - Small Widget: Right Now

struct RightNowWidgetView: View {
    let entry: PulseWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(PulseColors.accent)
                    .frame(width: 6, height: 6)
                Text("RIGHT NOW")
                    .font(PulseFont.bodyMedium(10))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Spacer()

            Text(entry.rightNow ?? "Rest")
                .font(PulseFont.titleMedium(20))
                .foregroundStyle(PulseColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(PulseColors.background)
    }
}

// MARK: - Medium Widget: Up Next

struct UpNextWidgetView: View {
    let entry: PulseWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PulseColors.accent)
                Text("Up Next")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Text("\(entry.streakDays)d streak")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textMuted)
            }

            ForEach(Array(entry.upNext.prefix(3).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Text(item.0)
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 60, alignment: .leading)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PulseColors.borderHairline)
                        .frame(width: 1, height: 14)
                    Text(item.1)
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textPrimary)
                        .lineLimit(1)
                }
            }

            if entry.upNext.isEmpty {
                Text("Nothing scheduled")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(PulseColors.background)
    }
}

// MARK: - Large Widget: Full Day

struct FullDayWidgetView: View {
    let entry: PulseWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(PulseFont.title(18))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(entry.date.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                readinessBadge
            }

            Divider().foregroundStyle(PulseColors.borderHairline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.upNext.prefix(4).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Text(item.0)
                            .font(PulseFont.bodyMedium(12))
                            .foregroundStyle(PulseColors.textSecondary)
                            .frame(width: 64, alignment: .leading)
                        Text(item.1)
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textPrimary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            HStack(spacing: 16) {
                statPill(icon: "drop.fill", value: "\(entry.hydrationCups)", label: "cups")
                statPill(icon: "flame.fill", value: "\(entry.streakDays)", label: "day streak")
                if let dose = entry.nextDose {
                    statPill(icon: "pills.fill", value: dose, label: "next")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(PulseColors.background)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: entry.date)
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var readinessBadge: some View {
        VStack(spacing: 2) {
            Text("\(entry.readinessScore)")
                .font(PulseFont.bodySemibold(18))
                .foregroundStyle(PulseColors.readiness)
            Text("ready")
                .font(PulseFont.body(9))
                .foregroundStyle(PulseColors.textMuted)
        }
        .frame(width: 44, height: 44)
        .background(PulseColors.fillSubtle)
        .clipShape(Circle())
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(PulseColors.accent)
            Text(value)
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(PulseFont.body(10))
                .foregroundStyle(PulseColors.textMuted)
        }
    }
}

// MARK: - Lock Screen: Circular Readiness

struct ReadinessLockScreenView: View {
    let entry: PulseWidgetEntry

    var body: some View {
        ZStack {
            Circle()
                .stroke(PulseColors.fillSubtle, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(entry.readinessScore) / 100)
                .stroke(PulseColors.readiness, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(entry.readinessScore)")
                    .font(PulseFont.bodySemibold(16))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("%")
                    .font(PulseFont.body(9))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
        .padding(4)
    }
}

// MARK: - Previews

#Preview("Next Dose - Small") {
    NextDoseWidgetView(entry: .sample)
        .frame(width: 160, height: 160)
}

#Preview("Right Now - Small") {
    RightNowWidgetView(entry: .sample)
        .frame(width: 160, height: 160)
}

#Preview("Up Next - Medium") {
    UpNextWidgetView(entry: .sample)
        .frame(width: 340, height: 160)
}

#Preview("Full Day - Large") {
    FullDayWidgetView(entry: .sample)
        .frame(width: 340, height: 360)
}

#Preview("Readiness - Lock Screen") {
    ReadinessLockScreenView(entry: .sample)
        .frame(width: 76, height: 76)
}
