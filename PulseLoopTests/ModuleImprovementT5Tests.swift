import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

// MARK: - Module self-improvement tests (Life OS T5)
//
// The improvement agent proposes a better version of an installed declarative
// module as a SubAppSpec diff (additive enhancement or self-healing repair), never
// editing the live module. The safe apply pipeline re-validates, classifies
// breaking vs non-breaking, auto-applies only non-breaking + opted-in changes, and
// requires confirmation otherwise. The daily runner is gated to once per day.

@MainActor
final class ModuleImprovementT5Tests: XCTestCase {

    private let testID = "improve_me_test"

    override func setUp() async throws {
        try await super.setUp()
        resetState()
    }

    override func tearDown() async throws {
        resetState()
        try await super.tearDown()
    }

    private func resetState() {
        ModuleImprovementStore.shared.clear(moduleId: testID)
        ModuleImprovementStore.shared.autoApplyNonBreaking = false
        SubAppRegistry.shared.uninstall(SubAppID(testID))
        UserSubAppStore.shared.delete(id: testID)
        SubAppRegistry.shared.loadUserSpecs()
        UserDefaults.standard.removeObject(forKey: "pulseloop.modules.improvements.lastRunDay")
    }

    private func inMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DynamicSubAppRecord.self, configurations: config)
        return ModelContext(container)
    }

    /// A minimal valid spec with a single entity (a required text field only, so the
    /// agent has room to add a Notes field) and a list screen — no dashboard, so the
    /// enhancement also has an Overview to add.
    private func baseSpec(version: SemanticVersion = SemanticVersion(major: 1, minor: 0, patch: 0)) -> SubAppSpec {
        SubAppSpec(
            id: testID,
            displayName: "Improve Me",
            icon: "wand.and.stars",
            summary: "A test module.",
            version: version,
            entities: [
                EntitySpec(name: "entry", label: "Entry", fields: [
                    FieldSpec(name: "title", label: "Title", type: .text, required: true),
                ]),
            ],
            screens: [
                ScreenSpec(id: "list", title: "Entries", kind: .list, entity: "entry"),
                ScreenSpec(id: "form", title: "New Entry", kind: .form, entity: "entry"),
            ]
        )
    }

    // MARK: Diff classification

    func testAddingOptionalFieldIsNonBreaking() {
        var improved = baseSpec()
        improved.entities[0].fields.append(FieldSpec(name: "notes", label: "Notes", type: .text))
        let diff = SubAppSpecDiff.between(baseSpec(), improved)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertFalse(diff.isBreaking, "Adding an optional field should be additive/non-breaking.")
    }

    func testRemovingFieldIsBreaking() {
        var stripped = baseSpec()
        stripped.entities[0].fields = []  // remove all fields
        let diff = SubAppSpecDiff.between(baseSpec(), stripped)
        XCTAssertTrue(diff.isBreaking, "Removing a field should be breaking.")
    }

    func testNewRequiredFieldIsBreaking() {
        var improved = baseSpec()
        improved.entities[0].fields.append(FieldSpec(name: "amount", label: "Amount", type: .number, required: true))
        let diff = SubAppSpecDiff.between(baseSpec(), improved)
        XCTAssertTrue(diff.isBreaking, "Adding a newly-required field should be breaking.")
    }

    // MARK: Agent proposals

    func testAgentProposesNonBreakingEnhancement() throws {
        let proposal = try XCTUnwrap(ModuleImprovementAgent.propose(for: baseSpec()),
                                     "Agent should propose an additive enhancement.")
        XCTAssertFalse(proposal.isBreaking)
        XCTAssertFalse(proposal.isRepair)
        // Version climbs (minor bump for non-breaking).
        XCTAssertGreaterThan(proposal.proposedVersion, baseSpec().version)
        // The improved spec adds a Notes field and/or an Overview dashboard.
        let addedNotes = proposal.proposedSpec.entities.contains { $0.fields.contains { $0.name == "notes" } }
        let addedDashboard = proposal.proposedSpec.screens.contains { $0.kind == .dashboard }
        XCTAssertTrue(addedNotes || addedDashboard)
    }

    func testAgentReturnsNilWhenNothingToImprove() {
        // A spec that already has a notes field and a dashboard leaves nothing additive.
        var full = baseSpec()
        full.entities[0].fields.append(FieldSpec(name: "notes", label: "Notes", type: .text))
        full.screens.append(ScreenSpec(id: "overview", title: "Overview", kind: .dashboard, entity: nil))
        XCTAssertNil(ModuleImprovementAgent.propose(for: full))
    }

    func testProposedSpecAlwaysValidates() throws {
        let proposal = try XCTUnwrap(ModuleImprovementAgent.propose(for: baseSpec()))
        XCTAssertNil(ModuleImprovementApplier.validationFailure(proposal.proposedSpec))
    }

    // MARK: Safe apply pipeline

    func testProcessRequiresConfirmationWhenAutoApplyOff() throws {
        UserSubAppStore.shared.save(baseSpec(), origin: .userCreated)
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(testID))

        let proposal = try XCTUnwrap(ModuleImprovementAgent.propose(for: baseSpec()))
        XCTAssertFalse(proposal.isBreaking)
        let ctx = try inMemoryContext()
        let outcome = ModuleImprovementApplier.process(proposal, autoApplyNonBreaking: false, context: ctx)
        XCTAssertEqual(outcome, .needsConfirmation)
    }

    func testProcessAutoAppliesNonBreakingWhenOptedIn() throws {
        UserSubAppStore.shared.save(baseSpec(), origin: .userCreated)
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(testID))

        let proposal = try XCTUnwrap(ModuleImprovementAgent.propose(for: baseSpec()))
        let ctx = try inMemoryContext()
        let outcome = ModuleImprovementApplier.process(proposal, autoApplyNonBreaking: true, context: ctx)
        guard case let .applied(version) = outcome else {
            return XCTFail("Expected .applied, got \(outcome)")
        }
        XCTAssertEqual(version, proposal.proposedVersion)
        // The persisted spec now reflects the improvement.
        let saved = try XCTUnwrap(UserSubAppStore.shared.specs.first { $0.id == testID })
        XCTAssertEqual(saved.version, proposal.proposedVersion)
        // The proposal is cleared after a successful commit.
        XCTAssertNil(ModuleImprovementStore.shared.proposal(for: testID))
    }

    func testProcessRejectsModuleThatIsntInstalled() throws {
        let proposal = try XCTUnwrap(ModuleImprovementAgent.propose(for: baseSpec()))
        let ctx = try inMemoryContext()
        let outcome = ModuleImprovementApplier.process(proposal, autoApplyNonBreaking: true, context: ctx)
        XCTAssertEqual(outcome, .notInstalled)
    }

    // MARK: Daily runner

    func testRunnerStagesProposalForInstalledModule() throws {
        UserSubAppStore.shared.save(baseSpec(), origin: .userCreated)
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(testID))

        let ctx = try inMemoryContext()
        let produced = ModuleImprovementRunner.run(context: ctx)
        XCTAssertTrue(produced.contains { $0.moduleId == testID })
        // Non-breaking, auto-apply off → staged (not committed).
        XCTAssertNotNil(ModuleImprovementStore.shared.proposal(for: testID))
        let saved = try XCTUnwrap(UserSubAppStore.shared.specs.first { $0.id == testID })
        XCTAssertEqual(saved.version, baseSpec().version, "Should stage, not auto-apply, when opted out.")
    }

    func testRunIfDueRunsOncePerDay() throws {
        UserSubAppStore.shared.save(baseSpec(), origin: .userCreated)
        SubAppRegistry.shared.loadUserSpecs()
        SubAppRegistry.shared.install(SubAppID(testID))

        let ctx = try inMemoryContext()
        let now = Date()
        let first = ModuleImprovementRunner.runIfDue(context: ctx, now: now)
        XCTAssertFalse(first.isEmpty, "First run of the day should produce a proposal.")
        let second = ModuleImprovementRunner.runIfDue(context: ctx, now: now)
        XCTAssertTrue(second.isEmpty, "A second run on the same day is a no-op.")
        // The next day, it runs again.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        ModuleImprovementStore.shared.clear(moduleId: testID)  // clear so there's room for a new proposal
        let third = ModuleImprovementRunner.runIfDue(context: ctx, now: tomorrow)
        XCTAssertFalse(third.isEmpty, "A new day should run again.")
    }
}
