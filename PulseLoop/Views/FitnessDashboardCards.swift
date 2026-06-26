import SwiftUI

// MARK: - Activity Calendar Card (heatmap)

/// Two-month dotted activity heatmap (like the Fitness screen). Each day is a
/// pill whose intensity reflects how many activities occurred that day.
struct ActivityCalendarCard: View {
    let workouts: [WorkoutLog]
    let templates: [WorkoutTemplate]

    private var calendar: Calendar { .current }

    /// Count of activities per day, keyed by start-of-day.
    private var activityByDay: [Date: Int] {
        var map: [Date: Int] = [:]
        for w in workouts {
            let day = calendar.startOfDay(for: w.date)
            map[day, default: 0] += 1
        }
        for t in templates {
            if let last = t.lastPerformed {
                let day = calendar.startOfDay(for: last)
                map[day, default: 0] += 1
            }
        }
        return map
    }

    private func monthGrid(monthsAgo: Int) -> (label: String, weeks: [[Date?]]) {
        let today = Date()
        let base = calendar.date(byAdding: .month, value: -monthsAgo, to: today) ?? today
        let comps = calendar.dateComponents([.year, .month], from: base)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return ("", [])
        }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM yyyy"
        let label = fmt.string(from: firstOfMonth)

        // weekday of the 1st (1 = Sunday)
        let leadingBlanks = calendar.component(.weekday, from: firstOfMonth) - 1
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(d)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0+7, cells.count)]) }
        return (label, weeks)
    }

    var body: some View {
        PulseCard(radius: PulseRadius.large) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    monthColumn(monthsAgo: 1)
                    monthColumn(monthsAgo: 0)
                }
                legend
            }
        }
    }

    private func monthColumn(monthsAgo: Int) -> some View {
        let grid = monthGrid(monthsAgo: monthsAgo)
        return VStack(alignment: .leading, spacing: 8) {
            Text(grid.label)
                .font(PulseFont.bodySemibold(14))
                .foregroundStyle(PulseColors.textPrimary)
            HStack(spacing: 4) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d)
                        .font(PulseFont.bodyMedium(9))
                        .foregroundStyle(PulseColors.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 4) {
                ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dayCell(_ day: Date?) -> some View {
        Group {
            if let day {
                let count = activityByDay[calendar.startOfDay(for: day)] ?? 0
                let isFuture = day > Date()
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(for: count, future: isFuture))
                    .frame(height: 9)
                    .overlay {
                        if calendar.isDateInToday(day) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(PulseColors.accent, lineWidth: 1.2)
                        }
                    }
            } else {
                Color.clear.frame(height: 9)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for count: Int, future: Bool) -> Color {
        if future { return PulseColors.fillSubtle.opacity(0.5) }
        switch count {
        case 0: return PulseColors.fillMuted
        case 1: return PulseColors.success.opacity(0.45)
        case 2: return PulseColors.success.opacity(0.7)
        default: return PulseColors.spo2
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(PulseColors.success.opacity(0.45), "1 activity")
            legendItem(PulseColors.success.opacity(0.7), "2 activities")
            legendItem(PulseColors.spo2, "3+ activities")
        }
        .font(PulseFont.bodyMedium(11))
        .foregroundStyle(PulseColors.textMuted)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - Total Volume Radar

/// Hexagonal radar of total lifted volume by muscle-group bucket, summed across
/// all template sets (reps × weight).
struct TotalVolumeRadarCard: View {
    let templates: [WorkoutTemplate]
    @AppStorage(WeightUnit.storageKey) private var weightUnitRaw: String = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private let buckets = ["Chest", "Back", "Shoulders", "Arms", "Core", "Legs"]

    private var volumeByBucket: [String: Double] {
        var map: [String: Double] = [:]
        for t in templates {
            for ex in t.exercises {
                let bucket = ex.muscleGroup.volumeBucket
                let vol = ex.sets.reduce(0.0) { $0 + $1.volume }
                map[bucket, default: 0] += vol
            }
        }
        return map
    }

    private var maxVolume: Double {
        max(volumeByBucket.values.max() ?? 1, 1)
    }

    var body: some View {
        PulseCard(radius: PulseRadius.large) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Total Volume", systemImage: "scalemass")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textSecondary)

                ZStack {
                    RadarChart(
                        axes: buckets,
                        values: buckets.map { (volumeByBucket[$0] ?? 0) / maxVolume }
                    )
                    .frame(height: 220)

                    ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                        radarLabel(bucket, value: volumeByBucket[bucket] ?? 0, index: index, count: buckets.count)
                    }
                }
                .frame(height: 240)
            }
        }
    }

    private func radarLabel(_ bucket: String, value: Double, index: Int, count: Int) -> some View {
        let fraction = CGFloat(index) / CGFloat(count)
        let full: CGFloat = 2 * .pi
        let angle: CGFloat = fraction * full - (.pi / 2)
        let radius: CGFloat = 130
        let dx: CGFloat = cos(angle) * radius
        let dy: CGFloat = sin(angle) * radius
        return VStack(spacing: 1) {
            Text(volumeText(value))
                .font(PulseFont.bodySemibold(13))
                .foregroundStyle(value > 0 ? PulseColors.textPrimary : PulseColors.textMuted)
            Text(bucket)
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
        }
        .offset(x: dx, y: dy)
    }

    private func volumeText(_ v: Double) -> String {
        if v <= 0 { return "0 \(unit.label)" }
        let converted = unit.fromKilograms(v)
        if converted >= 1000 { return String(format: "%.1fk %@", converted / 1000, unit.label) }
        return "\(Int(converted)) \(unit.label)"
    }
}

