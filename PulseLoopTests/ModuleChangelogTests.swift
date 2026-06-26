import Foundation
import XCTest
@testable import PulseLoop

// MARK: - Module changelog tests (Experience loop Track P / P2 + P6)
//
// The detail screen's "Version history" is driven by `SubApp.changelog`. These
// tests lock down the invariants that view depends on: every module has at least
// one entry, the default synthesizes from `version`, the newest entry matches the
// module's current `version`, and a module with hand-authored history (Tasks)
// surfaces multiple entries in a form the view can sort newest-first.
@MainActor
final class ModuleChangelogTests: XCTestCase {

    func testEveryModuleHasAtLeastOneChangelogEntry() {
        for app in SubAppRegistry.shared.subApps {
            XCTAssertFalse(app.changelog.isEmpty, "\(app.id.rawValue) must have a changelog (default synthesizes one)")
        }
    }

    func testChangelogNewestEntryMatchesCurrentVersion() {
        for app in SubAppRegistry.shared.subApps {
            let newest = app.changelog.map(\.version).max()
            XCTAssertEqual(
                newest, app.semanticVersion,
                "\(app.id.rawValue)'s newest changelog entry should match its current version"
            )
        }
    }

    func testEveryChangelogEntryHasNotes() {
        for app in SubAppRegistry.shared.subApps {
            for entry in app.changelog {
                XCTAssertFalse(entry.notes.isEmpty, "\(app.id.rawValue) v\(entry.version) must have at least one note")
            }
        }
    }

    func testTasksHasMultiVersionHistory() throws {
        let tasks = try XCTUnwrap(SubAppRegistry.shared.subApp(id: SubAppID(AppModule.tasks.rawValue)))
        let changelog = tasks.changelog
        XCTAssertGreaterThanOrEqual(changelog.count, 2, "Tasks ships a real multi-version history")
        // Sorted newest-first, the first entry is the current version.
        let sorted = changelog.sorted { $0.version > $1.version }
        XCTAssertEqual(sorted.first?.version, tasks.semanticVersion)
    }

    func testChangelogEntryIDIsVersionString() {
        let entry = SubAppChangelogEntry("2.3.4", ["note"], date: "Jun 2026")
        XCTAssertEqual(entry.id, "2.3.4")
        XCTAssertEqual(entry.version, SemanticVersion(major: 2, minor: 3, patch: 4))
    }
}
