import SwiftUI

/// OLED-optimized dark theme for Apple Watch.
enum WatchColors {
    static let background = Color.black
    static let card = Color(hex: "#1A1A1A")
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#AAAAAA")
    static let textMuted = Color(hex: "#666666")
    static let accent = Color(hex: "#FFFFFF")
    static let success = Color(hex: "#4ADE80")
    static let alert = Color(hex: "#F87171")
    static let ring = Color(hex: "#4ADE80")
}

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
