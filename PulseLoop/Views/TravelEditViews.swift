import SwiftUI
import SwiftData

// MARK: - Travel manual create & edit (Travel+ T3)
//
// AI-independent create/edit for trips and itinerary items so the Travel module
// is fully usable by hand. Follows the PulseLoop design system: PulseColors/
// PulseFont, black primary buttons, hairline cards, design-system sheets
// (detents + drag indicator). No emoji — SF Symbols only.

// MARK: - Pure save logic (testable, no SwiftUI)

enum TravelEditing {
    /// Apply edited trip fields to a `Trip` (create the model elsewhere, then call this).
    @MainActor
    static func apply(
        to trip: Trip,
        destination: String,
        origin: String?,
        startDate: Date?,
        endDate: Date?,
        travelerCount: Int,
        budgetAmount: Double?,
        budgetCurrency: String?,
        notes: String?
    ) {
        trip.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.originCity = origin?.trimmedNonEmpty
        trip.startDate = startDate
        trip.endDate = endDate
        trip.travelerCount = max(1, travelerCount)
        trip.budgetAmount = budgetAmount
        trip.budgetCurrency = budgetCurrency?.trimmedNonEmpty
        trip.notes = notes?.trimmedNonEmpty
        trip.updatedAt = Date()
    }

    /// Apply edited item fields to a `TripItem`.
    @MainActor
    static func apply(
        to item: TripItem,
        kind: TripItemKind,
        title: String,
        details: String?,
        location: String?,
        url: String?,
        price: Double?,
        currency: String?,
        dayOffset: Int?,
        booked: Bool
    ) {
        item.kind = kind
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.details = details?.trimmedNonEmpty
        item.location = location?.trimmedNonEmpty
        item.url = url?.trimmedNonEmpty
        item.price = price
        item.currency = currency?.trimmedNonEmpty
        item.dayOffset = dayOffset
        item.booked = booked
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Trip create / edit sheet

struct TripEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new trip; non-nil = edit it.
    let trip: Trip?
    /// Called with the saved trip (new or existing) after persistence.
    var onSaved: ((Trip) -> Void)?

    @State private var destination = ""
    @State private var origin = ""
    @State private var hasDates = false
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3 * 86_400)
    @State private var travelers = 1
    @State private var budgetText = ""
    @State private var currency = "USD"
    @State private var notes = ""

    private var isEditing: Bool { trip != nil }
    private var canSave: Bool {
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Destination", systemImage: "mappin.and.ellipse") {
                        TextField("e.g. Lisbon, Portugal", text: $destination)
                            .textInputAutocapitalization(.words)
                    }
                    field("From", systemImage: "airplane.departure") {
                        TextField("Departure city (optional)", text: $origin)
                            .textInputAutocapitalization(.words)
                    }

                    Toggle(isOn: $hasDates) {
                        Text("Set dates")
                            .font(PulseFont.bodyMedium(14))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                    .tint(PulseColors.accent)
                    if hasDates {
                        VStack(spacing: 10) {
                            DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                        }
                        .font(PulseFont.body(14))
                    }

                    Stepper(value: $travelers, in: 1...20) {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundStyle(PulseColors.textMuted)
                            Text(travelers == 1 ? "1 traveler" : "\(travelers) travelers")
                                .font(PulseFont.body(14))
                                .foregroundStyle(PulseColors.textPrimary)
                        }
                    }

                    HStack(spacing: 10) {
                        field("Budget", systemImage: "creditcard") {
                            TextField("Optional", text: $budgetText)
                                .keyboardType(.decimalPad)
                        }
                        field("Currency", systemImage: "dollarsign.circle") {
                            TextField("USD", text: $currency)
                                .textInputAutocapitalization(.characters)
                        }
                        .frame(width: 110)
                    }

