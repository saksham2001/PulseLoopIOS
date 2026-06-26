import SwiftUI
import SwiftData

struct DayPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayPlanAction.order) private var actions: [DayPlanAction]
    @Query(sort: \AuditLogEntry.createdAt, order: .reverse) private var auditLog: [AuditLogEntry]
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var generatedBlocks: [(time: String, title: String, note: String, emoji: String)] = []
    @State private var isGenerating = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 20) {
                    scheduleSection
                    agentActionsSection
                    auditLogSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Today's plan")
        .onAppear { ensureActionsExist() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's plan")
                .font(PulseFont.title(28))
                .foregroundStyle(PulseColors.textPrimary)
            Text("AI-drafted from your tasks, protocol & habits")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCHEDULE")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                if !isGenerating {
                    Button {
                        Task { await generateSchedule() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
            }

            if isGenerating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("AI drafting your day...")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if generatedBlocks.isEmpty {
                VStack(spacing: 0) {
                    if let tt = tripToday {
                        PlanBlock(time: "Trip", title: "Day \(tt.dayNumber) in \(tt.trip.destination)", note: tt.note, emoji: "airplane", isLast: false)
                    }
                    PlanBlock(time: "Morning", title: "Protocol & supplements", note: medicationNote, emoji: "pills.fill", isLast: false)
                    PlanBlock(time: "Today", title: taskNote, note: "\(todayTaskCount) tasks remaining", emoji: "checklist", isLast: false)
                    PlanBlock(time: "Evening", title: "Evening wind-down", note: "Review day & log progress", emoji: "moon.fill", isLast: true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(generatedBlocks.enumerated()), id: \.offset) { index, block in
                        PlanBlock(time: block.time, title: block.title, note: block.note, emoji: block.emoji, isLast: index == generatedBlocks.count - 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            }
        }
    }

    private var medicationNote: String {
        let amMeds = medications.filter { $0.timing == "AM" }
        return amMeds.isEmpty ? "No AM medications set" : amMeds.prefix(3).map(\.name).joined(separator: ", ")
    }

    /// If the user is currently on a trip (today falls within its date range),
    /// surface which day of the trip it is and what's planned for today so the
    /// Day Plan reflects travel — interconnecting the Travel module with Today.
    private var tripToday: (trip: Trip, dayNumber: Int, note: String)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for trip in trips where trip.status != .cancelled {
            guard let start = trip.startDate else { continue }
            let startDay = cal.startOfDay(for: start)
            let endDay = trip.endDate.map { cal.startOfDay(for: $0) } ?? startDay
            guard today >= startDay && today <= endDay else { continue }
            let offset = cal.dateComponents([.day], from: startDay, to: today).day ?? 0
            let todays = trip.items.filter { ($0.dayOffset ?? 0) == offset }
                .sorted { ($0.startAt ?? .distantFuture, $0.order) < ($1.startAt ?? .distantFuture, $1.order) }
            let note = todays.isEmpty ? "Nothing scheduled today" : todays.prefix(2).map(\.title).joined(separator: ", ")
            return (trip, offset + 1, note)
        }
        return nil
    }

    private var todayTaskCount: Int {
        tasks.filter { $0.group == "Today" && $0.status != .done }.count
    }

    private var taskNote: String {
        let todayTasks = tasks.filter { $0.group == "Today" && $0.status != .done }
        if todayTasks.isEmpty { return "No tasks for today" }
        return todayTasks.prefix(2).map(\.title).joined(separator: ", ")
    }

    private func generateSchedule() async {
        isGenerating = true
        let taskList = tasks.filter { $0.group == "Today" && $0.status != .done }.prefix(5).map(\.title).joined(separator: ", ")
        let medList = medications.filter(\.isActive).prefix(3).map { "\($0.name) (\($0.timing))" }.joined(separator: ", ")
        let prompt = """
        Create a simple 3-4 block daily schedule as JSON array. Each block has: time (e.g. "9-11am"), title (short), note (one line tip), emoji (SF Symbol name).
        User's tasks: \(taskList.isEmpty ? "none" : taskList)
        User's medications: \(medList.isEmpty ? "none" : medList)
        Return ONLY a JSON array like: [{"time":"9-11am","title":"Deep work","note":"Energy peaks now","emoji":"bolt.fill"}]
        """
        do {
            let messages = [AIService.Message(role: "user", content: prompt)]
            let response = try await AIService.shared.complete(messages: messages)
            if let jsonStart = response.firstIndex(of: "["),
               let jsonEnd = response.lastIndex(of: "]") {
                let jsonString = String(response[jsonStart...jsonEnd])
                if let data = jsonString.data(using: .utf8),
                   let blocks = try? JSONDecoder().decode([[String: String]].self, from: data) {
                    await MainActor.run {
                        generatedBlocks = blocks.compactMap { dict in
                            guard let time = dict["time"], let title = dict["title"],
                                  let note = dict["note"], let emoji = dict["emoji"] else { return nil }
                            return (time: time, title: title, note: note, emoji: emoji)
                        }
                    }
                }
            }
        } catch {}
        await MainActor.run { isGenerating = false }
    }

    private var agentActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI SUGGESTIONS")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                let pending = actions.filter { $0.status == .pending }
                if !pending.isEmpty {
                    Text("\(pending.count)")
                        .font(PulseFont.bodySemibold(11))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(PulseColors.accent)
                        .clipShape(Circle())
                }
            }

            ForEach(actions) { action in
                DayPlanActionRow(action: action, onApprove: { approveAction(action) }, onSkip: { skipAction(action) }, onUndo: { undoAction(action) })
            }

            let pendingCount = actions.filter { $0.status == .pending }.count
            if pendingCount > 0 {
                Text("Mark done or skip · \(pendingCount) pending")
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textFaint)
            } else {
                HStack(spacing: 4) {
                    Text("All suggestions handled")
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                }
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.success)
            }
        }
    }

    private var auditLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVITY LOG")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            VStack(spacing: 0) {
                ForEach(auditLog) { entry in
                    AuditRow(title: entry.actionDescription, time: entry.sourceContext ?? "")
                }
            }
        }
    }

    // MARK: - Actions

    private func approveAction(_ action: DayPlanAction) {
        withAnimation {
            action.status = .approved
            try? modelContext.save()
        }
    }

    private func skipAction(_ action: DayPlanAction) {
        withAnimation {
            action.status = .skipped
            try? modelContext.save()
        }
    }

    private func undoAction(_ action: DayPlanAction) {
        withAnimation {
            action.status = .pending
            try? modelContext.save()
        }
    }

    private func ensureActionsExist() {
        guard actions.isEmpty else { return }
        let plan = DayPlan(date: Date(), summary: "Today's AI-generated plan")
        modelContext.insert(plan)
        let items: [(String, String, String)] = [
            ("pills.fill", "Log evening supplements", "Magnesium & zinc before bed"),
            ("figure.walk", "Take a 10-min walk", "You've been sedentary 3h+"),
            ("drop.fill", "Drink more water", "Only 2 glasses logged so far"),
        ]
        for (i, item) in items.enumerated() {
            modelContext.insert(DayPlanAction(planId: plan.id, title: item.1, subtitle: item.2, icon: item.0, order: i))
        }
        try? modelContext.save()
    }
}

struct PlanBlock: View {
    let time: String
    let title: String
    let note: String
    let emoji: String
    var isLast: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: emoji)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 36, height: 36)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(time)
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.textMuted)
                Text(title)
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                if !note.isEmpty {
                    Text(note)
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(PulseColors.background)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
            }
        }
    }
}

struct DayPlanActionRow: View {
    let action: DayPlanAction
    var onApprove: () -> Void
    var onSkip: () -> Void
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 30, height: 30)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(action.subtitle)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            if action.status != .pending {
                HStack(spacing: 8) {
                    Text(action.status == .approved ? "Done" : "Skipped")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.textMuted)
                    Button(action: onUndo) {
                        Text("Undo")
                            .font(PulseFont.bodyMedium(12))
                            .foregroundStyle(PulseColors.textSecondary)
                            .underline()
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Button(action: onApprove) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(PulseColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .accessibilityLabel("Approve suggestion")
                    Button(action: onSkip) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PulseColors.textMuted)
                            .frame(width: 30, height: 30)
                            .background(PulseColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Skip suggestion")
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

struct AuditRow: View {
    let title: String
    let time: String
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(PulseColors.success).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textPrimary)
                if !time.isEmpty {
                    Text(time).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
        }
    }
}
