import SwiftUI

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Motion Preferences

extension EnvironmentValues {
    /// True when either the OS or the in-app comfort toggle asks to reduce motion.
    var motionReduced: Bool {
        accessibilityReduceMotion || ComfortPrefs.reduceMotion
    }
}

// MARK: - Navigation Routes

enum AppRoute: Hashable {
    case activityDetail(UUID)
    case recordSelect
    case recordLive(UUID)
    case recordSummary(UUID)
    case settings
    case debug
    case componentGallery
    case subAppBuilder
    case subAppEditor(String?)
    case credits
    case mySubApps
    case subAppRegistry
    case moduleUpdates
    /// AI quality dashboard: T0 signal rollup + deterministic eval pass rate.
    case coachQuality
    case inbox
    case dayPlan
    case notesList
    case noteEditor(UUID?)
    case mailReply(UUID)
    case connectAccounts
    case privacyPermissions
    case sidebar
    case health
    case vitals
    case sleep
    case activity
    case tasksList
    case friends
    case profile
    case insights
    case modulePicker
    /// Opens an installed spec sub-app's runtime by its id (e.g. just-installed
    /// AI-designed modules).
    case subApp(String)
    case fitness
    case workoutBuilder
    case exerciseLibrary
    case foodDiary
    case foodSearch(String)
    case workoutSession(UUID)
    case bodyProgress
    case journal
    case knowledgeBase
    case travel
    case tripDetail(UUID)
}

// MARK: - App Modules

enum AppModule: String, CaseIterable, Identifiable, Codable {
    case protocol_ = "protocol"
    case tasks = "tasks"
    case aiCapture = "ai_capture"
    case notes = "notes"
    case quitProgram = "quit_program"
    case accountability = "accountability"
    case dayPlan = "day_plan"
    case moodTracking = "mood"
    case nutrition = "nutrition"
    case sleep = "sleep"
    case workouts = "workouts"
    case travel = "travel"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .protocol_: return "Protocol"
        case .tasks: return "Tasks"
        case .aiCapture: return "AI Capture"
        case .notes: return "Notes"
        case .quitProgram: return "Quit Program"
        case .accountability: return "Accountability"
        case .dayPlan: return "Day Plan"
        case .moodTracking: return "Mood"
        case .nutrition: return "Nutrition"
        case .sleep: return "Sleep"
        case .workouts: return "Workouts"
        case .travel: return "Travel"
        }
    }

    var description: String {
        switch self {
        case .protocol_: return "Track supplements, medications & peptides"
        case .tasks: return "To-do lists and daily task management"
        case .aiCapture: return "Voice notes, photos & text organized by AI"
        case .notes: return "Structured note-taking with AI"
        case .quitProgram: return "Track vices you're quitting with streaks"
        case .accountability: return "Personal streaks, goals & milestones"
        case .dayPlan: return "AI-generated daily schedule"
        case .moodTracking: return "Daily mood & energy check-ins"
        case .nutrition: return "Meal logging & food scanning"
        case .sleep: return "Sleep tracking & quality logs"
        case .workouts: return "Workout logging & activity tracking"
        case .travel: return "Plan trips: flights, stays, things to do"
        }
    }

    var icon: String {
        switch self {
        case .protocol_: return "pills.fill"
        case .tasks: return "checklist"
        case .aiCapture: return "tray.fill"
        case .notes: return "note.text"
        case .quitProgram: return "xmark.circle.fill"
        case .accountability: return "flame.fill"
        case .dayPlan: return "calendar"
        case .moodTracking: return "face.smiling"
        case .nutrition: return "fork.knife"
        case .sleep: return "moon.fill"
        case .workouts: return "figure.run"
        case .travel: return "airplane"
        }
    }

    var color: Color {
        switch self {
        case .protocol_: return .orange
        case .tasks: return .blue
        case .aiCapture: return .purple
        case .notes: return .indigo
        case .quitProgram: return .red
        case .accountability: return .pink
        case .dayPlan: return .cyan
        case .moodTracking: return .yellow
        case .nutrition: return .green
        case .sleep: return .purple
        case .workouts: return .orange
        case .travel: return .teal
        }
    }
}

class ModuleManager {
    static let shared = ModuleManager()

    /// Enable/disable state and onboarding flag now live in `SubAppRegistry`.
    /// `ModuleManager` keeps its `AppModule`-based API and delegates storage so the
    /// platform has a single source of truth. The registry uses the same
    /// UserDefaults keys, so existing installs keep their saved selection.
    private var registry: SubAppRegistry { SubAppRegistry.shared }

