import Foundation
import Testing
@testable import PiBoard

@MainActor
struct AppPreferencesTests {
    private func makeDatabase() throws -> Database {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return database
    }

    @Test func defaultSuffixWhenUnset() throws {
        let database = try makeDatabase()
        let preferences = AppPreferences(database: database)
        #expect(preferences.planFirstSuffix == defaultPlanFirstSuffix)
    }

    @Test func persistedSuffixSurvivesSecondInstance() throws {
        let database = try makeDatabase()
        let first = AppPreferences(database: database)
        first.planFirstSuffix = "Custom suffix"

        let second = AppPreferences(database: database)
        #expect(second.planFirstSuffix == "Custom suffix")
    }

    @Test func planFirstEnabledRoundTrips() throws {
        let database = try makeDatabase()
        let first = AppPreferences(database: database)
        #expect(first.planFirstEnabled == false)
        first.planFirstEnabled = true

        let second = AppPreferences(database: database)
        #expect(second.planFirstEnabled == true)
    }

    @Test func terminalDefaultsWhenUnset() throws {
        let preferences = AppPreferences(database: try makeDatabase())
        #expect(preferences.terminalFontName == TerminalFontChoice.systemMonospaced)
        #expect(preferences.terminalFontSize == TerminalFontChoice.defaultSize)
        #expect(preferences.terminalLineHeightMultiplier == TerminalLineHeight.defaultMultiplier)
        #expect(preferences.terminalCursorStyle == .default)
        #expect(preferences.terminalScrollbackLines == TerminalScrollback.defaultLines)
        #expect(preferences.terminalOptionAsMeta == TerminalOptionAsMeta.defaultValue)
    }

    @Test func terminalPreferencesRoundTrip() throws {
        let database = try makeDatabase()
        let first = AppPreferences(database: database)
        first.terminalFontName = "Menlo"
        first.terminalFontSize = 16
        first.terminalLineHeightMultiplier = 1.2
        first.terminalCursorStyle = .steadyBar
        first.terminalScrollbackLines = 250_000
        first.terminalOptionAsMeta = false

        let second = AppPreferences(database: database)
        #expect(second.terminalFontName == "Menlo")
        #expect(second.terminalFontSize == 16)
        #expect(second.terminalLineHeightMultiplier == 1.2)
        #expect(second.terminalCursorStyle == .steadyBar)
        #expect(second.terminalScrollbackLines == 250_000)
        #expect(second.terminalOptionAsMeta == false)
    }

    @Test func terminalFontSizeIsClampedOnSet() throws {
        let database = try makeDatabase()
        let preferences = AppPreferences(database: database)

        preferences.terminalFontSize = 100
        #expect(preferences.terminalFontSize == TerminalFontChoice.sizeRange.upperBound)
        #expect(AppPreferences(database: database).terminalFontSize == TerminalFontChoice.sizeRange.upperBound)

        preferences.terminalFontSize = 1
        #expect(preferences.terminalFontSize == TerminalFontChoice.sizeRange.lowerBound)
    }

    @Test func outOfRangeStoredFontSizeIsClampedOnLoad() throws {
        let database = try makeDatabase()
        try SettingsRepository(database: database).setDouble(.terminalFontSize, value: 3)
        #expect(AppPreferences(database: database).terminalFontSize == TerminalFontChoice.sizeRange.lowerBound)
    }

    @Test func unknownStoredScrollbackFallsBackToDefault() throws {
        let database = try makeDatabase()
        try SettingsRepository(database: database).setInt(.terminalScrollbackLines, value: 123)
        #expect(AppPreferences(database: database).terminalScrollbackLines == TerminalScrollback.defaultLines)
    }

    @Test func changesPanelWidthDefaultsWhenUnset() throws {
        let preferences = AppPreferences(database: try makeDatabase())
        #expect(preferences.changesPanelWidth == ChangesPanelWidth.defaultValue)
    }

    @Test func changesPanelWidthRoundTrips() throws {
        let database = try makeDatabase()
        AppPreferences(database: database).changesPanelWidth = 600
        #expect(AppPreferences(database: database).changesPanelWidth == 600)
    }

    @Test func changesPanelWidthIsClampedOnSet() throws {
        let database = try makeDatabase()
        let preferences = AppPreferences(database: database)

        preferences.changesPanelWidth = 99_999
        #expect(preferences.changesPanelWidth == ChangesPanelWidth.maximum)
        #expect(AppPreferences(database: database).changesPanelWidth == ChangesPanelWidth.maximum)

        preferences.changesPanelWidth = 10
        #expect(preferences.changesPanelWidth == ChangesPanelWidth.minimum)
    }

    @Test func outOfRangeStoredChangesPanelWidthIsClampedOnLoad() throws {
        let database = try makeDatabase()
        let repository = SettingsRepository(database: database)
        try repository.setDouble(.changesPanelWidth, value: 10)
        #expect(AppPreferences(database: database).changesPanelWidth == ChangesPanelWidth.minimum)
        try repository.setDouble(.changesPanelWidth, value: 99_999)
        #expect(AppPreferences(database: database).changesPanelWidth == ChangesPanelWidth.maximum)
    }

    @Test func cursorStyleComposesFromShapeAndBlink() {
        for style in TerminalCursorStyleChoice.allCases {
            #expect(TerminalCursorStyleChoice(shape: style.shape, blinks: style.blinks) == style)
        }
    }
}
