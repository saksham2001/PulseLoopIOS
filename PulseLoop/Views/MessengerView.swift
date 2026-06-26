import SwiftUI
import SwiftData

// MARK: - Sample Data

private struct Conversation: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let lastMessage: String
    let timestamp: String
    let unreadCount: Int
}

private struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isSent: Bool
    let time: String
    var sharedCard: SharedCard? = nil
}

private struct SharedCard {
    let label: String
    let headline: String
    let detail: String
}

private let sampleConversations: [Conversation] = [
    .init(name: "Maya Chen", initials: "M", lastMessage: "see you at lunch!", timestamp: "2m", unreadCount: 1),
    .init(name: "Dad", initials: "D", lastMessage: "how'd you sleep?", timestamp: "1h", unreadCount: 0),
    .init(name: "Run Club", initials: "RC", lastMessage: "Jordan: 5k Saturday 8am?", timestamp: "3h", unreadCount: 1),
    .init(name: "Jordan", initials: "J", lastMessage: "shared a workout with you", timestamp: "1d", unreadCount: 0),
]

private let sampleMessages: [ChatMessage] = [
    .init(text: "Lunch at 1? That new place by the office", isSent: false, time: "12:02 PM"),
    .init(text: "yes! 1pm works", isSent: true, time: "12:04 PM"),
    .init(text: "see you at lunch! also  -  how was your run streak this week?", isSent: false, time: "12:05 PM"),
    .init(text: "", isSent: true, time: "12:06 PM", sharedCard: SharedCard(label: "YOU SHARED", headline: "6 of 7 active days", detail: "24-day streak · 18.4 km")),
    .init(text: "beast let's do the 5k Saturday", isSent: false, time: "12:07 PM"),
]

// MARK: - MessengerView

struct MessengerView: View {
    @State private var searchText = ""
    @State private var showCompose = false

