import SwiftData
import Foundation

// MARK: - Notes

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var collectionId: UUID?
    var aiSummary: String?
    /// Freeform AI/user tags for organization + retrieval. Defaulted so existing
    /// stores migrate lightly.
    var tags: [String] = []
    /// Optional link to a `TaskItem` this note expands on (e.g. project notes for
    /// a to-do). Defaulted nil for lightweight migration.
    var linkedTaskId: UUID?
    /// Optional link to a `Trip` this note belongs to (e.g. trip journal, packing
    /// notes, reservations). Additive + defaulted for migration.
    var linkedTripId: UUID?
    /// IDs of other notes this note explicitly links to. Backlinks are derived by
    /// scanning other notes' `linkedNoteIds`. Additive + defaulted for migration.
    var linkedNoteIds: [UUID] = []
    /// User-pinned/favorited note, surfaced at the top of the list. (E3)
    var isPinned: Bool = false
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade) var blocks: [NoteBlock]

    init(id: UUID = UUID(), title: String = "", collectionId: UUID? = nil, aiSummary: String? = nil, tags: [String] = [], linkedTaskId: UUID? = nil, linkedTripId: UUID? = nil, linkedNoteIds: [UUID] = [], isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.collectionId = collectionId
        self.aiSummary = aiSummary
        self.tags = tags
        self.linkedTaskId = linkedTaskId
        self.linkedTripId = linkedTripId
        self.linkedNoteIds = linkedNoteIds
        self.isPinned = isPinned
        self.blocks = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class NoteBlock {
    @Attribute(.unique) var id: UUID
    var noteId: UUID
    var order: Int
    var kindRaw: String
    var content: String
    var isChecked: Bool

    var kind: NoteBlockKind {
        get { NoteBlockKind(rawValue: kindRaw) ?? .paragraph }
        set { kindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), noteId: UUID, order: Int = 0, kind: NoteBlockKind = .paragraph, content: String = "", isChecked: Bool = false) {
        self.id = id
        self.noteId = noteId
        self.order = order
        self.kindRaw = kind.rawValue
        self.content = content
        self.isChecked = isChecked
    }
}

enum NoteBlockKind: String, Codable {
    case heading, paragraph, todo, quote, aiInsight, bulletList, numberedList, divider, callout
}

// MARK: - Tasks

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var statusRaw: String
    var group: String
    var label: String?
    var dueDate: Date?
    var boardId: UUID?
    var order: Int
    /// Effort points used by the weekly capacity planner (1 Tiny … 6 Half day).
    /// Defaulted so this is a lightweight SwiftData migration on existing stores.
    var weight: Int = 3
    /// Optional link to a `Trip` this task belongs to (e.g. a pre-trip checklist
    /// item). Additive + defaulted for migration.
    var tripId: UUID?
    var createdAt: Date
    var updatedAt: Date

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), title: String, status: TaskStatus = .todo, group: String = "Inbox", label: String? = nil, dueDate: Date? = nil, order: Int = 0, weight: Int = 3, tripId: UUID? = nil) {
        self.id = id
        self.title = title
        self.statusRaw = status.rawValue
        self.group = group
        self.label = label
        self.dueDate = dueDate
        self.boardId = nil
        self.order = order
        self.weight = weight
        self.tripId = tripId
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Task Weight

/// Effort weights for the weekly capacity planner ("Weekline" style).
enum TaskWeight: Int, CaseIterable, Identifiable {
    case tiny = 1
    case small = 2
    case medium = 3
    case large = 4
    case halfDay = 6

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .tiny: return "Tiny"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .halfDay: return "Half Day"
        }
    }

    static func nearest(to points: Int) -> TaskWeight {
        allCases.min(by: { abs($0.rawValue - points) < abs($1.rawValue - points) }) ?? .medium
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case todo = "todo"
    case inProgress = "in_progress"
    case done = "done"
    case cancelled = "cancelled"
}

@Model
final class TaskBoard {
    @Attribute(.unique) var id: UUID
    var name: String
    var columns: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "Default", columns: [String] = ["To do", "In progress", "Done"]) {
        self.id = id
        self.name = name
        self.columns = columns
        self.createdAt = Date()
    }
}

// MARK: - Collections

@Model
final class Collection {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var order: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, emoji: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.order = order
        self.createdAt = Date()
    }
}

// MARK: - Inbox

