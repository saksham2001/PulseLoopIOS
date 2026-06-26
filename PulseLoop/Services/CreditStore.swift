import Foundation
import StoreKit

// MARK: - CreditStore — StoreKit 2 credit-pack purchases (roadmap E2)
//
// Loads consumable credit-pack products, runs purchases, and grants credits to the
// `CreditsLedger` on success. Works gracefully when no products are configured yet
// (e.g. running without a StoreKit config / App Store Connect entry): `products`
// is simply empty and the paywall shows an "unavailable" state instead of crashing.
//
// Product ids follow the convention `com.pulseloop.credits.<amount>`. Add matching
// entries to a StoreKit configuration file / App Store Connect to enable purchases.

/// A purchasable credit pack, paired with how many credits it grants.
struct CreditPack: Identifiable {
    let product: Product
    let credits: Int
    var id: String { product.id }
    var displayPrice: String { product.displayPrice }
    var title: String { product.displayName }
}

@MainActor
@Observable
final class CreditStore {
    static let shared = CreditStore()

    /// Maps product id → credits granted. Keep in sync with store configuration.
    static let creditsByProductID: [String: Int] = [
        "com.pulseloop.credits.100": 100,
        "com.pulseloop.credits.500": 500,
        "com.pulseloop.credits.1200": 1200,
    ]

    private(set) var packs: [CreditPack] = []
    private(set) var isLoading = false
    private(set) var purchaseInFlight: String?
    var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Listen for transactions that arrive outside an explicit purchase (e.g.
        // Ask-to-Buy approvals, restores) so credits are always granted once.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verification: update)
            }
        }
    }

    /// Load products from the store. Safe to call repeatedly.
    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: Set(Self.creditsByProductID.keys))
            packs = products
                .compactMap { product in
                    Self.creditsByProductID[product.id].map { CreditPack(product: product, credits: $0) }
                }
                .sorted { $0.credits < $1.credits }
        } catch {
            lastError = "Couldn't load credit packs: \(error.localizedDescription)"
        }
    }

    /// Purchase a credit pack. Grants credits + finishes the transaction on success.
    func purchase(_ pack: CreditPack) async {
        guard purchaseInFlight == nil else { return }
        purchaseInFlight = pack.id
        lastError = nil
        defer { purchaseInFlight = nil }
        do {
            let result = try await pack.product.purchase()
            switch result {
            case let .success(verification):
                await handle(verification: verification)
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Restore/refresh entitlements. Consumables don't restore credits (they're
    /// already granted on purchase), but this surfaces any unfinished transactions.
    func refreshCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            await handle(verification: result)
        }
    }

    // MARK: Internals

    private func handle(verification: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = verification else {
            lastError = "Could not verify the purchase."
            return
        }
        guard let credits = Self.creditsByProductID[transaction.productID] else {
            await transaction.finish()
            return
        }

        // Prefer server-side validation so the server-authoritative ledger is the
        // source of truth and a tampered client can't forge a grant (roadmap D2).
        // The signed JWS is sent to the proxy, which verifies it with Apple, grants
        // credits idempotently, and returns the authoritative balance. When the
        // backend isn't configured we fall back to a local grant (fine for
        // TestFlight/sandbox and an initial release).
        let validatedOnServer = await validateOnServer(
            jws: verification.jwsRepresentation,
            credits: credits
        )
        if !validatedOnServer {
            CreditsLedger.shared.grant(credits)
        }
        await transaction.finish()
    }

    /// Posts the signed transaction to the backend validation endpoint. Returns true
    /// when the server accepted it and we adopted its balance; false when the backend
    /// isn't configured or the call failed (caller falls back to a local grant).
    private func validateOnServer(jws: String, credits: Int) async -> Bool {
        let settings = CoachSettingsStore.shared.settings
        let trimmed = settings.backendProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed), base.scheme == "https" || base.scheme == "http",
              let token = (try? CloudSyncKeychainStore().readKey()) ?? nil, !token.isEmpty
        else { return false }

        var request = URLRequest(url: base.appendingPathComponent("v1/credits/validate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["signedTransaction": jws])
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let balance = root["balance"] as? Int {
                CreditsLedger.shared.syncAuthoritativeBalance(balance)
            }
            return true
        } catch {
            return false
        }
    }
}
