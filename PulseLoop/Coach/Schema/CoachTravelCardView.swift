import SwiftUI
import MapKit

/// Renders the inline travel result cards (`CoachResponse.travelCards`) and an
/// optional `itinerary` outline in the assistant bubble — flights, stays,
/// activities, restaurants, and transport. Mirrors `CoachMediaCardView`'s role
/// for media. Each card maps 1:1 to a `TripItem`, and (when `onSave` is wired)
/// offers a "Save to trip" affordance so a chat result becomes a real itinerary
/// item ("one shape, two surfaces").
struct CoachTravelCardsView: View {
    let cards: [CoachTravelCard]
    let itinerary: [CoachItineraryDay]
    /// Save the given card to a trip. When nil, the save affordance is hidden.
    var onSave: ((CoachTravelCard) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Key by position: two cards can share the same derived id and would
            // otherwise collapse to one row under ForEach's Identifiable conformance.
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                CoachTravelCardView(card: card, onSave: onSave)
            }
            if !itinerary.isEmpty {
                CoachItineraryView(days: itinerary)
            }
        }
        .padding(.top, 2)
    }
}

/// A single travel result card.
struct CoachTravelCardView: View {
    let card: CoachTravelCard
    var onSave: ((CoachTravelCard) -> Void)?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let thumb = card.resolvedThumbnail {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        ProgressView().tint(PulseColors.accent)
                    default:
                        placeholderImage
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: card.kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulseColors.accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                        if let subtitle = card.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(PulseColors.textSecondary)
                        }
                    }
                    Spacer()
                    if let price = card.price {
                        Text(priceText(price, card.currency))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PulseColors.textPrimary)
                    }
                }

                metaRow

                HStack(spacing: 10) {
                    if let url = card.resolvedBookingURL {
                        Link(destination: url) {
                            Label("View", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(PulseColors.accent)
                        }
                    }
                    Spacer()
                    if onSave != nil {
                        Button {
                            onSave?(card)
                            withAnimation { saved = true }
                            HapticService.success()
                        } label: {
                            Label(saved ? "Saved" : "Save to trip",
                                  systemImage: saved ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(saved ? PulseColors.success : PulseColors.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .disabled(saved)
                    }
                }
                .padding(.top, 2)
            }
            .padding(12)
        }
        .background(PulseColors.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder private var metaRow: some View {
        let parts: [(String, String)] = {
            var p: [(String, String)] = []
            if let time = card.time, !time.isEmpty { p.append(("clock", time)) }
            if let location = card.location, !location.isEmpty { p.append(("mappin.and.ellipse", location)) }
            if let rating = card.rating { p.append(("star.fill", String(format: "%.1f", rating))) }
            return p
        }()
        if !parts.isEmpty {
            HStack(spacing: 12) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Label(part.1, systemImage: part.0)
                        .font(.system(size: 11))
                        .foregroundStyle(PulseColors.textMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Rectangle().fill(PulseColors.fillMuted)
            Image(systemName: card.kind.icon)
                .font(.system(size: 24))
                .foregroundStyle(PulseColors.textMuted)
        }
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

    private var accessibilityDescription: String {
        var parts = [card.kind.label, card.title]
        if let subtitle = card.subtitle { parts.append(subtitle) }
        if let time = card.time { parts.append(time) }
        if let location = card.location { parts.append(location) }
        if let price = card.price { parts.append(priceText(price, card.currency)) }
        if let rating = card.rating { parts.append("rated \(String(format: "%.1f", rating))") }
        return parts.joined(separator: ", ")
    }
}

/// A compact day-by-day outline rendered under the travel cards.
struct CoachItineraryView: View {
    let days: [CoachItineraryDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ITINERARY")
                .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(PulseColors.textMuted)
            ForEach(Array(days.sorted { $0.dayOffset < $1.dayOffset }.enumerated()), id: \.offset) { _, day in
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.displayLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PulseColors.textPrimary)
                    ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(PulseColors.accent)
                            Text(item).foregroundStyle(PulseColors.textSecondary)
                        }
                        .font(.system(size: 12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PulseColors.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
    }
}