@Model
final class InboxItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var subtitle: String
    var sourceRaw: String
    var icon: String
    var suggestedAction: String?
    var actionTypeRaw: String?
    var detectedProduct: String?
    var detectedDose: String?
    var isHandled: Bool
    var receivedAt: Date

    var source: InboxSource {
        get { InboxSource(rawValue: sourceRaw) ?? .other }
        set { sourceRaw = newValue.rawValue }
    }

    var actionType: InboxActionType? {
        get { actionTypeRaw.flatMap { InboxActionType(rawValue: $0) } }
        set { actionTypeRaw = newValue?.rawValue }
    }

    init(id: UUID = UUID(), title: String, subtitle: String, source: InboxSource = .other, icon: String = "tray.fill", suggestedAction: String? = nil, actionType: InboxActionType? = nil, detectedProduct: String? = nil, detectedDose: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.sourceRaw = source.rawValue
        self.icon = icon
        self.suggestedAction = suggestedAction
        self.actionTypeRaw = actionType?.rawValue
        self.detectedProduct = detectedProduct
        self.detectedDose = detectedDose
        self.isHandled = false
        self.receivedAt = Date()
    }
}

enum InboxActionType: String, Codable {
    case reply
    case addToCalendar
    case createTask
    case trackShipment
    case setReminder
    case addToProtocol
    case restockReminder
    case joinCall
}

enum InboxSource: String, Codable {
    case gmail, calendar, slack, messages, shareSheet, siri, other
}

// MARK: - Connected Accounts

@Model
final class ConnectedAccount {
    @Attribute(.unique) var id: UUID
    var providerRaw: String
    var displayName: String
    var isConnected: Bool
    var lastSyncAt: Date?
    var permissionReadEnabled: Bool

    var provider: AccountProvider {
        get { AccountProvider(rawValue: providerRaw) ?? .other }
        set { providerRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), provider: AccountProvider, displayName: String, isConnected: Bool = false) {
        self.id = id
        self.providerRaw = provider.rawValue
        self.displayName = displayName
        self.isConnected = isConnected
        self.permissionReadEnabled = true
    }
}

enum AccountProvider: String, Codable {
    case gmail, googleCalendar, appleCalendar, slack, messages, notion, todoist, bank, appleWatch, oura, whoop, garmin, fitbit, other
}

// MARK: - Routines

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var timeOfDay: String
    var currentStreak: Int
    var longestStreak: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var steps: [RoutineStep]

    init(id: UUID = UUID(), name: String, emoji: String, timeOfDay: String = "morning", currentStreak: Int = 0) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.timeOfDay = timeOfDay
        self.currentStreak = currentStreak
        self.longestStreak = currentStreak
        self.steps = []
        self.createdAt = Date()
    }
}

@Model
final class RoutineStep {
    @Attribute(.unique) var id: UUID
    var routineId: UUID
    var title: String
    var order: Int
    var completedToday: Bool

    init(id: UUID = UUID(), routineId: UUID, title: String, order: Int = 0, completedToday: Bool = false) {
        self.id = id
        self.routineId = routineId
        self.title = title
        self.order = order
        self.completedToday = completedToday
    }
}

// MARK: - Medications / Supplements / Peptides

@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String
    var dose: String
    var categoryRaw: String
    var emoji: String
    var timing: String
    var instructions: String?
    var cycleDayTotal: Int?
    var cycleDayCurrent: Int?
    var isActive: Bool
    var createdAt: Date
    var benefit: String?
    var mechanism: String?
    var interactionNotes: String?
    var bestTimeReason: String?
    var stackNotes: String?

    var category: MedicationCategory {
        get { MedicationCategory(rawValue: categoryRaw) ?? .medication }
        set { categoryRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, dose: String, category: MedicationCategory, emoji: String = "pills.fill", timing: String = "AM", instructions: String? = nil, benefit: String? = nil, mechanism: String? = nil, interactionNotes: String? = nil, bestTimeReason: String? = nil, stackNotes: String? = nil) {
        self.id = id
        self.name = name
        self.dose = dose
        self.categoryRaw = category.rawValue
        self.emoji = emoji
        self.timing = timing
        self.instructions = instructions
        self.benefit = benefit
        self.mechanism = mechanism
        self.interactionNotes = interactionNotes
        self.bestTimeReason = bestTimeReason
        self.stackNotes = stackNotes
        self.isActive = true
        self.createdAt = Date()
    }
}

enum MedicationCategory: String, Codable {
    case medication, supplement, vitamin, peptide
}

@Model
final class MedicationLog {
    @Attribute(.unique) var id: UUID
    var medicationId: UUID
    var statusRaw: String
    var loggedAt: Date

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), medicationId: UUID, status: DoseStatus = .taken) {
        self.id = id
        self.medicationId = medicationId
        self.statusRaw = status.rawValue
        self.loggedAt = Date()
    }
}

