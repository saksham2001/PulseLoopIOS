import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]
    @State private var viewMode: TaskViewMode = .week
    @State private var showNewTask = false
    @State private var newTaskTitle = ""
    @State private var addToDay: Date?

    enum TaskViewMode: String, CaseIterable, CustomStringConvertible {
        case week = "Week"
        case list = "List"
        case board = "Board"
        var description: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                tasksHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 16) {
                    if showNewTask {
                        newTaskField
                            .padding(.horizontal, 16)
                    }
                    switch viewMode {
                    case .week:
                        weekView
                    case .list:
                        listView
                    case .board:
                        boardView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .sheet(item: addToDaySheetItem) { item in
            AddWeightedTaskSheet(
                day: item.day,
                currentLoad: weekLoad(for: item.day),
                capacity: WeekPlannerView.dailyCapacity,
                onCommit: { title, weight in addWeekTask(title: title, weight: weight, on: item.day) }
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.hidden)
        }
    }

    private var tasksHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tasks")
                    .font(PulseFont.title(27))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { showNewTask.toggle() } label: {
                    Image(systemName: showNewTask ? "xmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(PulseColors.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(PulseColors.borderHairline, lineWidth: 1)
                        }
                }
            }
            .padding(.top, 8)

            HStack(spacing: 10) {
                PillToggle(selection: $viewMode, options: TaskViewMode.allCases)
                Text(countSummary)
                    .font(PulseFont.body(12.5))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
    }

    private var countSummary: String {
        switch viewMode {
        case .week:
            let unplaced = tasks.filter { $0.dueDate == nil && $0.status != .done }.count
            return unplaced > 0 ? "\(unplaced) at edge" : "\(tasks.count) tasks"
        case .list, .board:
            return "\(tasks.count) tasks · \(Set(tasks.map(\.group)).count) groups"
        }
    }

    // MARK: - Week View

    private struct DaySheetItem: Identifiable {
        let day: Date
        var id: TimeInterval { day.timeIntervalSince1970 }
    }

    private var addToDaySheetItem: Binding<DaySheetItem?> {
        Binding(
            get: { addToDay.map(DaySheetItem.init) },
            set: { addToDay = $0?.day }
        )
    }

    private var weekView: some View {
        WeekPlannerView(
            tasks: tasks,
            onToggle: toggleTask,
            onDelete: deleteTask,
            onMove: moveTask,
            onAdd: { addToDay = $0 }
        )
    }

    private func weekLoad(for day: Date) -> Int {
        let cal = Calendar.current
        return tasks
            .filter { $0.status != .done && ($0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false) }
            .reduce(0) { $0 + $1.weight }
    }

    private func addWeekTask(title: String, weight: Int, on day: Date) {
        let task = TaskItem(title: title, status: .todo, group: "Week", dueDate: day, order: tasks.count, weight: weight)
        modelContext.insert(task)
        try? modelContext.save()
        addToDay = nil
    }

    private func moveTask(_ task: TaskItem, to day: Date) {
        withAnimation(.snappy(duration: 0.25)) {
            task.dueDate = day
            task.updatedAt = Date()
            try? modelContext.save()
        }
    }

    // MARK: - New Task

    private var newTaskField: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PulseColors.accent, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            TextField("New task…", text: $newTaskTitle)
                .font(PulseFont.bodyMedium(14.5))
                .foregroundStyle(PulseColors.textPrimary)
                .submitLabel(.done)
                .onSubmit { addTask() }
            Button { addTask() } label: {
                Text("Add")
                    .font(PulseFont.bodySemibold(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.accent.opacity(0.3), lineWidth: 1)
        }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = TaskItem(title: title, status: .todo, group: "Today", order: tasks.count)
        modelContext.insert(task)
        try? modelContext.save()
        newTaskTitle = ""
        showNewTask = false
    }

    // MARK: List View

    private var listView: some View {
        VStack(spacing: 22) {
            ForEach(groupedTasks.keys.sorted { lhs, rhs in
                let order = ["Today": 0, "This week": 1, "Done": 2]
                return (order[lhs] ?? 3) < (order[rhs] ?? 3)
            }, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.uppercased())
                        .font(PulseFont.bodySemibold(11.5))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.6)

                    VStack(spacing: 0) {
                        ForEach(groupedTasks[group] ?? []) { task in
                            TaskRow(task: task, onToggle: { toggleTask(task) }, onDelete: { deleteTask(task) })
                        }
                    }
                }
            }
        }
    }

    // MARK: Board View

    private var boardView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                BoardColumn(title: "To do", tasks: tasks.filter { $0.status == .todo }, onToggle: toggleTask)
                BoardColumn(title: "In progress", tasks: tasks.filter { $0.status == .inProgress }, onToggle: toggleTask)
                BoardColumn(title: "Done", tasks: tasks.filter { $0.status == .done }, onToggle: toggleTask)
            }
            .padding(.horizontal, 4)
        }
    }

    private var groupedTasks: [String: [TaskItem]] {
        Dictionary(grouping: tasks, by: \.group)
    }

    private func toggleTask(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch task.status {
            case .todo: task.status = .inProgress
            case .inProgress: task.status = .done
            case .done: task.status = .todo
            case .cancelled: task.status = .todo
            }
            task.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private func deleteTask(_ task: TaskItem) {
        modelContext.delete(task)
        try? modelContext.save()
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: TaskItem
    var onToggle: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                if task.status == .done {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(PulseColors.accent)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                } else if task.status == .inProgress {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(PulseColors.accent.opacity(0.15))
                        .frame(width: 18, height: 18)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PulseColors.accent, lineWidth: 1.5)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(PulseFont.bodyMedium(14.5))
                .foregroundStyle(task.status == .done ? Color.secondary : PulseColors.textPrimary)
                .strikethrough(task.status == .done)

            Spacer()

            if let label = task.label {
                Text(label)
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(label == "Today" ? PulseColors.alert : PulseColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(label == "Today" ? PulseColors.alertBackground : PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Board Column

struct BoardColumn: View {
    let title: String
    let tasks: [TaskItem]
    var onToggle: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(title)
                    .font(PulseFont.bodySemibold(12.5))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("\(tasks.count)")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textMuted)
            }

            VStack(spacing: 9) {
                ForEach(tasks) { task in
                    Button { onToggle(task) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(task.title)
                                .font(PulseFont.bodyMedium(14))
                                .foregroundStyle(task.status == .done ? PulseColors.textPrimary : PulseColors.textPrimary)
                                .strikethrough(task.status == .done)
                                .opacity(task.status == .done ? 0.6 : 1)
                                .multilineTextAlignment(.leading)
                            if let label = task.label {
                                Text(label)
                                    .font(PulseFont.bodyMedium(11))
                                    .foregroundStyle(label == "Today" ? PulseColors.alert : PulseColors.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(label == "Today" ? PulseColors.alertBackground : PulseColors.fillSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(PulseColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(PulseColors.borderHairline, lineWidth: 1)
                        }
                        .shadow(color: Color.primary.opacity(0.03), radius: 1, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 220)
    }
}
