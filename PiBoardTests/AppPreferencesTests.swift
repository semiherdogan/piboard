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
}