enum DoseStatus: String, Codable {
    case taken, skipped, late
}

// MARK: - Meals

/// Which meal of the day a logged food belongs to. Mirrors MyFitnessPal's diary
/// sections so the food diary can group entries and show per-section subtotals.
enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snacks"

    var id: String { rawValue }

    /// SF Symbol (never emoji — design-system rule) for the section header / row.
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "carrot.fill"
        }
    }

    /// Diary display order (Breakfast → Lunch → Dinner → Snacks).
    var order: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }

    /// Best-guess meal type from the current time of day, used when logging
    /// without an explicit section (e.g. quick-add or a coach tool).
    static func forCurrentTime(_ date: Date = Date()) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }
}

@Model
final class MealLog {
    @Attribute(.unique) var id: UUID
    var name: String
    var description_: String
    /// SF Symbol name (legacy field name; never an emoji per design system).
    var emoji: String
    var calories: Int
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    /// Extended micronutrients carried through from Open Food Facts / estimates.
    /// Additive + defaulted nil for lightweight SwiftData migration.
    var fiberG: Double? = nil
    var sugarG: Double? = nil
    var sodiumMg: Double? = nil
    /// Which diary section this entry belongs to. Stored raw for migration safety.
    var mealTypeRaw: String = MealType.snack.rawValue
    /// Number of servings logged (the stored macros already reflect this quantity).
    var servings: Double = 1
    /// Optional human-readable serving size, e.g. "1 cup (240 ml)".
    var servingDescription: String? = nil
    var isPlanned: Bool
    var loggedAt: Date

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        description_: String = "",
        emoji: String = "fork.knife",
        calories: Int = 0,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        mealType: MealType = .snack,
        servings: Double = 1,
        servingDescription: String? = nil,
        isPlanned: Bool = false,
        loggedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description_ = description_
        self.emoji = emoji
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.mealTypeRaw = mealType.rawValue
        self.servings = servings
        self.servingDescription = servingDescription
        self.isPlanned = isPlanned
        self.loggedAt = loggedAt
    }
}

// MARK: - Nutrition Goal

/// The user's daily nutrition targets (MyFitnessPal-style calorie + macro budget).
/// A single active goal drives the food diary's rings and remaining-budget math.
@Model
final class NutritionGoal {
    @Attribute(.unique) var id: UUID
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var sodiumMg: Double?
    /// Whether this is the currently active goal (only one should be true).
    var isActive: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        calories: Int = 2000,
        proteinG: Double = 150,
        carbsG: Double = 200,
        fatG: Double = 67,
        fiberG: Double? = 28,
        sodiumMg: Double? = 2300,
        isActive: Bool = true
    ) {
        self.id = id
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sodiumMg = sodiumMg
        self.isActive = isActive
        self.updatedAt = Date()
    }

    /// Calories implied by the macro split (4/4/9 kcal per gram). Useful for
    /// validating a goal and for deriving a default when only macros are set.
    var caloriesFromMacros: Int {
        Int((proteinG * 4 + carbsG * 4 + fatG * 9).rounded())
    }
}

// MARK: - Saved / Custom Foods

/// A reusable food the user can re-log quickly (from a barcode scan, a search
/// result they saved, or a custom entry). Macros are stored PER SERVING; logging
/// multiplies by the chosen number of servings.
@Model
final class FoodItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String?
    /// Human-readable serving, e.g. "1 bar (40 g)" or "100 g".
    var servingDescription: String
    var caloriesPerServing: Int
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?
    /// Open Food Facts barcode when sourced from a scan/lookup.
    var barcode: String?
    /// Provenance label: "Open Food Facts", "Custom", "AI estimate".
    var source: String
    var isCustom: Bool
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        servingDescription: String = "1 serving",
        caloriesPerServing: Int = 0,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        barcode: String? = nil,
        source: String = "Custom",
        isCustom: Bool = true
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.servingDescription = servingDescription
        self.caloriesPerServing = caloriesPerServing
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.barcode = barcode
        self.source = source
        self.isCustom = isCustom
        self.createdAt = Date()
        self.lastUsedAt = nil
    }
}

// MARK: - Recipes

