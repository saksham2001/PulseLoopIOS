import SwiftUI
import SwiftData
import UserNotifications

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<InboxItem> { !$0.isHandled }, sort: \InboxItem.receivedAt, order: .reverse) private var items: [InboxItem]
    @Query(filter: #Predicate<InboxItem> { $0.isHandled }) private var handledItems: [InboxItem]
    @Query private var medications: [Medication]
    @Binding var path: NavigationPath
    @State private var aiTriageResults: [Int: AIService.InboxPriority] = [:]
    @State private var isTriaging = false
    @State private var addedToProtocol: Set<UUID> = []
    @State private var restockSet: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                inboxHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                if isTriaging {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(PulseColors.accent)
                        Text("AI is analyzing your inbox…")
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    .padding(.vertical, 12)
                }

                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        InboxItemRow(
                            item: item,
                            aiPriority: aiTriageResults[index],
                            isAddedToProtocol: addedToProtocol.contains(item.id),
                            isRestockSet: restockSet.contains(item.id),
                            onAction: { handleAction(item) },
                            onDismiss: { dismissItem(item) }
                        )
                    }

                    if !handledItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("HANDLED")
                                .font(PulseFont.bodyMedium(11))
                                .foregroundStyle(PulseColors.textMuted)
                                .tracking(0.8)
                                .padding(.top, 16)

                            ForEach(handledItems) { item in
                                HandledInboxRow(item: item, onUndo: { undoItem(item) })
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { triageInbox() }
    }

    private var inboxHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Capture")
                    .font(PulseFont.title(28))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { triageInbox() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("AI Triage")
                            .font(PulseFont.bodySemibold(12))
                    }
                    .foregroundStyle(PulseColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PulseColors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(PulseColors.accent)
                        .clipShape(Circle())
                }
            }
            .padding(.top, 8)

            Text("Feed voice notes, photos & text — AI organizes them for you")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
        }
    }

    private func triageInbox() {
        guard !items.isEmpty else { return }
        isTriaging = true
        Task {
            let itemData = items.prefix(10).map { (title: $0.title, source: $0.source.rawValue, preview: $0.subtitle) }
            let results = await AIService.shared.triageInbox(items: itemData)
            for result in results {
                aiTriageResults[result.index] = result
            }
            isTriaging = false
        }
    }

    private func handleAction(_ item: InboxItem) {
        switch item.actionType {
        case .reply:
            path.append(AppRoute.mailReply(item.id))
        case .addToProtocol:
            addToProtocol(item)
        case .restockReminder:
            setRestockReminder(item)
        default:
            withAnimation {
                item.isHandled = true
                try? modelContext.save()
            }
        }
    }

    private func addToProtocol(_ item: InboxItem) {
        guard let productName = item.detectedProduct else {
            item.isHandled = true
            try? modelContext.save()
            return
        }

        let alreadyExists = medications.contains { $0.name.lowercased() == productName.lowercased() }
        guard !alreadyExists else {
            addedToProtocol.insert(item.id)
            HapticService.impact(.light)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { item.isHandled = true; try? modelContext.save() }
            }
            return
        }

        let suppInfo = SupplementKnowledge.find(productName) ?? SupplementKnowledge.fuzzyMatch(productName).first
        let peptideInfo = PeptideKnowledge.find(productName) ?? PeptideKnowledge.fuzzyMatch(productName).first

        let dose = item.detectedDose ?? peptideInfo?.defaultDose ?? suppInfo?.defaultDose ?? "1 serving"
        let category: MedicationCategory = peptideInfo != nil ? .peptide : (suppInfo?.category == "vitamin" ? .vitamin : .supplement)
        let emoji = suppInfo?.emoji ?? (peptideInfo != nil ? "syringe" : "pills.fill")
        let timing = peptideInfo?.timing ?? suppInfo?.timing ?? "AM"

        let med = Medication(
            name: productName,
            dose: dose,
            category: category,
            emoji: emoji,
            timing: timing,
            instructions: peptideInfo?.instructions ?? suppInfo?.interactionNotes,
            benefit: peptideInfo?.benefit ?? suppInfo?.benefit,
            mechanism: peptideInfo?.mechanism ?? suppInfo?.mechanism,
            interactionNotes: peptideInfo?.warnings ?? suppInfo?.interactionNotes,
            bestTimeReason: suppInfo?.bestTimeReason,
            stackNotes: peptideInfo?.stackNotes ?? suppInfo?.stackNotes
        )
        modelContext.insert(med)
        try? modelContext.save()

        withAnimation { addedToProtocol.insert(item.id) }
        HapticService.success()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { item.isHandled = true; try? modelContext.save() }
        }
    }

    private func setRestockReminder(_ item: InboxItem) {
        let productName = item.detectedProduct ?? item.title

        let content = UNMutableNotificationContent()
        content.title = "Restock: \(productName)"
        content.body = "Time to reorder \(productName) — you're running low."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 24 * 3600, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        withAnimation { restockSet.insert(item.id) }
        HapticService.success()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { item.isHandled = true; try? modelContext.save() }
        }
    }

    private func dismissItem(_ item: InboxItem) {
        withAnimation {
            item.isHandled = true
            try? modelContext.save()
        }
    }

    private func undoItem(_ item: InboxItem) {
        withAnimation {
            item.isHandled = false
            try? modelContext.save()
        }
    }
}