/// Generic filled radar/spider polygon.
struct RadarChart: View {
    let axes: [String]
    let values: [Double]

    private func angle(_ i: Int) -> CGFloat {
        let fraction = CGFloat(i) / CGFloat(axes.count)
        let full: CGFloat = 2 * .pi
        return fraction * full - (.pi / 2)
    }

    private func point(center: CGPoint, radius: CGFloat, i: Int, scale: CGFloat) -> CGPoint {
        let a = angle(i)
        let x = center.x + cos(a) * radius * scale
        let y = center.y + sin(a) * radius * scale
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius: CGFloat = min(proxy.size.width, proxy.size.height) / 2 * 0.78
            ZStack {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { scale in
                    polygon(center: center, radius: radius * CGFloat(scale))
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
                ForEach(0..<axes.count, id: \.self) { i in
                    spoke(center: center, radius: radius, i: i)
                }
                dataPath(center: center, radius: radius)
                    .fill(PulseColors.success.opacity(0.18))
                dataPath(center: center, radius: radius)
                    .stroke(PulseColors.success.opacity(0.7), lineWidth: 1.5)
            }
        }
    }

    private func spoke(center: CGPoint, radius: CGFloat, i: Int) -> some View {
        Path { p in
            p.move(to: center)
            p.addLine(to: point(center: center, radius: radius, i: i, scale: 1))
        }
        .stroke(PulseColors.borderHairline, lineWidth: 1)
    }

    private func polygon(center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for i in 0..<axes.count {
                let pt = point(center: center, radius: radius, i: i, scale: 1)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    private func dataPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for i in 0..<axes.count {
                let raw: CGFloat = i < values.count ? CGFloat(values[i]) : 0
                let v = max(0.04, min(raw, 1))
                let pt = point(center: center, radius: radius, i: i, scale: v)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }
}

// MARK: - Strength Progression

struct StrengthProgressionCard: View {
    let templates: [WorkoutTemplate]
    @AppStorage(WeightUnit.storageKey) private var weightUnitRaw: String = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private var hasData: Bool {
        templates.contains { !$0.exercises.isEmpty }
    }

    /// Top exercises by total volume.
    private var topExercises: [(name: String, volume: Double)] {
        var map: [String: Double] = [:]
        for t in templates {
            for ex in t.exercises {
                map[ex.name, default: 0] += ex.sets.reduce(0.0) { $0 + $1.volume }
            }
        }
        return map.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(4).map { ($0.key, $0.value) }
    }

    var body: some View {
        PulseCard(radius: PulseRadius.large) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Strength Progression", systemImage: "chart.line.uptrend.xyaxis")
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(PulseColors.textSecondary)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                }
                if topExercises.isEmpty {
                    InlineEmptyState(
                        title: "No progression data",
                        message: "Build a workout with weighted sets to track strength over time."
                    )
                } else {
                    let maxVol = topExercises.map(\.volume).max() ?? 1
                    ForEach(Array(topExercises.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(PulseFont.bodyMedium(13))
                                    .foregroundStyle(PulseColors.textPrimary)
                                Spacer()
                                Text("\(Int(unit.fromKilograms(item.volume))) \(unit.label)")
                                    .font(PulseFont.bodySemibold(13))
                                    .monospacedDigit()
                                    .foregroundStyle(PulseColors.textSecondary)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(PulseColors.fillSubtle)
                                    Capsule()
                                        .fill(PulseColors.success)
                                        .frame(width: proxy.size.width * CGFloat(item.volume / maxVol))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
    }
}
