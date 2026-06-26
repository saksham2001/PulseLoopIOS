import Foundation
import SwiftData

/// Protocol for OAuth-based account connectors (Gmail, Calendar, Slack, etc.)
///
/// The current implementations are **demo stubs** (no real OAuth) — `isDemo` is `true`
/// for them so the UI can honestly badge them as "Demo" instead of implying a live
/// account link. When a real OAuth-backed connector is added, it sets `isDemo = false`.
protocol AccountConnector {
    var provider: AccountProvider { get }
    /// `true` when this connector returns canned demo data rather than a live account.
    var isDemo: Bool { get }
    func authorize() async throws -> Bool
    func fetchItems() async throws -> [InboxItemDTO]
    func disconnect() async
}

extension AccountConnector {
    var isDemo: Bool { true }
}

struct InboxItemDTO {
    let title: String
    let subtitle: String
    let icon: String
    let suggestedAction: String?
}

// MARK: - Gmail Stub

final class GmailConnector: AccountConnector {
    let provider: AccountProvider = .gmail

    func authorize() async throws -> Bool {
        // In production: OAuth 2.0 flow with Google
        return true
    }

    func fetchItems() async throws -> [InboxItemDTO] {
        return [
            InboxItemDTO(title: "Electric bill  -  $84", subtitle: "due Jun 22", icon: "envelope", suggestedAction: "Task · pay by Jun 22"),
            InboxItemDTO(title: "Your order ships today", subtitle: "Amazon · arriving Wed", icon: "shippingbox", suggestedAction: "Track shipment"),
            InboxItemDTO(title: "Maya: can you review the deck?", subtitle: "launch", icon: "number", suggestedAction: "Reply by voice"),
        ]
    }

    func disconnect() async {}
}

// MARK: - Calendar Stub

final class CalendarConnector: AccountConnector {
    let provider: AccountProvider = .googleCalendar

    func authorize() async throws -> Bool { true }

    func fetchItems() async throws -> [InboxItemDTO] {
        return [
            InboxItemDTO(title: "Team standup", subtitle: "9:30 AM · 30m", icon: "calendar", suggestedAction: nil),
            InboxItemDTO(title: "Strength workout", subtitle: "5:30 PM · 45m", icon: "figure.strengthtraining.traditional", suggestedAction: nil),
        ]
    }

    func disconnect() async {}
}

// MARK: - Slack Stub

final class SlackConnector: AccountConnector {
    let provider: AccountProvider = .slack

    func authorize() async throws -> Bool { true }

    func fetchItems() async throws -> [InboxItemDTO] {
        return [
            InboxItemDTO(title: "Standup reminder", subtitle: "#general", icon: "#", suggestedAction: "Join call"),
        ]
    }

    func disconnect() async {}
}

// MARK: - Extraction Pipeline

/// Reuses the Coach tool-calling pattern to extract structured data
/// (tasks, events, reminders) from raw inbox content.
@MainActor
final class ExtractionPipeline {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Takes raw content (email body, notification text, etc.) and extracts
    /// actionable items via the AI coach tooling.
    func extract(from content: String, source: InboxSource) async -> [InboxItem] {
        // In production: call CoachOrchestrator with extraction-specific tools
        // For now, return empty  -  the seed data already populates demo inbox items
        return []
    }

    /// Processes items from all connected account connectors.
    func processAllSources(connectors: [AccountConnector]) async {
        for connector in connectors {
            guard let items = try? await connector.fetchItems() else { continue }
            for dto in items {
                let item = InboxItem(
                    title: dto.title,
                    subtitle: dto.subtitle,
                    source: InboxSource(rawValue: connector.provider.rawValue) ?? .other,
                    icon: dto.icon,
                    suggestedAction: dto.suggestedAction
                )
                context.insert(item)
            }
        }
        context.saveOrLog("inbox.connectors")
    }
}
