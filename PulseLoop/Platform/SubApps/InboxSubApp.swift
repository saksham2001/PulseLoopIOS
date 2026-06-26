import SwiftUI
import SwiftData

// MARK: - Inbox / AI Capture SubApp
//
// Migrated built-in (roadmap B16). Backed by the legacy `AppModule.aiCapture`
// module. Owns the unified "Life Inbox": captured items from connected accounts
// (mail, Slack, calendar) that the coach triages into suggested actions. Provides
// router-native destinations for the inbox feed and the voice mail-reply composer.
// Legacy `AppRoute` cases still work.

enum InboxRoute: SubAppRoute {
    case inbox
    case mailReply(UUID)
}

struct InboxSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.aiCapture.rawValue) }
    var displayName: String { AppModule.aiCapture.name }
    var iconSystemName: String { AppModule.aiCapture.icon }
    var summary: String { AppModule.aiCapture.description }
    // 1.1.0 — on-device, open-source voice engine layer (Voice roadmap A3):
    // pluggable STT/TTS engines behind VoiceServices with Apple fallback.
    var version: String { "1.1.0" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [InboxItem.self] }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: InboxRoute.self) { route, ctx in
            switch route {
            case .inbox:
                InboxView(path: ctx.path)
            case let .mailReply(id):
                MailReplyView(itemId: id)
            }
        }
    }
}
