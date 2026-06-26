import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Tests for the "no module comes standard" install model (Phases A–D):
/// install/uninstall flips state and Coach tool surfaces, the fresh-install
/// default is empty, the migration grandfathers existing users, uninstall preserves
/// data, reinstall restores it, and `remove_module_data` wipes a spec sub-app.
@MainActor
final class InstallModelTests: XCTestCase {

    private let enabledKey = "enabledModules"
    private let onboardedKey = "hasCompletedModuleOnboarding"
    private let migrationKey = "installModel_noStandardModules_v1"

    private var savedEnabled: Data?
    private var savedOnboarded: Any?
    private var savedMigration: Any?

    override func setUp() {
        super.setUp()
        // Snapshot + clear the install-related UserDefaults so each test starts clean.
        let d = UserDefaults.standard
        savedEnabled = d.data(forKey: enabledKey)
        savedOnboarded = d.object(forKey: onboardedKey)
        savedMigration = d.object(forKey: migrationKey)
        d.removeObject(forKey: enabledKey)
        d.removeObject(forKey: onboardedKey)
        d.removeObject(forKey: migrationKey)
    }

    override func tearDown() {
        let d = UserDefaults.standard
        if let savedEnabled { d.set(savedEnabled, forKey: enabledKey) } else { d.removeObject(forKey: enabledKey) }
        if let savedOnboarded { d.set(savedOnboarded, forKey: onboardedKey) } else { d.removeObject(forKey: onboardedKey) }
        if let savedMigration { d.set(savedMigration, forKey: migrationKey) } else { d.removeObject(forKey: migrationKey) }
        super.tearDown()
    }

    private func flags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = true
        s.enablePlatformControl = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    // MARK: Default + install/uninstall

    func testFreshInstallDefaultsToEmpty() {
        // No persisted selection, not onboarded → nothing installed.
        XCTAssertTrue(SubAppRegistry.shared.installedIDs.isEmpty)
    }

    func testInstallAndUninstallFlipsState() {
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.sleep.rawValue)

        XCTAssertFalse(registry.isInstalled(id))
        registry.install(id)
        XCTAssertTrue(registry.isInstalled(id))
        XCTAssertTrue(registry.installedSubApps.contains { $0.id == id })