    private func id(_ module: AppModule) -> SubAppID { SubAppID(module.rawValue) }

    var hasOnboarded: Bool {
        get { registry.hasOnboarded }
        set { registry.hasOnboarded = newValue }
    }

    var enabledModules: Set<AppModule> {
        get { Set(registry.enabledIDs.compactMap { AppModule(rawValue: $0.rawValue) }) }
        set { registry.enabledIDs = Set(newValue.map { id($0) }) }
    }

    func isEnabled(_ module: AppModule) -> Bool {
        registry.isEnabled(id(module))
    }

    func toggle(_ module: AppModule) {
        registry.toggle(id(module))
    }

    func enable(_ module: AppModule) {
        registry.setEnabled(id(module), true)
    }

    func setInitialModules(_ modules: Set<AppModule>) {
        registry.setInitial(Set(modules.map { id($0) }))
    }

    /// One-time migrations for modules added after a user's saved set was written.
    /// Existing installs persisted an explicit module list before `.workouts`
    /// powered the Fitness feature, so it would never appear. Force-enable it once.
    func runMigrations() {
        let migrationKey = "moduleMigration_workouts_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            if UserDefaults.standard.data(forKey: "enabledModules") != nil {
                enable(.workouts)
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        // Clear a persisted smart-tier model that loops on JSON-apology replies
        // (e.g. Gemini Flash). Such a selection makes the assistant surface
        // "I'll stick to the JSON schema" non-answers; reset to the reliable
        // default so the picker and behavior match.
        let smartFixKey = "aiModelFix_jsonReliableSmart_v1"
        if !UserDefaults.standard.bool(forKey: smartFixKey) {
            let key = AIModel.smart.storageKey
            if let stored = UserDefaults.standard.string(forKey: key),
               AIModel.jsonUnreliableSlugs.contains(stored) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(true, forKey: smartFixKey)
        }
    }
}

extension Notification.Name {
    static let switchTab = Notification.Name("switchTab")
    /// Posted by `SubAppRegistry` after a module is installed or uninstalled so
    /// install-aware surfaces (tabs, Home, sidebar, settings, Coach tools) refresh.
    static let installedModulesChanged = Notification.Name("installedModulesChanged")
    /// Posted by `CoachNavigation.askAI(_:)` to ask the current host (MainTabView /
    /// HomeView) to present the coach. A `prefill` is read from `CoachNavigation`.
    static let openCoach = Notification.Name("openCoach")
}

// MARK: - Tabs

enum MainTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case tracker = "Tracker"
    case askAI = "Ask AI"
    case inbox = "Inbox"
    case friends = "You"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .tracker: return "calendar.badge.checkmark"
        case .askAI: return "sparkles"
        case .inbox: return "envelope"
        case .friends: return "flame.fill"
        }
    }
}

// MARK: - Layout Tokens

/// Canonical corner radii. Collapse the previous 8/10/12/14/16/18/20/22/24 spread
/// into a small/medium/large/xLarge scale for consistent visual rhythm.
enum PulseRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 24
    static let pill: CGFloat = 999
}

/// Minimum hit target per Apple Human Interface Guidelines.
enum PulseLayout {
    static let minTapTarget: CGFloat = 44
}

// MARK: - Fitness Units

/// User-facing weight unit for fitness. Weights are always *stored* in kilograms
/// (`ExerciseSet.weightKg`); this only controls display + input conversion.
enum WeightUnit: String, CaseIterable, Identifiable {
    case kg = "kg"
    case lb = "lb"

    var id: String { rawValue }

    var label: String { rawValue }

    /// Preference key used with `@AppStorage`.
    static let storageKey = "fitnessWeightUnit"

    /// The currently selected unit (defaults to kg).
    static var current: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .kg
    }

    private static let kgPerLb = 0.45359237

    /// Convert a stored kilogram value into this unit for display/input.
    func fromKilograms(_ kg: Double) -> Double {
        switch self {
        case .kg: return kg
        case .lb: return kg / Self.kgPerLb
        }
    }

    /// Convert a value entered in this unit back into kilograms for storage.
    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lb: return value * Self.kgPerLb
        }
    }

    /// Format a stored kilogram value as a clean string in this unit (no unit suffix).
    func displayValue(fromKilograms kg: Double) -> String {
        let v = fromKilograms(kg)
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    /// Format a stored kilogram value with the unit suffix (e.g. "135 lb").
    func displayString(fromKilograms kg: Double) -> String {
        "\(displayValue(fromKilograms: kg)) \(label)"
    }
}

