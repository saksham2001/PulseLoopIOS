import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Headless smoke tests for the critical end-to-end flow that the UI drives:
/// fresh install starts empty → installing a module makes it appear across surfaces
/// (installed set, installedSubApps, Coach tools) → uninstall reverts it → a Coach
/// conversation can be created and persisted (the "open Coach" entry point).
///
/// These run at the model/logic layer (no XCUITest target) so CI stays fast; the
/// dedicated UI-test target is tracked as a follow-up.
@MainActor
final class SmokeFlowTests: XCTestCase {

    private let enabledKey = "enabledModules"
    private let onboardedKey = "hasCompletedModuleOnboarding"
    private let migrationKey = "installModel_noStandardModules_v1"

    private var savedEnabled: Data?
    private var savedOnboarded: Any?
    private var savedMigration: Any?

    override func setUp() {
        super.setUp()
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
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    // MARK: Onboarding → empty catalog

    func testFreshInstallShowsEmptyCatalog() {
        let registry = SubAppRegistry.shared
        XCTAssertTrue(registry.installedIDs.isEmpty, "Fresh install must have nothing installed")
        XCTAssertTrue(registry.installedSubApps.isEmpty, "No installed sub-apps should render")
    }

    // MARK: Install a module → it appears

    func testInstallingModuleMakesItAppearAcrossSurfaces() throws {
        let registry = SubAppRegistry.shared
        let target = try XCTUnwrap(registry.subApps.first, "Expected at least one registered sub-app")

        XCTAssertFalse(registry.isInstalled(target.id))
        let toolsBefore = registry.aiTools(flags: flags()).count

        registry.install(target.id)

        XCTAssertTrue(registry.isInstalled(target.id), "Installed module must report installed")
        XCTAssertTrue(registry.installedSubApps.contains { $0.id == target.id }, "Installed module must render")
        let toolsAfter = registry.aiTools(flags: flags()).count
        XCTAssertGreaterThanOrEqual(toolsAfter, toolsBefore, "Installing must not reduce available Coach tools")
    }

    // MARK: Uninstall reverts

    func testUninstallRevertsInstallState() throws {
        let registry = SubAppRegistry.shared
        let target = try XCTUnwrap(registry.subApps.first)

        registry.install(target.id)
        XCTAssertTrue(registry.isInstalled(target.id))

        registry.uninstall(target.id)
        XCTAssertFalse(registry.isInstalled(target.id), "Uninstall must remove from installed set")
        XCTAssertFalse(registry.installedSubApps.contains { $0.id == target.id })
    }

    // MARK: Open Coach → conversation persists

    func testCoachConversationCanBeCreatedAndPersisted() throws {
        let context = try TestSupport.makeContext()
        let conversationId = UUID()
        let message = CoachMessage(conversationId: conversationId, role: "user", body: "Hello coach")
        context.insert(message)
        XCTAssertTrue(context.saveOrLog("smoke.coach"), "Coach message should persist")

        let fetched = try context.fetch(FetchDescriptor<CoachMessage>())
        XCTAssertTrue(fetched.contains { $0.body == "Hello coach" }, "Persisted Coach message should be retrievable")
    }

    // MARK: Cloud sync — consent gate (roadmap E1) + mappings (E2/E3)

    /// No health data may leave the device without explicit consent: `sync` must
    /// refuse and surface the consent error before any network work.
    func testCloudSyncRefusesUploadWithoutConsent() async throws {
        let context = try TestSupport.makeContext()
        let sync = CloudSyncService()
        sync.hasCloudConsent = false
        defer { sync.hasCloudConsent = false }

        let ok = await sync.sync(context: context)
        XCTAssertFalse(ok, "Sync must fail without consent")
        XCTAssertEqual(sync.lastError, CloudSyncService.SyncError.consentRequired.errorDescription)
    }

    /// The web schema mapping the iOS client uploads must stay stable — the server
    /// keys metric kinds on these exact strings.
    func testWebKindMappingIsStable() {
        XCTAssertEqual(CloudSyncService.webKind(for: .heartRate), "heart_rate")
        XCTAssertEqual(CloudSyncService.webKind(for: .spo2), "spo2")
    }

    /// Delete-scope identifiers feed both the API body and SwiftUI `.alert(item:)`;
    /// they must be the stable wire values the server expects.
    func testDeleteScopeIdentifiers() {
        XCTAssertEqual(CloudSyncService.DeleteScope.device.rawValue, "device")
        XCTAssertEqual(CloudSyncService.DeleteScope.account.rawValue, "account")
        XCTAssertEqual(CloudSyncService.DeleteScope.account.id, "account")
    }
}
