import SwiftUI
import SwiftData

// MARK: - Journal View

/// Daily journal with a week strip and tri-state habit/metric toggles grouped
/// by time-of-day section (Pinned / Daytime / Nighttime / Automatic), plus a
/// "copy entries from yesterday" shortcut. Matches the "Journal" screen.
struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalDay.date, order: .reverse) private var days: [JournalDay]

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { .current }

    private var monthLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM yyyy"
        return fmt.string(from: selectedDate)
    }

    private var selectedDay: JournalDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var weekDates: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                weekStrip
                todayBanner

                ForEach(JournalMetric.Section.allCases, id: \.self) { section in
                    let metrics = JournalCatalog.metrics(in: section)
                    if !metrics.isEmpty {
                        sectionView(section, metrics: metrics)
                    }
                }

                copyYesterdayButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(PulseColors.canvas)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Journal")
                    .font(PulseFont.title(28))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(monthLabel)
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            HStack(spacing: 8) {
                Label("Insights", systemImage: "sparkles")
                    .font(PulseFont.bodySemibold(13))
                    .foregroundStyle(PulseColors.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(PulseColors.background)
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(PulseColors.borderStrong, lineWidth: 1) }
            }
        }
    }

    private var weekStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { d in
                    Text(d)
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    dayPill(date)
                }
            }
        }
    }

    private func dayPill(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dayNum = calendar.component(.day, from: date)
        let hasEntries = days.first { calendar.isDate($0.date, inSameDayAs: date) }?.entries.contains { $0.state != 0 } ?? false
        let isFuture = date > calendar.startOfDay(for: Date())

        return Button {
            HapticService.selection()
            withAnimation(.snappy(duration: 0.2)) { selectedDate = calendar.startOfDay(for: date) }
        } label: {
            VStack(spacing: 6) {
                Text("\(dayNum)")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(isToday ? PulseColors.accent : (isFuture ? PulseColors.textMuted : PulseColors.textPrimary))
                ZStack {
                    Circle()
                        .stroke(isSelected ? PulseColors.accent : PulseColors.borderStrong, lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    if hasEntries {
                        Circle().fill(PulseColors.warning.opacity(0.85)).frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dayNum)\(isToday ? ", today" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var todayBanner: some View {
        Group {
            if calendar.isDateInToday(selectedDate) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Entries")
                        .font(PulseFont.bodySemibold(17))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("Your entries today will contribute to the 90-day rolling data for tomorrow's insights.")
                        .font(PulseFont.bodyMedium(13))
                        .foregroundStyle(PulseColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Sections

    private func sectionView(_ section: JournalMetric.Section, metrics: [JournalMetric]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(section.rawValue)
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textSecondary)
                if section == .nighttime {
                    Spacer()
                    Text(nightRangeLabel)
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
            VStack(spacing: 8) {
                ForEach(metrics) { metric in
                    JournalMetricRow(
                        metric: metric,
                        entry: entry(for: metric),
                        onChange: { state, amount in update(metric, state: state, amount: amount) }
                    )
                }
            }
        }
    }

    private var nightRangeLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        let next = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        return "\(fmt.string(from: selectedDate)) – \(fmt.string(from: next))"
    }

    private var hasYesterdayEntries: Bool {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        guard let prev = days.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) }) else { return false }
        return prev.entries.contains { src in
            guard src.state != 0 else { return false }
            if let metric = JournalCatalog.metric(for: src.metricKey), case .automatic = metric.kind { return false }
            return true
        }
    }

    @ViewBuilder
    private var copyYesterdayButton: some View {
        if hasYesterdayEntries {
            Button {
                copyYesterday()
            } label: {
                VStack(spacing: 2) {
                    Text("Copy entries from yesterday")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("Only toggles will be copied")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .pulseCardSurface()
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityHint("Copies yesterday's toggle entries into today")
        }
    }

    // MARK: Data

    private func entry(for metric: JournalMetric) -> JournalMetricEntry? {
        selectedDay?.entries.first { $0.metricKey == metric.key }
    }

    private func dayRecord() -> JournalDay {
        if let existing = selectedDay { return existing }
        let day = JournalDay(date: selectedDate)
        modelContext.insert(day)
        return day
    }

    private func update(_ metric: JournalMetric, state: Int, amount: Double?) {
        let day = dayRecord()
        if let existing = day.entries.first(where: { $0.metricKey == metric.key }) {
            existing.state = state
            existing.amount = amount
        } else {
            day.entries.append(JournalMetricEntry(metricKey: metric.key, state: state, amount: amount))
        }
        try? modelContext.save()
    }

    private func copyYesterday() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        guard let prev = days.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) }) else {
            HapticService.impact(.light)
            return
        }
        let day = dayRecord()
        for src in prev.entries where src.state != 0 {
            if let metric = JournalCatalog.metric(for: src.metricKey), case .automatic = metric.kind { continue }
            if let existing = day.entries.first(where: { $0.metricKey == src.metricKey }) {
                existing.state = src.state
            } else {
                day.entries.append(JournalMetricEntry(metricKey: src.metricKey, state: src.state))
            }
        }
        try? modelContext.save()
        HapticService.success()
    }
}

// MARK: - Journal Metric Row

struct JournalMetricRow: View {
    let metric: JournalMetric
    let entry: JournalMetricEntry?
    let onChange: (Int, Double?) -> Void

    private var state: Int { entry?.state ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            Text(metric.emoji)
                .font(.system(size: 20))
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(metric.title)
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .pulseCardSurface()
    }

    @ViewBuilder
    private var control: some View {
        switch metric.kind {
        case .toggle:
            TriStateControl(state: state) { onChange($0, entry?.amount) }
        case .amount(let unit):
            HStack(spacing: 10) {
                Text(amountText(unit))
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textMuted)
                ringButton
            }
        case .automatic(let unit):
            HStack(spacing: 10) {
                Text(amountText(unit))
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textMuted)
                Circle()
                    .stroke(PulseColors.success, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
        case .score:
            scoreToggle
        }
    }

    private func amountText(_ unit: String) -> String {
        if let amount = entry?.amount, amount > 0 {
            return "\(formatted(amount)) \(unit)"
        }
        return "- \(unit)"
    }

    private func formatted(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.1f", d)
    }

    private var ringButton: some View {
        Button {
            HapticService.selection()
            let next = state == 1 ? 0 : 1
            onChange(next, next == 1 ? (entry?.amount ?? 1) : nil)
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 32, height: 32)
                .background(PulseColors.fillSubtle)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(metric.title)")
    }

    private var scoreToggle: some View {
        Button {
            HapticService.selection()
            onChange(state == 1 ? 0 : 1, nil)
        } label: {
            ZStack {
                Circle()
                    .stroke(state == 1 ? PulseColors.success : PulseColors.borderStrong, lineWidth: 2)
                    .frame(width: 26, height: 26)
                if state == 1 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PulseColors.success)
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(metric.title)
        .accessibilityValue(state == 1 ? "met" : "not met")
    }
}

// MARK: - Tri-State Control (x / – / ✓)

struct TriStateControl: View {
    /// -1 no, 0 neutral, 1 yes
    let state: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(symbol: "xmark", value: -1, color: PulseColors.alert)
            divider
            segment(symbol: "minus", value: 0, color: PulseColors.textMuted)
            divider
            segment(symbol: "checkmark", value: 1, color: PulseColors.success)
        }
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var divider: some View {
        Rectangle().fill(PulseColors.borderHairline).frame(width: 1, height: 28)
    }

    private func segment(symbol: String, value: Int, color: Color) -> some View {
        let isActive = state == value
        return Button {
            HapticService.selection()
            onChange(value)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isActive ? .white : color.opacity(0.7))
                .frame(width: 40, height: 34)
                .background(isActive ? color : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: value))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func accessibilityLabel(for value: Int) -> String {
        switch value {
        case -1: return "No"
        case 1: return "Yes"
        default: return "Skip"
        }
    }
}
