import SwiftData
import Foundation

// MARK: - Rewards / points model (Travel+ T9)
//
// The user records the cards & loyalty programs they hold so Travel can compute the
// *best deal accounting for points*, not just the lowest cash price. Each `RewardCard`
// captures a rewards currency (e.g. "Amex MR", "Chase UR", "United miles"), the current
// balance, a per-point value (cents-per-point), and category earn multipliers used to
// estimate the value of points earned on a purchase.

@Model
final class RewardCard {
    @Attribute(.unique) var id: UUID
    /// Display name of the card/program, e.g. "Chase Sapphire Reserve".
    var name: String
    /// Rewards currency, e.g. "Chase UR", "Amex MR", "United miles".
    var currency: String
    /// Current points/miles balance.
    var pointsBalance: Int
    /// Value of one point in cents (cents-per-point). e.g. 1.5 for UR via transfers.
    var centsPerPoint: Double
    /// Earn multiplier on travel spend (points per $1).
    var earnTravel: Double
    /// Earn multiplier on dining spend (points per $1).
    var earnDining: Double
    /// Earn multiplier on everything else (points per $1).
    var earnOther: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        currency: String,
        pointsBalance: Int = 0,
        centsPerPoint: Double = 1.0,
        earnTravel: Double = 1.0,
        earnDining: Double = 1.0,
        earnOther: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.currency = currency
        self.pointsBalance = pointsBalance
        self.centsPerPoint = centsPerPoint
        self.earnTravel = earnTravel
        self.earnDining = earnDining
        self.earnOther = earnOther
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension RewardCard {
    /// Points-per-$1 earned for a given spend category.
    func earnRate(for category: SpendCategory) -> Double {
        switch category {
        case .travel: return max(0, earnTravel)
        case .dining: return max(0, earnDining)
        case .other: return max(0, earnOther)
        }
    }
}

// MARK: - Valuation engine (pure, unit-tested)

/// What kind of spend an option counts as, which decides the earn multiplier.
enum SpendCategory: String, Codable, CaseIterable {
    case travel, dining, other

    /// Map a travel option kind to a spend category for earn estimation.
    static func from(_ kind: TravelSearchResult.Kind) -> SpendCategory {
        switch kind {
        case .flight, .lodging, .transport: return .travel
        case .restaurant: return .dining
        case .activity: return .other
        }
    }
}

/// A points-based redemption option for an award price.
struct AwardPrice: Equatable, Sendable {
    /// Points/miles required.
    var points: Int
    /// Cash taxes/fees paid on top of points (in the option's currency).
    var fees: Double
    /// Which reward currency the points are in (must match a held card).
    var currency: String
}

/// The computed value of paying for one option, by method, ranked.
struct DealValuation: Equatable, Sendable {
    /// Straight cash price (nil when unknown).
    var cashPrice: Double?
    /// Points earned if paid with the best earning card, valued in cents → dollars.
    var earnedValue: Double
    /// Card used to earn (its name), if any held card applies.
    var earnCardName: String?
    /// Effective cost when paying cash = cash − value of points earned on the spend.
    var effectiveCashCost: Double?
    /// Effective cost of an award redemption = points×cpp + fees (nil when no award).
    var awardCost: Double?
    /// Card/program used for the award, if computed.
    var awardCardName: String?
    /// Human "best value" line, e.g. "≈ 35k pts + $56 — pay with Sapphire".
    var recommendation: String
    /// The lower of the comparable costs (used for ranking). Lower is better.
    var bestEffectiveCost: Double?
    /// True when any number here is an estimate (default cpp / no live valuation).
    var isEstimate: Bool
}

/// Pure points-aware valuation. No I/O — fed the option, its category, and the user's
/// held cards (plus an optional award price), returns a ranked recommendation.
enum PointsValuator {

    /// Format a point count compactly: 35200 → "35.2k", 1000000 → "1M".
    static func formatPoints(_ pts: Int) -> String {
        let p = Double(pts)
        if p >= 1_000_000 { return trimmed(p / 1_000_000) + "M" }
        if p >= 1_000 { return trimmed(p / 1_000) + "k" }
        return String(pts)
    }

