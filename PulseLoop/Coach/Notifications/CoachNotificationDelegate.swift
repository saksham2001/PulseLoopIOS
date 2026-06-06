import Foundation
import UserNotifications

/// Shared deep-link state set when a daily check-in notification is tapped.
/// `MainTabView` switches to the Coach tab and `CoachView` opens the
/// "Daily check-ins" thread when `openDailyCheckins` flips true.
@MainActor
@Observable
final class CoachNavigation {
    static let shared = CoachNavigation()
    var openDailyCheckins = false
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
        if info[CoachNotificationService.userInfoKey] != nil {
            await MainActor.run { CoachNavigation.shared.openDailyCheckins = true }
        }
    }
}
