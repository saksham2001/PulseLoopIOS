import Foundation
import Combine

// MARK: - CreditsLedger (roadmap E1)
//
// Tracks the user's AI credit balance and records every debit/credit as a ledger
// entry. Metering hooks (added in this iteration) call `meter(...)` on each AI call
// so usage is always accounted for. Enforcement (blocking calls when the balance is
// empty) and purchasing (StoreKit credit packs) arrive in E2/E3; for now the ledger
// records usage and exposes a balance so the UI + future paywall can read it.
//
// Persistence is a simple Codable snapshot in UserDefaults — credits are a
// client-side convenience here; a server-authoritative ledger lands with the
// backend-proxy provider mode (E3).

/// What an AI call was for. Drives both the public label and the credit cost model.
enum AIUsageKind: String, Codable {
    case coachTurn          // a chat turn with the coach
    case summary            // generated daily/weekly summary
    case notification       // generated push notification copy
    case dailyLearning      // generated learning card
    case subAppGeneration   // generate/refine a sub-app spec
    case imageAnalysis      // food/product image analysis
    case mediaGeneration    // image/video generation via muapi.ai
    case other

    var label: String {
        switch self {
        case .coachTurn: return "Assistant chat"
        case .summary: return "Summary"
        case .notification: return "Notification"
        case .dailyLearning: return "Daily learning"
        case .subAppGeneration: return "Sub-app builder"
        case .imageAnalysis: return "Image analysis"
        case .mediaGeneration: return "Media generation"
        case .other: return "AI usage"
        }
    }

    /// Flat credit cost per call. A token-based cost can layer on later; flat keeps
    /// the model legible for users. Sub-app generation is pricier (multi-step).
    var baseCost: Int {
        switch self {
        case .coachTurn: return 1
        case .summary: return 1
        case .notification: return 1
        case .dailyLearning: return 1
        case .subAppGeneration: return 2
        case .imageAnalysis: return 1
        case .mediaGeneration: return 3
        case .other: return 1
        }
    }
}

/// One immutable ledger entry.
struct CreditLedgerEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let kind: AIUsageKind
    /// Negative for debits (usage), positive for credits (grants/purchases).
    let delta: Int
    /// Balance immediately after this entry was applied.
    let balanceAfter: Int
    /// Optional token usage captured at metering time.
    let inputTokens: Int?
    let outputTokens: Int?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: AIUsageKind,
        delta: Int,
        balanceAfter: Int,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.delta = delta
        self.balanceAfter = balanceAfter
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

@MainActor
final class CreditsLedger: ObservableObject {
    static let shared = CreditsLedger()

    private static let balanceKey = "pulseloop.credits.balance.v1"
    private static let entriesKey = "pulseloop.credits.entries.v1"
    private static let grantedKey = "pulseloop.credits.initialGranted.v1"
    /// Credits granted to a fresh install so the features are usable out of the box.
    static let initialGrant = 50
    /// Cap stored history so UserDefaults stays small.
    private static let maxEntries = 200

    private let defaults: UserDefaults

    @Published private(set) var balance: Int
    @Published private(set) var entries: [CreditLedgerEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.balance = defaults.integer(forKey: Self.balanceKey)
        if let data = defaults.data(forKey: Self.entriesKey),
           let decoded = try? JSONDecoder().decode([CreditLedgerEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
        grantInitialIfNeeded()
    }

    /// Temporary override: credits are unlimited for now, so every call is
    /// affordable regardless of the recorded balance. Flip back to
    /// `balance >= kind.baseCost` to re-enable client-side enforcement.
    static let unlimited = true

    /// Whether there are enough credits to cover `kind`. Enforcement uses this in E2.
    func canAfford(_ kind: AIUsageKind) -> Bool {
        Self.unlimited || balance >= kind.baseCost
    }

    /// Record usage for an AI call. Returns the entry created. Always records, even
    /// if it drives the balance negative — enforcement (refusing the call) is a
    /// separate concern wired in E2 so we never silently lose accounting.
    @discardableResult
    func meter(_ kind: AIUsageKind, usage: OpenAIResponse.TokenUsage? = nil) -> CreditLedgerEntry {
        // Unlimited mode: record the usage for history but don't reduce the balance,
        // so the user is never blocked or shown an empty balance.
        let delta = Self.unlimited ? 0 : -kind.baseCost
        return apply(
            kind: kind,
            delta: delta,
            inputTokens: usage?.inputTokens,
            outputTokens: usage?.outputTokens
        )
    }

    /// Add credits (initial grant, future purchases, or a refund).
    @discardableResult
    func grant(_ amount: Int, kind: AIUsageKind = .other) -> CreditLedgerEntry {
        apply(kind: kind, delta: abs(amount), inputTokens: nil, outputTokens: nil)
    }

    /// Adopt a server-authoritative balance (roadmap E3 backend-proxy mode). The
    /// proxy is the source of truth when it reports a balance; we record the
    /// reconciliation as a ledger adjustment so history stays consistent, but only
    /// when it actually differs from the local count.
    func syncAuthoritativeBalance(_ serverBalance: Int) {
        // Unlimited mode: ignore server reconciliation so the local balance isn't
        // pulled down to a metered value while credits are free.
        guard !Self.unlimited else { return }
        guard serverBalance != balance else { return }
        let delta = serverBalance - balance
        apply(kind: .other, delta: delta, inputTokens: nil, outputTokens: nil)
    }

    // MARK: Internals

    private func grantInitialIfNeeded() {
        guard !defaults.bool(forKey: Self.grantedKey) else { return }
        defaults.set(true, forKey: Self.grantedKey)
        grant(Self.initialGrant)
    }

    @discardableResult
    private func apply(kind: AIUsageKind, delta: Int, inputTokens: Int?, outputTokens: Int?) -> CreditLedgerEntry {
        balance += delta
        let entry = CreditLedgerEntry(
            kind: kind,
            delta: delta,
            balanceAfter: balance,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        persist()
        return entry
    }

    private func persist() {
        defaults.set(balance, forKey: Self.balanceKey)
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.entriesKey)
        }
    }
}
