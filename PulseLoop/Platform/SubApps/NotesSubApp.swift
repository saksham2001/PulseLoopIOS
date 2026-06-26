import SwiftUI
import SwiftData

// MARK: - Notes SubApp (block-based notes + collections)
//
// Migrated built-in (roadmap B8). Backed by the legacy `AppModule.notes` module.
// Owns notes, note blocks, and collections, plus the notes list + editor screens.
// Legacy `AppRoute.notesList` / `.noteEditor` still work.

enum NotesRoute: SubAppRoute {
    case list
    case editor(UUID?)
}

struct NotesSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.notes.rawValue) }
    var displayName: String { AppModule.notes.name }
    var iconSystemName: String { AppModule.notes.icon }
    var summary: String { AppModule.notes.description }
    var version: String { "1.0.0" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] {
        [Note.self, NoteBlock.self, Collection.self]
    }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: NotesRoute.self) { route, ctx in
            switch route {
            case .list:
                NotesListView(path: ctx.path)
            case let .editor(id):
                NoteEditorView(noteId: id)
            }
        }
    }
}
