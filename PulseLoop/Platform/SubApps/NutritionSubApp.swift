import SwiftUI
import SwiftData

// MARK: - Nutrition SubApp (meals / macros / scanning)
//
// Migrated built-in (roadmap B6). Backed by the legacy `AppModule.nutrition` module.
// Owns meal logging. The nutrition UI lives inside `TrackerView` and the meal-scan
// sheet, so this sub-app contributes models + identity (no standalone route yet).

struct NutritionSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.nutrition.rawValue) }
    var displayName: String { AppModule.nutrition.name }
    var iconSystemName: String { AppModule.nutrition.icon }
    var summary: String { AppModule.nutrition.description }
    var version: String { "1.1.0" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [MealLog.self, NutritionGoal.self, FoodItem.self, Recipe.self, RecipeItem.self] }

    var permissions: Set<SubAppPermission> { [.camera] }

    @MainActor
    func aiTools(flags: CoachFeatureFlags) -> [AnyCoachTool] {
        var tools = NutritionTools.readTools
        if flags.writeToolsEnabled { tools += NutritionTools.writeTools }
        return tools
    }
}
