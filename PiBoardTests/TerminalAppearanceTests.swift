import AppKit
import Testing
@testable import PiBoard

@MainActor
struct TerminalAppearanceTests {
    private func makePreferences() throws -> AppPreferences {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return AppPreferences(database: database)
    }

    @Test func unknownFontNameFallsBackToSystemMonospaced() throws {
        let preferences = try makePreferences()
        preferences.terminalFontName = "No Such Font \(UUID().uuidString)"
        preferences.terminalFontSize = 15

        let appearance = TerminalAppearance.make(from: preferences)
        let expected = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        #expect(appearance.font.fontName == expected.fontName)
        #expect(appearance.font.pointSize == 15)
    }

    @Test func systemMonospacedSentinelUsesSystemFont() throws {
        let preferences = try makePreferences()
        let appearance = TerminalAppearance.make(from: preferences)
        let expected = NSFont.monospacedSystemFont(ofSize: TerminalFontChoice.defaultSize, weight: .regular)
        #expect(appearance.font.fontName == expected.fontName)
    }

    @Test func installedFontAndSizeAreRespected() throws {
        let preferences = try makePreferences()
        preferences.terminalFontName = "Menlo"
        preferences.terminalFontSize = 18

        let appearance = TerminalAppearance.make(from: preferences)
        #expect(appearance.font.familyName == "Menlo")
        #expect(appearance.font.pointSize == 18)
    }

    @Test func lineHeightMultiplierIsCarried() throws {
        let preferences = try makePreferences()
        preferences.terminalLineHeightMultiplier = 1.25
        #expect(TerminalAppearance.make(from: preferences).lineSpacing == 1.25)
    }

    @Test func applyUpdatesLiveSession() throws {
        let preferences = try makePreferences()
        preferences.terminalFontSize = 20
        let session = PTYSession()

        session.apply(TerminalAppearance.make(from: preferences), cursorStyle: .steadyBar, optionAsMeta: false)

        #expect(session.terminalView.font.pointSize == 20)
        #expect(session.terminalView.optionAsMetaKey == false)
        #expect(session.terminalView.getTerminal().options.cursorStyle == .steadyBar)
    }
}
