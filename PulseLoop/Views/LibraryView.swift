import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var path: NavigationPath
    @State private var searchText = ""
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \TaskItem.order) private var tasks: [TaskItem]
    @Query(filter: #Predicate<InboxItem> { !$0.isHandled }) private var inboxItems: [InboxItem]

    private var collections: [(emoji: String, title: String, subtitle: String, route: AppRoute?)] {
        let medCount = medications.filter { $0.category == .medication }.count
        let suppCount = medications.filter { $0.category == .supplement || $0.category == .vitamin }.count
        let peptideCount = medications.filter { $0.category == .peptide }.count

        return [
            ("doc.text", "Notes", "\(notes.count) pages", .notesList),
            ("pills.fill", "Protocol", "\(medCount + suppCount + peptideCount) items", nil),
            ("checkmark.circle", "Tasks", "\(tasks.filter { $0.status != .done }.count) active", .tasksList),
            ("target", "Goals", "\(tasks.filter { $0.status != .done }.count) active", nil),
            ("heart.fill", "Health", "Ring synced", .health),
            ("person.2", "People", "Contacts", nil),
            ("bookmark.fill", "Bookmarks", "Saved", nil),
            ("airplane", "Travel", "Trips", nil),
        ]
    }

    private var filteredCollections: [(emoji: String, title: String, subtitle: String, route: AppRoute?)] {
        guard !searchText.isEmpty else { return collections }
        return collections.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var recentNotes: [Note] {
        Array(notes.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                libraryHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                VStack(spacing: 20) {
                    searchBar
                    collectionsSection
                    recentsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(PulseColors.background)
    }

    private var libraryHeader: some View {
        HStack {
            Text("Library")
                .font(PulseFont.title(28))
                .foregroundStyle(PulseColors.textPrimary)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(PulseColors.textMuted)
            TextField("Search everything…", text: $searchText)
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(PulseColors.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLLECTIONS")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(filteredCollections, id: \.title) { item in
                    Button {
                        if let route = item.route {
                            path.append(route)
                        }
                    } label: {
                        CollectionCard(emoji: item.emoji, title: item.title, subtitle: item.subtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENTLY OPENED")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textMuted)
                .tracking(0.8)

            VStack(spacing: 0) {
                ForEach(recentNotes) { note in
                    Button {
                        path.append(AppRoute.noteEditor(note.id))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PulseColors.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(PulseColors.fillSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(PulseFont.bodyMedium(14))
                                .foregroundStyle(PulseColors.textPrimary)
                            Spacer()
                            Text(timeAgo(note.updatedAt))
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(PulseColors.borderHairline).frame(height: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}
