import Foundation
import SwiftData

/// Syncs every connected wearable + account in one pass. Called on app foreground
/// (and reusable from the existing background-refresh task) so newly connected
/// sources stay fresh without the user pressing "Sync now" on each row. Errors per
/// source are isolated — one provider failing never blocks the others — and surface
/// into each manager's `lastError`/row. Token auto-refresh is handled inside each
/// data source's `validAccessToken()` path; a hard auth failure leaves an honest
/// error on the row prompting reconnect.
@MainActor
enum ConnectedSourcesSyncCoordinator {
    /// Sync all connected sources. Returns the number that synced successfully.
    @discardableResult
    static func syncAll(context: ModelContext,
                        wearables: WearableConnectionManager = .shared,
                        accounts: AccountConnectionManager = .shared) async -> Int {
        var succeeded = 0

        for provider in WearableProvider.allCases where wearables.isConnected(provider) {
            do {
                _ = try await wearables.sync(provider, context: context)
                succeeded += 1
            } catch {
                // lastError is already set by the manager; keep going.
                continue
            }
        }

        let accountProviders: [AccountProvider] = [.gmail, .googleCalendar, .appleCalendar, .slack, .notion, .todoist]
        for provider in accountProviders where accounts.isConnected(provider) {
            do {
                _ = try await accounts.sync(provider, context: context)
                succeeded += 1
            } catch {
                continue
            }
        }

        return succeeded
    }

    /// Throttle key so foreground sync doesn't run on every brief resume.
    private static let lastRunKey = "connectedSources.lastFullSyncAt"

    /// Sync all connected sources at most once per `minInterval`. Use on foreground.
    static func syncAllIfDue(context: ModelContext, minInterval: TimeInterval = 15 * 60) async {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: lastRunKey) as? Date,
           now.timeIntervalSince(last) < minInterval {
            return
        }
        UserDefaults.standard.set(now, forKey: lastRunKey)
        _ = await syncAll(context: context)
    }
}
