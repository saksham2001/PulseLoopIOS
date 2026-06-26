import SwiftUI
import SwiftData
import MapKit
import CoreLocation

// MARK: - Travel module UI
//
// `TravelView` lists the user's trips; `TripDetailView` shows one trip's itinerary
// grouped by kind (flights, stay, things to do, food, transport, notes). Most
// content is created by the coach — the user talks/asks, the AI searches the web
// and files real options here — so the empty states point back to the assistant.

struct TravelView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var showingNewTrip = false
    @State private var showingWallet = false
    private let nav = CoachNavigation.shared

    private var activeTrips: [Trip] { trips.filter { $0.status != .cancelled } }

    /// Upcoming = not completed and (no end date, or end date today/future). Past = the rest.
    private var upcomingTrips: [Trip] {
        let now = Calendar.current.startOfDay(for: Date())
        return activeTrips
            .filter { $0.status != .completed && (($0.endDate ?? .distantFuture) >= now) }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var pastTrips: [Trip] {
        let now = Calendar.current.startOfDay(for: Date())
        return activeTrips
            .filter { $0.status == .completed || (($0.endDate ?? .distantFuture) < now) }
            .sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if activeTrips.isEmpty {
                    emptyState
                } else {
                    if !upcomingTrips.isEmpty {
                        sectionHeader("Upcoming")
                        ForEach(upcomingTrips) { tripCardButton($0) }
                    }
                    if !pastTrips.isEmpty {
                        sectionHeader("Past")
                        ForEach(pastTrips) { tripCardButton($0) }
                    }
                }
            }
            .padding(16)
        }
        .background(PulseColors.background)
        .navigationTitle("Travel")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingNewTrip = true
                    } label: {
                        Label("New trip", systemImage: "suitcase.rolling")
                    }
                    Button {
                        showingWallet = true
                    } label: {
                        Label("Wallet & rewards", systemImage: "creditcard")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(PulseColors.textPrimary)
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $showingNewTrip) {
            TripEditSheet(trip: nil) { trip in
                path.append(AppRoute.tripDetail(trip.id))
            }
        }
        .sheet(isPresented: $showingWallet) {
            RewardWalletView()
        }
    }

    /// Prefill the coach with a good planning prompt and open it (does not auto-send).
    private func planWithAI() {
        nav.askAI("Help me plan a trip. Find flights, a place to stay, and a few things to do, then save them to a new trip. Ask me for the destination, dates, and budget if you need them.")
    }

    private func tripCardButton(_ trip: Trip) -> some View {
        Button { path.append(AppRoute.tripDetail(trip.id)) } label: {
            TripCard(trip: trip)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(PulseFont.bodySemibold(13))
            .foregroundStyle(PulseColors.textMuted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trips")
                .font(PulseFont.heading)
                .foregroundStyle(PulseColors.textPrimary)
            Text("Ask the assistant to plan a trip, find flights, stays, or things to do — it'll organize everything here.")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 34))
                .foregroundStyle(PulseColors.accent)
            Text("No trips yet")
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Plan a trip with the assistant — it searches live for flights, stays, and things to do — or start one yourself and add items by hand.")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            VStack(spacing: 10) {
                Button(action: planWithAI) {
                    Label("Plan a trip with AI", systemImage: "sparkles")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    showingNewTrip = true
                } label: {
                    Label("New trip", systemImage: "plus")
                        .font(PulseFont.bodySemibold(15))
                        .foregroundStyle(PulseColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(PulseColors.borderStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .pulseCardSurface()
    }
}

private struct TripCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover = trip.coverImageURL, let url = URL(string: cover) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(PulseColors.fillMuted)
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(trip.destination)
                        .font(PulseFont.titleSemibold(20))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                    StatusChip(label: trip.status.rawValue.capitalized, style: chipStyle)
                }
                if let dates = dateRange {
                    Label(dates, systemImage: "calendar")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                HStack(spacing: 14) {
                    ForEach(itemCounts, id: \.0) { kind, count in
                        Label("\(count)", systemImage: kind.icon)
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                    Spacer()
                    if trip.estimatedCost > 0 {
                        Text(money(trip.estimatedCost, trip.effectiveCurrency))
                            .font(PulseFont.bodySemibold(13))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCardSurface()
    }

    private func money(_ amount: Double, _ currency: String) -> String {
        let symbol: String
        switch currency.uppercased() {
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        case "JPY": symbol = "¥"
        default: symbol = currency.uppercased() + " "
        }
        return symbol + (amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(format: "%.0f", amount))
    }

    private var chipStyle: ChipStyle {
        switch trip.status {
        case .booked: return .success
        case .completed: return .neutral
        case .cancelled: return .alert
        case .planning: return .neutral
        }
    }

    private var dateRange: String? {
        guard let start = trip.startDate else { return nil }
        if let end = trip.endDate {
            return "\(TravelFormat.shortDate.string(from: start)) – \(TravelFormat.shortDateYear.string(from: end))"
        }
        return TravelFormat.shortDate.string(from: start)
    }

    private var itemCounts: [(TripItemKind, Int)] {
        TripItemKind.allCases.compactMap { kind in
            let c = trip.items.filter { $0.kind == kind }.count
            return c > 0 ? (kind, c) : nil
        }
    }
}

// MARK: - Trip detail

/// Shared formatters (avoid per-row allocation in view bodies).
private enum TravelFormat {
    static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    static let shortDateYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()
    static let weekdayDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
}

struct TripDetailView: View {
    let tripId: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var trips: [Trip]
    @Query private var linkedTasks: [TaskItem]
    @Query private var linkedNotes: [Note]
    @State private var grouping: ItineraryGrouping = .day
    @State private var editingItem: TripItem?
    @State private var addingItemKind: TripItemKind?
    @State private var showingEditTrip = false
    @State private var newPackingItem = ""
    @State private var showingAddDoc = false
    private let nav = CoachNavigation.shared

    enum ItineraryGrouping: String, CaseIterable {
        case day = "By day"
        case type = "By type"
    }

    init(tripId: UUID) {
        self.tripId = tripId
        _trips = Query(filter: #Predicate<Trip> { $0.id == tripId })
        _linkedTasks = Query(
            filter: #Predicate<TaskItem> { $0.tripId == tripId },
            sort: \TaskItem.order
        )
        _linkedNotes = Query(
            filter: #Predicate<Note> { $0.linkedTripId == tripId },
            sort: \Note.updatedAt, order: .reverse
        )
    }

    private var trip: Trip? { trips.first }

    /// Pre-trip checklist tasks = trip-linked tasks NOT in the packing group.
    private var checklistTasks: [TaskItem] { linkedTasks.filter { $0.group != TravelTools.packingGroup } }
    /// Packing list tasks = trip-linked tasks in the packing group.
    private var packingTasks: [TaskItem] { linkedTasks.filter { $0.group == TravelTools.packingGroup } }
    /// Notes that aren't classified as travel documents.
    private var generalNotes: [Note] { linkedNotes.filter { !isDoc($0) } }

    var body: some View {
        ScrollView {
            if let trip {
                VStack(alignment: .leading, spacing: 20) {
                    tripHeader(trip)
                    if trip.estimatedCost > 0 || trip.budgetAmount != nil {
                        budgetSection(trip)
                    }
                    destinationInfoSection(trip)
                    if !checklistTasks.isEmpty {
                        checklistSection
                    }
                    packingSection(trip)
                    docsSection(trip)
                    if !generalNotes.isEmpty {
                        notesSection
                    }
                    if !mappableItems(trip).isEmpty {
                        TripMapView(items: mappableItems(trip))
                    }
                    if !trip.items.isEmpty {
                        Picker("Group", selection: $grouping) {
                            ForEach(ItineraryGrouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    switch grouping {
                    case .day: dayGroupedItinerary(trip)
                    case .type: typeGroupedItinerary(trip)
                    }
                    if trip.items.isEmpty {
                        emptyItineraryActions(trip)
                    }
                }
                .padding(16)
            } else {
                Text("Trip not found.")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textMuted)
                    .padding(40)
            }
        }
        .background(PulseColors.background)
        .navigationTitle(trip?.destination ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let trip {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            addingItemKind = .activity
                        } label: {
                            Label("Add item", systemImage: "plus")
                        }
                        Button {
                            showingEditTrip = true
                        } label: {
                            Label("Edit trip", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                    .accessibilityLabel("Trip options")
                    .disabled(trip.id != tripId)
                }
            }
        }
        .sheet(item: $editingItem) { item in
            if let trip {
                TripItemEditSheet(trip: trip, item: item)
            }
        }
        .sheet(item: $addingItemKind) { kind in
            if let trip {
                TripItemEditSheet(trip: trip, item: nil, defaultKind: kind)
            }
        }
        .sheet(isPresented: $showingEditTrip) {
            if let trip {
                TripEditSheet(trip: trip)
            }
        }
    }

    // MARK: Empty / discovery actions

    @ViewBuilder private func emptyItineraryActions(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing planned yet")
                .font(PulseFont.bodySemibold(16))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Plan it with the assistant, or add flights, a place to stay, and things to do yourself.")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textSecondary)

            Button { planTripWithAI(trip) } label: {
                Label("Plan this trip with AI", systemImage: "sparkles")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { addingItemKind = .activity } label: {
                Label("Add item manually", systemImage: "plus")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PulseColors.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Text("QUICK ADD")
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .foregroundStyle(PulseColors.textMuted)
                .padding(.top, 2)
            FlowChips(kinds: TripItemKind.allCases) { addingItemKind = $0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pulseCardSurface()
    }

    /// A discovery prompt for the coach referencing this specific trip.
    private func planTripWithAI(_ trip: Trip, kind: TripItemKind? = nil) {
        var ctx = "Plan my trip to \(trip.destination)"
        if let origin = trip.originCity { ctx += " from \(origin)" }
        if let start = trip.startDate {
            let range = trip.endDate.map { "\(TravelFormat.weekdayDate.string(from: start)) – \(TravelFormat.weekdayDate.string(from: $0))" } ?? TravelFormat.weekdayDate.string(from: start)
            ctx += " (\(range))"
        }
        ctx += " for \(trip.travelerCount == 1 ? "1 traveler" : "\(trip.travelerCount) travelers")."
        if let kind {
            ctx += " Focus on \(kind.label.lowercased()): find a few great options and show them as cards I can save to this trip."
        } else {
            ctx += " Find flights, a place to stay, and a few things to do, show them as cards, and save the best to this trip."
        }
        nav.askAI(ctx)
    }

    private func mappableItems(_ trip: Trip) -> [TripItem] {
        trip.items.filter { ($0.location?.isEmpty == false) }
    }

    // MARK: Pre-trip checklist

    private var checklistSection: some View {
        let done = checklistTasks.filter { $0.status == .done }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pre-trip checklist")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Text("\(done)/\(checklistTasks.count)")
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            ForEach(checklistTasks) { task in
                Button {
                    toggleTask(task)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.status == .done ? PulseColors.accent : PulseColors.textMuted)
                        Text(task.title)
                            .font(PulseFont.body(14))
                            .foregroundStyle(task.status == .done ? PulseColors.textMuted : PulseColors.textPrimary)
                            .strikethrough(task.status == .done)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(PulseColors.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toggleTask(_ task: TaskItem) {
        task.status = task.status == .done ? .todo : .done
        modelContext.saveOrLog("travel.checklist")
        HapticService.success()
    }

    // MARK: Destination info

    @ViewBuilder private func destinationInfoSection(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Good to know", systemImage: "info.circle")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { destinationInfoWithAI(trip) } label: {
                    Label(trip.hasDestinationInfo ? "Refresh" : "Get with AI", systemImage: "sparkles")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.accent)
                }
                .buttonStyle(.plain)
            }
            if trip.hasDestinationInfo {
                if let currency = trip.destinationCurrency, !currency.isEmpty {
                    infoRow("Currency", currency, systemImage: "dollarsign.circle")
                }
                if let language = trip.destinationLanguage, !language.isEmpty {
                    infoRow("Language", language, systemImage: "character.bubble")
                }
                if let delta = trip.timeZoneDeltaDescription {
                    infoRow("Time zone", delta, systemImage: "clock")
                }
                if let tip = trip.destinationTip, !tip.isEmpty {
                    Text(tip)
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                        .padding(.top, 2)
                }
            } else {
                Text("Ask the assistant for \(trip.destination)'s currency, language, time difference, and a local tip.")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
        .padding(14)
        .background(PulseColors.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoRow(_ label: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textSecondary)
            Spacer()
            Text(value)
                .font(PulseFont.bodyMedium(13))
                .foregroundStyle(PulseColors.textPrimary)
        }
    }

    private func destinationInfoWithAI(_ trip: Trip) {
        nav.askAI("Tell me the key facts for \(trip.destination): local currency (ISO code), main language, the time difference from where I am, and one essential local tip. Save them to this trip with set_destination_info.")
    }

    // MARK: Packing list
    @ViewBuilder private func packingSection(_ trip: Trip) -> some View {
        let done = packingTasks.filter { $0.status == .done }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Packing", systemImage: "suitcase.rolling")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                if !packingTasks.isEmpty {
                    Text("\(done)/\(packingTasks.count)")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textSecondary)
                } else {
                    Button { packWithAI(trip) } label: {
                        Label("Build with AI", systemImage: "sparkles")
                            .font(PulseFont.body(12))
                            .foregroundStyle(PulseColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(packingTasks) { task in
                HStack(spacing: 10) {
                    Button { toggleTask(task) } label: {
                        Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.status == .done ? PulseColors.success : PulseColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.status == .done ? "Mark not packed" : "Mark packed")
                    Text(task.title)
                        .font(PulseFont.body(14))
                        .foregroundStyle(task.status == .done ? PulseColors.textMuted : PulseColors.textPrimary)
                        .strikethrough(task.status == .done)
                    Spacer()
                    Button { deletePacking(task) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PulseColors.textFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(task.title)")
                }
            }
            HStack(spacing: 8) {
                TextField("Add item", text: $newPackingItem)
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textPrimary)
                    .onSubmit { addPacking(trip) }
                Button { addPacking(trip) } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(newPackingItem.trimmingCharacters(in: .whitespaces).isEmpty ? PulseColors.textFaint : PulseColors.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(newPackingItem.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add packing item")
            }
            .padding(10)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(PulseColors.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func addPacking(_ trip: Trip) {
        let title = newPackingItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let order = (packingTasks.map(\.order).max() ?? -1) + 1
        let task = TaskItem(title: title, group: TravelTools.packingGroup, label: trip.destination, order: order, tripId: trip.id)
        modelContext.insert(task)
        modelContext.saveOrLog("travel.packing")
        HapticService.selection()
        newPackingItem = ""
    }

    private func deletePacking(_ task: TaskItem) {
        modelContext.delete(task)
        modelContext.saveOrLog("travel.packing")
        HapticService.selection()
    }

    private func packWithAI(_ trip: Trip) {
        var ctx = "Build me a smart packing list for my trip to \(trip.destination)"
        if let start = trip.startDate, let end = trip.endDate {
            let days = max(1, (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
            ctx += " (\(days) days)"
        }
        ctx += ". Tailor it to the season, weather, and the things I have planned, then save it to this trip's packing list."
        nav.askAI(ctx)
    }

    // MARK: Travel documents

    @ViewBuilder private func docsSection(_ trip: Trip) -> some View {
        let docs = linkedNotes.filter { isDoc($0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Travel documents", systemImage: "doc.text")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { showingAddDoc = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add travel document")
            }
            if docs.isEmpty {
                Text("Keep passport, visa, and booking confirmation references here.")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textMuted)
            } else {
                ForEach(docs) { note in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(PulseColors.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Document" : note.title)
                                .font(PulseFont.bodyMedium(14))
                                .foregroundStyle(PulseColors.textPrimary)
                            if let preview = notedPreview(note) {
                                Text(preview)
                                    .font(PulseFont.body(12))
                                    .foregroundStyle(PulseColors.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(PulseColors.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showingAddDoc) {
            TravelDocSheet(trip: trip)
        }
    }

    /// A linked note is treated as a "travel document" when titled/tagged as such.
    private func isDoc(_ note: Note) -> Bool {
        let t = note.title.lowercased()
        return t.contains("passport") || t.contains("visa") || t.contains("confirmation")
            || t.contains("booking") || t.contains("reservation") || t.contains("doc")
            || t.contains("ticket") || t.contains("insurance")
    }

    // MARK: Trip notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(PulseFont.bodySemibold(14))
                .foregroundStyle(PulseColors.textPrimary)
            ForEach(generalNotes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textPrimary)
                    if let preview = notedPreview(note) {
                        Text(preview)
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(PulseColors.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func notedPreview(_ note: Note) -> String? {
        note.blocks
            .sorted { $0.order < $1.order }
            .first { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .content
    }

    // MARK: Itinerary — by day

    @ViewBuilder private func dayGroupedItinerary(_ trip: Trip) -> some View {
        let grouped = Dictionary(grouping: trip.items) { $0.dayOffset ?? 0 }
        let days = grouped.keys.sorted()
        ForEach(days, id: \.self) { day in
            let items = (grouped[day] ?? []).sorted {
                ($0.startAt ?? .distantFuture, $0.order) < ($1.startAt ?? .distantFuture, $1.order)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(dayLabel(day, trip: trip))
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                ForEach(items) { item in
                    TripItemRow(item: item, onToggleBooked: { toggleBooked(item) }, onEdit: { editingItem = item })
                }
            }
        }
    }

    private func dayLabel(_ offset: Int, trip: Trip) -> String {
        if let start = trip.startDate,
           let date = Calendar.current.date(byAdding: .day, value: offset, to: start) {
            return "Day \(offset + 1) · \(TravelFormat.weekdayDate.string(from: date))"
        }
        return "Day \(offset + 1)"
    }

    // MARK: Itinerary — by type

    @ViewBuilder private func typeGroupedItinerary(_ trip: Trip) -> some View {
        ForEach(TripItemKind.allCases, id: \.self) { kind in
            let items = trip.items.filter { $0.kind == kind }
                .sorted { ($0.dayOffset ?? 0, $0.order) < ($1.dayOffset ?? 0, $1.order) }
            if !items.isEmpty {
                section(kind: kind, items: items)
            }
        }
    }

    private func tripHeader(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover = trip.coverImageURL, let url = URL(string: cover) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(PulseColors.fillMuted)
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(trip.destination)
                        .font(PulseFont.title(26))
                        .foregroundStyle(PulseColors.textPrimary)
                    Spacer()
                    StatusChip(label: trip.status.rawValue.capitalized, style: .neutral)
                }
                if let origin = trip.originCity {
                    Label("From \(origin)", systemImage: "airplane.departure")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                if let start = trip.startDate {
                    let range = trip.endDate.map { "\(TravelFormat.weekdayDate.string(from: start)) – \(TravelFormat.weekdayDate.string(from: $0))" } ?? TravelFormat.weekdayDate.string(from: start)
                    Label(range, systemImage: "calendar")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                Label(trip.travelerCount == 1 ? "1 traveler" : "\(trip.travelerCount) travelers", systemImage: "person.2")
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textSecondary)
                if let notes = trip.notes, !notes.isEmpty {
                    Text(notes)
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCardSurface()
    }

    private func budgetSection(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Budget", systemImage: "creditcard")
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                if let budget = trip.budgetAmount {
                    Text("of \(money(budget, trip.effectiveCurrency))")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
            }
            HStack(spacing: 20) {
                budgetStat("Estimated", money(trip.estimatedCost, trip.effectiveCurrency))
                budgetStat("Booked", money(trip.bookedCost, trip.effectiveCurrency))
            }
            if let budget = trip.budgetAmount, budget > 0 {
                ProgressView(value: min(trip.estimatedCost / budget, 1.0))
                    .tint(trip.estimatedCost > budget ? PulseColors.alert : PulseColors.accent)
            }
            let byKind = trip.costByKind
            if !byKind.isEmpty {
                VStack(spacing: 4) {
                    ForEach(byKind, id: \.0) { kind, amount in
                        HStack {
                            Label(kind.label, systemImage: kind.icon)
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textSecondary)
                            Spacer()
                            Text(money(amount, trip.effectiveCurrency))
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textPrimary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pulseCardSurface()
    }

    private func budgetStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(PulseFont.body(11))
                .foregroundStyle(PulseColors.textMuted)
            Text(value)
                .font(PulseFont.titleSemibold(18))
                .foregroundStyle(PulseColors.textPrimary)
        }
    }

    private func money(_ amount: Double, _ currency: String) -> String {
        let symbol: String
        switch currency.uppercased() {
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        case "JPY": symbol = "¥"
        default: symbol = currency.uppercased() + " "
        }
        let n = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(format: "%.0f", amount)
        return symbol + n
    }

    private func section(kind: TripItemKind, items: [TripItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(kind.label, systemImage: kind.icon)
                    .font(PulseFont.bodySemibold(14))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                Button { planTripWithAI(currentTrip, kind: kind) } label: {
                    Label("Find with AI", systemImage: "sparkles")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.accent)
                }
                .buttonStyle(.plain)
                Button { addingItemKind = kind } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(kind.label)")
            }
            ForEach(items) { item in
                TripItemRow(item: item, onToggleBooked: { toggleBooked(item) }, onEdit: { editingItem = item })
            }
        }
    }

    private var currentTrip: Trip { trip ?? Trip(destination: "") }

    private func toggleBooked(_ item: TripItem) {
        item.booked.toggle()
        modelContext.saveOrLog("travel.ui")
        HapticService.selection()
    }
}

private struct TripItemRow: View {
    let item: TripItem
    var onToggleBooked: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button(action: onToggleBooked) {
                    Image(systemName: item.booked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.booked ? PulseColors.success : PulseColors.textMuted)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.booked ? "Mark not booked" : "Mark booked")
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(PulseFont.bodyMedium(14))
                            .foregroundStyle(PulseColors.textPrimary)
                            .multilineTextAlignment(.leading)
                        if let location = item.location {
                            Text(location)
                                .font(PulseFont.body(12))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                if let price = item.price {
                    Text(priceText(price, item.currency))
                        .font(PulseFont.bodySemibold(13))
                        .foregroundStyle(PulseColors.textPrimary)
                }
            }
            if let details = item.details, !details.isEmpty {
                Text(details)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textSecondary)
                    .padding(.leading, 26)
            }
            if let urlString = item.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.accent)
                }
                .padding(.leading, 26)
            }
        }
        .padding(12)
        .pulseCardSurface()
    }

    private func priceText(_ price: Double, _ currency: String?) -> String {
        let symbol: String
        switch (currency ?? "USD").uppercased() {
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        case "JPY": symbol = "¥"
        default: symbol = ((currency ?? "") + " ")
        }
        let n = price.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(price)) : String(format: "%.2f", price)
        return symbol + n
    }
}

// MARK: - Quick-add category chips

/// A wrapping row of category chips (SF Symbol + label) used in empty states to
/// jump straight into the manual add sheet pre-set to a kind. Design-system styled.
private struct FlowChips: View {
    let kinds: [TripItemKind]
    var onTap: (TripItemKind) -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(kinds) { kind in
                Button { onTap(kind) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: kind.icon)
                        Text(kind.label)
                    }
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Trip map
/// A map overview of a trip's located items. Geocodes each item's `location`
/// string lazily and drops a pin per resolved place, so the user gets a spatial
/// sense of the itinerary. Locations that fail to geocode are simply skipped.
private struct TripMapView: View {
    let items: [TripItem]
    @State private var places: [GeocodedPlace] = []
    @State private var position: MapCameraPosition = .automatic

    struct GeocodedPlace: Identifiable {
        let id: UUID
        let title: String
        let kind: TripItemKind
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        Group {
            if places.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Mapping your itinerary…")
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .pulseCardSurface()
            } else {
                Map(position: $position) {
                    ForEach(places) { place in
                        Marker(place.title, systemImage: place.kind.icon, coordinate: place.coordinate)
                            .tint(PulseColors.accent)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
            }
        }
        .task(id: items.map(\.id)) { await geocode() }
    }

    @MainActor private func geocode() async {
        let geocoder = CLGeocoder()
        var resolved: [GeocodedPlace] = []
        // Cap the number of geocodes to stay within Apple's rate limits.
        for item in items.prefix(12) {
            guard let location = item.location, !location.isEmpty else { continue }
            if let placemark = try? await geocoder.geocodeAddressString(location).first,
               let coord = placemark.location?.coordinate {
                resolved.append(GeocodedPlace(id: item.id, title: item.title, kind: item.kind, coordinate: coord))
            }
        }
        places = resolved
        if !resolved.isEmpty {
            position = .automatic
        }
    }
}
