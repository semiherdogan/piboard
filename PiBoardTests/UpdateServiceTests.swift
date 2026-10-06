import Foundation
import Testing
@testable import PiBoard

@MainActor
private final class FakeUpdater: UpdaterControlling {
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates = true
    private(set) var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}

@MainActor
struct UpdateServiceTests {
    private static let configuredKey = "dGVzdC1wdWJsaWMta2V5"

    private func makeSettings() throws -> SettingsRepository {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return SettingsRepository(database: database)
    }

    private func makeService(
        settings: SettingsRepository,
        publicEDKey: String? = configuredKey,
        updater: FakeUpdater = FakeUpdater(),
        captureAllowedChannels: ((@escaping @MainActor () -> Set<String>) -> Void)? = nil
    ) -> UpdateService {
        UpdateService(settings: settings, publicEDKey: publicEDKey) { allowedChannels, _ in
            captureAllowedChannels?(allowedChannels)
            return updater
        }
    }

    @Test func placeholderMissingOrBlankKeyIsNotConfigured() {
        #expect(!UpdateService.isConfigured(publicEDKey: nil))
        #expect(!UpdateService.isConfigured(publicEDKey: ""))
        #expect(!UpdateService.isConfigured(publicEDKey: "  \n"))
        #expect(!UpdateService.isConfigured(publicEDKey: UpdateService.placeholderPublicEDKey))
        #expect(UpdateService.isConfigured(publicEDKey: Self.configuredKey))
    }

    @Test func placeholderKeyNeverCreatesUpdater() throws {
        var factoryCalls = 0
        let service = UpdateService(settings: try makeSettings(), publicEDKey: UpdateService.placeholderPublicEDKey) { _, _ in
            factoryCalls += 1
            return FakeUpdater()
        }
        #expect(!service.isConfigured)
        #expect(!service.canCheckForUpdates)
        #expect(factoryCalls == 0)
        service.checkForUpdates()
    }

    @Test func configuredServiceMirrorsAndDrivesUpdater() throws {
        let updater = FakeUpdater()
        updater.automaticallyChecksForUpdates = false
        let service = makeService(settings: try makeSettings(), updater: updater)
        #expect(service.isConfigured)
        #expect(service.canCheckForUpdates)
        #expect(!service.automaticallyChecksForUpdates)

        service.automaticallyChecksForUpdates = true
        #expect(updater.automaticallyChecksForUpdates)

        service.checkForUpdates()
        #expect(updater.checkCount == 1)
    }

    @Test func channelDefaultsToStableAndRoundTrips() throws {
        let settings = try makeSettings()
        let first = makeService(settings: settings)
        #expect(first.channel == UpdateService.defaultChannel)

        first.channel = .beta
        #expect(settings.get(.updateChannel) == UpdateChannel.beta.rawValue)
        #expect(makeService(settings: settings).channel == .beta)
    }

    @Test func unknownStoredChannelFallsBackToDefault() throws {
        let settings = try makeSettings()
        try settings.set(.updateChannel, value: "nightly")
        #expect(makeService(settings: settings).channel == UpdateService.defaultChannel)
    }

    @Test func allowedChannelsFollowSelectedChannel() throws {
        #expect(UpdateChannel.stable.allowedSparkleChannels.isEmpty)
        #expect(UpdateChannel.beta.allowedSparkleChannels == [UpdateChannel.betaSparkleChannel])

        var allowedChannels: (@MainActor () -> Set<String>)?
        let service = makeService(settings: try makeSettings()) { allowedChannels = $0 }
        #expect(allowedChannels?() == [])
        service.channel = .beta
        #expect(allowedChannels?() == [UpdateChannel.betaSparkleChannel])
    }

    @Test func versionDescriptionCombinesVersionAndBuild() {
        let info: [String: Any] = [BundleInfoKey.shortVersion: "1.2.3", BundleInfoKey.buildVersion: "1042"]
        #expect(UpdateService.versionDescription(infoDictionary: info) == "1.2.3 (1042)")
    }
}