/// A named recipe: a set of `RecipeItem` portions whose macros sum to the whole,
/// optionally divided into servings so a portion can be logged.
@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var servings: Int
    var notes: String?
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var items: [RecipeItem]

    init(id: UUID = UUID(), name: String, servings: Int = 1, notes: String? = nil, items: [RecipeItem] = []) {
        self.id = id
        self.name = name
        self.servings = max(1, servings)
        self.notes = notes
        self.createdAt = Date()
        self.items = items
    }

    var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
    var totalProteinG: Double { items.reduce(0) { $0 + ($1.proteinG ?? 0) } }
    var totalCarbsG: Double { items.reduce(0) { $0 + ($1.carbsG ?? 0) } }
    var totalFatG: Double { items.reduce(0) { $0 + ($1.fatG ?? 0) } }

    /// Macros for a single serving (totals divided by `servings`).
    var perServingCalories: Int { totalCalories / max(1, servings) }
    var perServingProteinG: Double { totalProteinG / Double(max(1, servings)) }
    var perServingCarbsG: Double { totalCarbsG / Double(max(1, servings)) }
    var perServingFatG: Double { totalFatG / Double(max(1, servings)) }
}

@Model
final class RecipeItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var calories: Int
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var order: Int

    init(id: UUID = UUID(), name: String, calories: Int = 0, proteinG: Double? = nil, carbsG: Double? = nil, fatG: Double? = nil, order: Int = 0) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.order = order
    }
}

// MARK: - Custom Product Catalog (AI/web/API-discovered items, persisted for reuse)
//
// A reusable catalog row for any food / drug / supplement / vitamin / peptide that
// the unified search engine discovered outside the bundled knowledge bases — from
// an API (Open Food Facts / openFDA) or the AI research pass. Persisting it means
// the next search for the same item is instant and it flows back into autocomplete
// + fuzzy match. Mirrors `SupplementInfo`'s fields so the two are interchangeable in
// the search/result layer. Additive + fully defaulted for lightweight migration.
@Model
final class CustomProductInfo {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Lowercased name + known aliases used for de-dupe and fuzzy lookup.
    var aliases: [String] = []
    /// One of: medication / supplement / vitamin / peptide / food.
    var category: String = "supplement"
    var defaultDose: String = ""
    /// SF Symbol name (no emoji) used by result/protocol rows.
    var iconSystemName: String = "pills.fill"
    var timing: String = "AM"
    var benefit: String = ""
    var mechanism: String = ""
    var bestTimeReason: String = ""
    var stackNotes: String = ""
    var interactionNotes: String = ""
    var pros: [String] = []
    var cons: [String] = []
    /// Provenance label, e.g. "AI research", "Open Food Facts", "FDA Database".
    var source: String = "AI research"
    /// True when the profile was synthesized by the AI research pass; surfaces the
    /// "AI-generated — verify with a professional" disclaimer in the UI.
    var isAIGenerated: Bool = false
    /// Source URLs / references backing an AI/web-grounded profile.
    var citations: [String] = []
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        category: String = "supplement",
        defaultDose: String = "",
        iconSystemName: String = "pills.fill",
        timing: String = "AM",
        benefit: String = "",
        mechanism: String = "",
        bestTimeReason: String = "",
        stackNotes: String = "",
        interactionNotes: String = "",
        pros: [String] = [],
        cons: [String] = [],
        source: String = "AI research",
        isAIGenerated: Bool = false,
        citations: [String] = []
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.defaultDose = defaultDose
        self.iconSystemName = iconSystemName
        self.timing = timing
        self.benefit = benefit
        self.mechanism = mechanism
        self.bestTimeReason = bestTimeReason
        self.stackNotes = stackNotes
        self.interactionNotes = interactionNotes
        self.pros = pros
        self.cons = cons
        self.source = source
        self.isAIGenerated = isAIGenerated
        self.citations = citations
        self.createdAt = Date()
    }
}

// MARK: - Subscriptions (Money)

@Model
final class Subscription {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var monthlyAmount: Double
    var currency: String
    var lastChargedAt: Date?
    var isActive: Bool
    var unusedWeeks: Int?

    init(id: UUID = UUID(), name: String, emoji: String = "creditcard", monthlyAmount: Double, currency: String = "USD") {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.monthlyAmount = monthlyAmount
        self.currency = currency
        self.isActive = true
    }
}

// MARK: - Audit Log

@Model
final class AuditLogEntry {
    @Attribute(.unique) var id: UUID
    var actionDescription: String
    var sourceContext: String?
    var isReversible: Bool
    var wasUndone: Bool
    var createdAt: Date

    init(id: UUID = UUID(), actionDescription: String, sourceContext: String? = nil, isReversible: Bool = true) {
        self.id = id
        self.actionDescription = actionDescription
        self.sourceContext = sourceContext
        self.isReversible = isReversible
        self.wasUndone = false
        self.createdAt = Date()
    }
}

