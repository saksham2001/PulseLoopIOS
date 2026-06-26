import Foundation
import XCTest
@testable import PulseLoop

// MARK: - SubApp platform tests (roadmap G1)
//
// Covers the safety-critical seams of the sub-app platform: the spec validator,
// the signed package round-trip (sign/verify/tamper), the moderation pass, and the
// credits ledger metering/grant math.

final class SubAppPlatformTests: XCTestCase {

    // MARK: Fixtures

    private func validSpec(id: String = "habit_tracker") -> SubAppSpec {
        SubAppSpec(
            id: id,
            displayName: "Habit Tracker",
            icon: "checkmark.circle",
            summary: "Track daily habits.",
            author: "Tester",
            permissions: [],
            entities: [
                EntitySpec(name: "habit", label: "Habit", fields: [
                    FieldSpec(name: "name", label: "Name", type: .text, required: true),
                    FieldSpec(name: "done", label: "Done", type: .boolean),
                ])
            ],
            screens: [
                ScreenSpec(id: "list", title: "Habits", kind: .list, entity: "habit"),
                ScreenSpec(id: "add", title: "Add", kind: .form, entity: "habit"),
            ]
        )
    }

    // MARK: Validator

    func testValidatorAcceptsWellFormedSpec() throws {
        XCTAssertNoThrow(try SubAppSpecValidator.validate(validSpec()))
    }

    func testValidatorRejectsNonSlugID() {
        var spec = validSpec()
        spec.id = "Not A Slug"
        XCTAssertThrowsError(try SubAppSpecValidator.validate(spec))
    }

    func testValidatorRejectsScreenReferencingUnknownEntity() {
        var spec = validSpec()
        spec.screens.append(ScreenSpec(id: "ghost", title: "Ghost", kind: .list, entity: "nope"))
        XCTAssertThrowsError(try SubAppSpecValidator.validate(spec))
    }

    func testValidatorRejectsEmojiIcon() {
        var spec = validSpec()
        spec.icon = "🔥"
        XCTAssertThrowsError(try SubAppSpecValidator.validate(spec))
    }

    func testValidatorRejectsEntityWithoutFields() {
        var spec = validSpec()
        spec.entities = [EntitySpec(name: "empty", label: "Empty", fields: [])]
        spec.screens = [ScreenSpec(id: "list", title: "List", kind: .list, entity: "empty")]
        XCTAssertThrowsError(try SubAppSpecValidator.validate(spec))
    }

    // MARK: Packager (sign / verify / tamper)

    func testPackageRoundTripVerifies() throws {
        let spec = validSpec()
        let data = try SubAppPackager.exportData(for: spec)
        let imported = try SubAppPackager.importSpec(from: data)
        XCTAssertEqual(imported.id, spec.id)
        XCTAssertEqual(imported.displayName, spec.displayName)
        XCTAssertEqual(imported.entities.count, spec.entities.count)
    }

    func testTamperedPackageFailsVerification() throws {
        let spec = validSpec()
        var data = try SubAppPackager.exportData(for: spec)
        // Flip the display name in the serialized spec without re-signing.
        var string = String(data: data, encoding: .utf8)!
        string = string.replacingOccurrences(of: "Habit Tracker", with: "Evil Tracker")
        data = Data(string.utf8)
        XCTAssertThrowsError(try SubAppPackager.importSpec(from: data)) { error in
            guard case SubAppPackageError.signatureMismatch = error else {
                return XCTFail("Expected signatureMismatch, got \(error)")
            }
        }
    }

    func testCorruptJSONFailsGracefully() {
        let data = Data("{ not json".utf8)
        XCTAssertThrowsError(try SubAppPackager.importSpec(from: data))
    }

    // MARK: Moderation

    func testModeratorApprovesCleanSpec() {
        XCTAssertEqual(SubAppModerator.moderate(validSpec()), .approved)
    }

    func testModeratorRejectsMedicalClaims() {
        var spec = validSpec(id: "cure_all")
        spec.summary = "This will cure your illness."
        if case .rejected = SubAppModerator.moderate(spec) { } else {
            XCTFail("Expected rejection for medical-claim content")
        }
    }

    func testModeratorFlagsBorderlineClaims() {
        var spec = validSpec(id: "detox_app")
        spec.summary = "A daily detox routine."
        if case .flagged = SubAppModerator.moderate(spec) { } else {
            XCTFail("Expected flag for borderline wellness claim")
        }
    }

    func testModeratorRejectsReservedID() {
        // AppModule-backed ids are reserved; sleep is a built-in.
        let spec = validSpec(id: "sleep")
        if case .rejected = SubAppModerator.moderate(spec) { } else {
            XCTFail("Expected rejection for reserved built-in id")
        }
    }

    // MARK: Credits ledger

    @MainActor
    private func freshLedger() -> CreditsLedger {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return CreditsLedger(defaults: suite)
    }

    @MainActor
    func testInitialGrantOnFreshInstall() {
        let ledger = freshLedger()
        XCTAssertEqual(ledger.balance, CreditsLedger.initialGrant)
    }

    @MainActor
    func testMeterDebitsBaseCost() {
        let ledger = freshLedger()
        let before = ledger.balance
        ledger.meter(.coachTurn)
        // While credits are unlimited, metering is a no-op so the balance is
        // unchanged; otherwise it debits the kind's base cost.
        if CreditsLedger.unlimited {
            XCTAssertEqual(ledger.balance, before)
        } else {
            XCTAssertEqual(ledger.balance, before - AIUsageKind.coachTurn.baseCost)
        }
    }

    @MainActor
    func testSubAppGenerationCostsMore() {
        XCTAssertGreaterThan(AIUsageKind.subAppGeneration.baseCost, AIUsageKind.coachTurn.baseCost)
    }

    @MainActor
    func testCanAffordReflectsBalance() {
        let ledger = freshLedger()
        XCTAssertTrue(ledger.canAfford(.coachTurn))
        // Drain the balance.
        for _ in 0..<(CreditsLedger.initialGrant + 1) { ledger.meter(.coachTurn) }
        // While credits are unlimited, calls stay affordable and metering doesn't
        // reduce the balance; otherwise a drained balance can't afford a turn.
        if CreditsLedger.unlimited {
            XCTAssertTrue(ledger.canAfford(.coachTurn))
        } else {
            XCTAssertFalse(ledger.canAfford(.coachTurn))
        }
    }

    @MainActor
    func testGrantAddsCredits() {
        let ledger = freshLedger()
        let before = ledger.balance
        ledger.grant(100)
        XCTAssertEqual(ledger.balance, before + 100)
    }

    @MainActor
    func testSyncAuthoritativeBalanceOverrides() {
        let ledger = freshLedger()
        ledger.syncAuthoritativeBalance(7)
        // While credits are unlimited the local balance is pinned to the unlimited
        // sentinel and server balances are ignored; otherwise the server value wins.
        if CreditsLedger.unlimited {
            XCTAssertEqual(ledger.balance, CreditsLedger.initialGrant)
        } else {
            XCTAssertEqual(ledger.balance, 7)
            // No-op when already equal.
            let entriesBefore = ledger.entries.count
            ledger.syncAuthoritativeBalance(7)
            XCTAssertEqual(ledger.entries.count, entriesBefore)
        }
    }
}