    private var filtered: [Conversation] {
        if searchText.isEmpty { return sampleConversations }
        return sampleConversations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            messengerHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseColors.textMuted)
                TextField("Search friends", text: $searchText)
                    .font(PulseFont.body(15))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { convo in
                        conversationRow(convo)
                    }
                }
            }
        }
        .background(PulseColors.background)
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                ChatThreadView(contactName: "New message")
                    .navigationTitle("New message")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showCompose = false } } }
            }
        }
    }

    private var messengerHeader: some View {
        HStack {
            Text("Messages")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(PulseColors.textPrimary)
            Spacer()
            Button { showCompose = true } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(PulseColors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func conversationRow(_ convo: Conversation) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(PulseColors.fillMuted)
                .frame(width: 48, height: 48)
                .overlay {
                    Text(convo.initials)
                        .font(.system(size: convo.initials.count > 1 ? 14 : 16, weight: .semibold))
                        .foregroundStyle(PulseColors.textSecondary)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(convo.name)
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(convo.lastMessage)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(convo.timestamp)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textMuted)
                if convo.unreadCount > 0 {
                    Circle()
                        .fill(PulseColors.textPrimary)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - ChatThreadView

struct ChatThreadView: View {
    let contactName: String
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var showShareSheet = false
    @State private var sharedMessages: [SharedMessage] = []
    @State private var showPhotoPicker = false
    @State private var messages: [ChatMessage] = sampleMessages

    struct SharedMessage: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let detail: String
        var healthScore: Int? = nil
        var scoreLabel: String? = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            encryptionBanner

            ScrollView {
                LazyVStack(spacing: 0) {
                    dayHeader("Today")
                    ForEach(messages) { msg in
                        if msg.sharedCard != nil {
                            sharedCardBubble(msg)
                        } else {
                            messageBubble(msg)
                        }
                    }
                    ForEach(sharedMessages) { shared in
                        sharedItemBubble(shared)
                    }
                }
                .padding(.vertical, 12)
            }

            inputBar
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text(String(contactName.prefix(1)).uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PulseColors.textPrimary)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(contactName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                        Text("Active now")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.green)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            ChatSettingsSheet(contactName: contactName)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            ChatShareSheet(onAction: { action in
                handleShareAction(action)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var encryptionBanner: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                Text("End-to-end encrypted")
                    .font(PulseFont.body(13))
            }
            .foregroundStyle(PulseColors.textMuted)
            Spacer()
            Button { showSettings = true } label: {
                Text("Settings")
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PulseColors.fillSubtle.opacity(0.5))
    }

    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(PulseFont.body(13))
            .foregroundStyle(PulseColors.textMuted)
            .padding(.vertical, 8)
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.isSent { Spacer(minLength: 60) }
            Text(msg.text)
                .font(.system(size: 16))
                .foregroundStyle(msg.isSent ? .white : PulseColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(msg.isSent ? Color.black : PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !msg.isSent { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func sharedCardBubble(_ msg: ChatMessage) -> some View {
        HStack {
            Spacer(minLength: 80)
            if let card = msg.sharedCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.5)
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.headline)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(PulseColors.textPrimary)
                            Text(card.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(PulseColors.textMuted)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func sharedItemBubble(_ shared: SharedMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: shared.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shared.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(shared.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let score = shared.healthScore {
                        VStack(spacing: 2) {
                            Text("\(score)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor(score))
                            Text(shared.scoreLabel ?? "")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(scoreColor(score).opacity(0.8))
                        }
                        .frame(width: 44)
                    }
                }
                .padding(12)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return Color.green }
        if score >= 60 { return Color.yellow }
        if score >= 40 { return Color.orange }
        return Color.red
    }

    private func handleShareAction(_ action: ChatShareSheet.ShareAction) {
        switch action {
        case .photo:
            sharedMessages.append(SharedMessage(icon: "photo.fill", label: "Photo shared", detail: "1 photo from library"))
        case .camera:
            sharedMessages.append(SharedMessage(icon: "camera.fill", label: "Photo captured", detail: "Just now"))
        case .task(let text):
            sharedMessages.append(SharedMessage(icon: "checkmark.square.fill", label: text, detail: "Shared task"))
        case .healthStat:
            sharedMessages.append(SharedMessage(icon: "heart.fill", label: "Today's stats", detail: "HR 68 · 8,240 steps · HRV 42ms"))
        case .event(let text):
            sharedMessages.append(SharedMessage(icon: "calendar", label: text, detail: "Event shared"))
        case .location:
            sharedMessages.append(SharedMessage(icon: "location.fill", label: "Current location", detail: "Shared just now"))
        case .protocol_(let text):
            sharedMessages.append(SharedMessage(icon: "pills.fill", label: text, detail: "Protocol item shared"))
        case .sleep(let text):
            sharedMessages.append(SharedMessage(icon: "moon.fill", label: text, detail: "Sleep data shared"))
        case .mood(let text):
            sharedMessages.append(SharedMessage(icon: "face.smiling", label: text, detail: "Mood shared"))
        case .note(let text):
            sharedMessages.append(SharedMessage(icon: "doc.text", label: text, detail: "Shared note"))
        case .meal(let text):
            sharedMessages.append(SharedMessage(icon: "fork.knife", label: text, detail: "Analyzing health score..."))
            Task { await fetchHealthScore(for: text, type: "meal", icon: "fork.knife") }
        case .beverage(let text):
            sharedMessages.append(SharedMessage(icon: "cup.and.saucer.fill", label: text, detail: "Analyzing health score..."))
            Task { await fetchHealthScore(for: text, type: "beverage", icon: "cup.and.saucer.fill") }
        case .workout(let text):
            sharedMessages.append(SharedMessage(icon: "figure.run", label: text, detail: "Workout shared"))
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        messages.append(ChatMessage(text: trimmed, isSent: true, time: f.string(from: Date())))
        inputText = ""
        HapticService.impact(.light)
    }

    private func fetchHealthScore(for item: String, type: String, icon: String) async {
        if let result = await AIService.shared.rateHealthScore(item: item, type: type) {
            await MainActor.run {
                if let index = sharedMessages.lastIndex(where: { $0.icon == icon && $0.label == item }) {
                    sharedMessages[index] = SharedMessage(
                        icon: icon,
                        label: item,
                        detail: result.breakdown,
                        healthScore: result.score,
                        scoreLabel: result.label
                    )
                }
            }
        } else {
            await MainActor.run {
                if let index = sharedMessages.lastIndex(where: { $0.icon == icon && $0.label == item }) {
                    sharedMessages[index] = SharedMessage(
                        icon: icon,
                        label: item,
                        detail: "Shared \(type)"
                    )
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button { showShareSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
            }

            HStack {
                TextField("Message...", text: $inputText)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }

            Button { sendMessage() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(inputText.isEmpty ? PulseColors.textMuted : Color.black)
                    .clipShape(Circle())
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PulseColors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 0.5)
        }
    }
}

// MARK: - ChatSettingsSheet

struct ChatSettingsSheet: View {
    let contactName: String
    @Environment(\.dismiss) private var dismiss
    @State private var disappearingSetting = "24 hours"
    @State private var isMuted = false
    @State private var isEncrypted = true
    @State private var showBlockConfirm = false
    @State private var savedToNotes = false
    @State private var isBlocked = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Text(String(contactName.prefix(1)).uppercased())
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                Text(contactName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("View profile")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseColors.textMuted)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 12) {
                Text("DISAPPEARING MESSAGES")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.5)

                HStack(spacing: 0) {
                    ForEach(["Off", "24 hours", "7 days"], id: \.self) { option in
                        Button { withAnimation { disappearingSetting = option } } label: {
                            Text(option)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(disappearingSetting == option ? PulseColors.textPrimary : PulseColors.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(disappearingSetting == option ? PulseColors.background : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: disappearingSetting == option ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
                        }
                    }
                }
                .padding(3)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                Button { withAnimation { isEncrypted.toggle() } } label: {
                    settingsRow(icon: "lock.fill", title: "End-to-end encrypted", trailing: isEncrypted ? "On" : "Off", color: PulseColors.textPrimary)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)

                Button { withAnimation { isMuted.toggle() } } label: {
                    settingsRow(icon: isMuted ? "bell.slash.fill" : "bell.slash", title: isMuted ? "Unmute notifications" : "Mute notifications", trailing: isMuted ? "Muted" : nil, color: PulseColors.textPrimary)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)

                Button {
                    withAnimation { savedToNotes = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { savedToNotes = false }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        settingsRow(icon: savedToNotes ? "checkmark.circle.fill" : "plus", title: savedToNotes ? "Saved to Notes" : "Save chat to Notes", trailing: nil, color: savedToNotes ? Color.green : PulseColors.textPrimary)
                        if !savedToNotes {
                            Text("AI folds this thread into a note")
                                .font(.system(size: 12))
                                .foregroundStyle(PulseColors.textMuted)
                                .padding(.leading, 54)
                                .padding(.bottom, 12)
                        }
                    }
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)

                Button { showBlockConfirm = true } label: {
                    settingsRow(icon: "nosign", title: isBlocked ? "Unblock" : "Block & clear chat", trailing: nil, color: .red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(PulseColors.background)
        .alert("Block \(contactName)?", isPresented: $showBlockConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(isBlocked ? "Unblock" : "Block", role: .destructive) {
                withAnimation { isBlocked.toggle() }
            }
        } message: {
            Text(isBlocked ? "This will unblock \(contactName)." : "This will clear chat history and block \(contactName). You can unblock later.")
        }
    }

    private func settingsRow(icon: String, title: String, trailing: String?, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(color)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.green)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - ChatShareSheet

struct ChatShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAction: ((ShareAction) -> Void)?

    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \MealLog.loggedAt, order: .reverse) private var meals: [MealLog]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \WorkoutLog.date, order: .reverse) private var workouts: [WorkoutLog]
    @Query(sort: \SleepLog.date, order: .reverse) private var sleepLogs: [SleepLog]
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]

    @State private var activeSection: ShareSection?
    @State private var searchText = ""
    @State private var newItemText = ""

    init(onAction: ((ShareAction) -> Void)? = nil) {
        self.onAction = onAction
    }

    enum ShareAction {
        case photo, camera, task(String), healthStat, event(String), location
        case protocol_(String), sleep(String), mood(String), note(String), meal(String), beverage(String), workout(String)
    }

    enum ShareSection: String, CaseIterable {
        case task, meal, beverage, protocol_, note, workout, sleep, mood
        case photo, camera, healthStat, event, location

        var icon: String {
            switch self {
            case .photo: return "photo.on.rectangle"
            case .camera: return "camera"
            case .task: return "checkmark.square"
            case .healthStat: return "waveform.path.ecg"
            case .protocol_: return "pills.fill"
            case .meal: return "fork.knife"
            case .beverage: return "cup.and.saucer.fill"
            case .sleep: return "moon.fill"
            case .mood: return "face.smiling"
            case .note: return "doc.text"
            case .workout: return "figure.run"
            case .event: return "calendar"
            case .location: return "mappin.circle"
            }
        }

        var label: String {
            switch self {
            case .photo: return "Photo"
            case .camera: return "Camera"
            case .task: return "Task"
            case .healthStat: return "Health stat"
            case .protocol_: return "Protocol"
            case .meal: return "Meal"
            case .beverage: return "Beverage"
            case .sleep: return "Sleep"
            case .mood: return "Mood"
            case .note: return "Note"
            case .workout: return "Workout"
            case .event: return "Event"
            case .location: return "Location"
            }
        }

        var hasSelectable: Bool {
            switch self {
            case .task, .meal, .protocol_, .note, .workout, .sleep, .mood:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let section = activeSection {
                sectionDetailView(section)
            } else {
                gridView
            }
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if activeSection != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { activeSection = nil; searchText = ""; newItemText = "" }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            Text(activeSection?.label ?? "Share")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                ForEach(ShareSection.allCases, id: \.self) { section in
                    shareButton(icon: section.icon, label: section.label) {
                        handleSectionTap(section)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Section Detail

    @ViewBuilder
    private func sectionDetailView(_ section: ShareSection) -> some View {
        VStack(spacing: 0) {
            switch section {
            case .task: taskPickerView
            case .meal: mealPickerView
            case .protocol_: protocolPickerView
            case .note: notePickerView
            case .workout: workoutPickerView
            case .sleep: sleepPickerView
            case .mood: moodPickerView
            case .beverage: newItemInputView(placeholder: "What are you drinking?") { text in
                onAction?(.beverage(text)); dismiss()
            }
            case .event: newItemInputView(placeholder: "What's happening?") { text in
                onAction?(.event(text)); dismiss()
            }
            default: EmptyView()
            }
        }
    }

    // MARK: - Task Picker

    private var taskPickerView: some View {
        let filtered = tasks.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
        return itemListView(
            searchPlaceholder: "Search tasks...",
            items: Array(filtered.prefix(20)),
            emptyText: "No tasks yet",
            newItemPlaceholder: "Create new task..."
        ) { task in
            selectableRow(icon: "checkmark.square", title: task.title, subtitle: task.group, chipText: task.label) {
                onAction?(.task(task.title)); dismiss()
            }
        } onNew: { text in
            onAction?(.task(text)); dismiss()
        }
    }

    // MARK: - Meal Picker

    private var mealPickerView: some View {
        let filtered = meals.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
        return itemListView(
            searchPlaceholder: "Search meals...",
            items: Array(filtered.prefix(20)),
            emptyText: "No meals logged",
            newItemPlaceholder: "Describe a meal (e.g. Chipotle bowl)..."
        ) { meal in
            selectableRow(icon: "fork.knife", title: meal.name, subtitle: "\(meal.calories) kcal", chipText: nil) {
                onAction?(.meal(meal.name)); dismiss()
            }
        } onNew: { text in
            onAction?(.meal(text)); dismiss()
        }
    }

    // MARK: - Protocol Picker

    private var protocolPickerView: some View {
        let filtered = medications.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
        return itemListView(
            searchPlaceholder: "Search protocol...",
            items: Array(filtered.prefix(20)),
            emptyText: "No supplements added",
            newItemPlaceholder: nil
        ) { med in
            selectableRow(icon: "pills.fill", title: med.name, subtitle: med.dose, chipText: med.timing) {
                onAction?(.protocol_("\(med.name) \(med.dose)")); dismiss()
            }
        } onNew: { _ in }
    }

    // MARK: - Note Picker

    private var notePickerView: some View {
        let filtered = notes.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
        return itemListView(
            searchPlaceholder: "Search notes...",
            items: Array(filtered.prefix(20)),
            emptyText: "No notes yet",
            newItemPlaceholder: "Write a quick note..."
        ) { note in
            selectableRow(icon: "doc.text", title: note.title, subtitle: note.aiSummary ?? "", chipText: nil) {
                onAction?(.note(note.title)); dismiss()
            }
        } onNew: { text in
            onAction?(.note(text)); dismiss()
        }
    }

    // MARK: - Workout Picker

    private var workoutPickerView: some View {
        let filtered = workouts.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
        return itemListView(
            searchPlaceholder: "Search workouts...",
            items: Array(filtered.prefix(20)),
            emptyText: "No workouts logged",
            newItemPlaceholder: "Describe your workout..."
        ) { workout in
            selectableRow(icon: "figure.run", title: workout.name, subtitle: "\(workout.durationMinutes) min", chipText: nil) {
                onAction?(.workout(workout.name)); dismiss()
            }
        } onNew: { text in
            onAction?(.workout(text)); dismiss()
        }
    }

    // MARK: - Sleep Picker

    private var sleepPickerView: some View {
        let filtered = sleepLogs.prefix(10)
        return itemListView(
            searchPlaceholder: nil,
            items: Array(filtered),
            emptyText: "No sleep logs",
            newItemPlaceholder: "Describe how you slept..."
        ) { log in
            let hours = Calendar.current.dateComponents([.hour, .minute], from: log.bedtime, to: log.wakeTime)
            let dur = "\(hours.hour ?? 0)h \(hours.minute ?? 0)m"
            selectableRow(icon: "moon.fill", title: dur, subtitle: log.date.formatted(date: .abbreviated, time: .omitted), chipText: "Quality: \(log.quality)/5") {
                onAction?(.sleep("Slept \(dur), quality \(log.quality)/5")); dismiss()
            }
        } onNew: { text in
            onAction?(.sleep(text)); dismiss()
        }
    }

    // MARK: - Mood Picker

    private var moodPickerView: some View {
        let filtered = moods.prefix(10)
        let moodLabels = ["", "Low", "Down", "Okay", "Good", "Great"]
        return itemListView(
            searchPlaceholder: nil,
            items: Array(filtered),
            emptyText: "No mood entries",
            newItemPlaceholder: "How are you feeling?..."
        ) { entry in
            let label = entry.mood >= 1 && entry.mood <= 5 ? moodLabels[entry.mood] : "Okay"
            selectableRow(icon: "face.smiling", title: "\(label) · Mood \(entry.mood)/5", subtitle: entry.date.formatted(date: .abbreviated, time: .shortened), chipText: entry.notes) {
                onAction?(.mood("Mood \(entry.mood)/5 (\(label)), Energy \(entry.energy)/5\(entry.notes != nil ? " – \(entry.notes!)" : "")")); dismiss()
            }
        } onNew: { text in
            onAction?(.mood(text)); dismiss()
        }
    }

    // MARK: - Generic Item List

    private func itemListView<T: Identifiable>(
        searchPlaceholder: String?,
        items: [T],
        emptyText: String,
        newItemPlaceholder: String?,
        @ViewBuilder rowBuilder: @escaping (T) -> some View,
        onNew: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            if let placeholder = searchPlaceholder {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                    TextField(placeholder, text: $searchText)
                        .font(.system(size: 15))
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let newPlaceholder = newItemPlaceholder {
                        newItemRow(placeholder: newPlaceholder, onNew: onNew)
                    }

                    if items.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(items) { item in
                            rowBuilder(item)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - New Item Row

    private func newItemRow(placeholder: String, onNew: @escaping (String) -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.primary.opacity(0.5))
            TextField(placeholder, text: $newItemText)
                .font(.system(size: 15))
                .submitLabel(.send)
                .onSubmit {
                    guard !newItemText.isEmpty else { return }
                    onNew(newItemText)
                }
            if !newItemText.isEmpty {
                Button {
                    onNew(newItemText)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - New Item Input (simple)

    private func newItemInputView(placeholder: String, onSend: @escaping (String) -> Void) -> some View {
        VStack(spacing: 14) {
            TextField(placeholder, text: $newItemText)
                .font(.system(size: 15))
                .padding(14)
                .background(Color(UIColor.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                guard !newItemText.isEmpty else { return }
                onSend(newItemText)
            } label: {
                Text("Send")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(newItemText.isEmpty ? Color.secondary : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(newItemText.isEmpty)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Selectable Row

    private func selectableRow(icon: String, title: String, subtitle: String, chipText: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let chip = chipText, !chip.isEmpty {
                    Text(chip)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid Button

    private func shareButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 64, height: 64)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func handleSectionTap(_ section: ShareSection) {
        switch section {
        case .photo:
            onAction?(.photo); dismiss()
        case .camera:
            onAction?(.camera); dismiss()
        case .healthStat:
            onAction?(.healthStat); dismiss()
        case .location:
            onAction?(.location); dismiss()
        default:
            withAnimation(.easeInOut(duration: 0.2)) { activeSection = section }
        }
    }
}

#Preview {
    NavigationStack {
        MessengerView()
    }
}