// MARK: - Permission Gate

@Model
final class PermissionGate {
    @Attribute(.unique) var id: UUID
    var actionType: String
    var permissionLevel: String
    var updatedAt: Date

    init(id: UUID = UUID(), actionType: String, permissionLevel: String = "ask") {
        self.id = id
        self.actionType = actionType
        self.permissionLevel = permissionLevel
        self.updatedAt = Date()
    }
}

// MARK: - Day Plan

@Model
final class DayPlan {
    @Attribute(.unique) var id: UUID
    var date: Date
    var summary: String?
    var generatedAt: Date

    @Relationship(deleteRule: .cascade) var actions: [DayPlanAction]

    init(id: UUID = UUID(), date: Date = Date(), summary: String? = nil) {
        self.id = id
        self.date = date
        self.summary = summary
        self.actions = []
        self.generatedAt = Date()
    }
}

@Model
final class DayPlanAction {
    @Attribute(.unique) var id: UUID
    var planId: UUID
    var title: String
    var subtitle: String
    var icon: String
    var statusRaw: String
    var order: Int
    /// Optional generic link to a domain entity this plan action represents (e.g.
    /// entityType "trip_item" + the TripItem's id), so the day plan can deep-link
    /// back to its source. Additive + defaulted for lightweight migration.
    var entityType: String?
    var entityId: UUID?

    var status: PlanActionStatus {
        get { PlanActionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), planId: UUID, title: String, subtitle: String = "", icon: String = "list.bullet", order: Int = 0, entityType: String? = nil, entityId: UUID? = nil) {
        self.id = id
        self.planId = planId
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.statusRaw = PlanActionStatus.pending.rawValue
        self.order = order
        self.entityType = entityType
        self.entityId = entityId
    }
}

enum PlanActionStatus: String, Codable {
    case pending, approved, skipped, undone
}

// MARK: - AI Memory

@Model
final class AIMemory {
    @Attribute(.unique) var id: UUID
    var content: String
    var categoryRaw: String
    var importance: Int
    var source: String
    var createdAt: Date
    var lastReferencedAt: Date
    var referenceCount: Int

    var category: MemoryCategory {
        get { MemoryCategory(rawValue: categoryRaw) ?? .fact }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        content: String,
        category: MemoryCategory = .fact,
        importance: Int = 5,
        source: String = "conversation"
    ) {
        self.id = UUID()
        self.content = content
        self.categoryRaw = category.rawValue
        self.importance = importance
        self.source = source
        self.createdAt = Date()
        self.lastReferencedAt = Date()
        self.referenceCount = 0
    }
}

enum MemoryCategory: String, Codable, CaseIterable {
    case preference
    case fact
    case goal
    case routine
    case health
    case relationship
    case pattern
    case dislike
}

// MARK: - AI Conversation Log

@Model
final class AIConversationLog {
    @Attribute(.unique) var id: UUID
    var userMessage: String
    var aiResponse: String
    var extractedAction: String?
    var createdAt: Date

    init(userMessage: String, aiResponse: String, extractedAction: String? = nil) {
        self.id = UUID()
        self.userMessage = userMessage
        self.aiResponse = aiResponse
        self.extractedAction = extractedAction
        self.createdAt = Date()
    }
}

// MARK: - Sleep Log

@Model
final class SleepLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var bedtime: Date
    var wakeTime: Date
    var durationMinutes: Int
    var quality: Int // 1-5
    var deepMinutes: Int?
    var remMinutes: Int?
    var lightMinutes: Int?
    var awakeMinutes: Int?
    var notes: String?

    init(date: Date = Date(), bedtime: Date, wakeTime: Date, quality: Int = 3, deepMinutes: Int? = nil, remMinutes: Int? = nil, lightMinutes: Int? = nil, awakeMinutes: Int? = nil, notes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        // Sleep crosses midnight: when the wake time is the same day as (or before)
        // the bedtime, it belongs to the next morning, so roll it forward a day
        // rather than recording a negative duration.
        let rawMinutes = Int(wakeTime.timeIntervalSince(bedtime) / 60)
        self.durationMinutes = rawMinutes >= 0 ? rawMinutes : rawMinutes + 24 * 60
        self.quality = quality
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.lightMinutes = lightMinutes
        self.awakeMinutes = awakeMinutes
        self.notes = notes
    }
}

// MARK: - Mood Entry

