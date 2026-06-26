import SwiftUI
import SwiftData

// MARK: - Week Planner ("Weekline")

/// A calm weekly planner built around real capacity rather than endless lists.
/// Each day has a point budget; tasks beyond it fall below a red "over the line"
/// divider so overload is visible at a glance. Tasks are placed on a day via
/// their `dueDate`; tasks with no due date live in "Week Edge" (leftovers).
struct WeekPlannerView: View {
    let tasks: [TaskItem]
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onMove: (TaskItem, Date) -> Void
    let onAdd: (Date) -> Void

    /// Points a single day can hold before tasks spill "over the line".
    static let dailyCapacity = 5

    @State private var expandedDay: Date?
    @State private var showWeekEdge = false

    private var calendar: Calendar { .current }

    private var weekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        }
        // Build Mon…Sun starting from the week's first day.
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekNumber: Int {
        calendar.component(.weekOfYear, from: Date())
    }

    private var weekRangeText: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "d"
        return "\(fmt.string(from: first)) – \(endFmt.string(from: last))"
    }

    private func tasksFor(_ day: Date) -> [TaskItem] {
        tasks
            .filter { task in
                guard let due = task.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: day)
            }
            .sorted { $0.order < $1.order }
    }

    /// Tasks with no day assigned — the "Week Edge" leftovers.
    private var edgeTasks: [TaskItem] {
        tasks.filter { $0.dueDate == nil && $0.status != .done }
    }

    private func load(for day: Date) -> Int {
        tasksFor(day).filter { $0.status != .done }.reduce(0) { $0 + $1.weight }
    }

    private func overflow(for day: Date) -> Int {
        max(0, load(for: day) - Self.dailyCapacity)
    }

    private var totalOver: Int {
        weekDays.reduce(0) { $0 + overflow(for: $1) }
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            ForEach(weekDays, id: \.self) { day in
                WeekDayRow(
                    day: day,
                    tasks: tasksFor(day),
                    capacity: Self.dailyCapacity,
                    load: load(for: day),
                    isExpanded: isExpanded(day),
                    onTapHeader: { toggleExpanded(day) },
                    onToggle: onToggle,
                    onDelete: onDelete,
                    onAdd: { onAdd(day) },
                    onDropTask: { id in handleDrop(id, on: day) }
                )
            }

            if !edgeTasks.isEmpty {
                weekEdgeButton
            }
        }
        .onAppear {
            if expandedDay == nil {
                expandedDay = weekDays.first(where: { calendar.isDateInToday($0) }) ?? weekDays.first
            }
        }
        .sheet(isPresented: $showWeekEdge) {
            WeekEdgeSheet(
                leftovers: edgeTasks,
                weekDays: weekDays,
                onToggle: onToggle,
                onDelete: onDelete,
                onPlace: { task, day in onMove(task, day) }
            )
            .presentationDetents([.large])
        }
    }

    private func isExpanded(_ day: Date) -> Bool {
        guard let expandedDay else { return false }
        return calendar.isDate(expandedDay, inSameDayAs: day)
    }

    private func handleDrop(_ idString: String, on day: Date) -> Bool {
        guard let id = UUID(uuidString: idString),
              let task = tasks.first(where: { $0.id == id }) else { return false }
        // Ignore drops onto the same day.
        if let due = task.dueDate, calendar.isDate(due, inSameDayAs: day) { return false }
        HapticService.impact(.medium)
        onMove(task, day)
        withAnimation(.snappy(duration: 0.28)) { expandedDay = day }
        return true
    }

    private func toggleExpanded(_ day: Date) {
        HapticService.selection()
        withAnimation(.snappy(duration: 0.28)) {
            if isExpanded(day) {
                expandedDay = nil
            } else {
                expandedDay = day
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WEEK \(weekNumber)")
                    .font(PulseFont.bodyBold(20))
                    .tracking(0.5)
                    .foregroundStyle(PulseColors.textPrimary)
                Text(weekRangeText)
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            if totalOver > 0 {
                Text("\(totalOver) over")
                    .font(PulseFont.bodySemibold(13))
                    .foregroundStyle(PulseColors.alert)
                    .accessibilityLabel("\(totalOver) points over capacity this week")
            } else {
                Text("on track")
                    .font(PulseFont.bodySemibold(13))
                    .foregroundStyle(PulseColors.success)
            }
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private var weekEdgeButton: some View {
        Button {
            HapticService.impact(.light)
            showWeekEdge = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Week Edge")
                        .font(PulseFont.bodySemibold(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("\(edgeTasks.count) unplaced from before")
                        .font(PulseFont.bodyMedium(11.5))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PulseColors.textMuted)
            }
            .foregroundStyle(PulseColors.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week Edge, \(edgeTasks.count) unplaced tasks")
        .accessibilityHint("Opens leftovers to place into the week")
    }
}

// MARK: - Day Row

struct WeekDayRow: View {
    let day: Date
    let tasks: [TaskItem]
    let capacity: Int
    let load: Int
    let isExpanded: Bool
    let onTapHeader: () -> Void
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onAdd: () -> Void
    var onDropTask: ((String) -> Bool)? = nil

    @State private var isDropTarget = false

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var overflow: Int { max(0, load - capacity) }

    private var weekdayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: day).uppercased()
    }

    private var dayNumber: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: day)
    }

    /// Tasks split at the capacity line: those that fit vs. those over.
    private var split: (fitting: [TaskItem], over: [TaskItem]) {
        var running = 0
        var fitting: [TaskItem] = []
        var over: [TaskItem] = []
        for task in tasks {
            if task.status == .done {
                fitting.append(task)
                continue
            }
            running += task.weight
            if running <= capacity {
                fitting.append(task)
            } else {
                over.append(task)
            }
        }
        return (fitting, over)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? PulseColors.background : PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous)
                .stroke(isDropTarget ? PulseColors.accent : (isExpanded ? PulseColors.borderHairline : Color.clear), lineWidth: isDropTarget ? 2 : 1)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, let onDropTask else { return false }
            return onDropTask(id)
        } isTargeted: { targeted in
            withAnimation(.snappy(duration: 0.15)) { isDropTarget = targeted }
        }
        .overlay(alignment: .leading) {
            if isExpanded {
                RoundedRectangle(cornerRadius: 2)
                    .fill(PulseColors.textPrimary)
                    .frame(width: 3)
                    .padding(.vertical, 14)
            }
        }
    }

    private var headerRow: some View {
        Button(action: onTapHeader) {
            HStack(spacing: 10) {
                Text(weekdayName)
                    .font(PulseFont.bodyBold(13))
                    .tracking(0.5)
                    .foregroundStyle(isExpanded || isToday ? PulseColors.textPrimary : PulseColors.textSecondary)
                Text(dayNumber)
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textMuted)
                Spacer()
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(PulseFont.bodySemibold(13))
                        .foregroundStyle(PulseColors.alert)
                        .accessibilityLabel("\(overflow) over capacity")
                } else if load > 0 {
                    Text("\(load)/\(capacity)")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: PulseLayout.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(weekdayName) \(dayNumber)\(isToday ? ", today" : "")")
        .accessibilityValue(overflow > 0 ? "\(overflow) over capacity" : "\(load) of \(capacity) points")
        .accessibilityHint(isExpanded ? "Collapse day" : "Expand day")
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            let groups = split

            ForEach(groups.fitting) { task in
                WeekTaskRow(task: task, onToggle: { onToggle(task) }, onDelete: { onDelete(task) })
                    .draggable(task.id.uuidString)
            }

            if !groups.over.isEmpty {
                capacityLine
                ForEach(groups.over) { task in
                    WeekTaskRow(task: task, onToggle: { onToggle(task) }, onDelete: { onDelete(task) }, isOver: true)
                        .draggable(task.id.uuidString)
                }
            }

            addRow
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var capacityLine: some View {
        Rectangle()
            .fill(PulseColors.alert)
            .frame(height: 1.5)
            .padding(.vertical, 8)
            .accessibilityLabel("Capacity line. Tasks below this are over capacity.")
    }

    private var addRow: some View {
        Button {
            HapticService.impact(.light)
            onAdd()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(PulseColors.textMuted)
                Text("Add a task…")
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textMuted)
                Spacer()
                if overflow > 0 {
                    Text("+\(overflow) over")
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(PulseColors.alert)
                }
            }
            .frame(minHeight: PulseLayout.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a task to \(weekdayName)")
    }
}

// MARK: - Task Row (within a day)

struct WeekTaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    var isOver: Bool = false

    private var done: Bool { task.status == .done }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(done ? PulseColors.success : (isOver ? PulseColors.alert : PulseColors.borderStrong), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PulseColors.success)
                    }
                }
                .frame(width: PulseLayout.minTapTarget, height: PulseLayout.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark \(task.title) not done" : "Complete \(task.title)")

            Text(task.title)
                .font(PulseFont.bodyMedium(15))
                .foregroundStyle(done ? PulseColors.textMuted : PulseColors.textPrimary)
                .strikethrough(done)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text("\(task.weight)")
                .font(PulseFont.bodyMedium(12))
                .monospacedDigit()
                .foregroundStyle(isOver ? PulseColors.alert : PulseColors.textMuted)
                .accessibilityLabel("\(task.weight) points")
        }
        .padding(.trailing, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Add Task Sheet (with weight selector)

struct AddWeightedTaskSheet: View {
    let day: Date
    let currentLoad: Int
    let capacity: Int
    let onCommit: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var weight: TaskWeight = .medium
    @FocusState private var focused: Bool

    private var weekdayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: day).uppercased()
    }

    private var dayNumber: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: day)
    }

    private var pushesOver: Bool {
        currentLoad + weight.rawValue > capacity
    }

    private var canCommit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                EyebrowLabel("ADD TO")
                    .fixedSize()
                Text("\(weekdayName) \(dayNumber)")
                    .font(PulseFont.bodyBold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button {
                    HapticService.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                        .frame(width: PulseLayout.minTapTarget, height: PulseLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.top, 8)

            TextField("Add a task…", text: $title)
                .font(PulseFont.titleMedium(24))
                .foregroundStyle(PulseColors.textPrimary)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { commit() }
                .padding(.vertical, 16)

            HStack {
                EyebrowLabel("WEIGHT")
                Spacer()
                if pushesOver {
                    Label("Pushes over the line", systemImage: "exclamationmark.triangle.fill")
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(PulseColors.alert)
                        .accessibilityLabel("This task pushes the day over capacity")
                }
            }
            .padding(.bottom, 10)

            weightSelector
                .padding(.bottom, 18)

            Button {
                commit()
            } label: {
                HStack(spacing: 8) {
                    Text("Place on \(weekdayName)")
                    Image(systemName: "arrow.down")
                }
                .font(PulseFont.bodySemibold(16))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(canCommit ? .white : PulseColors.textMuted)
                .background(canCommit ? PulseColors.accent : PulseColors.fillMuted)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
            .accessibilityLabel("Place task on \(weekdayName)")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(PulseColors.background)
        .onAppear { focused = true }
    }

    private var handle: some View {
        Capsule()
            .fill(PulseColors.borderStrong)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }

    private var weightSelector: some View {
        HStack(spacing: 6) {
            ForEach(TaskWeight.allCases) { option in
                Button {
                    if weight != option { HapticService.selection() }
                    withAnimation(.snappy(duration: 0.2)) { weight = option }
                } label: {
                    VStack(spacing: 4) {
                        Text("\(option.rawValue)")
                            .font(PulseFont.bodyBold(18))
                            .foregroundStyle(weight == option ? PulseColors.textPrimary : PulseColors.textSecondary)
                        Text(option.label)
                            .font(PulseFont.bodyMedium(10))
                            .foregroundStyle(weight == option ? PulseColors.textSecondary : PulseColors.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(weight == option ? PulseColors.fillSubtle : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous)
                            .stroke(weight == option ? PulseColors.borderStrong : PulseColors.borderHairline, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label), \(option.rawValue) points")
                .accessibilityAddTraits(weight == option ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        HapticService.success()
        onCommit(trimmed, weight.rawValue)
        dismiss()
    }
}

// MARK: - Week Edge Sheet (leftovers)

struct WeekEdgeSheet: View {
    let leftovers: [TaskItem]
    let weekDays: [Date]
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onPlace: (TaskItem, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targetDay: Date = Date()
    @State private var selected: Set<UUID> = []

    private var calendar: Calendar { .current }

    private func shortName(_ day: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: day).uppercased()
    }

    private var selectedPoints: Int {
        leftovers.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.weight }
    }

    var body: some View {
        VStack(spacing: 0) {
            handle

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEK EDGE")
                        .font(PulseFont.bodyBold(18))
                        .tracking(0.5)
                        .foregroundStyle(PulseColors.textPrimary)
                    Text("Unfinished from before")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                Button {
                    HapticService.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                        .frame(width: PulseLayout.minTapTarget, height: PulseLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            dayPicker
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(leftovers) { task in
                        edgeRow(task)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .safeAreaInset(edge: .bottom) {
            placeBar
        }
        .onAppear {
            targetDay = weekDays.first(where: { calendar.isDateInToday($0) }) ?? weekDays.first ?? Date()
        }
    }

    private var handle: some View {
        Capsule()
            .fill(PulseColors.borderStrong)
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .accessibilityHidden(true)
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel("PLACE INTO")
            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    let isSel = calendar.isDate(day, inSameDayAs: targetDay)
                    Button {
                        HapticService.selection()
                        withAnimation(.snappy(duration: 0.2)) { targetDay = day }
                    } label: {
                        Text(shortName(day))
                            .font(PulseFont.bodySemibold(12))
                            .foregroundStyle(isSel ? PulseColors.textPrimary : PulseColors.textMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isSel ? PulseColors.fillSubtle : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: PulseRadius.small, style: .continuous)
                                    .stroke(isSel ? PulseColors.borderStrong : PulseColors.borderHairline, lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shortName(day))
                    .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private func edgeRow(_ task: TaskItem) -> some View {
        let isSel = selected.contains(task.id)
        return Button {
            HapticService.selection()
            if isSel { selected.remove(task.id) } else { selected.insert(task.id) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSel ? PulseColors.accent : PulseColors.borderStrong, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isSel {
                        Circle().fill(PulseColors.accent).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(task.title)
                    .font(PulseFont.bodyMedium(15))
                    .foregroundStyle(PulseColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("\(task.weight)")
                    .font(PulseFont.bodyMedium(12))
                    .monospacedDigit()
                    .foregroundStyle(PulseColors.textMuted)
            }
            .frame(minHeight: PulseLayout.minTapTarget)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete(task) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(task.title)
        .accessibilityValue("\(task.weight) points\(isSel ? ", selected" : "")")
    }

    private var placeBar: some View {
        VStack(spacing: 0) {
            Button {
                placeSelected()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                    Text("Place selected on \(shortName(targetDay))")
                }
                .font(PulseFont.bodySemibold(16))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(selected.isEmpty ? PulseColors.textMuted : .white)
                .background(selected.isEmpty ? PulseColors.fillMuted : PulseColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)

            Text("\(leftovers.count) at edge · \(selected.count) selected · \(selectedPoints) pts")
                .font(PulseFont.bodyMedium(11.5))
                .foregroundStyle(PulseColors.textMuted)
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func placeSelected() {
        guard !selected.isEmpty else { return }
        HapticService.success()
        for task in leftovers where selected.contains(task.id) {
            onPlace(task, targetDay)
        }
        let placedAll = leftovers.count == selected.count
        selected.removeAll()
        if placedAll { dismiss() }
    }
}

