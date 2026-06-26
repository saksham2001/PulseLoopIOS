import SwiftUI
import SwiftData

// MARK: - Tasks SubApp (to-dos + weekly planner)
//
// Migrated built-in (roadmap B7). Backed by the legacy `AppModule.tasks` module.
// Owns task + board models and the Tasks/WeekPlanner screens. Legacy
// `AppRoute.tasksList` still works.

enum TasksRoute: SubAppRoute {
    case list
}

struct TasksSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.tasks.rawValue) }
    var displayName: String { AppModule.tasks.name }
    var iconSystemName: String { AppModule.tasks.icon }
    var summary: String { AppModule.tasks.description }
    var origin: SubAppOrigin { .builtIn }
    var version: String { "1.1.0" }

    var changelog: [SubAppChangelogEntry] {
        [
            SubAppChangelogEntry("1.1.0", [
                "Weekly planner board for organizing tasks across the week.",
                "Assistant can create and complete tasks for you by voice or chat.",
            ], date: "Jun 2026"),
            SubAppChangelogEntry("1.0.0", [
                "To-do lists with due dates and daily task management.",
            ], date: "May 2026"),
        ]
    }

    var models: [any PersistentModel.Type] { [TaskItem.self, TaskBoard.self] }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: TasksRoute.self) { route, _ in
            switch route {
            case .list:
                TasksView()
            }
        }
    }
}