@Model
final class MoodEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var mood: Int // 1-5
    var energy: Int // 1-5
    var anxiety: Int? // 1-5
    var focus: Int? // 1-5
    var tags: [String]
    var notes: String?

    init(date: Date = Date(), mood: Int, energy: Int, anxiety: Int? = nil, focus: Int? = nil, tags: [String] = [], notes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.mood = mood
        self.energy = energy
        self.anxiety = anxiety
        self.focus = focus
        self.tags = tags
        self.notes = notes
    }
}

// MARK: - Workout

@Model
final class WorkoutLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var type: WorkoutType
    var name: String
    var durationMinutes: Int
    var caloriesBurned: Int?
    var intensity: Int // 1-10
    var heartRateAvg: Int?
    var heartRateMax: Int?
    var notes: String?
    var exercises: [ExerciseEntry]

    init(date: Date = Date(), type: WorkoutType = .strength, name: String, durationMinutes: Int, caloriesBurned: Int? = nil, intensity: Int = 5, heartRateAvg: Int? = nil, heartRateMax: Int? = nil, notes: String? = nil, exercises: [ExerciseEntry] = []) {
        self.id = UUID()
        self.date = date
        self.type = type
        self.name = name
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.intensity = intensity
        self.heartRateAvg = heartRateAvg
        self.heartRateMax = heartRateMax
        self.notes = notes
        self.exercises = exercises
    }
}

enum WorkoutType: String, Codable, CaseIterable {
    case strength = "Strength"
    case cardio = "Cardio"
    case hiit = "HIIT"
    case yoga = "Yoga"
    case running = "Running"
    case cycling = "Cycling"
    case swimming = "Swimming"
    case walking = "Walking"
    case sports = "Sports"
    case flexibility = "Flexibility"
    case other = "Other"

    /// Human-readable label (mirrors `rawValue`; kept for call-site clarity).
    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "heart.fill"
        case .hiit: return "bolt.fill"
        case .yoga: return "figure.yoga"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .walking: return "figure.walk"
        case .sports: return "sportscourt.fill"
        case .flexibility: return "figure.flexibility"
        case .other: return "figure.mixed.cardio"
        }
    }
}

struct ExerciseEntry: Codable, Hashable {
    var name: String
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var durationSeconds: Int?
}

// MARK: - Body Metrics

@Model
final class BodyMetric {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var muscleMassKg: Double?
    var waistCm: Double?
    var chestCm: Double?
    var hipsCm: Double?
    var armCm: Double?
    var notes: String?

    init(date: Date = Date(), weightKg: Double? = nil, bodyFatPercent: Double? = nil, muscleMassKg: Double? = nil, waistCm: Double? = nil, chestCm: Double? = nil, hipsCm: Double? = nil, armCm: Double? = nil, notes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.muscleMassKg = muscleMassKg
        self.waistCm = waistCm
        self.chestCm = chestCm
        self.hipsCm = hipsCm
        self.armCm = armCm
        self.notes = notes
    }
}

// MARK: - Habit

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var frequency: HabitFrequency
    var targetCount: Int
    var createdAt: Date
    var isActive: Bool
    @Relationship(deleteRule: .cascade) var logs: [HabitLog]

    var currentStreak: Int {
        guard !logs.isEmpty else { return 0 }
        let sorted = logs.sorted { $0.date > $1.date }
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())
        for log in sorted {
            let logDay = Calendar.current.startOfDay(for: log.date)
            if logDay == checkDate {
                streak += 1
                checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if logDay < checkDate {
                break
            }
        }
        return streak
    }

    var completedToday: Bool {
        logs.contains { Calendar.current.isDateInToday($0.date) }
    }

    init(name: String, emoji: String = "✓", frequency: HabitFrequency = .daily, targetCount: Int = 1) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.frequency = frequency
        self.targetCount = targetCount
        self.createdAt = Date()
        self.isActive = true
        self.logs = []
    }
}

@Model
final class HabitLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var count: Int

    init(date: Date = Date(), count: Int = 1) {
        self.id = UUID()
        self.date = date
        self.count = count
    }
}

enum HabitFrequency: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"
    case custom = "Custom"
}

// MARK: - Symptom Log

@Model
final class SymptomLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var symptom: String
    var severity: Int // 1-10
    var duration: String?
    var possibleTriggers: [String]
    var notes: String?
    var bodyArea: String?

    init(date: Date = Date(), symptom: String, severity: Int, duration: String? = nil, possibleTriggers: [String] = [], notes: String? = nil, bodyArea: String? = nil) {
        self.id = UUID()
        self.date = date
        self.symptom = symptom
        self.severity = severity
        self.duration = duration
        self.possibleTriggers = possibleTriggers
        self.notes = notes
        self.bodyArea = bodyArea
    }
}