                    field("Notes", systemImage: "note.text") {
                        TextField("Anything to remember", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }

                    Button(action: save) {
                        Text(isEditing ? "Save changes" : "Create trip")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(canSave ? Color.black : PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle(isEditing ? "Edit trip" : "New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: loadIfEditing)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label.uppercased(), systemImage: systemImage)
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .foregroundStyle(PulseColors.textMuted)
            content()
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func loadIfEditing() {
        guard let trip else { return }
        destination = trip.destination
        origin = trip.originCity ?? ""
        if let s = trip.startDate { hasDates = true; startDate = s }
        if let e = trip.endDate { endDate = e }
        travelers = trip.travelerCount
        if let b = trip.budgetAmount { budgetText = b.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(b)) : String(b) }
        currency = trip.budgetCurrency ?? trip.effectiveCurrency
        notes = trip.notes ?? ""
    }

    private func save() {
        let target: Trip
        if let trip {
            target = trip
        } else {
            target = Trip(destination: destination)
            modelContext.insert(target)
        }
        TravelEditing.apply(
            to: target,
            destination: destination,
            origin: origin,
            startDate: hasDates ? startDate : nil,
            endDate: hasDates ? endDate : nil,
            travelerCount: travelers,
            budgetAmount: Double(budgetText.replacingOccurrences(of: ",", with: "")),
            budgetCurrency: currency,
            notes: notes
        )
        modelContext.saveOrLog("travel.tripEdit")
        HapticService.success()
        onSaved?(target)
        dismiss()
    }
}

// MARK: - Trip item create / edit sheet

struct TripItemEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    /// nil = add a new item; non-nil = edit it.
    let item: TripItem?
    /// Pre-selected kind for a new item (e.g. from a category "+" button).
    var defaultKind: TripItemKind = .activity

    @State private var kind: TripItemKind = .activity
    @State private var title = ""
    @State private var details = ""
    @State private var location = ""
    @State private var url = ""
    @State private var priceText = ""
    @State private var currency = "USD"
    @State private var dayText = ""
    @State private var booked = false

    private var isEditing: Bool { item != nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    kindPicker

                    field("Title", systemImage: "textformat") {
                        TextField(placeholder, text: $title)
                    }
                    field("Details", systemImage: "text.alignleft") {
                        TextField("Optional", text: $details, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    field("Location", systemImage: "mappin.and.ellipse") {
                        TextField("Address, neighborhood, or SFO → HND", text: $location)
                    }
                    field("Link", systemImage: "link") {
                        TextField("Booking or info URL (optional)", text: $url)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    HStack(spacing: 10) {
                        field("Price", systemImage: "tag") {
                            TextField("Optional", text: $priceText)
                                .keyboardType(.decimalPad)
                        }
                        field("Currency", systemImage: "dollarsign.circle") {
                            TextField("USD", text: $currency)
                                .textInputAutocapitalization(.characters)
                        }
                        .frame(width: 100)
                        field("Day", systemImage: "calendar") {
                            TextField("1", text: $dayText)
                                .keyboardType(.numberPad)
                        }
                        .frame(width: 70)
                    }

                    Toggle(isOn: $booked) {
                        Text("Booked / confirmed")
                            .font(PulseFont.bodyMedium(14))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                    .tint(PulseColors.success)

                    Button(action: save) {
                        Text(isEditing ? "Save changes" : "Add to trip")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(canSave ? Color.black : PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle(isEditing ? "Edit item" : "Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
    }

    private var placeholder: String {
        switch kind {
        case .flight: return "e.g. United UA837 SFO → HND"
        case .lodging: return "e.g. Park Hyatt Tokyo"
        case .activity: return "e.g. teamLab Planets"
        case .restaurant: return "e.g. Sukiyabashi Jiro"
        case .transport: return "e.g. Narita Express"
        case .note: return "e.g. Reservation confirmation"
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TYPE")
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .foregroundStyle(PulseColors.textMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TripItemKind.allCases, id: \.self) { k in
                        Button { kind = k } label: {
                            HStack(spacing: 6) {
                                Image(systemName: k.icon)
                                Text(k.label)
                            }
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(kind == k ? .white : PulseColors.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(kind == k ? Color.black : PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label.uppercased(), systemImage: systemImage)
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .foregroundStyle(PulseColors.textMuted)
            content()
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func load() {
        if let item {
            kind = item.kind
            title = item.title
            details = item.details ?? ""
            location = item.location ?? ""
            url = item.url ?? ""
            if let p = item.price { priceText = p.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(p)) : String(p) }
            currency = item.currency ?? trip.effectiveCurrency
            if let d = item.dayOffset { dayText = String(d + 1) }
            booked = item.booked
        } else {
            kind = defaultKind
            currency = trip.effectiveCurrency
        }
    }

    private func save() {
        let target: TripItem
        if let item {
            target = item
        } else {
            let nextOrder = (trip.items.map(\.order).max() ?? -1) + 1
            target = TripItem(tripId: trip.id, kind: kind, title: title, order: nextOrder)
            modelContext.insert(target)
            trip.items.append(target)
        }
        // Day field is 1-based in the UI; store 0-based dayOffset.
        let dayOffset = Int(dayText).map { max(0, $0 - 1) }
        TravelEditing.apply(
            to: target,
            kind: kind,
            title: title,
            details: details,
            location: location,
            url: url,
            price: Double(priceText.replacingOccurrences(of: ",", with: "")),
            currency: currency,
            dayOffset: dayOffset,
            booked: booked
        )
        trip.updatedAt = Date()
        modelContext.saveOrLog("travel.itemEdit")
        HapticService.success()
        dismiss()
    }
}

// MARK: - Travel document sheet (Travel+ T4)

/// Capture a travel document reference — passport, visa, or a booking/reservation
/// confirmation — as a `Note` linked to the trip. Titled with a doc keyword so the
/// trip's "Travel documents" section picks it up. Design-system styled.
struct TravelDocSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let trip: Trip

    enum DocKind: String, CaseIterable, Identifiable {
        case confirmation = "Confirmation"
        case passport = "Passport"
        case visa = "Visa"
        case insurance = "Insurance"
        case ticket = "Ticket"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .confirmation: return "checkmark.seal"
            case .passport: return "person.text.rectangle"
            case .visa: return "doc.badge.gearshape"
            case .insurance: return "cross.case"
            case .ticket: return "ticket"
            }
        }
    }

    @State private var kind: DocKind = .confirmation
    @State private var title = ""
    @State private var reference = ""

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TYPE")
                            .font(PulseFont.bodyMedium(11))
                            .tracking(0.8)
                            .foregroundStyle(PulseColors.textMuted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(DocKind.allCases) { k in
                                    Button { kind = k } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: k.icon)
                                            Text(k.rawValue)
                                        }
                                        .font(PulseFont.bodyMedium(13))
                                        .foregroundStyle(kind == k ? .white : PulseColors.textSecondary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 36)
                                        .background(kind == k ? Color.black : PulseColors.fillSubtle)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    field("Title", systemImage: "textformat") {
                        TextField(titlePlaceholder, text: $title)
                    }
                    field("Reference / details", systemImage: "number") {
                        TextField("Confirmation #, doc number, notes (optional)", text: $reference, axis: .vertical)
                            .lineLimit(2...6)
                    }

                    Button(action: save) {
                        Text("Save document")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(canSave ? Color.black : PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Add document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { if title.isEmpty { title = defaultTitle } }
        .onChange(of: kind) { _, _ in title = defaultTitle }
    }

    private var defaultTitle: String { "\(kind.rawValue) — \(trip.destination)" }

    private var titlePlaceholder: String {
        switch kind {
        case .confirmation: return "Hotel booking confirmation"
        case .passport: return "Passport"
        case .visa: return "Tourist visa"
        case .insurance: return "Travel insurance"
        case .ticket: return "Flight ticket"
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label.uppercased(), systemImage: systemImage)
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .foregroundStyle(PulseColors.textMuted)
            content()
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(title: trimmed, linkedTripId: trip.id)
        modelContext.insert(note)
        let body = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            let block = NoteBlock(noteId: note.id, order: 0, kind: .paragraph, content: body)
            modelContext.insert(block)
            note.blocks.append(block)
        }
        modelContext.saveOrLog("travel.doc")
        HapticService.success()
        dismiss()
    }
}

// MARK: - Reward card create / edit sheet (Travel+ T9)

/// Capture a credit card / loyalty program so Travel can value points and recommend
/// the best way to pay — not just the lowest cash price. Design-system styled.
struct RewardCardEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = create; non-nil = edit.
    let card: RewardCard?

    @State private var name = ""
    @State private var currency = ""
    @State private var balanceText = ""
    @State private var cppText = ""
    @State private var earnTravelText = "1"
    @State private var earnDiningText = "1"
    @State private var earnOtherText = "1"

    private var isEditing: Bool { card != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Card / program", systemImage: "creditcard") {
                        TextField("e.g. Chase Sapphire Reserve", text: $name)
                            .textInputAutocapitalization(.words)
                    }
                    field("Rewards currency", systemImage: "star.circle") {
                        TextField("e.g. Chase UR, Amex MR, United miles", text: $currency)
                    }
                    HStack(spacing: 10) {
                        field("Points balance", systemImage: "number") {
                            TextField("0", text: $balanceText)
                                .keyboardType(.numberPad)
                        }
                        field("Value / pt (¢)", systemImage: "centsign.circle") {
                            TextField("1.5", text: $cppText)
                                .keyboardType(.decimalPad)
                        }
                        .frame(width: 130)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("EARN MULTIPLIERS (PTS PER $1)", systemImage: "chart.line.uptrend.xyaxis")
                            .font(PulseFont.bodyMedium(11))
                            .tracking(0.8)
                            .foregroundStyle(PulseColors.textMuted)
                        HStack(spacing: 10) {
                            earnField("Travel", text: $earnTravelText)
                            earnField("Dining", text: $earnDiningText)
                            earnField("Other", text: $earnOtherText)
                        }
                    }

                    Button(action: save) {
                        Text(isEditing ? "Save changes" : "Add card")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(canSave ? Color.black : PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle(isEditing ? "Edit card" : "Add rewards card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
        .onChange(of: currency) { _, new in
            // Prefill a sensible default cpp the first time a known currency is typed.
            if cppText.isEmpty { cppText = trimmedNumber(DefaultPointValues.cpp(for: new)) }
        }
    }

    @ViewBuilder
    private func earnField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(PulseFont.body(11))
                .foregroundStyle(PulseColors.textMuted)
            TextField("1", text: text)
                .keyboardType(.decimalPad)
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label.uppercased(), systemImage: systemImage)
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .foregroundStyle(PulseColors.textMuted)
            content()
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func trimmedNumber(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    private func load() {
        guard let card else { return }
        name = card.name
        currency = card.currency
        balanceText = card.pointsBalance > 0 ? String(card.pointsBalance) : ""
        cppText = trimmedNumber(card.centsPerPoint)
        earnTravelText = trimmedNumber(card.earnTravel)
        earnDiningText = trimmedNumber(card.earnDining)
        earnOtherText = trimmedNumber(card.earnOther)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCurrency.isEmpty else { return }
        let target: RewardCard
        if let card {
            target = card
        } else {
            target = RewardCard(name: trimmedName, currency: trimmedCurrency)
            modelContext.insert(target)
        }
        target.name = trimmedName
        target.currency = trimmedCurrency
        target.pointsBalance = max(0, Int(balanceText.filter(\.isNumber)) ?? 0)
        target.centsPerPoint = Double(cppText) ?? DefaultPointValues.cpp(for: trimmedCurrency)
        target.earnTravel = max(0, Double(earnTravelText) ?? 1)
        target.earnDining = max(0, Double(earnDiningText) ?? 1)
        target.earnOther = max(0, Double(earnOtherText) ?? 1)
        target.updatedAt = Date()
        modelContext.saveOrLog("travel.rewardCard")
        HapticService.success()
        dismiss()
    }
}

// MARK: - Wallet & rewards (Travel+ T9)

/// Manage the credit cards / loyalty programs the user holds so Travel can compute the
/// best deal accounting for points. Design-system styled; AI-independent.
struct RewardWalletView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RewardCard.createdAt, order: .reverse) private var cards: [RewardCard]

    @State private var editingCard: RewardCard?
    @State private var addingCard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add the cards and loyalty programs you hold. Travel uses your points value and earn rates to recommend the best way to pay — not just the lowest cash price.")
                        .font(PulseFont.body(13))
                        .foregroundStyle(PulseColors.textSecondary)
                        .padding(.bottom, 2)

                    if cards.isEmpty {
                        emptyState
                    } else {
                        ForEach(cards) { card in
                            Button { editingCard = card } label: { cardRow(card) }
                                .buttonStyle(.plain)
                        }
                    }

                    Button { addingCard = true } label: {
                        Label("Add card", systemImage: "plus")
                            .font(PulseFont.bodySemibold(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(PulseColors.background)
            .navigationTitle("Wallet & rewards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $addingCard) { RewardCardEditSheet(card: nil) }
        .sheet(item: $editingCard) { RewardCardEditSheet(card: $0) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(PulseColors.textMuted)
            Text("No cards yet")
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Add a card to unlock points-aware deal recommendations.")
                .font(PulseFont.body(13))
                .foregroundStyle(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .pulseCardSurface()
    }

    private func cardRow(_ card: RewardCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.name)
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                Spacer()
                if card.pointsBalance > 0 {
                    Text("\(PointsValuator.formatPoints(card.pointsBalance)) pts")
                        .font(PulseFont.bodyMedium(13))
                        .foregroundStyle(PulseColors.textSecondary)
                }
            }
            Text(card.currency)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
            HStack(spacing: 12) {
                metric("Value", trimNum(card.centsPerPoint) + "¢/pt")
                metric("Travel", trimNum(card.earnTravel) + "x")
                metric("Dining", trimNum(card.earnDining) + "x")
                metric("Other", trimNum(card.earnOther) + "x")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .pulseCardSurface()
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(PulseFont.body(9))
                .tracking(0.6)
                .foregroundStyle(PulseColors.textMuted)
            Text(value)
                .font(PulseFont.bodyMedium(12))
                .foregroundStyle(PulseColors.textPrimary)
        }
    }

    private func trimNum(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
