import SwiftUI
import SwiftData

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \MealLog.loggedAt, order: .reverse) private var meals: [MealLog]
    @Query(sort: \AIMemory.createdAt, order: .reverse) private var memories: [AIMemory]
    @Query private var profiles: [UserProfile]

    var onNavigate: ((AppRoute) -> Void)?
    var onSwitchTab: ((MainTab) -> Void)?

    @State private var inputText = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var isStreaming = false
    @State private var streamingText = ""
    @State private var showVoiceCapture = false
    @State private var showPersonalityPicker = false
    @FocusState private var inputFocused: Bool
    private var settingsStore: CoachSettingsStore { CoachSettingsStore.shared }

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: String
        let content: String
        let timestamp: Date
        var parsedItems: [ParsedItem]?
        var followUpChips: [String]?
    }

    var body: some View {
        NavigationStack {
            if !settingsStore.settings.hasCompletedOnboarding {
                commandPaletteOnboarding
            } else {
                mainChatBody
            }
        }
    }

    private var mainChatBody: some View {
        VStack(spacing: 0) {
            aiHeader
            chatArea
            if chatMessages.isEmpty && !isStreaming {
                Spacer()
                suggestionsArea
            }
            composerBar
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
        }
        .sheet(isPresented: $showVoiceCapture) {
            VoiceCaptureView(onSaved: { route in
                dismiss()
                onNavigate?(route)
            })
        }
        .sheet(isPresented: $showPersonalityPicker) {
            CoachPersonalityPicker(settingsStore: CoachSettingsStore.shared)
        }
        .onAppear { inputFocused = true }
    }

    // MARK: - AI Header

    private var userName: String { profiles.first?.name ?? "there" }

    private var randomGreeting: String {
        let greetings = [
            "What's on your mind?",
            "How can I help?",
            "Let's get things done.",
            "Ready when you are.",
            "What's next?",
            "I'm all ears.",
            "Fire away.",
        ]
        return greetings[Int.random(in: 0..<greetings.count)]
    }

    private var aiHeader: some View {
        HStack(spacing: 12) {
            if let data = profiles.first?.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PulseColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(String(userName.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hey, \(userName)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(randomGreeting)
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Button { showPersonalityPicker = true } label: {
                Image(systemName: CoachSettingsStore.shared.settings.personality.iconSystemName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 0.5)
        }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatMessages) { msg in
                        chatBubble(msg)
                            .id(msg.id)
                    }
                    if isStreaming {
                        streamingBubble
                            .id("streaming")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: chatMessages.count) {
                if let last = chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: streamingText) {
                withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
            }
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(message.role == "user" ? .white : PulseColors.textPrimary)
                    .lineSpacing(3)

                if let items = message.parsedItems, !items.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            miniParsedRow(item)
                        }
                        Button { saveItems(items) } label: {
                            Text("Confirm & Save")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.top, 4)
                }

                if let chips = message.followUpChips, !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(chips, id: \.self) { chip in
                                Button { inputText = chip; sendMessage() } label: {
                                    Text(chip)
                                        .font(PulseFont.bodyMedium(12))
                                        .foregroundStyle(PulseColors.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(PulseColors.background)
                                        .clipShape(Capsule())
                                        .overlay { Capsule().stroke(PulseColors.borderStrong, lineWidth: 1) }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .background(message.role == "user" ? Color.black : PulseColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if message.role != "user" {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            }
            if message.role != "user" { Spacer(minLength: 60) }
        }
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if streamingText.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(PulseColors.accent)
                        Text("Thinking…")
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                } else {
                    Text(streamingText)
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textPrimary)
                        .lineSpacing(3)
                }
            }
            .padding(14)
            .background(PulseColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
            Spacer(minLength: 60)
        }
    }

    private func miniParsedRow(_ item: ParsedItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.emoji.isEmpty ? "circle.fill" : item.emoji)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(PulseFont.bodySemibold(12))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(item.category)
                    .font(PulseFont.body(10))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(PulseColors.success)
        }
        .padding(8)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Suggestions

    private var suggestionsArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    suggestionChip("Log my morning stack", icon: "pill.fill")
                    suggestionChip("What should I take next?", icon: "brain.head.profile")
                    suggestionChip("How did I sleep?", icon: "moon.fill")
                    suggestionChip("Summarize my day", icon: "doc.text")
                    suggestionChip("How's my health?", icon: "heart.fill")
                    suggestionChip("Create a task", icon: "checkmark.circle")
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 12)
    }

    private func suggestionChip(_ text: String, icon: String) -> some View {
        Button { inputText = text; sendMessage() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(PulseColors.textPrimary)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PulseColors.background)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(PulseColors.borderStrong, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Composer

    private var composerBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 0.5)
            HStack(spacing: 10) {
                TextField("Ask AI anything…", text: $inputText)
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textPrimary)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if inputText.isEmpty {
                    Button { showVoiceCapture = true } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                            .frame(width: 34, height: 34)
                            .background(PulseColors.fillSubtle)
                            .clipShape(Circle())
                    }
                } else {
                    Button { sendMessage() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(canSend ? .white : PulseColors.textFaint)
                            .frame(width: 34, height: 34)
                            .background(canSend ? Color.black : PulseColors.fillSubtle)
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isStreaming
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""

        let userMsg = ChatMessage(role: "user", content: text, timestamp: Date())
        chatMessages.append(userMsg)

        Task { await handleChat(text) }
    }

    private func handleChat(_ text: String) async {
        let lowerText = text.lowercased()

        // Detect if this is a logging intent (require stronger signals)
        let logKeywords = ["took", "logged", "ate", "drank", "morning stack", "my stack", "log my", "i had"]
        let isLoggingIntent = logKeywords.contains(where: { lowerText.contains($0) })
            && !lowerText.hasPrefix("how")
            && !lowerText.hasPrefix("what")
            && !lowerText.hasPrefix("why")
            && !lowerText.hasPrefix("when")
            && !lowerText.hasPrefix("update")
            && !lowerText.hasPrefix("show")
            && !lowerText.hasPrefix("tell")
        if isLoggingIntent {
            await handleQuickLog(text)
            return
        }

        // Detect task/note creation intent  -  execute immediately
        if let result = detectAndExecuteAction(text) {
            chatMessages.append(ChatMessage(role: "assistant", content: result, timestamp: Date()))
            return
        }

        // Detect search intent
        let searchKeywords = ["search", "find", "look up", "look for", "where is", "show me"]
        if searchKeywords.contains(where: { lowerText.hasPrefix($0) }) {
            let query = text
                .replacingOccurrences(of: "search for ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "search ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "find ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "look up ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "look for ", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            await handleSearch(query.isEmpty ? text : query)
            return
        }

        isStreaming = true
        streamingText = ""

        let context = buildUserContext()
        var history: [AIService.Message] = chatMessages.dropLast().map {
            AIService.Message(role: $0.role, content: $0.content)
        }
        history.append(AIService.Message(role: "user", content: text))

        do {
            let stream = AIService.shared.chat(messages: history, userContext: context)
            for try await chunk in stream {
                streamingText += chunk
            }
            let finalText = streamingText
            let suggestions = generateFollowUps(userText: text, aiResponse: finalText)
            chatMessages.append(ChatMessage(role: "assistant", content: finalText, timestamp: Date(), followUpChips: suggestions))

            // Background: silently extract memories (no visible UI, just learning)
            Task {
                let existingMemories = self.memories.map(\.content)

                let newMemories = await AIService.shared.extractMemories(
                    userMessage: text,
                    aiResponse: finalText,
                    existingMemories: existingMemories
                )
                for mem in newMemories {
                    let category = MemoryCategory(rawValue: mem.category) ?? .fact
                    let memory = AIMemory(content: mem.content, category: category, importance: mem.importance)
                    modelContext.insert(memory)
                }

                modelContext.insert(AIConversationLog(userMessage: text, aiResponse: finalText))

                if !newMemories.isEmpty {
                    try? modelContext.save()
                }
            }
        } catch {
            let errorMsg = "I couldn't reach my AI brain right now. Try again in a moment."
            chatMessages.append(ChatMessage(role: "assistant", content: errorMsg, timestamp: Date()))
        }

        isStreaming = false
        streamingText = ""
    }

    private func handleQuickLog(_ text: String) async {
        isStreaming = true
        streamingText = "Parsing your input…"

        let items = await parseInputToItems(text)

        isStreaming = false
        streamingText = ""

        if items.isEmpty {
            chatMessages.append(ChatMessage(
                role: "assistant",
                content: "I couldn't identify any items to log. Try being more specific, like \"took 5mg creatine\" or \"had a chicken salad\".",
                timestamp: Date()
            ))
        } else {
            let summary = items.map { "\($0.emoji) \($0.title)" }.joined(separator: "\n")
            chatMessages.append(ChatMessage(
                role: "assistant",
                content: "I found \(items.count) item\(items.count == 1 ? "" : "s") to log:\n\n\(summary)\n\nConfirm to save these to your tracker.",
                timestamp: Date(),
                parsedItems: items
            ))
        }
    }

    private func handleSearch(_ text: String) async {
        isStreaming = true
        streamingText = "Searching…"

        let context = AIService.SearchContext(
            medications: medications.map(\.name),
            noteTitles: notes.prefix(20).map(\.title),
            tasks: tasks.prefix(20).map(\.title),
            recentMeals: meals.prefix(10).map(\.name)
        )

        let results = await AIService.shared.smartSearch(query: text, context: context)

        isStreaming = false
        streamingText = ""

        if results.isEmpty {
            chatMessages.append(ChatMessage(
                role: "assistant",
                content: "No results found for \"\(text)\". Try a different search term.",
                timestamp: Date()
            ))
        } else {
            let resultText = results.map { "• **\($0.title)**  -  \($0.subtitle)" }.joined(separator: "\n")
            chatMessages.append(ChatMessage(
                role: "assistant",
                content: "Here's what I found:\n\n\(resultText)",
                timestamp: Date()
            ))
        }
    }

    // MARK: - Parsing Logic

    private func parseInputToItems(_ text: String) async -> [ParsedItem] {
        let lower = text.lowercased()

        // "Morning stack" shortcut
        if lower.contains("morning stack") || lower.contains("my stack") {
            let amMeds = medications.filter { $0.timing == "AM" && $0.isActive }
            return amMeds.map { med in
                let info = SupplementKnowledge.find(med.name)
                return ParsedItem(
                    title: "\(med.name)  -  \(med.dose)",
                    category: med.category.rawValue.capitalized,
                    emoji: med.emoji,
                    benefit: info?.benefit ?? med.benefit,
                    knowledgeMatch: info
                )
            }
        }

        // Try AI parsing first
        let knownMeds = medications.map(\.name)
        let aiResults = await AIService.shared.parseNaturalLanguage(input: text, knownMedications: knownMeds)

        if !aiResults.isEmpty {
            return aiResults.map { result in
                let info = SupplementKnowledge.find(result.title) ?? SupplementKnowledge.fuzzyMatch(result.title).first
                return ParsedItem(
                    title: result.dose != nil ? "\(result.title)  -  \(result.dose!)" : result.title,
                    category: result.category.capitalized,
                    emoji: result.emoji,
                    benefit: result.benefit,
                    knowledgeMatch: info
                )
            }
        }

        // Fallback to local parsing
        return await localParse(text)
    }

    private func localParse(_ text: String) async -> [ParsedItem] {
        let lower = text.lowercased()
        let separators = CharacterSet(charactersIn: ",\n")
        let segments = lower.components(separatedBy: separators)
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var items: [ParsedItem] = []

        for segment in segments {
            let cleaned = segment
                .replacingOccurrences(of: "i took ", with: "")
                .replacingOccurrences(of: "i had ", with: "")
                .replacingOccurrences(of: "took ", with: "")
                .replacingOccurrences(of: "had ", with: "")
                .replacingOccurrences(of: "logged ", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Check supplement knowledge base first
            let matches = SupplementKnowledge.fuzzyMatch(cleaned)
            if let best = matches.first {
                items.append(ParsedItem(
                    title: "\(best.name)  -  \(best.defaultDose)",
                    category: best.category.capitalized,
                    emoji: best.emoji,
                    benefit: best.benefit,
                    knowledgeMatch: best
                ))
                continue
            }

            // Check medication knowledge base
            if let medInfo = MedicationKnowledge.find(cleaned) ?? MedicationKnowledge.fuzzyMatch(cleaned).first {
                items.append(ParsedItem(
                    title: "\(medInfo.name)  -  \(medInfo.defaultDose)",
                    category: medInfo.category.capitalized,
                    emoji: "pills.fill",
                    benefit: medInfo.benefit,
                    knowledgeMatch: nil
                ))
                continue
            }

            // Check if it matches a user's existing medication
            if let existingMed = medications.first(where: { $0.name.lowercased().contains(cleaned) || cleaned.contains($0.name.lowercased()) }) {
                items.append(ParsedItem(
                    title: "\(existingMed.name)  -  \(existingMed.dose)",
                    category: existingMed.category.rawValue.capitalized,
                    emoji: existingMed.emoji,
                    benefit: existingMed.benefit,
                    knowledgeMatch: nil
                ))
                continue
            }

            // Check peptide knowledge base
            if let peptideInfo = PeptideKnowledge.find(cleaned) {
                items.append(ParsedItem(
                    title: "\(peptideInfo.name)  -  \(peptideInfo.defaultDose)",
                    category: "Peptide",
                    emoji: "syringe.fill",
                    benefit: peptideInfo.benefit,
                    knowledgeMatch: nil
                ))
                continue
            }

            // Try product search as last resort
            let results = await ProductSearchService.search(query: cleaned)
            if let best = results.first {
                items.append(ParsedItem(
                    title: "\(best.info.name)  -  \(best.info.defaultDose)",
                    category: best.info.category.capitalized,
                    emoji: best.info.emoji,
                    benefit: best.info.benefit,
                    knowledgeMatch: best.info
                ))
            }
            // If nothing matches, skip it — don't create garbage entries
        }

        return items
    }

    // MARK: - Save

    private func saveItems(_ items: [ParsedItem]) {
        for item in items {
            switch item.category.lowercased() {
            case "supplement", "vitamin", "medication", "peptide":
                let searchName = item.title.components(separatedBy: "  - ").first ?? item.title
                let descriptor = FetchDescriptor<Medication>()
                if let meds = try? modelContext.fetch(descriptor),
                   let med = meds.first(where: { $0.name.localizedCaseInsensitiveContains(searchName) }) {
                    modelContext.insert(MedicationLog(medicationId: med.id, status: .taken))
                } else if let info = item.knowledgeMatch {
                    let cat = MedicationCategory(rawValue: info.category) ?? .supplement
                    let newMed = Medication(
                        name: info.name, dose: info.defaultDose, category: cat,
                        emoji: info.emoji, timing: info.timing,
                        benefit: info.benefit, mechanism: info.mechanism,
                        interactionNotes: info.interactionNotes,
                        bestTimeReason: info.bestTimeReason, stackNotes: info.stackNotes
                    )
                    modelContext.insert(newMed)
                    modelContext.insert(MedicationLog(medicationId: newMed.id, status: .taken))
                }
            case "meal":
                let mealInfo = SupplementKnowledge.estimateMeal(item.title)
                modelContext.insert(MealLog(
                    name: item.title,
                    description_: mealInfo?.supplementNote ?? "",
                    emoji: item.emoji,
                    calories: mealInfo?.estimatedCalories ?? 0,
                    proteinG: mealInfo?.estimatedProtein,
                    carbsG: mealInfo?.estimatedCarbs,
                    fatG: mealInfo?.estimatedFat
                ))
            case "task":
                modelContext.insert(TaskItem(title: item.title, status: .todo, group: "Today"))
            default:
                let note = Note(title: item.title)
                modelContext.insert(note)
            }
        }
        try? modelContext.save()

        chatMessages.append(ChatMessage(
            role: "assistant",
            content: "Done! \(items.count) item\(items.count == 1 ? "" : "s") saved to your tracker. ✓",
            timestamp: Date()
        ))
    }

    // MARK: - Context Builder

    private func buildUserContext() -> AIService.UserContext {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeStr = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"

        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayMeals = meals.filter { $0.loggedAt >= todayStart }
        let calories = todayMeals.reduce(0) { $0 + $1.calories }

        let protocolItems = medications.filter { $0.isActive }.map { med in
            AIService.ProtocolItem(
                name: med.name,
                dose: med.dose,
                category: med.category.rawValue,
                timing: med.timing,
                benefit: med.benefit,
                mechanism: med.mechanism
            )
        }

        let descriptor = FetchDescriptor<MedicationLog>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        let allLogs = (try? modelContext.fetch(descriptor)) ?? []
        let todayLogs = allLogs.filter { $0.loggedAt >= todayStart }
        let loggedIds = Set(todayLogs.map(\.medicationId))

        let takenMeds = medications.filter { loggedIds.contains($0.id) }.map(\.name)
        let missedMeds = medications.filter { $0.isActive && !loggedIds.contains($0.id) }.map(\.name)

        return AIService.UserContext(
            name: "Rey",
            timeOfDay: timeStr,
            currentHour: hour,
            medicationsDue: medications.filter { $0.isActive }.map(\.name),
            protocolDetails: protocolItems,
            pendingTasks: tasks.filter { $0.statusRaw == "todo" }.prefix(5).map(\.title),
            recentMeals: todayMeals.prefix(3).map(\.name),
            caloriesToday: calories,
            streakDays: 7,
            todayMedsTaken: takenMeds,
            todayMedsMissed: missedMeds,
            memories: memories.sorted { $0.importance > $1.importance }.prefix(15).map { "[\($0.category.rawValue)] \($0.content)" },
            personalityModifier: settingsStore.settings.personality.promptModifier,
            primaryGoal: settingsStore.settings.primaryGoal
        )
    }

    private func generateFollowUps(userText: String, aiResponse: String) -> [String] {
        let lower = userText.lowercased()
        let responseLower = aiResponse.lowercased()

        if lower.contains("sleep") {
            return ["What affects my sleep quality?", "Show my sleep trends", "Tips to improve it?"]
        }
        if lower.contains("protocol") || lower.contains("stack") || lower.contains("supplement") {
            return ["Any interactions I should know?", "Best timing for my stack?", "What am I missing?"]
        }
        if lower.contains("heart") || lower.contains("hr") {
            return ["Show my HR trend this week", "What's my resting HR?", "Is this normal for me?"]
        }
        if lower.contains("stress") || lower.contains("anxiety") {
            return ["Guide me through breathing", "What helps reduce stress?", "How's my recovery?"]
        }
        if lower.contains("workout") || lower.contains("exercise") || lower.contains("fitness") {
            return ["Am I recovered enough?", "Suggest today's workout", "Show my activity trend"]
        }
        if lower.contains("meal") || lower.contains("food") || lower.contains("eat") || lower.contains("diet") {
            return ["How are my macros today?", "Suggest a healthy meal", "Show calorie trend"]
        }
        if responseLower.contains("remaining") || responseLower.contains("consider taking") || responseLower.contains("missed") {
            return ["What should I take next?", "Remind me later", "Show my full protocol"]
        }
        if responseLower.contains("goal") || responseLower.contains("progress") {
            return ["How am I tracking?", "What should I prioritize?", "Adjust my targets"]
        }
        return ["Tell me more", "What should I focus on?", "Any insights from my data?"]
    }

    /// Detects explicit task/note/reminder creation intent and executes immediately.
    /// Returns a confirmation string if action was taken, nil otherwise.
    private func detectAndExecuteAction(_ text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        // Task creation patterns
        let taskPatterns = ["create a task", "add a task", "new task", "remind me to", "reminder to", "add to my tasks", "todo:", "task:"]
        if let pattern = taskPatterns.first(where: { lower.contains($0) }) {
            let title = text
                .replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let cleanTitle = title.isEmpty ? text : title
            let finalTitle = cleanTitle.prefix(1).uppercased() + cleanTitle.dropFirst()
            modelContext.insert(TaskItem(title: String(finalTitle), status: .todo, group: "Today"))
            try? modelContext.save()
            return "Done  -  added \"\(finalTitle)\" to your tasks. ✓"
        }

        // Note creation patterns
        let notePatterns = ["create a note", "add a note", "new note", "write a note", "note about", "note:"]
        if let pattern = notePatterns.first(where: { lower.contains($0) }) {
            let title = text
                .replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let cleanTitle = title.isEmpty ? "Untitled" : String(title.prefix(1).uppercased() + title.dropFirst())
            let note = Note(title: cleanTitle)
            modelContext.insert(note)
            try? modelContext.save()
            return "Done  -  created note \"\(cleanTitle)\". ✓"
        }

        return nil
    }

    // MARK: - Onboarding

    @State private var onboardingStep = 0

    private var commandPaletteOnboarding: some View {
        VStack(spacing: 0) {
            if onboardingStep == 0 {
                onboardingWelcome
            } else if onboardingStep == 1 {
                onboardingGoals
            } else {
                onboardingPersonality
            }
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
        }
    }

    private var onboardingWelcome: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("PulseLoop AI")
                    .font(PulseFont.title(24))
                    .foregroundStyle(PulseColors.textPrimary)
            }

            Text("Your personal health intelligence.\nAsk anything, get insights, take action.")
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 14) {
                onboardingCapRow(icon: "brain.head.profile", text: "Understands your protocol & health data")
                onboardingCapRow(icon: "waveform.path.ecg", text: "Tracks patterns across sleep, HR, and activity")
                onboardingCapRow(icon: "lightbulb.fill", text: "Gives personalized, contextual suggestions")
                onboardingCapRow(icon: "mic.fill", text: "Supports voice input and natural language")
            }
            .padding(.horizontal, 30)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { onboardingStep = 1 }
            } label: {
                Text("Continue")
                    .font(PulseFont.bodySemibold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func onboardingCapRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 36, height: 36)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
        }
    }

    private var onboardingGoals: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 50)

            Image(systemName: "target")
                .font(.system(size: 28))
                .foregroundStyle(PulseColors.textPrimary)

            Text("What's your primary goal?")
                .font(PulseFont.title(20))
                .foregroundStyle(PulseColors.textPrimary)

            Text("This helps personalize your experience.")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)

            VStack(spacing: 8) {
                goalCard("Build strength & fitness", key: "fitness", icon: "figure.run")
                goalCard("Sleep better & recover", key: "sleep", icon: "moon.fill")
                goalCard("Reduce stress & find balance", key: "stress", icon: "leaf.fill")
                goalCard("Optimize my supplement protocol", key: "protocol", icon: "pills.fill")
                goalCard("General health & longevity", key: "longevity", icon: "heart.fill")
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func goalCard(_ label: String, key: String, icon: String) -> some View {
        Button {
            CoachSettingsStore.shared.settings.primaryGoal = key
            withAnimation(.easeInOut(duration: 0.25)) { onboardingStep = 2 }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(PulseColors.textMuted)
                    .frame(width: 32, height: 32)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(label)
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PulseColors.textFaint)
            }
            .padding(14)
            .background(PulseColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var onboardingPersonality: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 50)

            Text("Choose your AI style")
                .font(PulseFont.title(20))
                .foregroundStyle(PulseColors.textPrimary)

            Text("You can change this anytime.")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textMuted)

            VStack(spacing: 10) {
                ForEach(Array(CoachPersonality.allCases), id: \.self) { p in
                    Button {
                        CoachSettingsStore.shared.settings.personality = p
                        CoachSettingsStore.shared.settings.hasCompletedOnboarding = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.iconSystemName)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.label)
                                    .font(PulseFont.bodySemibold(14))
                                    .foregroundStyle(PulseColors.textPrimary)
                                Text(p.traits.joined(separator: " · "))
                                    .font(PulseFont.body(11))
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PulseColors.textFaint)
                        }
                        .padding(14)
                        .background(PulseColors.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PulseColors.borderHairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }
}

// MARK: - Supporting Types

struct ParsedItem: Identifiable {
    let id = UUID()
    let title: String
    let category: String
    let emoji: String
    let benefit: String?
    let knowledgeMatch: SupplementInfo?
}