// MARK: - Lab Result

@Model
final class LabResult {
    @Attribute(.unique) var id: UUID
    var date: Date
    var testName: String
    var value: Double
    var unit: String
    var referenceMin: Double?
    var referenceMax: Double?
    var category: String
    var isOutOfRange: Bool
    var notes: String?

    init(date: Date = Date(), testName: String, value: Double, unit: String, referenceMin: Double? = nil, referenceMax: Double? = nil, category: String = "General", notes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.testName = testName
        self.value = value
        self.unit = unit
        self.referenceMin = referenceMin
        self.referenceMax = referenceMax
        self.category = category
        self.isOutOfRange = {
            if let min = referenceMin, value < min { return true }
            if let max = referenceMax, value > max { return true }
            return false
        }()
        self.notes = notes
    }
}

// MARK: - Stress Log

@Model
final class StressLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var level: Int // 1-10
    var triggers: [String]
    var physicalSymptoms: [String]
    var copingUsed: String?
    var notes: String?

    init(date: Date = Date(), level: Int, triggers: [String] = [], physicalSymptoms: [String] = [], copingUsed: String? = nil, notes: String? = nil) {
        self.id = UUID()
        self.date = date
        self.level = level
        self.triggers = triggers
        self.physicalSymptoms = physicalSymptoms
        self.copingUsed = copingUsed
        self.notes = notes
    }
}

// MARK: - Meditation Log

@Model
final class MeditationLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var durationMinutes: Int
    var type: MeditationType
    var notes: String?
    var moodBefore: Int?
    var moodAfter: Int?

    init(date: Date = Date(), durationMinutes: Int, type: MeditationType = .mindfulness, notes: String? = nil, moodBefore: Int? = nil, moodAfter: Int? = nil) {
        self.id = UUID()
        self.date = date
        self.durationMinutes = durationMinutes
        self.type = type
        self.notes = notes
        self.moodBefore = moodBefore
        self.moodAfter = moodAfter
    }
}

enum MeditationType: String, Codable, CaseIterable {
    case mindfulness = "Mindfulness"
    case breathwork = "Breathwork"
    case bodyScan = "Body Scan"
    case guided = "Guided"
    case loving = "Loving-Kindness"
    case transcendental = "Transcendental"
    case visualization = "Visualization"
    case other = "Other"
}

// MARK: - Friends & Social

@Model
final class Friend {
    @Attribute(.unique) var id: UUID
    var name: String
    var initial: String
    var colorHex: String
    var birthday: Date?
    var addedAt: Date

    init(name: String, initial: String? = nil, colorHex: String = "888888", birthday: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.initial = initial ?? String(name.prefix(1)).uppercased()
        self.colorHex = colorHex
        self.birthday = birthday
        self.addedAt = Date()
    }
}

@Model
final class FriendActivity {
    @Attribute(.unique) var id: UUID
    var friendName: String
    var friendInitial: String
    var friendColorHex: String
    var action: String
    var emoji: String
    var emojiColorName: String
    var timestamp: Date
    var isCheered: Bool

    init(friendName: String, friendInitial: String, friendColorHex: String = "888888", action: String, emoji: String, emojiColorName: String = "gray", timestamp: Date = Date()) {
        self.id = UUID()
        self.friendName = friendName
        self.friendInitial = friendInitial
        self.friendColorHex = friendColorHex
        self.action = action
        self.emoji = emoji
        self.emojiColorName = emojiColorName
        self.timestamp = timestamp
        self.isCheered = false
    }
}

@Model
final class Wishlist {
    @Attribute(.unique) var id: UUID
    var title: String
    var ownerName: String
    var isOwn: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var items: [WishlistItem]

    init(title: String, ownerName: String, isOwn: Bool = false) {
        self.id = UUID()
        self.title = title
        self.ownerName = ownerName
        self.isOwn = isOwn
        self.items = []
        self.createdAt = Date()
    }
}

@Model
final class WishlistItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var link: String?
    var price: String?
    var isClaimed: Bool
    var claimedBy: String?
    var createdAt: Date

    init(name: String, link: String? = nil, price: String? = nil) {
        self.id = UUID()
        self.name = name
        self.link = link
        self.price = price
        self.isClaimed = false
        self.claimedBy = nil
        self.createdAt = Date()
    }
}