    private static func trimmed(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(r)) : String(format: "%.1f", r)
    }

    private static func money(_ v: Double, currency: String) -> String {
        let symbol = currency.uppercased() == "USD" ? "$" : (currency.uppercased() + " ")
        let r = (v * 100).rounded() / 100
        if r.truncatingRemainder(dividingBy: 1) == 0 { return symbol + String(Int(r)) }
        return symbol + String(format: "%.2f", r)
    }

    /// The best card to *earn* on a given category: highest (earnRate × cpp).
    static func bestEarnCard(_ cards: [RewardCard], category: SpendCategory) -> RewardCard? {
        cards.max { a, b in
            (a.earnRate(for: category) * a.centsPerPoint) < (b.earnRate(for: category) * b.centsPerPoint)
        }
    }

    /// Find a held card matching an award currency (case-insensitive contains).
    static func card(for currency: String, in cards: [RewardCard]) -> RewardCard? {
        let needle = currency.lowercased()
        return cards.first { $0.currency.lowercased() == needle }
            ?? cards.first { $0.currency.lowercased().contains(needle) || needle.contains($0.currency.lowercased()) }
    }

    /// Compute the value of paying for `result`, considering cash earn and an optional
    /// award redemption, returning a ranked recommendation.
    static func evaluate(
        cashPrice: Double?,
        currency: String = "USD",
        category: SpendCategory,
        cards: [RewardCard],
        award: AwardPrice? = nil,
        valuationIsLive: Bool = false
    ) -> DealValuation {
        var isEstimate = !valuationIsLive

        // Value of points earned on cash spend with the best card for this category.
        var earnedValue = 0.0
        var earnCardName: String?
        if let cash = cashPrice, cash > 0, let earnCard = bestEarnCard(cards, category: category),
           earnCard.earnRate(for: category) > 0 {
            let pointsEarned = cash * earnCard.earnRate(for: category)
            earnedValue = pointsEarned * earnCard.centsPerPoint / 100.0
            earnCardName = earnCard.name
            isEstimate = true  // earn value is always an estimate
        }
        let effectiveCash = cashPrice.map { max(0, $0 - earnedValue) }

        // Award redemption cost, if an award price + matching card is available.
        var awardCost: Double?
        var awardCardName: String?
        if let award {
            let cppCard = card(for: award.currency, in: cards)
            let cpp = cppCard?.centsPerPoint ?? 1.0
            awardCost = Double(award.points) * cpp / 100.0 + award.fees
            awardCardName = cppCard?.name
            if cppCard == nil { isEstimate = true }
        }

        // Rank: lower comparable cost wins. Compare effective cash vs award cost.
        let candidates: [(cost: Double, isAward: Bool)] = [
            effectiveCash.map { ($0, false) },
            awardCost.map { ($0, true) },
        ].compactMap { $0 }
        let best = candidates.min { $0.cost < $1.cost }

        let recommendation: String = {
            guard let best else { return "No price available" }
            if best.isAward, let award {
                let card = awardCardName.map { " — pay with \($0)" } ?? ""
                let feeStr = award.fees > 0 ? " + \(money(award.fees, currency: currency))" : ""
                return "≈ \(formatPoints(award.points)) pts\(feeStr), ~\(money(best.cost, currency: currency)) value\(card)"
            } else {
                let card = earnCardName.map { " — pay with \($0)" } ?? ""
                let earn = earnedValue > 0 ? " (earn ~\(money(earnedValue, currency: currency)) back)" : ""
                return "\(money(best.cost, currency: currency)) effective\(earn)\(card)"
            }
        }()

        return DealValuation(
            cashPrice: cashPrice,
            earnedValue: earnedValue,
            earnCardName: earnCardName,
            effectiveCashCost: effectiveCash,
            awardCost: awardCost,
            awardCardName: awardCardName,
            recommendation: recommendation,
            bestEffectiveCost: best?.cost,
            isEstimate: isEstimate
        )
    }
}