// MARK: - Comfort Preferences

/// User-facing sensory accommodations, persisted so the Onboarding "Comfort profile"
/// toggles actually take effect across the app.
enum ComfortPrefs {
    static let reduceMotionKey = "comfortReduceMotion"
    static let softHapticsKey = "comfortSoftHaptics"
    static let quietHoursKey = "comfortQuietHours"

    static var reduceMotion: Bool {
        get { UserDefaults.standard.bool(forKey: reduceMotionKey) }
        set { UserDefaults.standard.set(newValue, forKey: reduceMotionKey) }
    }

    static var softHaptics: Bool {
        // Default on: gentle feedback is the safe default.
        get { UserDefaults.standard.object(forKey: softHapticsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: softHapticsKey) }
    }

    static var quietHours: Bool {
        get { UserDefaults.standard.bool(forKey: quietHoursKey) }
        set { UserDefaults.standard.set(newValue, forKey: quietHoursKey) }
    }

    /// True during the 22:00–07:00 quiet window when the user has opted in.
    static var isQuietNow: Bool {
        guard quietHours else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 7
    }
}

// MARK: - Color System (Adaptive: Light = Notion/Attio, Dark = Aura)

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum PulseColors {
    // Surfaces
    static let background = Color("background", bundle: nil)
    static let canvas = Color("canvas", bundle: nil)
    static let fillSubtle = Color("fillSubtle", bundle: nil)
    static let fillMuted = Color("fillMuted", bundle: nil)

    // Borders
    static let borderHairline = Color("borderHairline", bundle: nil)
    static let borderStrong = Color("borderStrong", bundle: nil)

    // Text
    static let textPrimary = Color("textPrimary", bundle: nil)
    static let textSecondary = Color("textSecondary", bundle: nil)
    static let textMuted = Color("textMuted", bundle: nil)
    static let textFaint = Color("textFaint", bundle: nil)

    // Accent
    static let accent = Color("pulseAccent", bundle: nil)
    static let accentSoft = Color("pulseAccent", bundle: nil).opacity(0.06)

    // Semantic
    static let success = Color(hex: "#2F7D5B")
    static let successBackground = Color("successBg", bundle: nil)
    static let alert = Color(hex: "#B4453A")
    static let alertBackground = Color("alertBg", bundle: nil)
    static let warning = Color(hex: "#B8860B")
    static let warningBackground = Color("warningBg", bundle: nil)

    // Health metrics
    static let heartRate = Color(hex: "#B4453A")
    static let steps = Color(hex: "#2F7D5B")
    static let spo2 = Color(hex: "#4A7FB5")
    static let sleep = Color(hex: "#6B5FA0")
    static let sleepScore = Color(hex: "#8B7CFF")
    static let calories = Color(hex: "#C47230")
    static let distance = Color(hex: "#4A7FB5")
    static let battery = Color(hex: "#2F7D5B")
    static let readiness = Color(hex: "#5B7D2F")

    // Legacy compatibility
    static let secondaryBackground = canvas
    static let card = background
    static let cardSoft = fillSubtle
    static let elevated = fillMuted
    static let info = spo2
    static let danger = alert
    static let borderSubtle = borderHairline

    /// Neutral chip fill that adapts to light/dark (replaces hardcoded white opacity).
    static let chipFill = fillSubtle
}

// MARK: - Typography

enum PulseFont {
    static func body(_ size: CGFloat) -> Font {
        .custom("Hanken Grotesk", size: size).weight(.regular)
    }
    static func bodyMedium(_ size: CGFloat) -> Font {
        .custom("Hanken Grotesk", size: size).weight(.medium)
    }
    static func bodySemibold(_ size: CGFloat) -> Font {
        .custom("Hanken Grotesk", size: size).weight(.semibold)
    }
    static func bodyBold(_ size: CGFloat) -> Font {
        .custom("Hanken Grotesk", size: size).weight(.bold)
    }
    static func title(_ size: CGFloat) -> Font {
        .custom("Newsreader", size: size).weight(.regular)
    }
    static func titleMedium(_ size: CGFloat) -> Font {
        .custom("Newsreader", size: size).weight(.medium)
    }
    static func titleSemibold(_ size: CGFloat) -> Font {
        .custom("Newsreader", size: size).weight(.semibold)
    }

