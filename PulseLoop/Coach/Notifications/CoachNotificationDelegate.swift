import Foundation
import UserNotifications

/// Shared deep-link state. Setting `requestedConversationId` makes `MainTabView`
/// switch to the Coach tab and `CoachView` open that conversation. Used by both
/// daily-check-in notification taps and Today/Sleep summary-card taps.
@MainActor
@Observable
final class CoachNavigation {
    static let shared = CoachNavigation()
    var requestedConversationId: UUID?
    /// Set by the `navigate_to` Coach tool. `MainTabView` consumes this when the
    /// Coach is dismissed: it switches to `requestedTab` (if any) and/or pushes
    /// `requestedRoute` onto the navigation stack.
    var requestedRoute: AppRoute?
    var requestedTab: MainTab?

    /// A composer prefill to drop into the coach when it next opens (does NOT
    /// auto-send). Set by in-app "Ask AI"/"Plan with AI" affordances alongside
    /// posting `.openCoach`; consumed and cleared by `CoachView` on appear.
    var prefill: String?

    func open(_ conversationId: UUID) { requestedConversationId = conversationId }

    /// Open the coach from anywhere with the composer prefilled. Sets `prefill`
    /// and posts `.openCoach` so the host presents the coach fullScreenCover.
    func askAI(_ prompt: String) {
        prefill = prompt
        NotificationCenter.default.post(name: .openCoach, object: nil)
    }

    /// Queue an in-app navigation from the Coach. Either argument may be nil.
    func requestNavigation(route: AppRoute? = nil, tab: MainTab? = nil) {
        requestedRoute = route
        requestedTab = tab
    }
}

/// UNUserNotificationCenter delegate: shows check-ins while foreground and
/// deep-links a tap to the coach thread.
final class CoachNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let idString = info[CoachNotificationService.conversationIdKey] as? String,
           let id = UUID(uuidString: idString) {
            await MainActor.run { CoachNavigation.shared.open(id) }
        }
    }
}
