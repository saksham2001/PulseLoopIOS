import Foundation
import UserNotifications
import SwiftData

@MainActor
final class MedicationReminderService {
    static let shared = MedicationReminderService()

    private let notificationCenter = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleReminders(for medications: [Medication]) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers:
            medications.map { "med-\($0.id.uuidString)" }
        )

        for med in medications where med.isActive {
            let (hour, minute) = timeComponents(for: med.timing)
            scheduleDaily(medication: med, hour: hour, minute: minute)
        }
    }

    func rescheduleAll(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Medication>()
        guard let meds = try? modelContext.fetch(descriptor) else { return }
        scheduleReminders(for: meds)
    }

    func cancelAll() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    private func scheduleDaily(medication: Medication, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(medication.name)"
        content.body = "\(medication.dose) · \(medication.category.rawValue.capitalized)"
        content.sound = .default
        content.categoryIdentifier = "MEDICATION_REMINDER"
        content.userInfo = ["medicationId": medication.id.uuidString]

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "med-\(medication.id.uuidString)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }

    private func timeComponents(for timing: String) -> (hour: Int, minute: Int) {
        switch timing.lowercased() {
        case "am", "morning":
            return (8, 0)
        case "pm", "afternoon":
            return (14, 0)
        case "evening":
            return (18, 0)
        case "before bed", "night":
            return (21, 0)
        case "with meals", "lunch":
            return (12, 0)
        default:
            return (9, 0)
        }
    }
}