    // Convenience presets
    static let largeTitle = title(32)
    static let heading = titleMedium(24)
    static let subheading = bodySemibold(17)
    static let bodyDefault = body(15)
    static let bodySmall = body(13)
    static let caption = bodyMedium(12)
    static let micro = bodyMedium(11)
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        switch trimmed.count {
        case 3:
            red = (value >> 8) * 17
            green = (value >> 4 & 0xF) * 17
            blue = (value & 0xF) * 17
            alpha = 255
        case 6:
            red = value >> 16
            green = value >> 8 & 0xFF
            blue = value & 0xFF
            alpha = 255
        case 8:
            red = value >> 24
            green = value >> 16 & 0xFF
            blue = value >> 8 & 0xFF
            alpha = value & 0xFF
        default:
            red = 255
            green = 255
            blue = 255
            alpha = 255
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

// MARK: - Card Primitives

struct PulseCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
            .shadow(color: Color(hex: "#111111").opacity(0.04), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Card Surface Modifier

/// Shared bordered card surface (fill + clip + hairline stroke). Use on any view
/// that needs the PulseCard look without wrapping it (rows, tiles, custom layouts).
extension View {
    func pulseCardSurface(
        radius: CGFloat = PulseRadius.large,
        fill: Color = PulseColors.background,
        stroke: Color = PulseColors.borderHairline
    ) -> some View {
        self
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let title: String
    let value: String
    var unit: String?
    var color: Color
    var trend: [Double] = []

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(title.uppercased())
                        .font(PulseFont.micro)
                        .foregroundStyle(PulseColors.textMuted)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(PulseFont.titleMedium(30))
                        .monospacedDigit()
                        .foregroundStyle(PulseColors.textPrimary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    if let unit {
                        Text(unit)
                            .font(PulseFont.caption)
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }

                MiniSparkline(values: trend, color: color)
                    .frame(height: 34)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Mini Sparkline

struct MiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1, let minValue = values.min(), let maxValue = values.max() else { return }
                let range = max(maxValue - minValue, 1)
                for index in values.indices {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let yRatio = (values[index] - minValue) / range
                    let y = proxy.size.height - proxy.size.height * CGFloat(yRatio)
                    if index == values.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color.opacity(values.count > 1 ? 0.7 : 0.2), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.impact(.medium)
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .font(PulseFont.bodySemibold(16))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(PulseColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.impact(.light)
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(PulseFont.bodySemibold(15))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(PulseColors.textPrimary)
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PulseColors.borderStrong, lineWidth: 1)
            }
        }
    }
}

// MARK: - Pill Toggle (Segmented Control)

struct PillToggle<T: Hashable & CustomStringConvertible>: View {
    @Binding var selection: T
    let options: [T]
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    if selection != option { HapticService.selection() }
                    withAnimation(.snappy(duration: 0.25)) { selection = option }
                } label: {
                    Text(option.description)
                        .font(PulseFont.bodyMedium(13))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selection == option ? PulseColors.textPrimary : PulseColors.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(PulseColors.background)
                                    .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(PulseColors.fillSubtle)
        .clipShape(Capsule())
        .fixedSize()
    }
}

// MARK: - Status Chip

enum ChipStyle {
    case neutral
    case success
    case alert
    case warning
}

struct StatusChip: View {
    let label: String
    var style: ChipStyle = .neutral
    var icon: String?

    private var foreground: Color {
        switch style {
        case .neutral: return PulseColors.textSecondary
        case .success: return PulseColors.success
        case .alert: return PulseColors.alert
        case .warning: return PulseColors.warning
        }
    }

    private var bg: Color {
        switch style {
        case .neutral: return PulseColors.fillSubtle
        case .success: return PulseColors.successBackground
        case .alert: return PulseColors.alertBackground
        case .warning: return PulseColors.warningBackground
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .font(PulseFont.bodyMedium(12))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(bg)
        .clipShape(Capsule())
    }
}

// MARK: - Eyebrow Label

/// The small uppercase section label used across the app. Standardizes the
/// previously inconsistent sizes (11/11.5/13) and tracking (0.6/0.8/1.0/1.8).
struct EyebrowLabel: View {
    let text: String
    var trailing: AnyView?

    init(_ text: String) {
        self.text = text
        self.trailing = nil
    }

    init<Trailing: View>(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack {
            Text(text)
                .font(PulseFont.bodyMedium(11))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(PulseColors.textMuted)
                .accessibilityAddTraits(.isHeader)
            if let trailing {
                Spacer()
                trailing
            }
        }
    }
}

