import SwiftUI
import SwiftData

// MARK: - Sleep Tracking View

struct SleepTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepLog.date, order: .reverse) private var sleepLogs: [SleepLog]
    @State private var showAddSleep = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if let latest = sleepLogs.first {
                sleepSummaryCard(latest)
            }
            weeklyChart
            recentLogs
        }
        .sheet(isPresented: $showAddSleep) {
            AddSleepSheet()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SLEEP")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Text(averageSleepLabel)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            Spacer()
            Button { showAddSleep = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Log")
                        .font(PulseFont.bodySemibold(12))
                }
                .foregroundStyle(PulseColors.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PulseColors.accent.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    private var averageSleepLabel: String {
        let week = sleepLogs.prefix(7)
        guard !week.isEmpty else { return "No data yet" }
        let avg = week.reduce(0) { $0 + $1.durationMinutes } / week.count
        return "Avg \(avg / 60)h \(avg % 60)m this week"
    }

    private func sleepSummaryCard(_ log: SleepLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "moon.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PulseColors.sleep)
                Text("Last Night")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        Image(systemName: i < log.quality ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(i < log.quality ? Color.yellow : PulseColors.textFaint)
                    }
                }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(log.durationMinutes / 60)h \(log.durationMinutes % 60)m")
                        .font(PulseFont.bodySemibold(20))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("Total sleep")
                        .font(PulseFont.body(11))
                        .foregroundStyle(PulseColors.textMuted)
                }

                if let deep = log.deepMinutes {
                    miniStat("Deep", "\(deep)m", Color.indigo)
                }
                if let rem = log.remMinutes {
                    miniStat("REM", "\(rem)m", Color.purple)
                }
                if let light = log.lightMinutes {
                    miniStat("Light", "\(light)m", Color.cyan)
                }
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(PulseFont.bodySemibold(14))
                .foregroundStyle(color)
            Text(label)
                .font(PulseFont.body(10))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    private var weeklyChart: some View {
        let week = Array(sleepLogs.prefix(7).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            Text("This Week")
                .font(PulseFont.bodyMedium(12))
                .foregroundStyle(PulseColors.textSecondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let mins = i < week.count ? week[i].durationMinutes : 0
                    let height = max(CGFloat(mins) / 600.0 * 60, 4)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(mins >= 420 ? PulseColors.accent : PulseColors.fillSubtle)
                            .frame(width: 28, height: height)
                        Text(dayLabel(i, week))
                            .font(PulseFont.body(9))
                            .foregroundStyle(PulseColors.textFaint)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func dayLabel(_ index: Int, _ week: [SleepLog]) -> String {
        if index < week.count {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: week[index].date).prefix(2).uppercased()
        }
        return " - "
    }

    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sleepLogs.count > 1 {
                Text("Recent")
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textSecondary)
                ForEach(sleepLogs.prefix(5)) { log in
                    HStack {
                        Text(log.date, style: .date)
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textSecondary)
                        Spacer()
                        Text("\(log.durationMinutes / 60)h \(log.durationMinutes % 60)m")
                            .font(PulseFont.bodySemibold(13))
                            .foregroundStyle(PulseColors.textPrimary)
                        HStack(spacing: 1) {
                            ForEach(0..<5) { i in
                                Circle()
                                    .fill(i < log.quality ? Color.yellow : PulseColors.fillSubtle)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }
}

// MARK: - Add Sleep Sheet

struct AddSleepSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var bedtime = Calendar.current.date(bySettingHour: 22, minute: 30, second: 0,
        of: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) ?? Date()
    @State private var wakeTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quality = 3
    @State private var deepMin = ""
    @State private var remMin = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bedtime")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                        DatePicker("", selection: $bedtime, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wake Time")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                        DatePicker("", selection: $wakeTime, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quality")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { i in
                                Button { quality = i } label: {
                                    Image(systemName: i <= quality ? "star.fill" : "star")
                                        .font(.system(size: 24))
                                        .foregroundStyle(i <= quality ? Color.yellow : PulseColors.textFaint)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                        TextField("How did you sleep?", text: $notes)
                            .font(PulseFont.body(15))
                            .padding(12)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Spacer(minLength: 20)

                    Button { save() } label: {
                        Text("Log Sleep")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Log Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let log = SleepLog(
            bedtime: bedtime,
            wakeTime: wakeTime,
            quality: quality,
            deepMinutes: Int(deepMin),
            remMinutes: Int(remMin),
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(log)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Mood Tracking View

struct MoodTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MoodEntry.date, order: .reverse) private var entries: [MoodEntry]
    @State private var showAddMood = false

    var body: some View {
        VStack(spacing: 16) {
            header
            if let latest = entries.first, Calendar.current.isDateInToday(latest.date) {
                todayCard(latest)
            } else {
                quickCheckIn
            }
            weeklyTrend
        }
        .sheet(isPresented: $showAddMood) {
            AddMoodSheet()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MOOD & ENERGY")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Text(avgMoodLabel)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            Spacer()
            Button { showAddMood = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Check-in")
                        .font(PulseFont.bodySemibold(12))
                }
                .foregroundStyle(PulseColors.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PulseColors.accent.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    private var avgMoodLabel: String {
        let week = entries.prefix(7)
        guard !week.isEmpty else { return "No data yet" }
        let avg = Double(week.reduce(0) { $0 + $1.mood }) / Double(week.count)
        return "Avg mood: \(String(format: "%.1f", avg))/5"
    }

    private var quickCheckIn: some View {
        VStack(spacing: 12) {
            Text("How are you feeling?")
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textPrimary)
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { i in
                    Button { quickLog(mood: i) } label: {
                        Image(systemName: moodEmoji(i))
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func todayCard(_ entry: MoodEntry) -> some View {
        HStack(spacing: 16) {
            Image(systemName: moodEmoji(entry.mood))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 40, height: 40)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Check-in")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                HStack(spacing: 12) {
                    Label("Mood: \(entry.mood)/5", systemImage: "face.smiling")
                    Label("Energy: \(entry.energy)/5", systemImage: "bolt.fill")
                }
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private var weeklyTrend: some View {
        let week = Array(entries.prefix(7).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            Text("7-Day Trend")
                .font(PulseFont.bodyMedium(12))
                .foregroundStyle(PulseColors.textSecondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let mood = i < week.count ? week[i].mood : 0
                    VStack(spacing: 4) {
                        if mood > 0 {
                            Image(systemName: moodEmoji(mood))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PulseColors.textPrimary)
                        } else {
                            Circle()
                                .fill(PulseColors.fillSubtle)
                                .frame(width: 16, height: 16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }

    private func moodEmoji(_ level: Int) -> String {
        switch level {
        case 1: return "cloud.rain.fill"
        case 2: return "cloud.fill"
        case 3: return "cloud.sun.fill"
        case 4: return "sun.max.fill"
        case 5: return "sparkles"
        default: return "cloud.sun.fill"
        }
    }

    private func quickLog(mood: Int) {
        let entry = MoodEntry(mood: mood, energy: mood)
        modelContext.insert(entry)
        try? modelContext.save()
    }
}

// MARK: - Add Mood Sheet

struct AddMoodSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var mood = 3
    @State private var energy = 3
    @State private var anxiety = 3
    @State private var focus = 3
    @State private var notes = ""
    @State private var selectedTags: Set<String> = []

    private let tagOptions = ["Rested", "Anxious", "Focused", "Social", "Creative", "Tired", "Stressed", "Calm", "Motivated", "Low"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    sliderSection("Mood", value: $mood, emoji: moodEmoji(mood))
                    sliderSection("Energy", value: $energy, emoji: energyEmoji(energy))
                    sliderSection("Anxiety", value: $anxiety, emoji: anxietyEmoji(anxiety))
                    sliderSection("Focus", value: $focus, emoji: focusEmoji(focus))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textMuted)
                        FlowLayout(spacing: 8) {
                            ForEach(tagOptions, id: \.self) { tag in
                                Button {
                                    if selectedTags.contains(tag) { selectedTags.remove(tag) }
                                    else { selectedTags.insert(tag) }
                                } label: {
                                    Text(tag)
                                        .font(PulseFont.body(13))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedTags.contains(tag) ? PulseColors.accent.opacity(0.15) : PulseColors.fillSubtle)
                                        .foregroundStyle(selectedTags.contains(tag) ? PulseColors.accent : PulseColors.textSecondary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    TextField("Notes (optional)", text: $notes)
                        .font(PulseFont.body(15))
                        .padding(12)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button { save() } label: {
                        Text("Save Check-in")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Mood Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sliderSection(_ label: String, value: Binding<Int>, emoji: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textMuted)
                Spacer()
                Image(systemName: emoji)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("\(value.wrappedValue)/5")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button { value.wrappedValue = i } label: {
                        Circle()
                            .fill(i <= value.wrappedValue ? PulseColors.accent : PulseColors.fillSubtle)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text("\(i)")
                                    .font(PulseFont.bodySemibold(14))
                                    .foregroundStyle(i <= value.wrappedValue ? .white : PulseColors.textMuted)
                            }
                    }
                }
            }
        }
    }

    private func moodEmoji(_ v: Int) -> String {
        switch v {
        case 1: return "cloud.rain.fill"
        case 2: return "cloud.fill"
        case 3: return "cloud.sun.fill"
        case 4: return "sun.max.fill"
        case 5: return "sparkles"
        default: return "cloud.sun.fill"
        }
    }
    private func energyEmoji(_ v: Int) -> String {
        switch v {
        case 1: return "battery.0percent"
        case 2: return "battery.25percent"
        case 3: return "battery.50percent"
        case 4: return "battery.75percent"
        case 5: return "battery.100percent"
        default: return "battery.50percent"
        }
    }
    private func anxietyEmoji(_ v: Int) -> String {
        switch v {
        case 1: return "leaf.fill"
        case 2: return "wind"
        case 3: return "wind.circle"
        case 4: return "bolt.fill"
        case 5: return "bolt.trianglebadge.exclamationmark.fill"
        default: return "wind.circle"
        }
    }
    private func focusEmoji(_ v: Int) -> String {
        switch v {
        case 1: return "circle.dashed"
        case 2: return "circle.dotted.circle"
        case 3: return "scope"
        case 4: return "target"
        case 5: return "brain.fill"
        default: return "scope"
        }
    }

    private func save() {
        let entry = MoodEntry(
            mood: mood,
            energy: energy,
            anxiety: anxiety,
            focus: focus,
            tags: Array(selectedTags),
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