@Model
final class FriendEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var subtitle: String
    var icon: String
    var date: Date
    var isRSVPd: Bool
    var attendeeCount: Int

    init(title: String, subtitle: String = "", icon: String = "calendar", date: Date, attendeeCount: Int = 0) {
        self.id = UUID()
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.date = date
        self.isRSVPd = false
        self.attendeeCount = attendeeCount
    }
}

@Model
final class TravelPlan {
    @Attribute(.unique) var id: UUID
    var destination: String
    var friendName: String
    var startDate: Date
    var endDate: Date
    var hasPlanned: Bool

    init(destination: String, friendName: String, startDate: Date, endDate: Date) {
        self.id = UUID()
        self.destination = destination
        self.friendName = friendName
        self.startDate = startDate
        self.endDate = endDate
        self.hasPlanned = false
    }
}

// MARK: - Vices / Quit Program

enum TaperType: String, Codable, CaseIterable {
    case coldTurkey = "Cold Turkey"
    case gradual = "Gradual Reduction"
}

enum ViceLogType: String, Codable {
    case relapse = "Relapse"
    case urgeResisted = "Urge Resisted"
    case triggerLogged = "Trigger"
    case taperDose = "Taper Dose"
}

@Model
final class Vice {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var quitDate: Date
    var dailyCostSaved: Double
    var isActive: Bool
    var taperScheduleRaw: String
    var taperStartAmount: Double?
    var taperCurrentTarget: Double?
    var taperUnit: String?
    var motivations: [String]
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var logs: [ViceLog]

    var taperSchedule: TaperType {
        get { TaperType(rawValue: taperScheduleRaw) ?? .coldTurkey }
        set { taperScheduleRaw = newValue.rawValue }
    }

    var daysSinceQuit: Int {
        max(0, Calendar.current.dateComponents([.day], from: quitDate, to: Date()).day ?? 0)
    }

    var moneySaved: Double {
        Double(daysSinceQuit) * dailyCostSaved
    }

    var currentStreak: Int {
        guard !logs.isEmpty else { return daysSinceQuit }
        let relapses = logs.filter { $0.typeRaw == ViceLogType.relapse.rawValue }
            .sorted { $0.date > $1.date }
        guard let lastRelapse = relapses.first else { return daysSinceQuit }
        return max(0, Calendar.current.dateComponents([.day], from: lastRelapse.date, to: Date()).day ?? 0)
    }

    var longestStreak: Int {
        let relapses = logs.filter { $0.typeRaw == ViceLogType.relapse.rawValue }
            .sorted { $0.date < $1.date }
        guard !relapses.isEmpty else { return daysSinceQuit }
        var longest = 0
        var prev = quitDate
        for r in relapses {
            let gap = Calendar.current.dateComponents([.day], from: prev, to: r.date).day ?? 0
            longest = max(longest, gap)
            prev = r.date
        }
        let final_ = Calendar.current.dateComponents([.day], from: prev, to: Date()).day ?? 0
        longest = max(longest, final_)
        return longest
    }

    init(name: String, emoji: String, quitDate: Date = Date(), dailyCostSaved: Double = 0, taperSchedule: TaperType = .coldTurkey, taperStartAmount: Double? = nil, taperUnit: String? = nil, motivations: [String] = []) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.quitDate = quitDate
        self.dailyCostSaved = dailyCostSaved
        self.isActive = true
        self.taperScheduleRaw = taperSchedule.rawValue
        self.taperStartAmount = taperStartAmount
        self.taperCurrentTarget = taperStartAmount
        self.taperUnit = taperUnit
        self.motivations = motivations
        self.createdAt = Date()
        self.logs = []
    }
}

extension Vice: Hashable {
    static func == (lhs: Vice, rhs: Vice) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@Model
final class ViceLog {
    @Attribute(.unique) var id: UUID
    var viceId: UUID
    var date: Date
    var typeRaw: String
    var amount: Double?
    var triggerContext: String?
    var intensity: Int
    var copingUsed: String?
    var notes: String?

    var type: ViceLogType {
        get { ViceLogType(rawValue: typeRaw) ?? .urgeResisted }
        set { typeRaw = newValue.rawValue }
    }

    init(viceId: UUID, type: ViceLogType, amount: Double? = nil, triggerContext: String? = nil, intensity: Int = 5, copingUsed: String? = nil, notes: String? = nil) {
        self.id = UUID()
        self.viceId = viceId
        self.date = Date()
        self.typeRaw = type.rawValue
        self.amount = amount
        self.triggerContext = triggerContext
        self.intensity = intensity
        self.copingUsed = copingUsed
        self.notes = notes
    }
}

