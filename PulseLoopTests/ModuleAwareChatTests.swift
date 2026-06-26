import Foundation
import XCTest
@testable import PulseLoop

// MARK: - Module-aware chat UI tests (Experience loop Track M / M2)
//
// Verifies the cold-start greeting + suggestion chips are derived from the user's
// installed modules, and that with nothing installed we fall back to neutral,
// install-oriented prompts (never broken health prompts).
@MainActor
final class ModuleAwareChatTests: XCTestCase {

    /// Minimal `SubApp` conformer for deterministic tests.
    private struct StubApp: SubApp {
        let id: SubAppID
        let displayName: String
        var iconSystemName: String { "circle" }
        var summary: String { "stub" }
        init(_ id: String, _ name: String) {
            self.id = SubAppID(id)
            self.displayName = name
        }
    }

    func testNoModulesFallsBackToNeutralPrompts() {
        let chips = ModuleAwareChat.suggestionChips(installed: [])
        XCTAssertFalse(chips.isEmpty)
        XCTAssertTrue(chips.contains("What can you help me with?"))
        // No health-specific prompt should leak when nothing health is installed.
        XCTAssertFalse(chips.contains("Explain my heart rate trend"))
    }

    func testKnownModuleProducesTailoredPrompts() {
        let chips = ModuleAwareChat.suggestionChips(installed: [StubApp("tasks", "Tasks")])
        XCTAssertTrue(chips.contains("What's on my list today?"))
    }

    func testUnknownModuleFallsBackToGenericChip() {
        let chips = ModuleAwareChat.suggestionChips(installed: [StubApp("custom_widget", "Budget Buddy")])
        XCTAssertTrue(chips.contains("Help me with Budget Buddy"))
    }

    func testChipsAreCappedAndDeduped() {
        let many = (0..<20).map { StubApp("m\($0)", "Module \($0)") }
        let chips = ModuleAwareChat.suggestionChips(installed: many, limit: 6)
        XCTAssertLessThanOrEqual(chips.count, 6)
        XCTAssertEqual(Set(chips).count, chips.count, "Chips must be de-duplicated")
    }

    func testGreetingNamesInstalledModules() {
        let greeting = ModuleAwareChat.greeting(installed: [StubApp("tasks", "Tasks"), StubApp("notes", "Notes")])
        XCTAssertTrue(greeting.contains("Tasks"))
        XCTAssertTrue(greeting.contains("Notes"))
    }

    func testGreetingIsGenericWhenNothingInstalled() {
        let greeting = ModuleAwareChat.greeting(installed: [])
        XCTAssertTrue(greeting.lowercased().contains("install"))
    }
}
