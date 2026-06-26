import SwiftUI
import SwiftData

// MARK: - Notes List (Notion-style page list)

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Collection.order) private var collections: [Collection]
    @Binding var path: NavigationPath
    @State private var searchText = ""
    @State private var sortMode: SortMode = .recent
    @State private var showVoiceNote = false
    @State private var selectedCollectionId: UUID?
    @State private var semanticMode = false
    @State private var semanticMatchIds: Set<UUID>?
    @State private var semanticSearching = false

    enum SortMode: String, CaseIterable, CustomStringConvertible {
        case recent = "Recent"
        case alpha = "A–Z"
        var description: String { rawValue }
    }

    private var filteredNotes: [Note] {
        var result = notes
        if let cid = selectedCollectionId {
            result = result.filter { $0.collectionId == cid }
        }
        if !searchText.isEmpty {
            let q = searchText
            if semanticMode, let ids = semanticMatchIds {
                result = result.filter { ids.contains($0.id) }
            } else {
                result = result.filter { note in
                    if note.title.localizedCaseInsensitiveContains(q) { return true }
                    if note.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return true }
                    if let summary = note.aiSummary, summary.localizedCaseInsensitiveContains(q) { return true }
                    return note.blocks.contains { $0.content.localizedCaseInsensitiveContains(q) }
                }
            }
        }
        switch sortMode {
        case .recent:
            return result.sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
        case .alpha:
            return result.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.title.localizedCompare($1.title) == .orderedAscending
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 12) {
                    searchBar
                    if !collections.isEmpty {
                        collectionChips
                    }
                    sortRow
                    notesList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showVoiceNote) {
            VoiceNoteRecorderView(path: $path)
        }
    }

    private var header: some View {
        HStack {
            Text("Notes")
                .font(PulseFont.title(28))
                .foregroundStyle(PulseColors.textPrimary)
            Spacer()
            Button { showVoiceNote = true } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulseColors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .accessibilityLabel("Capture a note by voice or text")
            Button { showVoiceNote = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .accessibilityLabel("New note")
        }
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(PulseColors.textMuted)
            TextField("Search notes…", text: $searchText)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textPrimary)
                .onSubmit { if semanticMode { runSemanticSearch() } }
            if semanticSearching {
                ProgressView().controlSize(.small)
            }
            Button {
                semanticMode.toggle()
                semanticMatchIds = nil
                if semanticMode && !searchText.isEmpty { runSemanticSearch() }
                HapticService.impact(.light)
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(semanticMode ? PulseColors.accent : PulseColors.textFaint)
            }
            .accessibilityLabel(semanticMode ? "Semantic search on" : "Semantic search off")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var collectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                collectionChip(id: nil, emoji: "🗂", name: "All")
                ForEach(collections) { c in
                    collectionChip(id: c.id, emoji: c.emoji, name: c.name)
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityLabel("Filter notes by collection")
    }

    private func collectionChip(id: UUID?, emoji: String, name: String) -> some View {
        let isSelected = selectedCollectionId == id
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedCollectionId = isSelected ? nil : id
            }
            HapticService.impact(.light)
        } label: {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 12))
                Text(name).font(PulseFont.bodyMedium(13))
            }
            .foregroundStyle(isSelected ? .white : PulseColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.black : PulseColors.fillSubtle)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var sortRow: some View {
        HStack(spacing: 10) {
            PillToggle(selection: $sortMode, options: SortMode.allCases)
            Spacer()
            Text("\(filteredNotes.count) notes")
                .font(PulseFont.body(12.5))
                .foregroundStyle(PulseColors.textFaint)
        }
    }

    private var notesList: some View {
        VStack(spacing: 0) {
            if filteredNotes.isEmpty {
                notesEmptyState
            }
            ForEach(filteredNotes) { note in
                Button { path.append(AppRoute.noteEditor(note.id)) } label: {
                    NoteListRow(note: note)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button { togglePin(note) } label: {
                        Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(PulseColors.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteNote(note) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var notesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(PulseColors.textFaint)
            Text(searchText.isEmpty ? "No notes yet" : "No matches")
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textSecondary)
            Text(searchText.isEmpty ? "Tap + to capture your first note by voice or text." : "Try a different search\(semanticMode ? " or turn off semantic mode" : "").")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .accessibilityElement(children: .combine)
    }

    private func togglePin(_ note: Note) {
        note.isPinned.toggle()
        modelContext.saveOrLog("notes")
        HapticService.impact(.light)
    }

    private func createNote() {
        let note = Note(title: "")
        let block = NoteBlock(noteId: note.id, order: 0, kind: .paragraph, content: "")
        modelContext.insert(note)
        modelContext.insert(block)
        modelContext.saveOrLog("notes")
        path.append(AppRoute.noteEditor(note.id))
    }

    private func deleteNote(_ note: Note) {
        modelContext.delete(note)
        modelContext.saveOrLog("notes")
    }

    /// Semantic search: asks AI which notes best match the query by meaning, using a
    /// compact candidate digest (title + summary + first line). Requires an API key.
    private func runSemanticSearch() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, AIService.shared.hasAPIKey else { semanticMatchIds = nil; return }
        let candidates = notes.prefix(60).map { note -> (UUID, String) in
            let firstLine = note.blocks.sorted { $0.order < $1.order }.first?.content ?? ""
            let digest = [note.title, note.aiSummary ?? "", firstLine].filter { !$0.isEmpty }.joined(separator: " — ")
            return (note.id, digest)
        }
        guard !candidates.isEmpty else { return }
        semanticSearching = true
        Task {
            let numbered = candidates.enumerated().map { "\($0.offset): \($0.element.1.prefix(140))" }.joined(separator: "\n")
            let prompt = """
            The user is searching their notes for: "\(q)"
            Return ONLY a JSON array of the indices (numbers) of notes that match the \
            intent, best first, max 15. Example: [3,0,7]

            Notes:
            \(numbered)
            """
            var matched: Set<UUID> = []
            do {
                let response = try await AIService.shared.complete(
                    messages: [AIService.Message(role: "user", content: prompt)],
                    temperature: 0.1,
                    maxTokens: 120
                )
                let cleaned = response.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                if let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]"),
                   let data = String(cleaned[start...end]).data(using: .utf8),
                   let indices = try? JSONSerialization.jsonObject(with: data) as? [Int] {
                    for i in indices where candidates.indices.contains(i) {
                        matched.insert(candidates[i].0)
                    }
                }
            } catch {}
            await MainActor.run {
                semanticMatchIds = matched
                semanticSearching = false
            }
        }
    }
}

struct NoteListRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(PulseColors.accent)
                    }
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(PulseFont.bodyMedium(15))
                        .foregroundStyle(PulseColors.textPrimary)
                        .lineLimit(1)
                }

                if let summary = note.aiSummary, !summary.isEmpty {
                    Text(summary)
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textMuted)
                        .lineLimit(2)
                } else {
                    let preview = note.blocks.sorted(by: { $0.order < $1.order }).prefix(2).map(\.content).joined(separator: " ")
                    if !preview.isEmpty {
                        Text(preview)
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textMuted)
                            .lineLimit(2)
                    }
                }

                if !note.tags.isEmpty {
                    Text(note.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(PulseFont.body(11))
                        .foregroundStyle(PulseColors.textFaint)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(timeAgo(note.updatedAt))
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textFaint)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.isPinned ? "Pinned. " : "")\(note.title.isEmpty ? "Untitled note" : note.title)")
    }

    private func timeAgo(_ date: Date) -> String {
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 1 { return "now" }
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

// MARK: - Note Editor (Notion-style block editor)

struct NoteEditorView: View {
    let noteId: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.order) private var collections: [Collection]
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \TaskItem.order) private var allTasks: [TaskItem]
    @State private var note: Note?
    @State private var blocks: [NoteBlock] = []
    @State private var title = ""
    @State private var showSlashMenu = false
    @State private var slashMenuIndex: Int?
    @State private var focusedBlockId: UUID?
    @State private var isAIGenerating = false
    @State private var showAIMenu = false
    @State private var showAICommandBar = false
    @State private var aiCommand = ""
    @State private var aiStreamingText = ""
    @State private var streamingBlockId: UUID?
    @FocusState private var aiBarFocused: Bool
    @State private var preAIBlockIds: Set<UUID> = []
    @State private var lastAIBlockId: UUID?
    @State private var showAIUndo = false
    @State private var pendingRewrite: String?
    @State private var autoSummaryTask: Task<Void, Never>?
    @State private var showLinkPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                breadcrumb
                    .padding(.bottom, 12)
                titleField
                    .padding(.bottom, 8)

                collectionRow
                    .padding(.bottom, 8)

                if let summary = note?.aiSummary, !summary.isEmpty {
                    aiSummaryCard(summary)
                        .padding(.bottom, 16)
                }

                blocksEditor
                    .padding(.bottom, 16)

                linkedTaskSection
                    .padding(.bottom, 16)

                linkedReferencesSection
                    .padding(.bottom, 16)

                newBlockHint
                editorFooter
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(PulseColors.background)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if showAICommandBar {
                    aiCommandBar
                }
                toolbar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Notes")
                    .font(PulseFont.bodyMedium(15))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { togglePinCurrent() } label: {
                    Image(systemName: (note?.isPinned ?? false) ? "pin.fill" : "pin")
                        .font(.system(size: 16))
                        .foregroundStyle((note?.isPinned ?? false) ? PulseColors.accent : PulseColors.textSecondary)
                }
                .accessibilityLabel((note?.isPinned ?? false) ? "Unpin note" : "Pin note")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { addBlock(.heading) } label: { Label("Heading", systemImage: "textformat.size.larger") }
                    Button { addBlock(.paragraph) } label: { Label("Text", systemImage: "text.alignleft") }
                    Button { addBlock(.todo) } label: { Label("To-do", systemImage: "checkmark.square") }
                    Button { addBlock(.bulletList) } label: { Label("Bullet list", systemImage: "list.bullet") }
                    Button { addBlock(.numberedList) } label: { Label("Numbered list", systemImage: "list.number") }
                    Button { addBlock(.quote) } label: { Label("Quote", systemImage: "text.quote") }
                    Button { addBlock(.callout) } label: { Label("Callout", systemImage: "lightbulb") }
                    Button { addBlock(.divider) } label: { Label("Divider", systemImage: "minus") }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
        .onAppear { loadNote() }
        .onDisappear { autoSummaryTask?.cancel(); saveNote() }
        .sheet(isPresented: $showSlashMenu) {
            SlashCommandMenu { kind in
                if let idx = slashMenuIndex {
                    insertBlock(at: idx, kind: kind)
                } else {
                    addBlock(kind)
                }
                showSlashMenu = false
            }
            .presentationDetents([.medium])
        }
        .alert("Replace note?", isPresented: Binding(get: { pendingRewrite != nil }, set: { if !$0 { pendingRewrite = nil } })) {
            Button("Replace", role: .destructive) {
                if let text = pendingRewrite { replaceNoteBody(with: text) }
                pendingRewrite = nil
            }
            Button("Cancel", role: .cancel) { pendingRewrite = nil }
        } message: {
            Text("This replaces the whole note body with the AI result. You can't undo this.")
        }
        .sheet(isPresented: $showLinkPicker) {
            NoteLinkPicker(
                candidates: allNotes.filter { $0.id != note?.id && !(note?.linkedNoteIds.contains($0.id) ?? false) },
                onPick: { linkNote($0) }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Components

    private var editorFooter: some View {
        let words = wordCount
        let chars = note?.blocks.reduce(0) { $0 + $1.content.count } ?? 0
        return HStack(spacing: 12) {
            Text("\(words) word\(words == 1 ? "" : "s")")
            Text("·")
            Text("\(chars) characters")
            Spacer()
        }
        .font(PulseFont.body(11))
        .foregroundStyle(PulseColors.textFaint)
        .padding(.top, 20)
        .accessibilityLabel("\(words) words, \(chars) characters")
    }

    private var wordCount: Int {
        guard let note else { return 0 }
        let text = (note.title + " " + note.blocks.map(\.content).joined(separator: " "))
        return text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    private func togglePinCurrent() {
        guard let note else { return }
        note.isPinned.toggle()
        modelContext.saveOrLog("notes")
        HapticService.impact(.light)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(PulseColors.textMuted)
            Text("Notes")
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
            if !title.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(PulseColors.textFaint)
                Text(title)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if let note {
                Text("Edited \(timeAgo(note.updatedAt))")
                    .font(PulseFont.body(11))
                    .foregroundStyle(PulseColors.textFaint)
            }
        }
    }

    private var titleField: some View {
        TextField("Untitled", text: $title)
            .font(PulseFont.title(28))
            .foregroundStyle(PulseColors.textPrimary)
            .onChange(of: title) { _, _ in saveNote() }
    }

    private var currentCollection: Collection? {
        guard let cid = note?.collectionId else { return nil }
        return collections.first { $0.id == cid }
    }

    private var collectionRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button { setCollection(nil) } label: { Label("No collection", systemImage: "tray") }
                if !collections.isEmpty { Divider() }
                ForEach(collections) { c in
                    Button { setCollection(c.id) } label: { Text("\(c.emoji)  \(c.name)") }
                }
            } label: {
                HStack(spacing: 5) {
                    if let c = currentCollection {
                        Text(c.emoji).font(.system(size: 12))
                        Text(c.name).font(PulseFont.bodyMedium(13))
                    } else {
                        Image(systemName: "folder.badge.plus").font(.system(size: 12))
                        Text("Add to collection").font(PulseFont.bodyMedium(13))
                    }
                }
                .foregroundStyle(currentCollection == nil ? PulseColors.textMuted : PulseColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PulseColors.fillSubtle)
                .clipShape(Capsule())
            }
            .accessibilityLabel(currentCollection.map { "Collection: \($0.name)" } ?? "Add to collection")

            if !(note?.tags.isEmpty ?? true) {
                ForEach(note?.tags ?? [], id: \.self) { tag in
                    Text("#\(tag)")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(PulseColors.fillSubtle)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }

    private func setCollection(_ id: UUID?) {
        note?.collectionId = id
        saveNote()
        HapticService.impact(.light)
    }

    /// AI auto-file: picks/creates a collection and tags from the note content.
    private func autoFileNote() {
        guard let note else { return }
        let content = blocks.map(\.content).joined(separator: "\n")
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty || !title.isEmpty else { return }
        isAIGenerating = true
        let existing = collections.map(\.name)
        Task {
            let filing = await AIService.shared.autoFileNote(title: title, content: content, existingCollections: existing)
            await MainActor.run {
                if let name = filing.collection {
                    let match = collections.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                    if let match {
                        note.collectionId = match.id
                    } else {
                        let created = Collection(name: name, emoji: "🗂", order: collections.count)
                        modelContext.insert(created)
                        note.collectionId = created.id
                    }
                }
                if !filing.tags.isEmpty {
                    var merged = Set(note.tags)
                    filing.tags.forEach { merged.insert($0) }
                    note.tags = Array(merged).sorted()
                }
                saveNote()
                isAIGenerating = false
                HapticService.success()
            }
        }
    }

    private func aiSummaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseColors.textMuted)
                Text("AI SUMMARY")
                    .font(PulseFont.bodySemibold(10))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
            }
            Text(summary)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .lineSpacing(2)
        }
        .padding(14)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Block Editor

    private var blocksEditor: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                BlockView(
                    block: block,
                    index: index,
                    onContentChange: { newContent in
                        blocks[index].content = newContent
                        saveNote()
                    },
                    onToggleCheck: {
                        blocks[index].isChecked.toggle()
                        saveNote()
                    },
                    onDelete: { deleteBlock(at: index) },
                    onSlash: {
                        slashMenuIndex = index + 1
                        showSlashMenu = true
                    },
                    onNewLine: { insertBlock(at: index + 1, kind: block.kind == .todo ? .todo : .paragraph) }
                )
            }
        }
    }

    private var newBlockHint: some View {
        Button {
            slashMenuIndex = blocks.count
            showSlashMenu = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PulseColors.textFaint)
                Text("Type / for commands, or tap to add a block")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textFaint)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Linked task (E2)

    private var linkedTask: TaskItem? {
        guard let tid = note?.linkedTaskId else { return nil }
        return allTasks.first { $0.id == tid }
    }

    @ViewBuilder
    private var linkedTaskSection: some View {
        if let task = linkedTask {
            HStack(spacing: 12) {
                Button { toggleLinkedTask(task) } label: {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(task.status == .done ? PulseColors.success : PulseColors.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.status == .done ? "Mark task not done" : "Mark task done")
                VStack(alignment: .leading, spacing: 2) {
                    Text("LINKED TASK")
                        .font(PulseFont.bodySemibold(9))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.6)
                    Text(task.title)
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textPrimary)
                        .strikethrough(task.status == .done)
                        .lineLimit(1)
                }
                Spacer()
                Button { unlinkTask() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unlink task")
            }
            .padding(12)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Button { createLinkedTask() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                    Text("Create task from this note")
                        .font(PulseFont.bodyMedium(13))
                    Spacer()
                }
                .foregroundStyle(PulseColors.textSecondary)
                .padding(12)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Creates a to-do linked to this note")
        }
    }

    private func toggleLinkedTask(_ task: TaskItem) {
        task.status = task.status == .done ? .todo : .done
        task.updatedAt = Date()
        modelContext.saveOrLog("notes", surface: true)
        HapticService.impact(.light)
    }

    private func createLinkedTask() {
        guard let note else { return }
        let taskTitle = title.isEmpty ? "Follow up on note" : title
        let task = TaskItem(title: taskTitle, group: "Inbox", order: allTasks.count)
        modelContext.insert(task)
        note.linkedTaskId = task.id
        saveNote()
        HapticService.success()
    }

    private func unlinkTask() {
        note?.linkedTaskId = nil
        saveNote()
        HapticService.impact(.light)
    }

    // MARK: - Linked references (E1)

    private var outgoingLinks: [Note] {
        guard let ids = note?.linkedNoteIds else { return [] }
        return ids.compactMap { id in allNotes.first { $0.id == id } }
    }

    private var backlinks: [Note] {
        guard let id = note?.id else { return [] }
        return allNotes.filter { $0.id != id && $0.linkedNoteIds.contains(id) }
    }

    @ViewBuilder
    private var linkedReferencesSection: some View {
        let outgoing = outgoingLinks
        let back = backlinks
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LINKED NOTES")
                    .font(PulseFont.bodySemibold(10))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)
                Spacer()
                Button { showLinkPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.system(size: 11))
                        Text("Link note").font(PulseFont.bodyMedium(12))
                    }
                    .foregroundStyle(PulseColors.accent)
                }
                .accessibilityLabel("Link another note")
            }

            if outgoing.isEmpty && back.isEmpty {
                Text("No linked notes yet.")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textFaint)
            } else {
                ForEach(outgoing) { linked in
                    linkRow(linked, isBacklink: false)
                }
                if !back.isEmpty {
                    Text("BACKLINKS")
                        .font(PulseFont.bodySemibold(10))
                        .foregroundStyle(PulseColors.textFaint)
                        .tracking(0.6)
                        .padding(.top, 4)
                    ForEach(back) { linked in
                        linkRow(linked, isBacklink: true)
                    }
                }
            }
        }
        .padding(14)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func linkRow(_ linked: Note, isBacklink: Bool) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: AppRoute.noteEditor(linked.id)) {
                HStack(spacing: 10) {
                    Image(systemName: isBacklink ? "arrow.turn.down.left" : "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.textMuted)
                    Text(linked.title.isEmpty ? "Untitled" : linked.title)
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { saveNote() })
            if !isBacklink {
                Button { unlinkNote(linked) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove link to \(linked.title)")
            }
        }
        .padding(.vertical, 6)
    }

    private func linkNote(_ other: Note) {
        guard let note else { return }
        if !note.linkedNoteIds.contains(other.id) {
            note.linkedNoteIds.append(other.id)
            saveNote()
            HapticService.impact(.light)
        }
        showLinkPicker = false
    }

    private func unlinkNote(_ other: Note) {
        guard let note else { return }
        note.linkedNoteIds.removeAll { $0 == other.id }
        saveNote()
        HapticService.impact(.light)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button { addBlock(.paragraph) } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Button { addBlock(.heading) } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Button { addBlock(.todo) } label: {
                Image(systemName: "checkmark.square")
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textMuted)
            }
            Button { addBlock(.bulletList) } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Spacer()

            if isAIGenerating {
                ProgressView().controlSize(.small).tint(PulseColors.accent)
            }

            Menu {
                Button { generateAISummary() } label: { Label("Summarize", systemImage: "sparkles") }
                Button { generateAIContinue() } label: { Label("Continue writing", systemImage: "text.append") }
                Button { generateAITags() } label: { Label("Auto-tag", systemImage: "tag") }
                Button { autoFileNote() } label: { Label("Auto-file", systemImage: "folder.badge.gearshape") }
                Button { addBlock(.aiInsight) } label: { Label("Add AI insight", systemImage: "brain.head.profile") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseColors.textMuted)
                    .padding(.horizontal, 6)
            }
            .accessibilityLabel("AI quick actions")

            Button {
                withAnimation(.snappy(duration: 0.2)) { showAICommandBar.toggle() }
                if showAICommandBar { aiBarFocused = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.accent)
                    Text("Ask AI")
                        .font(PulseFont.bodySemibold(12))
                        .foregroundStyle(PulseColors.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PulseColors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .accessibilityLabel("Ask AI about this note")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
        }
    }

    // MARK: - AI Command Bar (primary inline AI surface, streaming → aiInsight)

    private var aiCommandBar: some View {
        VStack(spacing: 8) {
            if showAIUndo && !isAIGenerating {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseColors.success)
                    Text("AI added an insight block")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                    Spacer()
                    Button { undoLastAIEdit() } label: {
                        Text("Undo")
                            .font(PulseFont.bodySemibold(13))
                            .foregroundStyle(PulseColors.accent)
                    }
                    .accessibilityLabel("Undo AI edit")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !aiStreamingText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.accent)
                        .padding(.top, 2)
                    Text(aiStreamingText)
                        .font(PulseFont.body(14))
                        .foregroundStyle(PulseColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(PulseColors.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if showAIUndo && lastAIBlockId != nil && !isAIGenerating {
                Button { pendingRewrite = blocks.first(where: { $0.id == lastAIBlockId })?.content } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.2.squarepath").font(.system(size: 11))
                        Text("Replace note with this result")
                            .font(PulseFont.bodyMedium(12))
                    }
                    .foregroundStyle(PulseColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Replaces the whole note body with the AI result. Asks for confirmation.")
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseColors.accent)
                TextField("Ask AI to summarize, rewrite, extract tasks…", text: $aiCommand, axis: .vertical)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textPrimary)
                    .focused($aiBarFocused)
                    .lineLimit(1...3)
                    .onSubmit { runAICommand() }
                    .accessibilityLabel("AI command")
                if isAIGenerating {
                    ProgressView().controlSize(.small).tint(PulseColors.accent)
                } else {
                    Button { runAICommand() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(aiCommand.trimmingCharacters(in: .whitespaces).isEmpty ? PulseColors.textFaint : PulseColors.accent)
                    }
                    .disabled(aiCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Run AI command")
                }
            }
            quickAIChips
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
        }
    }

    private var quickAIChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                aiChip("Summarize", "text.append") { aiCommand = "Summarize this note in 2–3 sentences."; runAICommand() }
                aiChip("Action items", "checkmark.square") { aiCommand = "Extract concrete action items as a checklist."; runAICommand() }
                aiChip("Rewrite", "wand.and.stars") { aiCommand = "Rewrite this note to be clearer and better organized."; runAICommand() }
                aiChip("Continue", "text.alignleft") { aiCommand = "Continue writing this note naturally."; runAICommand() }
            }
        }
    }

    private func aiChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(PulseFont.bodyMedium(12))
            }
            .foregroundStyle(PulseColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PulseColors.fillSubtle)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isAIGenerating)
    }

    /// Runs the user's free-form instruction against the note content and streams the
    /// result into a fresh `aiInsight` block — the primary inline AI surface.
    private func runAICommand() {
        let instruction = aiCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, let note else { return }
        let content = blocks.map(\.content).joined(separator: "\n")
        aiBarFocused = false
        isAIGenerating = true
        aiStreamingText = ""
        // Snapshot for undo (C3): remember block IDs that existed before the AI edit.
        preAIBlockIds = Set(blocks.map(\.id))

        Task {
            let system = "You are an inline writing assistant inside a note editor. Apply the user's instruction to their note. Respond with only the resulting text — no preamble, no quotes."
            let prompt = "Note title: \(title)\n\nNote content:\n\(content.prefix(2000))\n\nInstruction: \(instruction)"
            var accumulated = ""
            do {
                if AIService.shared.hasAPIKey {
                    for try await chunk in AIService.shared.stream(
                        messages: [AIService.Message(role: "user", content: prompt)],
                        systemPrompt: system,
                        temperature: 0.5,
                        maxTokens: 700
                    ) {
                        accumulated += chunk
                        await MainActor.run { aiStreamingText = accumulated }
                    }
                } else {
                    accumulated = "AI is unavailable offline. Add an API key in Settings to use Ask AI."
                    await MainActor.run { aiStreamingText = accumulated }
                }
            } catch {
                accumulated = accumulated.isEmpty ? "Couldn't reach AI. Please try again." : accumulated
            }
            await MainActor.run {
                commitAIResult(accumulated, instruction: instruction, on: note)
                isAIGenerating = false
                aiCommand = ""
            }
        }
    }

    private func commitAIResult(_ text: String, instruction: String, on note: Note) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { aiStreamingText = ""; return }
        let block = NoteBlock(noteId: note.id, order: blocks.count, kind: .aiInsight, content: trimmed)
        modelContext.insert(block)
        blocks.append(block)
        lastAIBlockId = block.id
        aiStreamingText = ""
        showAIUndo = true
        saveNote()
        HapticService.success()
    }

    /// Removes the most recent AI-inserted block, restoring the note to its
    /// pre-command state. Only blocks that didn't exist before the command are
    /// candidates, so user content is never touched.
    private func undoLastAIEdit() {
        guard let lastAIBlockId,
              let idx = blocks.firstIndex(where: { $0.id == lastAIBlockId }),
              !preAIBlockIds.contains(lastAIBlockId) else {
            showAIUndo = false
            return
        }
        let block = blocks.remove(at: idx)
        modelContext.delete(block)
        self.lastAIBlockId = nil
        showAIUndo = false
        saveNote()
        HapticService.impact(.light)
    }

    /// Destructive: replaces all blocks with paragraphs derived from `text`. Gated
    /// behind an explicit confirmation alert (see `pendingRewrite`).
    private func replaceNoteBody(with text: String) {
        guard let note else { return }
        for block in blocks { modelContext.delete(block) }
        blocks.removeAll()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let paragraphs = lines.isEmpty ? [text] : lines
        for (i, line) in paragraphs.enumerated() {
            let block = NoteBlock(noteId: note.id, order: i, kind: .paragraph, content: line)
            modelContext.insert(block)
            blocks.append(block)
        }
        lastAIBlockId = nil
        showAIUndo = false
        saveNote()
        HapticService.success()
    }

    // MARK: - AI Features

    private func generateAISummary() {
        guard let note else { return }
        let content = blocks.map(\.content).joined(separator: " ")
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isAIGenerating = true
        Task {
            if let summary = await AIService.shared.summarizeNote(content: content) {
                note.aiSummary = summary
                modelContext.saveOrLog("notes")
                self.note = note
            }
            isAIGenerating = false
        }
    }

    private func generateAIContinue() {
        let content = blocks.map(\.content).joined(separator: "\n")
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isAIGenerating = true
        Task {
            let prompt = "Continue writing this note naturally. Write 2-3 sentences that follow from:\n\n\(content.prefix(1000))\n\nJust the continuation, no labels:"
            do {
                let continuation = try await AIService.shared.complete(
                    messages: [AIService.Message(role: "user", content: prompt)],
                    temperature: 0.8,
                    maxTokens: 200
                )
                addBlockWithContent(.paragraph, content: continuation)
            } catch {}
            isAIGenerating = false
        }
    }

    private func generateAITags() {
        let content = blocks.map(\.content).joined(separator: " ")
        guard !content.isEmpty else { return }

        isAIGenerating = true
        Task {
            let tags = await AIService.shared.generateNoteTags(title: title, content: content)
            if !tags.isEmpty {
                let tagText = tags.map { "#\($0)" }.joined(separator: " ")
                addBlockWithContent(.callout, content: "Tags: \(tagText)")
            }
            isAIGenerating = false
        }
    }

    private func addBlockWithContent(_ kind: NoteBlockKind, content: String) {
        guard let note else { return }
        let block = NoteBlock(noteId: note.id, order: blocks.count, kind: kind, content: content)
        modelContext.insert(block)
        blocks.append(block)
        saveNote()
    }

    // MARK: - Data

    private func loadNote() {
        // Already loaded (e.g. a second .onAppear after backgrounding); don't
        // insert another blank note, which would orphan an empty record each time.
        guard note == nil else { return }
        guard let noteId else {
            let newNote = Note(title: "")
            modelContext.insert(newNote)
            let block = NoteBlock(noteId: newNote.id, order: 0, kind: .paragraph, content: "")
            modelContext.insert(block)
            modelContext.saveOrLog("notes")
            self.note = newNote
            self.title = ""
            self.blocks = [block]
            return
        }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteId })
        if let fetched = try? modelContext.fetch(descriptor).first {
            self.note = fetched
            self.title = fetched.title
            self.blocks = fetched.blocks.sorted { $0.order < $1.order }
        }
    }

    private func saveNote() {
        guard let note else { return }
        note.title = title
        note.updatedAt = Date()
        for (i, block) in blocks.enumerated() {
            block.order = i
        }
        modelContext.saveOrLog("notes")
        scheduleAutoEnhance()
    }

    /// Debounced background pass: derive a title when the user hasn't set one, and
    /// refresh the AI summary. Cancels on each keystroke so it only runs when the
    /// note has settled (~2.5s idle). Skipped offline.
    private func scheduleAutoEnhance() {
        autoSummaryTask?.cancel()
        guard let note else { return }
        autoSummaryTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            await MainActor.run { applyAutoTitleIfNeeded(note) }
            let content = blocks.map(\.content).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard content.count > 60, AIService.shared.hasAPIKey else { return }
            if let summary = await AIService.shared.summarizeNote(content: content) {
                if Task.isCancelled { return }
                await MainActor.run {
                    note.aiSummary = summary
                    modelContext.saveOrLog("notes")
                    self.note = note
                }
            }
        }
    }

    /// Auto-title from the first heading or non-empty paragraph when the user left the
    /// title blank. Never overwrites a user-entered title.
    private func applyAutoTitleIfNeeded(_ note: Note) {
        guard title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let sorted = blocks.sorted { $0.order < $1.order }
        let source = sorted.first { $0.kind == .heading && !$0.content.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? sorted.first { !$0.content.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let source else { return }
        let derived = String(source.content.trimmingCharacters(in: .whitespaces).prefix(60))
        guard !derived.isEmpty else { return }
        title = derived
        note.title = derived
        modelContext.saveOrLog("notes")
    }

    private func addBlock(_ kind: NoteBlockKind) {
        guard let note else { return }
        let block = NoteBlock(noteId: note.id, order: blocks.count, kind: kind, content: "")
        modelContext.insert(block)
        blocks.append(block)
        saveNote()
    }

    private func insertBlock(at index: Int, kind: NoteBlockKind) {
        guard let note else { return }
        let block = NoteBlock(noteId: note.id, order: index, kind: kind, content: "")
        modelContext.insert(block)
        blocks.insert(block, at: min(index, blocks.count))
        saveNote()
    }

    private func deleteBlock(at index: Int) {
        guard blocks.count > 1 else { return }
        let block = blocks.remove(at: index)
        modelContext.delete(block)
        saveNote()
    }

    private func timeAgo(_ date: Date) -> String {
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

// MARK: - Block View

struct BlockView: View {
    let block: NoteBlock
    let index: Int
    var onContentChange: (String) -> Void
    var onToggleCheck: () -> Void
    var onDelete: () -> Void
    var onSlash: () -> Void
    var onNewLine: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(block: NoteBlock, index: Int, onContentChange: @escaping (String) -> Void, onToggleCheck: @escaping () -> Void, onDelete: @escaping () -> Void, onSlash: @escaping () -> Void, onNewLine: @escaping () -> Void) {
        self.block = block
        self.index = index
        self.onContentChange = onContentChange
        self.onToggleCheck = onToggleCheck
        self.onDelete = onDelete
        self.onSlash = onSlash
        self.onNewLine = onNewLine
        _text = State(initialValue: block.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leadingElement
            contentField
        }
        .padding(.vertical, blockVerticalPadding)
        .contextMenu {
            Button { onSlash() } label: { Label("Insert below", systemImage: "plus") }
            Divider()
            Button { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var leadingElement: some View {
        switch block.kind {
        case .todo:
            Button(action: onToggleCheck) {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(block.isChecked ? PulseColors.accent : PulseColors.textFaint)
                    .font(.system(size: 17))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .padding(.top, 2)
        case .bulletList:
            Text("•")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 20)
                .padding(.top, 1)
        case .numberedList:
            Text("\(index + 1).")
                .font(PulseFont.bodyMedium(14))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 24, alignment: .trailing)
                .padding(.trailing, 6)
                .padding(.top, 2)
        case .quote:
            Rectangle()
                .fill(PulseColors.accent.opacity(0.5))
                .frame(width: 3)
                .clipShape(Capsule())
                .padding(.trailing, 12)
        case .divider:
            EmptyView()
        case .callout:
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(PulseColors.warning)
                .padding(.trailing, 10)
                .padding(.top, 2)
        case .aiInsight:
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(PulseColors.accent)
                .padding(.trailing, 10)
                .padding(.top, 2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var contentField: some View {
        switch block.kind {
        case .divider:
            Rectangle()
                .fill(PulseColors.borderHairline)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .heading:
            TextField("Heading", text: $text, axis: .vertical)
                .font(PulseFont.titleMedium(20))
                .foregroundStyle(PulseColors.textPrimary)
                .focused($isFocused)
                .onChange(of: text) { _, newVal in
                    handleTextChange(newVal)
                }
        case .todo:
            TextField("To-do", text: $text, axis: .vertical)
                .font(PulseFont.body(15))
                .foregroundStyle(block.isChecked ? PulseColors.textMuted : PulseColors.textPrimary)
                .strikethrough(block.isChecked)
                .focused($isFocused)
                .onChange(of: text) { _, newVal in
                    handleTextChange(newVal)
                }
        case .quote:
            TextField("Quote", text: $text, axis: .vertical)
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textSecondary)
                .italic()
                .focused($isFocused)
                .onChange(of: text) { _, newVal in
                    handleTextChange(newVal)
                }
        case .callout:
            TextField("Callout", text: $text, axis: .vertical)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .padding(10)
                .background(PulseColors.warningBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($isFocused)
                .onChange(of: text) { _, newVal in
                    handleTextChange(newVal)
                }
        case .aiInsight:
            TextField("AI insight", text: $text, axis: .vertical)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textSecondary)
                .lineSpacing(4)
                .padding(10)
                .background(PulseColors.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(PulseColors.accent.opacity(0.25), lineWidth: 1))
                .focused($isFocused)
                .onChange(of: text) { _, newVal in
                    handleTextChange(newVal)
                }
        default:
            TextField("Type something…", text: $text, axis: .vertical)
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .lineSpacing(4)
                .focused($isFocused)
                .onChange(of: text) { _, newVal in
                    handleTextChange(newVal)
                }
        }
    }

    private var blockVerticalPadding: CGFloat {
        switch block.kind {
        case .heading: return 8
        case .divider: return 4
        default: return 4
        }
    }

    private func handleTextChange(_ newVal: String) {
        if newVal.hasSuffix("/") && newVal.count > 1 {
            text = String(newVal.dropLast())
            onContentChange(text)
            onSlash()
        } else {
            onContentChange(newVal)
        }
    }
}

// MARK: - Slash Command Menu

struct SlashCommandMenu: View {
    var onSelect: (NoteBlockKind) -> Void
    @Environment(\.dismiss) private var dismiss

    private let commands: [(icon: String, title: String, subtitle: String, kind: NoteBlockKind)] = [
        ("text.alignleft", "Text", "Plain text paragraph", .paragraph),
        ("textformat.size.larger", "Heading", "Section heading", .heading),
        ("checkmark.square", "To-do", "Checkbox item", .todo),
        ("list.bullet", "Bullet list", "Unordered list item", .bulletList),
        ("list.number", "Numbered list", "Ordered list item", .numberedList),
        ("text.quote", "Quote", "Block quote", .quote),
        ("lightbulb", "Callout", "Highlighted note", .callout),
        ("minus", "Divider", "Horizontal separator", .divider),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(commands, id: \.title) { cmd in
                        Button {
                            onSelect(cmd.kind)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: cmd.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(PulseColors.textMuted)
                                    .frame(width: 32, height: 32)
                                    .background(PulseColors.fillSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cmd.title)
                                        .font(PulseFont.bodyMedium(15))
                                        .foregroundStyle(PulseColors.textPrimary)
                                    Text(cmd.subtitle)
                                        .font(PulseFont.body(12))
                                        .foregroundStyle(PulseColors.textMuted)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(PulseColors.background)
            .navigationTitle("Add a block")
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
    }
}

// MARK: - Note Link Picker (E1)

struct NoteLinkPicker: View {
    let candidates: [Note]
    let onPick: (Note) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Note] {
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(PulseColors.textMuted)
                    TextField("Search notes to link…", text: $query)
                        .font(PulseFont.body(14))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(16)

                ScrollView {
                    VStack(spacing: 0) {
                        if filtered.isEmpty {
                            InlineEmptyState(title: "No notes", message: "There are no other notes to link.")
                                .padding(.top, 40)
                        }
                        ForEach(filtered) { note in
                            Button { onPick(note) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 14))
                                        .foregroundStyle(PulseColors.textMuted)
                                    Text(note.title.isEmpty ? "Untitled" : note.title)
                                        .font(PulseFont.bodyMedium(15))
                                        .foregroundStyle(PulseColors.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "link")
                                        .font(.system(size: 12))
                                        .foregroundStyle(PulseColors.accent)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(PulseColors.borderHairline).frame(height: 1).padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .background(PulseColors.background)
            .navigationTitle("Link a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Voice Note Recorder (Granola-style capture → Todoist-style organization)

struct VoiceNoteRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var path: NavigationPath

    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var transcribedText = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var voiceServices = VoiceServices()
    @State private var plan: VoiceCaptureRouter.CapturePlan?
    @State private var showResult = false
    @State private var showTranscript = false
    @State private var typedText = ""
    @FocusState private var typingFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    if showResult, let result = plan {
                        resultCard(result)
                    } else {
                        recordingCard
                    }
                }
                .padding(8)
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { stopAndDismiss() } label: {
                        Text("Cancel")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !showResult {
                        Button { createBlankNote() } label: {
                            Text("Blank note")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .accessibilityHint("Skip capture and open an empty note")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onChange(of: voiceServices.transcribedText) { _, newValue in
            if isRecording { transcribedText = newValue }
        }
    }

    // MARK: - Recording Card (Granola-style floating inverted card)

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if !isRecording && !isProcessing {
                    Menu {
                        Button {} label: { Label("Settings", systemImage: "gear") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color(UIColor.systemBackground).opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.top, 20)
            .padding(.trailing, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text("New Note")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(Color(UIColor.systemBackground))

                if isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(UIColor.systemBackground).opacity(0.7))
                            .controlSize(.small)
                        Text("Generating your notes...")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.7))
                    }
                    .padding(.top, 4)
                    Text("We'll let you know when they're ready")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
                } else if !transcribedText.isEmpty {
                    ScrollView {
                        Text(transcribedText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                } else {
                    ZStack(alignment: .topLeading) {
                        if typedText.isEmpty {
                            Text("Write or speak your thoughts… AI will organize them into a note and tasks.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(UIColor.systemBackground).opacity(0.4))
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $typedText)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(UIColor.systemBackground))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: 120, maxHeight: 200)
                            .focused($typingFocused)
                            .accessibilityLabel("Note text")
                            .accessibilityHint("Type your thoughts, then tap Generate")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Spacer(minLength: 20)

            // Bottom controls
            HStack(spacing: 16) {
                if isRecording {
                    Button { stopRecording() } label: {
                        Text("Resume")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.systemBackground))
                            .clipShape(Capsule())
                    }

                    Text(formatDuration(recordingDuration))
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.7))

                    HStack(spacing: 3) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                                .opacity(Double(i) < (recordingDuration.truncatingRemainder(dividingBy: 5) + 1) ? 1 : 0.3)
                        }
                    }

                    Spacer()

                    Button { stopRecording() } label: {
                        Text("End")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(UIColor.systemBackground))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.systemBackground).opacity(0.2))
                            .clipShape(Capsule())
                    }
                } else if !isProcessing {
                    Button { startRecording() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14))
                            Text("Record")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.systemBackground))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    if !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { processTyped() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14))
                                Text("Generate")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Color(UIColor.systemBackground))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.systemBackground).opacity(0.22))
                            .clipShape(Capsule())
                        }
                        .accessibilityLabel("Generate note from typed text")
                    } else {
                        Button { stopAndDismiss() } label: {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(UIColor.systemBackground).opacity(0.6))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.systemBackground).opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .background(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
    }

    // MARK: - Result Card

    private func resultCard(_ result: VoiceCaptureRouter.CapturePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI ORGANIZED")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color(UIColor.systemBackground).opacity(0.45))
                Spacer()
                Button { showTranscript.toggle() } label: {
                    Text(showTranscript ? "Hide transcript" : "Original")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.6))
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(result.title)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(Color(UIColor.systemBackground))

                    if showTranscript {
                        Text(result.transcript)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.55))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.systemBackground).opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.heading)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(UIColor.systemBackground))
                            ForEach(section.bullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
                                    Text(bullet)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.85))
                                }
                            }
                        }
                    }

                    if !result.tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Text("Tasks")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color(UIColor.systemBackground))
                                if result.scheduledCount > 0 {
                                    Text("· scheduled this week")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(UIColor.systemBackground).opacity(0.5))
                                }
                            }
                            ForEach(Array(result.tasks.enumerated()), id: \.offset) { _, task in
                                HStack(spacing: 10) {
                                    Circle()
                                        .stroke(Color(UIColor.systemBackground).opacity(0.4), lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(task.title)
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color(UIColor.systemBackground).opacity(0.9))
                                        if task.group != "Inbox" || task.dayOffset != nil {
                                            Text(taskSubtitle(task))
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color(UIColor.systemBackground).opacity(0.45))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }

            Button { saveEverywhere(result) } label: {
                Text(saveButtonLabel(result))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .background(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
    }

    private func taskSubtitle(_ task: VoiceCaptureRouter.CapturePlan.PlannedTask) -> String {
        var parts: [String] = []
        if task.group != "Inbox" { parts.append(task.group) }
        if let offset = task.dayOffset { parts.append(dayLabel(offset)) }
        return parts.joined(separator: " · ")
    }

    private func dayLabel(_ offset: Int) -> String {
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date())) else { return "" }
        if offset == 0 { return "Today" }
        if offset == 1 { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private func saveButtonLabel(_ result: VoiceCaptureRouter.CapturePlan) -> String {
        if result.tasks.isEmpty { return "Save note" }
        return "Save note + \(result.taskCount) task\(result.taskCount == 1 ? "" : "s")"
    }

    // MARK: - Recording Logic (routed through the unified VoiceServices layer)

    private func startRecording() {
        Task {
            let granted = await voiceServices.requestSpeechAuthorization()
            guard granted else { return }
            voiceServices.startListening()
            isRecording = true
            recordingDuration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                recordingDuration += 1
            }
            HapticService.impact(.medium)
        }
    }

    private func stopRecording() {
        voiceServices.stopListening()
        transcribedText = voiceServices.transcribedText
        timer?.invalidate()
        timer = nil
        isRecording = false
        HapticService.success()

        guard !transcribedText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        processTranscription()
    }

    private func stopAndDismiss() {
        if isRecording {
            voiceServices.stopListening()
            timer?.invalidate()
        }
        dismiss()
    }

    /// Blank-note fallback: skip the capture pipeline and open an empty note.
    private func createBlankNote() {
        if isRecording {
            voiceServices.stopListening()
            timer?.invalidate()
        }
        let note = Note(title: "")
        let block = NoteBlock(noteId: note.id, order: 0, kind: .paragraph, content: "")
        modelContext.insert(note)
        modelContext.insert(block)
        modelContext.saveOrLog("notes")
        dismiss()
        path.append(AppRoute.noteEditor(note.id))
    }

    // MARK: - AI Processing

    private func processTranscription() {
        isProcessing = true
        let captured = transcribedText
        Task {
            let router = VoiceCaptureRouter()
            let result = await router.plan(from: captured)
            await MainActor.run {
                plan = result
                showResult = true
                isProcessing = false
                HapticService.success()
            }
        }
    }

    /// Routes typed text through the same capture pipeline as voice, so the `+`
    /// capture surface is input-agnostic. Falls back to the local parser offline.
    private func processTyped() {
        let captured = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !captured.isEmpty else { return }
        typingFocused = false
        isProcessing = true
        Task {
            let router = VoiceCaptureRouter()
            let result = await router.plan(from: captured)
            await MainActor.run {
                plan = result
                showResult = true
                isProcessing = false
                HapticService.success()
            }
        }
    }

    // MARK: - Save Actions

    /// Creates a polished note AND files every classified task into the app
    /// (with due dates when scheduled this week), then opens the note.
    private func saveEverywhere(_ result: VoiceCaptureRouter.CapturePlan) {
        let router = VoiceCaptureRouter()
        let note = Note(title: result.title)
        modelContext.insert(note)

        var order = 0
        for section in result.sections {
            let heading = NoteBlock(noteId: note.id, order: order, kind: .heading, content: section.heading)
            modelContext.insert(heading)
            note.blocks.append(heading)
            order += 1
            for bullet in section.bullets {
                let block = NoteBlock(noteId: note.id, order: order, kind: .bulletList, content: bullet)
                modelContext.insert(block)
                note.blocks.append(block)
                order += 1
            }
        }

        for task in result.tasks {
            let todo = NoteBlock(noteId: note.id, order: order, kind: .todo, content: task.title)
            modelContext.insert(todo)
            note.blocks.append(todo)
            order += 1

            let item = TaskItem(
                title: task.title,
                group: task.group,
                dueDate: router.dueDate(forDayOffset: task.dayOffset),
                order: order
            )
            modelContext.insert(item)
        }

        let scheduled = result.scheduledCount
        note.aiSummary = "Voice capture · \(formatDuration(recordingDuration)) · \(result.taskCount) task\(result.taskCount == 1 ? "" : "s")"
            + (scheduled > 0 ? ", \(scheduled) scheduled this week" : "")
        modelContext.saveOrLog("notes")
        HapticService.success()
        dismiss()
        path.append(AppRoute.noteEditor(note.id))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
