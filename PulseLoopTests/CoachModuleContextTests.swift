import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

// MARK: - Coach module-context tests (Experience loop Track M / M3 + M6)
//
// The assistant routes requests by the context packet's `modules` block: a
// module the user has installed is used directly; one that's only `available`
// (not installed) is offered for install rather than faked. These tests prove
// the builder partitions the catalog correctly so that routing data is honest.
@MainActor
final class CoachModuleContextTests: XCTestCase {

    private func freshRegistry() {
        // Start from a known-empty install set so partitioning is deterministic.
        SubAppRegistry.shared.installedIDs = []
    }

    func testInstalledModuleAppearsInstalledNotAvailable() throws {
        freshRegistry()
        let context = try TestSupport.makeContext()
        let tasksId = AppModule.tasks.rawValue
        SubAppRegistry.shared.install(SubAppID(tasksId))

        let packet = CoachContextBuilder.build(context: context)
        let installedIds = packet.modules.installed.map(\.id)
        let availableIds = packet.modules.available.map(\.id)

        XCTAssertTrue(installedIds.contains(tasksId), "Installed module must be in `installed`")
        XCTAssertFalse(availableIds.contains(tasksId), "Installed module must NOT be in `available`")
    }

    func testUninstalledModuleAppearsAvailableNotInstalled() throws {
        freshRegistry()
        let context = try TestSupport.makeContext()
        // With nothing installed, a known built-in must be offered as available.
        let notesId = AppModule.notes.rawValue

        let packet = CoachContextBuilder.build(context: context)
        let installedIds = packet.modules.installed.map(\.id)
        let availableIds = packet.modules.available.map(\.id)

        XCTAssertTrue(availableIds.contains(notesId), "Uninstalled module must be in `available` to be offered for install")
        XCTAssertFalse(installedIds.contains(notesId), "Uninstalled module must NOT be in `installed`")
    }

    func testInstalledAndAvailableArePartitioned() throws {
        freshRegistry()
        let context = try TestSupport.makeContext()
        SubAppRegistry.shared.install(SubAppID(AppModule.tasks.rawValue))

        let packet = CoachContextBuilder.build(context: context)
        let installedIds = Set(packet.modules.installed.map(\.id))
        let availableIds = Set(packet.modules.available.map(\.id))

        XCTAssertTrue(installedIds.isDisjoint(with: availableIds), "A module can't be both installed and available")
        let total = installedIds.count + availableIds.count
        XCTAssertEqual(total, SubAppRegistry.shared.subApps.count, "Every registered module is classified exactly once")
    }

    func testEachModuleSummaryHasIdAndName() throws {
        freshRegistry()
        let context = try TestSupport.makeContext()
        SubAppRegistry.shared.install(SubAppID(AppModule.tasks.rawValue))

        let packet = CoachContextBuilder.build(context: context)
        for summary in packet.modules.installed + packet.modules.available {
            XCTAssertFalse(summary.id.isEmpty, "module id must be non-empty for routing")
            XCTAssertFalse(summary.name.isEmpty, "module name must be non-empty for the assistant to reference")
        }
    }
}