struct InboxItemRow: View {
    let item: InboxItem
    var aiPriority: AIService.InboxPriority?
    var isAddedToProtocol: Bool = false
    var isRestockSet: Bool = false
    var onAction: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    Text(item.subtitle)
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
                Spacer()
                if let priority = aiPriority {
                    priorityBadge(priority.priority)
                }
                Button(action: onDismiss) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(PulseColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .accessibilityLabel("Mark handled")
            }

            if let priority = aiPriority, !priority.reason.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 9))
                        .foregroundStyle(PulseColors.textMuted)
                    Text(priority.reason)
                        .font(PulseFont.body(11))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }

            if isAddedToProtocol {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseColors.success)
                    Text("Added to Protocol")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.success)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(PulseColors.successBackground)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isRestockSet {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseColors.accent)
                    Text("Restock reminder set · 30 days")
                        .font(PulseFont.bodyMedium(12))
                        .foregroundStyle(PulseColors.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(PulseColors.accentSoft)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if let action = item.suggestedAction {
                Button(action: onAction) {
                    HStack(spacing: 6) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(PulseColors.textMuted)
                        Text(action)
                            .font(PulseFont.bodyMedium(12))
                            .foregroundStyle(PulseColors.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PulseColors.fillSubtle)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(priorityBorderColor, lineWidth: aiPriority?.priority == "high" ? 1.5 : 1)
        }
        .animation(.snappy(duration: 0.3), value: isAddedToProtocol)
        .animation(.snappy(duration: 0.3), value: isRestockSet)
    }

    private var actionIcon: String {
        switch item.actionType {
        case .addToProtocol: return "pills.fill"
        case .restockReminder: return "bell.badge"
        case .reply: return "arrowshape.turn.up.left"
        case .addToCalendar: return "calendar.badge.plus"
        case .createTask: return "checkmark.circle"
        default: return "sparkles"
        }
    }

    private var priorityBorderColor: Color {
        switch aiPriority?.priority {
        case "high": return Color.orange.opacity(0.5)
        default: return PulseColors.borderHairline
        }
    }

    @ViewBuilder
    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = priority == "high" ? .orange : priority == "medium" ? PulseColors.accent : PulseColors.textFaint
        Text(priority.uppercased())
            .font(PulseFont.bodySemibold(9))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

struct HandledInboxRow: View {
    let item: InboxItem
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.title)
                .font(PulseFont.body(13))
                .foregroundStyle(Color.secondary)
                .strikethrough(true, color: Color.secondary.opacity(0.5))
            Spacer()
            Button(action: onUndo) {
                Text("Undo")
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(Color.primary)
                    .underline()
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