        registry.uninstall(id)
        XCTAssertFalse(registry.isInstalled(id))
        XCTAssertFalse(registry.installedSubApps.contains { $0.id == id })
    }

    // MARK: Migration

    func testMigrationGrandfathersOnboardedUser() {
        // Simulate an existing user: onboarded under the old "all enabled" default,
        // with no explicit persisted set.
        UserDefaults.standard.set(true, forKey: onboardedKey)
        XCTAssertNil(UserDefaults.standard.data(forKey: enabledKey))

        SubAppRegistry.shared.runInstallMigration()

        // They keep their app: everything registered is now explicitly installed.
        let installed = SubAppRegistry.shared.installedIDs
        XCTAssertFalse(installed.isEmpty)
        XCTAssertEqual(installed.count, SubAppRegistry.shared.subApps.count)
    }

    func testMigrationLeavesFreshInstallEmpty() {
        // Not onboarded, no selection → stays empty after migration.
        SubAppRegistry.shared.runInstallMigration()
        XCTAssertTrue(SubAppRegistry.shared.installedIDs.isEmpty)
    }

    func testMigrationPreservesExplicitSelection() {
        let only: Set<SubAppID> = [SubAppID(AppModule.tasks.rawValue)]
        SubAppRegistry.shared.installedIDs = only
        SubAppRegistry.shared.runInstallMigration()
        XCTAssertEqual(SubAppRegistry.shared.installedIDs, only)
    }

    // MARK: Coach tool surfaces reflect install state

    func testListModulesReportsInstallState() async throws {
        let c = try TestSupport.makeContext()
        let registry = SubAppRegistry.shared
        let sleepID = SubAppID(AppModule.sleep.rawValue)
        registry.install(sleepID)

        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "list_modules"))
        let result = try parse(try await tool.run(Data("{}".utf8), ToolExecutionContext(modelContext: c, flags: flags())))
        let modules = try XCTUnwrap(result["modules"] as? [[String: Any]])
        let sleep = try XCTUnwrap(modules.first { ($0["id"] as? String) == sleepID.rawValue })
        XCTAssertEqual(sleep["installed"] as? Bool, true)
        XCTAssertEqual(result["installed_count"] as? Int, 1)
    }

    func testSetModuleInstallIsImmediateUninstallConfirms() async throws {
        let c = try TestSupport.makeContext()
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "set_module_enabled"))

        // Install applies immediately.
        _ = try await tool.run(Data(#"{"module_id":"\#(id.rawValue)","enabled":true,"reason":"user asked"}"#.utf8),
                               ToolExecutionContext(modelContext: c, flags: flags()))
        XCTAssertTrue(registry.isInstalled(id))

        // Uninstall requires confirmation and doesn't apply until executed.
        let ctx = ToolExecutionContext(modelContext: c, flags: flags())
        let res = try parse(try await tool.run(Data(#"{"module_id":"\#(id.rawValue)","enabled":false,"reason":"declutter"}"#.utf8), ctx))
        XCTAssertEqual(res["needs_confirmation"] as? Bool, true)
        XCTAssertTrue(registry.isInstalled(id))
        XCTAssertEqual(ctx.pendingActions.first?.kind, .disableModule)

        _ = PendingActionExecutor.execute(try XCTUnwrap(ctx.pendingActions.first), context: c)
        XCTAssertFalse(registry.isInstalled(id))
    }

    func testAiToolsOnlyFromInstalledSubApps() {
        let registry = SubAppRegistry.shared
        // With nothing installed, no sub-app contributes tools.
        XCTAssertTrue(registry.aiTools(flags: flags()).isEmpty)
        // Install a sub-app that contributes tools (QuitProgram).
        registry.install(SubAppID(AppModule.quitProgram.rawValue))
        XCTAssertFalse(registry.aiTools(flags: flags()).isEmpty)
    }

    // MARK: Uninstall preserves data; remove_module_data wipes it

    func testUninstallPreservesSpecDataAndReinstallRestores() throws {
        let c = try TestSupport.makeContext()
        let store = SwiftDataSubAppRecordStore(context: c)
        let subAppID = "mood_spec"
        let entity = "checkin"
        store.upsert(SubAppRecord(id: UUID(), values: ["mood": .integer(4)], createdAt: Date()),
                     subAppID: subAppID, entity: entity)

        let registry = SubAppRegistry.shared
        registry.install(SubAppID(subAppID))
        registry.uninstall(SubAppID(subAppID))

        // Data survives the uninstall.
        XCTAssertEqual(store.records(subAppID: subAppID, entity: entity).count, 1)

        // Reinstall restores access to the same data.
        registry.install(SubAppID(subAppID))
        XCTAssertEqual(store.records(subAppID: subAppID, entity: entity).count, 1)
    }

    func testRemoveModuleDataWipesSpecRecords() throws {
        let c = try TestSupport.makeContext()
        let store = SwiftDataSubAppRecordStore(context: c)
        let subAppID = "mood_spec"
        let entity = "checkin"
        store.upsert(SubAppRecord(id: UUID(), values: ["mood": .integer(2)], createdAt: Date()),
                     subAppID: subAppID, entity: entity)
        SubAppRegistry.shared.install(SubAppID(subAppID))

        let action = PendingAction(
            kind: .removeModuleData,
            summary: "wipe",
            confirmLabel: "Delete data",
            platform: PlatformActionPayload(targetId: subAppID, displayName: "Mood Journal")
        )
        _ = PendingActionExecutor.execute(action, context: c)

        XCTAssertFalse(SubAppRegistry.shared.isInstalled(SubAppID(subAppID)))
        XCTAssertTrue(store.records(subAppID: subAppID, entity: entity).isEmpty)
    }
}
