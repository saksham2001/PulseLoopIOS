import UIKit

enum HapticService {
    /// Whether tactile feedback is enabled (Comfort profile → Soft haptics).
    private static var enabled: Bool { ComfortPrefs.softHaptics }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard enabled else { return }
        // "Soft" comfort mode dials medium/heavy impacts down to a gentler level.
        let softened: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .heavy, .rigid: softened = .light
        case .medium: softened = .soft
        default: softened = style
        }
        UIImpactFeedbackGenerator(style: softened).impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
