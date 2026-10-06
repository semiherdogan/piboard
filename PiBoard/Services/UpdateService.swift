import Foundation
import Observation
import Sparkle

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    // Must match the `--channel` value scripts/release.sh passes to generate_appcast.
    static let betaSparkleChannel = "beta"

    var id: Self { self }

    var title: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        }
    }

    // Sparkle always offers items without a channel, so stable needs no opt-in.
    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .beta: [Self.betaSparkleChannel]
        }
    }
}

enum BundleInfoKey {
    static let shortVersion = "CFBundleShortVersionString"
    static let buildVersion = "CFBundleVersion"
    static let sparklePublicEDKey = "SUPublicEDKey"
}

@MainActor
protocol UpdaterControlling: AnyObject {
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

@MainActor
@Observable
final class UpdateService {
    typealias UpdaterFactory = @MainActor (
        _ allowedChannels: @escaping @MainActor () -> Set<String>,
        _ onStateChange: @escaping @MainActor () -> Void
    ) -> any UpdaterControlling

    // Must match the SUPublicEDKey placeholder in project.yml.
    static let placeholderPublicEDKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
    static let notConfiguredMessage = "Updates are not configured in this build."
    static let defaultChannel = UpdateChannel.stable
    private static let unknownVersion = "unknown"

    @ObservationIgnored private let settingsRepository: SettingsRepository
    @ObservationIgnored private var updater: (any UpdaterControlling)?

    // False when SUPublicEDKey is missing or still the placeholder; Sparkle refuses to start then.
    let isConfigured: Bool
    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?

    var automaticallyChecksForUpdates = false {
        didSet {
            guard automaticallyChecksForUpdates != oldValue else { return }
            updater?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var channel: UpdateChannel {
        didSet {
            guard channel != oldValue else { return }
            try? settingsRepository.set(.updateChannel, value: channel.rawValue)
        }
    }

    init(settings: SettingsRepository, publicEDKey: String?, makeUpdater: UpdaterFactory) {
        settingsRepository = settings
        channel = settings.get(.updateChannel).flatMap(UpdateChannel.init(rawValue:)) ?? Self.defaultChannel
        isConfigured = Self.isConfigured(publicEDKey: publicEDKey)
        guard isConfigured else { return }
        updater = makeUpdater(
            { [weak self] in self?.channel.allowedSparkleChannels ?? [] },
            { [weak self] in self?.refreshFromUpdater() }
        )
        refreshFromUpdater()
    }

    static func isConfigured(publicEDKey: String?) -> Bool {
        guard let key = publicEDKey?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !key.isEmpty && key != placeholderPublicEDKey
    }

    static func versionDescription(infoDictionary: [String: Any]?) -> String {
        let version = infoDictionary?[BundleInfoKey.shortVersion] as? String ?? unknownVersion
        let build = infoDictionary?[BundleInfoKey.buildVersion] as? String ?? unknownVersion
        return "\(version) (\(build))"
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updater?.checkForUpdates()
    }

    private func refreshFromUpdater() {
        guard let updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
}

@MainActor
final class SparkleUpdater: UpdaterControlling {
    private let channelDelegate: SparkleChannelDelegate
    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    init(allowedChannels: @escaping @MainActor () -> Set<String>, onStateChange: @escaping @MainActor () -> Void) {
        // The controller holds its delegate weakly, so this object keeps it alive.
        channelDelegate = SparkleChannelDelegate(allowedChannels: allowedChannels)
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: channelDelegate,
            userDriverDelegate: nil
        )
        // Flips back to true when a check session ends, which is also when lastUpdateCheckDate settles.
        // Sparkle mutates it on the main thread, so the KVO callback arrives there too.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates) { _, _ in
            MainActor.assumeIsolated { onStateChange() }
        }
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

private final class SparkleChannelDelegate: NSObject, SPUUpdaterDelegate {
    private let allowedChannels: @MainActor () -> Set<String>

    init(allowedChannels: @escaping @MainActor () -> Set<String>) {
        self.allowedChannels = allowedChannels
    }

    // Sparkle calls updater delegate methods on the main thread.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { allowedChannels() }
    }
}
