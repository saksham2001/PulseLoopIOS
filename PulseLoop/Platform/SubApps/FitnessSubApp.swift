import SwiftUI
import SwiftData

// MARK: - Fitness SubApp (strength training)
//
// Migrated built-in (roadmap B4). Backed by the legacy `AppModule.workouts` module
// (so its enable/disable toggle is unchanged) and owns the strength-training domain:
// exercise catalog, workout templates, sets, and strength/body logs. Legacy
// `AppRoute.fitness` / `.workoutBuilder` / `.exerciseLibrary` still work.

enum FitnessRoute: SubAppRoute {
    case dashboard
    case workoutBuilder
    case exerciseLibrary
}

struct FitnessSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.workouts.rawValue) }
    var displayName: String { AppModule.workouts.name }
    var iconSystemName: String { AppModule.workouts.icon }
    var summary: String { AppModule.workouts.description }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            ExerciseSet.self,
            WorkoutLog.self,
            BodyMetric.self,
        ]
    }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: FitnessRoute.self) { route, _ in
            switch route {
            case .dashboard:
                FitnessDashboardView()
            case .workoutBuilder:
                WorkoutBuilderView()
            case .exerciseLibrary:
                ExerciseLibraryView { _ in }
            }
        }
    }

    @MainActor
    func aiTools(flags: CoachFeatureFlags) -> [AnyCoachTool] {
        var tools = FitnessTools.readTools
        if flags.writeToolsEnabled { tools += FitnessTools.writeTools }
        return tools
    }
}
